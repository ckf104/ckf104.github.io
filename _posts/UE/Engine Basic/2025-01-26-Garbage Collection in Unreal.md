---
title: Garbage Collection in Unreal
comments: true
categories:
  - UE5
date: 2025-01-26 12:17:00 +0800
---

### Overview
GC 的入口函数 `CollectGarbage` 或者 `TryCollectGarbage`，总是从 game thread 发起。这很好理解，如果 GC 从其它线程发起，同时 game thread 还在自由地对 uobject 进行修改，这就发生竞争了。那么反过来说，我们通常也不能在其它线程上对 uobject 进行修改。如果确实有必要，例如 async package loader，需要在修改前持有 GC 锁，来避免与 GC 发生竞争

GC 锁，也即 `FGCCSyncObject` 这个全局单例，可以大概看作是一把读写锁。读者通过定义一个 `FGCScopeGuard` 以 RAII 的方式获取读者锁，而写者（GC 的调用者）调用 `AcquireGCLock` 来获取写者锁

GC 的流程大概可以分为三个阶段：Pre GC，Reachability Analysis（下称 RA），Purge。RA 和 Purge 都是比较耗时，可以启用 Incremental 来递增地进行，保证严格的时间限制

用户可以调用的 `TryCollectGarbage` 或 `CollectGarbage` 来触发一次完整的 GC，但更常见的是引擎自动地触发 GC。在 `UWorld` 的 tick 函数中，会调用 `UEngine::ConditionalCollectGarbage`，该函数会根据当前的状况决定是否需要执行 GC，需要从哪个流程开始执行 GC
* 如果用户此前调用过 `UEngine::ForceGarbageCollection`，那么会引擎会调用 `TryCollectGarbage` 触发一次完整的 GC
* 如果没有 world begin play，不执行 GC
* 如果 `IsIncrementalReachabilityAnalysisPending` 返回 true，表明 RA 处于 pending 状态，调用 `PerformIncrementalReachabilityAnalysis` 来继续执行 RA，以及后续的 Purge
* 如果 `IsIncrementalPurgePending` 返回 true，表明 Purge 处于 Pending 状态，调用 `IncrementalPurgeGarbage` 继续执行 Purge。注意，RA 和 Purge 不可能同时处于 pending 状态，因为只有 RA 完整执行完毕后才会执行 Purge，而 Purge 尚未执行完时是不能执行 RA 的
* 否则，调用 `PerformGarbageCollectionAndCleanupActors`（一个 `TryCollectGarbage` 的 wrapper 函数）来执行完整的 GC

UE 使用的是标准的标记清扫算法。一开始将所有的 objects 标记为不可达，然后从 gc root 开始，根据引用关系进行扫描，将所有扫描到的 objects 标记为可达。最后回收所有标记为不可达的 objects。与之相关的是三个 `FUObjectItem` 中的 flags
```c++
	/** EInternalObjectFlags value representing a reachable object */
	EInternalObjectFlags GReachableObjectFlag = EInternalObjectFlags::ReachabilityFlag0;

	/** EInternalObjectFlag value representing an unreachable object */
	EInternalObjectFlags GUnreachableObjectFlag = EInternalObjectFlags::ReachabilityFlag1;

	/** EInternalObjectFlag value representing a maybe unreachable object */
	EInternalObjectFlags GMaybeUnreachableObjectFlag = EInternalObjectFlags::ReachabilityFlag2;
```
在 object 创建出来时，`FUObjectArray::AllocateUObjectIndex` 中会给它的 `FUObjectItem` 加上 `GReachableObjectFlag` 标记。因此在 GC 开始前，所有存活的 objects 都是 `GReachableObjectFlag` 标记。在 RA 开始时，会互换 `GReachableObjectFlag` 和 `GMaybeUnreachableObjectFlag` 的值，这样所有的 object 都被标记为了 maybe unreachable。RA 过程中会将可达的 objects 重新标记为 `GReachableObjectFlag`。在 Purge 阶段，会互换 `GMaybeUnreachableObjectFlag` 和 `GUnreachableObjectFlag` 的值。这样所有不可达的 objects 都被标记为了 unreachable， 然后被回收掉。这就是为什么 RA 和 Purge 不能同时 pending，如果这样的话这些 gc flags 的值就乱套了

在本文中，我们希望回答下面这些问题
* 增量 RA 如何实现？虽然有 TObjectPtr 带来的写屏障，但那些 pre gc delegate 的，以及通过 add reference object 回调来添加引用的是怎么处理的
* 多线程 GC 大概是个什么思路
* gc 是如何将引用置空的，哪些引用会被置空，`UObjectBaseUtility::MarkAsGarbage` 的功能是什么，在 GC 流程中意味着什么？object 的销毁流程是怎样的
* cluster gc 是怎么做的
* upackage 在垃圾回收中是否处于特殊地位，编辑器模式下的 GC 和 Game 模式下的 GC 有什么区别
* 解释 FGCObject 的 `AddStableNativeReferencesOnly` 标志，以及相应的 `AddStableReference` 和 `AddReferenceObject` 的区别
### GC Cluster
#### Overview
引入 Cluster 的基本想法是说一些 object 的生命周期是一致的（例如 actor 和它的 component），并且这些 object 间的引用关系不会发生改变，那我们就可以为这些 object 建立一个 cluster，这样他们在 GC 的 RA 流程中被视为一个整体，不必分析 cluster 内部的引用关系
```c++
struct FUObjectCluster
{
	/** Root object index */
	int32 RootIndex;
	/** Objects that belong to this cluster */
	TArray<int32> Objects;
	/** Other clusters referenced by this cluster */
	TArray<int32> ReferencedClusters;
	/** Objects that could not be added to the cluster but still need to be referenced by it */
	TArray<int32> MutableObjects;
	/** List of clusters that direcly reference this cluster. Used when dissolving a cluster. */
	TArray<int32> ReferencedByClusters;
};
```
object cluster 的 `Objects` 字段表明了哪些 object 属于这个 cluster（cluster root 不在 `Objects` 字段中），当 GC 发现 cluster root 不可达时，会将 cluster root 以及 `Objects` 字段中的 objects 一并销毁。`ReferencedClusters` 和 `MutableObjects` 则记录了该 cluster 的引用关系，前者是它引用的 cluster，后者是它引用的不属于 cluster 的 objects。当 cluster root 被标记为可达时，`ReferencedClusters` 中包含的 cluster root 也会被标记为可达，同时 `MutableObjects` 中的 objects 标记为新的待搜索节点

所有的 cluster 的信息都存储在 `FUObjectClusterContainer` 类的全局单例 `GUObjectClusters` 中。`FUObjectItem` 的 `ClusterRootIndex` 如果大于 0 则记录了该 object 所在的 cluster 的 cluster root 的 index，等于 0 表示不属于任何的 cluster（编号为 0 的 object 是 `CoreUObject` Module 对应的 upackage）。小于 0 表示该 object 是 cluster root，它的相反数减 1 表示 cluster 在 `GUObjectClusters` 中 cluster 数组的 index

值得注意的是，用户需要自己保证 cluster 内的引用不发生变化，UE 并没有任何检测 cluster 内引用发生变化的机制。例如，如果 cluster root 原来引用 object A，现在修改为引用 object B，那么需要将 cluster 销毁掉重新创建，或者手动地修改 cluster 内的字段调整引用关系
#### Cluster Creation
现在我们来看看 cluster 的创建逻辑。用户可以重载 `UObject` 的 `CreateCluster` 来完全自定义自己的 cluster 创建逻辑。以 `ULevelActorContainer::CreateCluster` 的实现作为一个例子。在 `ULevel` 的 `CreateCluster` 函数中，`ULevel` 根据自己包含的 actor 的 `CanBeInCluster` 的返回值，将这些 actor 分为两批，不可以加入 cluster 的 actor 加入 `ActorsForGC` 数组，这些 actor 的 GC 引用由 `ULevel` 的 `AddReferencedObjects` 函数进行添加。其余的 actor 由 `ULevelActorContainer` 的 `Actors` 字段进行管理。进一步调用的 `ULevelActorContainer::CreateCluster` 则将自己管理的这些 actor 以及它们引用的，以及间接引用的所有 uobject 都加入到 cluster 的 `Objects` 字段。这只是一个大概的描述，其实并不是所有 actor 引用到的 uobject 都会加入到这个 cluster 中。[UE4 垃圾回收（二）GC Cluster](https://zhuanlan.zhihu.com/p/133293284) 中对此有详细的讨论。例如
* 如果被引用到的 uobject 的 `CanBeInCluster` 返回 false，亦或者不在该 level 或者 package 中，再或者该 uobject 是 gc root 了等，那么将该 uobject 加入到 cluster 的 `MutableObjects` 中
* 如果被引用到的 uobject 已经在一个 cluster 中了，那么：
	* 将这个被引用到的 cluster，以及它引用的 cluster，都加入到正在创建的这个 cluster 的 `ReferencedClusters` 字段
	* 将这个被引用的 cluster 的 `MutableObjects` 也加入到正在创建的 cluster 的 `MutableObjects` 中。对于这类 uobject，它的 `ClusterRootIndex` 仍然为 0，即名义上它并不属于该 cluster
	* 将正在创建的 cluster 加入到被引用的 cluster 的 `ReferencedByClusters` 字段。比较 `ReferencedClusters` 的加入逻辑，可以看出 `ReferencedClusters` 和 `ReferencedByClusters` 的含义有些区别。`ReferencedClusters` 中包含了该 cluster 直接和间接引用的所有 cluster，而 `ReferencedByClusters` 中仅仅包含直接引用该 cluster 的 cluster。`ReferencedByClusters` 在 cluster 销毁的时候会用到

cluster 的创建时机以及控制 cluster 是否创建的 uobject 成员函数见 [UE4 垃圾回收（二）GC Cluster](https://zhuanlan.zhihu.com/p/133293284)
#### Cluster Dissolution
然后我们看一下 cluster 的销毁逻辑。`FUObjectClusterContainer::DissolveCluster` 以及 `FUObjectClusterContainer::DissolveClusterAndMarkObjectsAsUnreachable` 是主要的销毁 cluster 的接口。主要做了下面几件事
* 将 cluster root 和 cluster 中包含的所有 object 的 `ClusterRootIndex` 字段设置为 0（注意：cluster 的 `Objects` 字段不包含 cluster root）
* 将该 cluster 从它引用的其它 cluster 的 `ReferencedByClusters` 字段中剔除
* 将该 cluster 的 index 加入到 `FUObjectClusterContainer` 的 `FreeClusterIndices` 字段，表明该 cluster 可以用于新的分配请求
* 利用 `ReferencedByClusters` 包含的引用信息，递归地将引用该 cluster 的 cluster 也给 dissolve 掉。这样做的原因在于，我们只有 cluster 间的引用信息，并不知道具体是这个 cluster 内的哪个 object 引用了另一个 cluster 的哪个 object。在 cluster 销毁后，GC 时就没办法正确处理它们间的引用关系了
### Pre GC
在进行 RA 前还有一个 Pre GC Stage，由 `PreCollectGarbageImpl` 函数完成。它主要包含下面的一些工作
* 如果没有 pending 的 RA，这就是一个全新的 GC 的开始，广播 `PreGarbageCollect` 代理
* 如果此时还有 pending purge，调用 `IncrementalPurgeGarbage` 将待 purge 的 objects 清理干净
### Reachability Analysis
RA 负责可达性分析，找出哪些 uobjects 不可达。RA 的实现又可以细分为两阶段，一个是 `FRealtimeGC::StartReachabilityAnalysis`，负责初始的 gc root 标记，另一个是 `FRealtimeGC::PerformReachabilityAnalysisPass`，负责根据引用关系和提供的初始的可达 objects 标记新的可达 objects
#### StartReachabilityAnalysis
该函数负责收集起始节点（称为 initial objects），这些起始节点以及可以通过起始节点的引用关系到达的节点会被 gc 标记为 reachable。主要完成下面的工作
* swap `GReachableObjectFlag` 和 `GMaybeUnreachableObjectFlag` 的值，这样所有的 objects 都被标记上了 maybe unreachable
* 多线程地遍历当前存在的 cluster，将 cluster 包含的 objects 都标记为 reachable。 我觉得这样做的意义在于后续在遍历引用时可以用 `FObjectItem` 的 `IsMaybeUnreachable` 将没有访问的且不属于 cluster 的 object 和访问过的 object 以及 cluster 内的 object 区分开，而不必要先检查是否该 object 是否属于 cluster。另外，如果 cluster root 是 gc root，那么会将 cluster root 标记为可达，并把这个 cluster 引用的 cluster 的 root 都标记为可达，然后把 cluster 的所有 mutable objects 都加入到 initial objects 中。这些工作由 `FRealtimeGC` 的 `MarkClusteredObjectsAsReachable` 完成
* 多线程地遍历 gc root，将 gc root 标记为可达，并且加入到 initial objects 中。gc 的入口函数都有一个 `KeepFlags` 参数，表示任何包含 `KeepFlags` 中的 flag 的 objects 都不应该被回收。因此还会多线程地遍历 `GUObjectArray`，将所有包含 `KeepFlags` 中的 flag 的 objects 都加入到 initial objects 中

这个 `KeepFlags` 参数就是体现编辑器和 game 模式下垃圾回收区别的地方了。通常调用垃圾回收时，使用的 `KeepFlags` 参数为`GARBAGE_COLLECTION_KEEPFLAGS` ，它在编辑器模式下会包含 `RF_Standalone`
```c++
/** Context sensitive keep flags for garbage collection */
#define GARBAGE_COLLECTION_KEEPFLAGS	(GIsEditor ? RF_Standalone : RF_NoFlags)
```
TODO：看看 `RF_Standalone` flag 是在哪被添加的，我看 load package 得到的 asset 对应的 uobject 都包含这个标记
#### PerformReachabilityAnalysisPass
该函数根据提供的 initial objects，递归地遍历其引用关系，将所有可达的 objects 标记为 reachable，并且会把指向 garbage 的引用置空。我主要解释一些要点，而不会详细地谈每行代码是如何工作的
##### Reference Schema
首先是如何遍历 objects 的引用关系。因为 object 引用都用 uproperty 标记了，那自然可以通过遍历 uproperty 来获取到 object 引用到的所有其它 objects。不过 ue 为了加速这一过程，对每种类型的 object 进行了预处理，可以调用 uclass 的 `AssembleReferenceTokenStream` 生成了一个 reference schema 存储在 uclass 的 `ReferenceSchema` 字段。 [UE4 垃圾回收](https://zhuanlan.zhihu.com/p/67055774) 中讨论了 UE4 是如何组织一个 uclass 的 reference schema 的，但我目前看的 UE5.4 中 reference schema 的组织已经大不相同了，不过本质大差不差吧
```c++
/** GC schema, finalized in AssembleReferenceTokenStream */
UE::GC::FSchemaOwner ReferenceSchema;
```
如下图所示，reference schema 仍然是数组的形式组织，`FSchemaOwner` 和 `FSchemaView` 类型都是 64bits 指针的 wrapper，指向 `FMemberWord` 数组的第一个元素，`FSchemaOwner` 强调所有权，负责这块数组内存的释放
```
| Schema Header | FMemberWord | FMemberWord | FMemberWord |...|
|               |
|--->堆分配起点   |---> FSchemaOwner, FSchemaView
```
`FMmeberWord` 是一个 64bits 的 union，最常用的字段是 `Members`，它包含一个 type 字段和一个 offset 字段。显然所有的 object 引用的地址都是 8 字节对齐的，因此 offset 字段记录的是实际的 offset 除以 8 的结果。所有类型的 type 由 `enum class ` 这个枚举类型定义。例如一个 uobject 的定义中包含 4 个 `TObjectPtr` 引用，那么这四个 object 引用能够 pack 为一个 `FMemberWord`，每个 `FMemberPacked` 的 type 字段是 `EMemberType::Reference`，offset 则是 `TObjectPtr` 引用在该 object 中的偏移除以 8。新的组织方式有着更高的密度
```c++
union FMemberWord
{
	FMemberPacked Members[4];
	FSchemaView InnerSchema{NoInit};
	ObjectAROFn ObjectARO;
	StructAROFn StructARO;
	FStridedLayout StridedLayout;
};

struct FMemberPacked
{
	static constexpr uint32 TypeBits = 5;
	static constexpr uint32 OffsetBits = 16 - TypeBits;
	static constexpr uint32 OffsetRange = 1u << FMemberPacked::OffsetBits;

	uint16 Type : TypeBits;
	uint16 WordOffset : OffsetBits;
};
```
这样做显而易见的代价是，offset 的大小被限制了，11 位的 offset 字段最多能够记录 2048 * 8 的偏移。因此 UE 引入了 `EMemberType::Jump` 表示额外的偏移，在遍历 `FMemberWord` 数组时，如果遇到了 jump 类型的 member，则将当前的指针前移 `offset * OffsetRange`，来保证引用的偏移总是在 11 bits 的表示范围内。遍历  `FMemberWord` 数组的逻辑见 `UE::GC::Private::VisitMembers` 函数

如果 object 包含嵌套的 struct，那么 struct 中包含的引用会内联进 object 的  `FMemberWord` 数组。稍微复杂的情况是 sturct 包裹在 `TArray` 或者 `TSet` 之类的变长容器里，就没办法将 struct 中的引用内联进去了（因为 struct 的数目是不确定的）。以 `TArray<UMyStruct>` 这类的成员为例，它会在 `FMemberWord` 占据两个项，第一个项是一个 16 bits 的 `FMemberPacked`，它的 type 为 `EMemberType::StructArray`，offset 表示这个 `TArray` 在 object 中的偏移。随后一个项占据一个完整的 `FMemberWord`，它的有效字段是 `InnerSchema`，指向一个新的 `FMemberWord` 数组，这个数组存储了 `UMyStruct` 的引用情况

还有一个值得一提的是 `EMemberType::ARO` 类型。uobject 可以重载 `UObject::AddReferencedObjects` 这个静态函数（ARO）来添加额外的引用。例如前面提到的 `ULevel` 用这个函数来添加自己对 actor 的引用，以及我们熟悉的 `UGCObjectReferencer`，它的 ARO 会调用所有的 `GCObject` 的`AddReferencedObjects` 来收集引用。object 的 ARO 存储在 uclass 的 `CppClassStaticFunctions` 中。`AssembleReferenceTokenStream` 函数在创建 `FMemberWord` 数组时，如果发现 object 的 ARO 并非默认的 `UObject::AddReferencedObjects`，就会添加一个 `EMemberType::ARO` 类型的 `FMemberPacked`，以及一个额外的有效字段为 `ObjectARO` 的 `FMemberWord`。`ObjectARO` 字段记录了 ARO 函数的地址

另外用户可以调用 `RegisterSlowImplementation` 函数来标记 object 的 ARO 函数为 `EMemberType::SlowARO`。目前 UE 中只有 `UDataTable` 和 `UClass` 的 ARO 函数注册为了 Slow ARO，我们会在 Multi-Thread RA 小节中讨论 Slow ARO 和 ARO 的区别

`FMemberWord` 数组显然是可以做一些复用的，例如可以设计为子类的 schema 复用父类的 schema，然后再包含一些子类额外的引用字段。但 UE 实际上做得很克制，他只包含两种类型的复用
* 如果子类完全不包含额外的引用，且子类的 ARO 和父类相同，直接复用父类的 schema
* 子类会复用父类的 `InnerSchema`：上面讨论过，父类中如果包含类似于 `TArray<UMyStruct>` 的字段时，父类的 `FMemberWord` 数组中包含一个 `InnerSchema`，指向表达 `UMyStruct` 引用字段的`FMemberWord` 数组。子类的 `FMemberWord` 数组会复用这个 `UMyStruct` 的 `FMemberWord` 数组（即做一个浅拷贝，而非深拷贝）

既然有 schema 的复用，就需要引用计数来统计复用次数来确保资源的正确释放，这是前面示意图中 Schema Header 的作用了
```c++
struct FSchemaHeader
{
	uint32 StructStride; // sizeof(T), required to iterate over struct array
	std::atomic<int32> RefCount;
};
```
其中 `RefCount` 就是该 schema 的引用计数
##### Reference Collection
现在我们讨论 UE 在使用 reference schema 收集引用时涉及到三种类型：Reference Processor，Reference Collector，Reference Dispatcher。这三种类型分别都有许多具体的实现，并且不局限于做 RA，更宽泛地说，它们负责引用收集和处理，例如在创建 cluster 时收集 cluster root 的引用关系也需要用到它们。下面我们将这三种类型简称为 processor，collector，dispatcher

首先说最基础的 collector。它主要用来收集 ARO 提供的引用信息。所有种类的 collector 都继承自 `FReferenceCollector`，这个我们很熟悉，因为 ARO，以及 `FGCObject` 重载的 `AddReferencedObjects` 都接收一个 `FReferenceCollector` 参数

`FReferenceCollector` 提供了两类 API，一种是 `AddStableReferenceXXX`，这种仅接受 objects 参数。产生的引用关系是当前的 ARO 对应的 uobject 引用参数传递的 objects。而如果是 `FGCObject` 中调用的，产生的引用关系就是全局的 `UGCObjectReferencer` 引用参数传递的 objects。另一种是 `AddReferencedObject`，这类 API 除了接收被引用的 objects 参数，还可以指定是哪个 object 引用了这些，以及是哪个 uproperty 产生了这个引用

观察这两类 API 的参数可以发现，`FReferenceCollector` 收集的是引用的引用（二级指针），这样做的目的是，如果发现引用指向的 object 是 garbage 的话，可以直接将引用置空。而两类 API 的主要区别就在于这个 stable。`AddStableReferenceXXX` 表示传入的引用不是一个栈上的临时引用，在整个 GC 过程中这个引用都是有效的（这里不是说引用指向的 object 是有效的，而是说这个 8 字节的引用本身是有效的，因为 collector 存储的是引用的地址）。这样的话就可以延迟处理，做一些 batch 操作。而 `AddReferencedObject` API 则不保证这一点，需要立刻对传入的引用进行处理

通常 collector 会将 ARO 中收集到的引用转发到 dispatcher，以及 `UE::GC::Private::VisitMembers` 中遍历 reference schema 直接得到的引用也会调用 dispatcher 的 API 来处理。dispatcher 提供了两种 API，`HandleImmutableReference` 和 `HandleKillableReference`，immutable ref 指的是不能置空的引用，对应的，killable ref 就是可以置空的引用。查看 `TFastReferenceCollector::ProcessObjects` 这部分的代码可以知道，object 对 outer 以及 uclass 的引用是 immutable 的，而 reference schema 中包含的引用是 killable 的。UE 中实现了两种 dispatcher
* 一种是 `TDirectDispatcher`，它将引用的处理转发给 processor 的 `HandleTokenStreamObjectReference` 函数，`bAllowReferenceElimination` 参数将 immutable 和 killable ref 区分开
* 另外一种是 `TBatchDispatcher`，这也是 RA 中使用的 dispatcher，它会将收集到的 immutable 和 killable ref 存放在分别的 immutable 和 killable batcher 中。当 batcher 满之后再统一转发给 processor 的 `HandleBatchedReference` 函数

最后 processor 负责实际地处理收集到的引用，依据 processor 的目的处理方式也不尽相同。例如 cluster 创建的 processor 就负责将引用的新的 object 加入到 cluster 中，而 RA 中的 processor 就需要负责标记 object 可达

这里我们总结一下 RA 中实际使用的 collector，dispatcher，processor 类型：
* collector 是 `TReachabilityCollector`。它的特点是关联 `TBatchDispatcher`，将所有的 ref 处理都转发到 `TBatchDispatcher` 上
* dispatcher 是 `TBatchDispatcher`，它会将收到的 reference 缓存到队列中，队列满了之后再统一派发到 processor 给 `HandleBatchedReference` 函数
* processor 是 `TReachabilityProcessor`，它的 `ProcessReferenceDirectly` 处理非 batch 的单个 ref（例如调用 collector 非 stable 的 API），而两个 `HandleBatchedReference` 负责处理通过 batch 传递过来的 killable 和 immutable ref。如果一个 killable ref 引用到了 garbage object，那么该引用会被置空。用户可以使用 `UObjectBaseUtility::MarkAsGarbage` 将 object 标记为 garbage
```c++
FORCEINLINE static void HandleBatchedReference(FWorkerContext& Context, FResolvedMutableReference Reference, FReferenceMetadata Metadata);
FORCEINLINE static void HandleBatchedReference(FWorkerContext& Context, FImmutableReference Reference, FReferenceMetadata Metadata);
```
TODO：batch 在多线程的背景下是否尤其重要呢？我其实不太理解这里的 batch 有什么好处
##### Multi-Thread RA
我们接下来讨论 RA 是如何多线程进行的。核心要义是，每个线程都有一个自己的 `FWorkerContext`，前面提到 RA 开始时会收集到 initial objects，UE 会把这些 initial objects 均分给各个 `FWorkerContext`，每个线程就从自己分配到的 initial objects 开始遍历引用关系
```c++
struct alignas(PLATFORM_CACHE_LINE_SIZE) FWorkerContext
{
	// This is set by GC when processing references from the current referencing object
	UObject* ReferencingObject = nullptr;
	TConstArrayView<UObject*> InitialObjects;

	FWorkBlockifier ObjectsToSerialize;
};
```
这些引用关系肯定会有交叉，不可避免地多个线程访问到同一个 object，那如何避免重复遍历呢？前面提到过，未访问的 object 是 maybe unreachable 状态，因此如果线程访问到一个 reachable 的 object，那就跳过这个引用关系。而如果线程访问到一个 maybe unreachable 的 object，就使用原子操作将它的状态从 maybe unreachable 切换到 reachable，如果成功了，那么才遍历该 object 的引用关系

`TReachabilityProcessor` 的 `ProcessReferenceDirectly` 以及 `HandleBatchedReference` 函数都会转发到它的 `HandleValidReference` 函数中。这个函数实际地将引用到的 object 标记为可达，分下面几种情况
* 如果能够使用 `MarkAsReachableInterlocked_ForGC` 函数将 object 从 maybe unreachable 切换为 reachable（那么该 object 必然不在 cluster 中）
	* 如果该 object 不是 cluster root，那么将该 object 加入到 `FWorkerContext` 的 `ObjectsToSerialize` 中，表示该 object 的引用关系需要遍历
	* 如果该 object 是 cluster root，那么将该 cluster 引用到的 cluster 的 root 都标记为可达，然后将这个 cluster 的 mutable objects 都加入到 `FWorkerContext` 的 `ObjectsToSerialize` 中
* 如果该 object 位于 cluster 中，并且能成功地将 cluster root 的状态从 maybe unreachable 切换为 reachable，那么将该 cluster 引用到的 cluster 的 root 都标记为可达，然后将这个 cluster 的 mutable objects 都加入到 `FWorkerContext` 的 `ObjectsToSerialize` 中

`FWorkBlockifier ObjectsToSerialize` 是多线程负载均衡的重要组成部分，因为均分 initial objects 显然不能保证每个线程的工作量是一致的。它是一个 lock free 的 work stealing queue。队列中每个元素是 `FWorkBlock` 类型，这个 block 中包含 512 个待遍历引用的 objects。当一个线程遍历完自己的 objects 的引用后，它就会偷取其它线程的 `FWorkBlock`

另外，Slow ARO 也和多线程负载均衡有些关系。ARO 函数如果使用 Slow ARO 标记了，说明该函数跑得比较慢，在遍历 reference schema 时如果遇到了 `EMemberType::SlowARO`，不会马上调用对应的 ARO 函数来收集应用，而是将该 ARO 函数加入到 `FSlowAROManager` 的全局单例中。在线程完成自己的工作，除了偷取其它线程 `FWorkBlock`，也可能向 `FSlowAROManager` 的全局单例偷取待调用的 Slow ARO
##### Update
[UE4 垃圾回收（二）GC Cluster](https://zhuanlan.zhihu.com/p/133293284) 中对 cluster 销毁时为什么向上递归的分析很有启发性。我发现上面叙述的引用置空逻辑只适用于不属于任何 cluster 并且不是某个 cluster 的 mutable objects 的 object 被标记为 garbage 的情况，对于 object 是 cluster root 或者 cluster 的 mutable objects 时，UE 实际上做了一些额外的处理。这是因为这些 objects 可能被 cluster 中的某个 obj 引用，而在引用遍历时根本就不会处理 cluster 中的 obj

因此为了保证能够将 cluster objects 的指向 garbage 的引用也置空，我们需要对上面的引用置空逻辑叙述打额外的两个补丁
* 指向 cluster root 的引用可能来自任何引用该 cluster 的 cluster 中的 obj。因此在 StartReachabilityAnalysis 阶段遍历 cluster 数组时，就会判断该 cluster root 是否是 garbage，如果是的话，就递归地将该 cluster，以及所有直接或间接引用该 cluster 的 cluster 都销毁掉
* 指向 mutable objects 的引用来自本 cluster 的 obj。在 processor 的 `HandleValidReference` 处理引用时，将 cluster 的 mutable objects 都加入到 `FWorkerContext` 的 `ObjectsToSerialize` 中之前，它会检查每个 mutable objects 是否是 garbage，如果是，会将该 cluster 的 `bNeedsDissolving` 设置为 true，并且将 cluster 中所有的 obj 都加入到 `ObjectsToSerialize` 中，因此后续将遍历 cluster 的所有 objects 来将指向 mutable objects 的引用置空
##### 2025.06.18 Update
清楚了 cluster 中 `ReferencedClusters` 和 `ReferencedByClusters` 以及 `MutableObjects` 的含义后，会发现 `UObjectBaseUtility::AddToCluster` 的实现是有问题的。假设加入一个 object 到已有的 cluster A 中，如果我们遍历该 object 直接和间接的引用得到了新的 cluster 引用 Bs 和 mutable objects objs（s 表示可能有多个 cluster），那么我们需要
* 在 cluster Bs 的 `ReferencedByClusters` 中加入 cluster A
* 在 cluster A 的 `ReferencedClusters` 中加入 cluster Bs 以及 cluster Bs 的 `ReferencedClusters`
* 在 cluster A 的 `MutableObjects` 中加入 objs 以及 cluster Bs 中的 `MutableObjects`
* 递归遍历 cluster A 的 `ReferencedByClusters`，得到所有直接或间接引用 cluster A 的 cluster Ks
	* cluster Ks 的 `ReferencedClusters` 中加入 cluster Bs 以及 cluster Bs 的 `ReferencedClusters`
	* cluster Ks 的 `MutableObjects` 中加入 objs 以及 cluster Bs 中的 `MutableObjects`

但是源码的实现只处理了 1，2，3 步，没有递归遍历 cluster A 的 `ReferencedByClusters`。但是新创建 cluster A 并收集引用时则不需要考虑 cluster A 的 `ReferencedByClusters`，**因为新创建的 cluster 不可能被已有的 cluster 引用**
### Purge
最后我们讨论 GC 的 Purge 阶段。这个阶段由 `PostCollectGarbageImpl` 函数实现，它做了下面的事情来回收不可达的 objects
1. 首先是交换 `GUnreachableObjectFlag` 和 `GMaybeUnreachableObjectFlag`，那么之前没有访问到的 object 都被标记上了 unreachable
2. 调用 `DissolveUnreachableClusters` 函数，它多线程地遍历 cluster，将所有 root unreachable 的 cluster 都销毁掉，cluster 包含的 objects 也都标记为 unreachable
3. 调用 `ClearWeakReferences` 函数，负责将 collector 通过 `MarkWeakObjectReferenceForClearing` 收集到的 weak ref 置空
4. 调用 `GatherUnreachableObjects` 函数，多线程地遍历 `GUObjectArray`，将所有 unreachable 的 objects 都添加到 `GUnreachableObjects` 这个全局数组中
5. `PostReachabilityAnalysis` 广播
6. 调用 `UnhashUnreachableObjects` 函数，这个函数触发 `PreGarbageCollectConditionalBeginDestroy` 广播，然后调用 `GUnreachableObjects` 所有 objects 的 `ConditionalBeginDestroy` 函数，最后触发 `PostGarbageCollectConditionalBeginDestroy` 广播。之所以叫作 unhash 是因为在 object 的 `ConditionalBeginDestroy` 中会把 object 从全局的 object 哈希表中移除
7. 调用 `IncrementalPurgeGarbage` 函数，它遍历 `GUnreachableObjects` 数组，调用 object 的 `IsReadyForFinishDestroy` 函数，如果返回 true，那么会调用 object 的 `ConditionalFinishDestroy`，而如果返回 false，则将 object 加入 `GGCObjectsPendingDestruction` 数组中。接下来，它将不断地遍历 `GGCObjectsPendingDestruction` 数组，调用所有 ready for finish destroy 的 object 的 `ConditionalFinishDestroy` 函数，知道所有的 object 的 `ConditionalFinishDestroy` 都被调用。每完成一次遍历，它将主动让出 CPU，等待 OS 的下一次调度。最后是调用 `GUnreachableObjects` 中 unreachable objects 的析构函数。这里存在一个额外的析构线程 `FAsyncPurge`。当所有 unreachable objects 的 `ConditionalFinishDestroy` 执行完毕后，析构线程开始执行，遍历 `GUnreachableObjects`，调用 `IsDestructionThreadSafe` 返回 true 的 objects 的析构函数，以及 `GUObjectAllocator.FreeUObject` 回收 object 的内存。遇到需要在主线程析构的 object，则递增 local counter。与此同时，主线程也遍历 `GUnreachableObjects`，负责调用指定在主线程析构的 object 的析构函数以及回收它们的内存。所有析构完成后，触发 `PostPurgeGarbage` 广播
8. 触发 `GarbageCollectComplete` 广播

这样我们就讨论完了整个 GC 的流程，这里我们总结一下 object 的销毁流程
* `ConditionalBeginDestroy`，可以重载内部调用的 `BeginDestroy`
* `ConditionalFinishDestroy`，可以重载内部调用的 `FinishDestroy`
* 析构函数
以及 `IsReadyForFinishDestroy` 决定该 object 当前是否能够调用 `ConditionalFinishDestroy`，`IsDestructionThreadSafe` 决定该 object 是否可以在另一个线程调用析构函数
### Incremental GC
最后我们讨论一下 Incremental GC。比较简单的是 incremental purge。可以看到 purge 阶段干的事情就是反复遍历那些全局数组，要把它做成 incremental 是比较容易的。只需要在超时的时候保存一下当前遍历的 index 以及其它的一些信息就好了

这里多说一句调用 objects 析构函数时的 incremental 处理。首先 objects 的析构函数本身是没有办法并发执行的（`UObjectBase` 的析构函数会访问线程不安全的 `GUObjectArray`），因此主线程和析构线程在调用 object 的析构函数前都会获取 `GUObjectArray` 的 `ObjObjectsCritical` 锁。那这里额外引入析构线程的意义是什么呢？实际上，主线程在获取 `ObjObjectsCritical` 锁后，不会完整地遍历整个 `GUnreachableObjects`。它一旦析构了析构线程中的 local counter 那么多的 objects 后，就会释放 `ObjObjectsCritical` 锁，退出循环。也就是说在主线程退出 GC，执行其它工作时，异步的析构线程就可以没有竞争地析构 objects 了（当然这时候主线程广播 `PostPurgeGarbage` 和 `GarbageCollectComplete` 就得相应推迟了）

然后我们讨论稍微麻烦一点的 incremental RA。从编译的角度来说，实现 incremental RA 需要引入写屏障，保证系统能捕获到被修改的引用。但是 C++ 显然没有办法原生地支持写屏障，因此 UE 通过 `TObjectPtr` 来模拟

具体来说，在修改，设置 `TObjectPtr` 包含的引用时，如果此时有 pending RA，且引用的 object 是 maybe unreachable，那么会将新的引用或者 cluster 加入到 `GReachableObjects` 或 `GReachableClusters` 中（取决于该 object 在不在 cluster 中）
```c++
	explicit FORCEINLINE FObjectPtr(UObject* Object)
		: Handle(UE::CoreUObject::Private::MakeObjectHandle(Object))
	{
#if UE_OBJECT_PTR_GC_BARRIER
		ConditionallyMarkAsReachable(Object);
#endif // UE_OBJECT_PTR_GC_BARRIER
	}

	FORCEINLINE void ConditionallyMarkAsReachable(const UObject* InObj) const
	{
		if (UE::GC::GIsIncrementalReachabilityPending && InObj)
		{
			UE::GC::MarkAsReachable(InObj);
		}
	}
```
然后在 pending RA 重启时，将 `GReachableObjects` 和 `GReachableClusters` 中包含的 objects 和 cluster 标记为可达，并加入到 initial objects 中

注意，要 Incremental RA，就需要所有的引用都使用 `TObjectPtr`，一个典型的例子是 `ULevel` 的 `ActorsForGC`
```c++
	/** Array of actors to be exposed to GC in this level. All other actors will be referenced through ULevelActorContainer */
	TArray<TObjectPtr<AActor>> ActorsForGC;
```
`ActorsForGC` 没有使用 uproperty 标记，它包含的引用是通过 `ULevel` 的 ARO 添加的。可能在上一次未完成的 RA 中通过 ARO 访问了 `ActorsForGC` 中包含的引用，但在继续下一次 RA 之前 `ActorsForGC` 中的引用发生了改变。由于 ARO 已经调用过了，如果这里的 `AActor` 引用没有使用 `TObjectPtr` 包裹，新的引用关系就没有被 GC 捕获掉，导致 objects 被提前回收了

在多线程 RA 遍历引用时，线程每完成一个 `FWorkBlock` 包含的遍历工作，就会检查当前 RA 是否超时。如果超时了就保存相应的信息，退出 RA，由此保证严格的时间约束

另外就是 `ClearWeakReferences` 函数也需要修改。因为上一次未完成的 RA 添加的 weak reference 可能已经失效了。所以当最终完成的 RA 的 iteration 次数大于 1 时（即该 RA 分成多次完成），需要利用 `FWeakReferenceEliminator`，重新调用所有需要添加的 weak ref 的 objects 的 ARO 函数来置空它们的指向 unreachable objects 的 weak ref（但是在遍历引用，重启 pending RA 时我们不会重新调用 objects 的 ARO 来收集可能的新修改的引用，因为这个开销太大了）
### GC Debugging
一个通常的需求是，给一个 object，我希望弄清楚它的引用关系，它引用了谁，谁又引用了它。Rama 在帖子 [Count References to Any Object, and Know Who is Referring!](https://forums.unrealengine.com/t/new-wiki-memory-management-count-references-to-any-object-and-know-who-is-referring/59401) 中发布了一个新的 wiki，这个 wiki 使用 UE 提供的 `FReferenceFinder` 来找出一个 object 直接或间接地引用了哪些 object。对应的 wiki 页面是 [Garbage Collection ~ Count References To Any Object](https://unrealcommunity.wiki/garbage-collection-~-count-references-to-any-object-2afrgp8l)

但我认为搞清楚谁引用了给定的 object 是常见的需求，[Count References to Any Object, and Know Who is Referring!](https://forums.unrealengine.com/t/new-wiki-memory-management-count-references-to-any-object-and-know-who-is-referring/59401) 中的一个评论谈到可以使用 `IsReferenced` 这个函数来找出所有引用这个 object 的 objects。但我翻了一下这个函数的实现，它内部做 RA 时，会将所有不可达的 objects 都标记为 unreachable，这会扰乱正常的 GC flow（它要求 GC 开始时所有的 objects 都有且仅有 reachable 标记，见 GC 开始时调用的 `VerifyObjectFlags` 函数）。在源码中搜索了一下，发现只有 editor 会调用这个函数，而在 PIE 之前 tick 都不会触发垃圾回收，我猜 editor 内部可能会在调用 `IsReferenced` 后自己再做一个 garbage purge，来清理掉所有的 unreachable flag 之类的吧

找了一圈，发现 `FReferencerFinder::GetAllReferencers` 是一个不错的选择，和 GC 类似，它会使用 collector 和 processor 来多线程地遍历 `GUObjectArray`：
* 它把 `GUObjectArray` 中几乎所有的 objects 都加入到了 initial objects 中，这样就不需要像 GC 那样递归地搜索了
* 它使用默认的 `TDefaultCollector` 和 `TDirectDispatcher`，但 processor 使用自定义的 `FAllReferencesProcessor`，这个 processor 的 `HandleTokenStreamObjectReference` 实现也很自然，就是判断 dispatcher 传过来的引用关系是不是引用我们关注的 objects，如果是，那么就把这个引用关系保存起来即可。最后把所有保存的引用关系返回给用户即可

TODO：解释与 GC debug 有关的 console variable
gc.ForceEnableGCProcessor
gc.GarbageReferenceTrackingEnabled
### GC Performance Optimization
TODO：解释下面的
```c++
	FIterationTimerStat ReachabilityTime;
	FIterationTimerStat ReferenceCollectionTime;
	FIterationTimerStat GatherUnreachableTime;
	FIterationTimerStat UnhashingTime;
	FIterationTimerStat DestroyGarbageTime;
```
TODO：看看 [UE4 垃圾收集大杂烩](https://zhuanlan.zhihu.com/p/219588301)