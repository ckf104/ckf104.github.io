### Object Path
每个 uobject 路径名唯一，路径由 uobject 自身的名字与它的 outer 链组装而成，见 `UObjectBaseUtility::GetPathName`
通常 `/Game` 表示 project 的 content 目录，`/Engine` 表示 engine 的 content 目录，`/Script` 则表示模块目录，例如 `/Script/MyModuleName` 之类的，而插件的路径名就是将 `Game` 替换为插件的名字

反过来我们也可以通过路径名去拿到内存中的 uobject，调用 `FindObject`，将 outer 设置为 nullptr，name 设置为完整路径名即可
```c++
/**
 * Find an optional object.
 * @see StaticFindObject()
 */
template< class T > 
inline T* FindObject( UObject* Outer, const TCHAR* Name, bool ExactClass=false );
```
`ConstructorHelpers::FObjectFinder` 中会在路径后自动加上 .ObjectName（如果自己没加的话），并且会把 load 上来的 uobject 给加到 gc root 里，虽然我感觉有点多余，因为通常已经有 `RF_StandAlone` 了？但 `RF_StandAlone` 应该不能保证它引用的对象不被回收？
对比之下 `ConstructorHelpers::FClassFinder` 则是会在路径后加上 .ObjectName_C（如果自己没加的话），其它部分和 object finder 是一样的
### GUObjectArray
UE 通过一个全局的，以 chunk 形式组织的 `UObjectItem` 数组来管理 uobject
```c++
// Global UObject array instance
FUObjectArray GUObjectArray;
```
首先想到的问题是为什么要额外借助一个 `UObjectItem`，而不是直接来一个全局的 uobject 数组？这是因为 uobject 的基类那么多，大小又不一样，当然没办法放在一个数组里了。那整个 uobject 指针数组好了呗。单单一个 uobject 指针可能不够，我有可能还要存储一些其它的和这个 uobject 绑定的，但又不想放在 uobject 里的元数据，uobject 指针包括其它的元数据，就构成了 `UObjectItem`
```c++
struct FUObjectItem
{
	// Pointer to the allocated object
	class UObjectBase* Object;
private:
	// Internal flags. These can only be changed via Set* and Clear* functions
	int32 Flags;
public:
	// UObject Owner Cluster Index
	int32 ClusterRootIndex;	
	// Weak Object Pointer Serial number associated with the object
	int32 SerialNumber;
}
```
`ClusterRootIndex` 字段与 UE 的 GC 机制有关。`SerialNumber` 与 `TWeakObjectPtr` 有关，待会会进行解释

在 `UObjectBase` 的构造函数中，它会在 `GUObjectArray` 中寻找一个空的插槽，将这个空的插槽上的 `UObjectItem` 的 `Object` 字段设置为自己，然后 `UObjectBase` 的 `InternalIndex` 设置为这个插槽的 index。这样就把一个 uobject 和一个 object item 关联上了。具体找插槽的方式见 [UE4 UObject管理方式](https://zhuanlan.zhihu.com/p/362228148)。主要分为两类，一类是初始创建的，不会被 GC 回收的走 DisregardForGC 的逻辑，而通常的 uobject 就从 `ObjAvailableList` 这个缓存里面找 index。初始的 `SerialNumber` 设置为 0

`GUObjectArray` 的 `PrimarySerialNumber` 字段单调递增。每当 uobject 赋值给一个 `TWeakObjectPtr` 时，`PrimarySerialNumber` 增加 1，然后将新的 primary serial number 的值赋给 `TWeakObjectPtr` 的 `ObjectSerialNumber`，同时赋给这个 uobject 对应的 object item 的 `SerialNumber`

在 `UObjectBase` 的析构函数中，将自己占有的 object item 插槽又释放给 `ObjAvailableList`，同时将 `SerialNumber` 置 0，结合 primary serial number 的单调性，我们就可以保证 `TWeakObjectPtr` 通过判断 serial number 是否相等就知道对应的 uobject 是否还可用了
### Object Hash
```c++
class FUObjectHashTables;
```
`FUObjectHashTables` 类是一个全局单例，它负责管理所有 uobject 相关的 hash 表项，使得能够快速地对 uobject 进行查询

在 `UObjectBase` 的构造函数中会调用 `HashObject` 函数，这个函数负责将新生成的 uobject 加入到各种 hash 表中
* `TBucketMap<int32> Hash`，这个 hash 表根据 object 的名字进行 hash，对应的 key 是 object 指针
* `TMultiMap<int32, uint32> HashOuter`，这个 hash 表根据 object 的名字和它的 outer 地址进行 hash，对应的 key 是 object 在 `GUObjectArray` 中的下标
* `TBucketMap<UObjectBase*> ObjectOuterMap`，这个 hash 表根据 object 的 outer 地址进行 hash，对应的 key 是 object 指针
* `TBucketMap<UClass*> ClassToObjectListMap`，这个 hash 表根据 object 的 uclass 进行 hash，对应的 key 是 object 指针

`TBucketMap` 是 `TMap` 的子类，关于这个数据结构的说明见 [用UObjectHashTables管理UObjectHash](https://zhuanlan.zhihu.com/p/464960701)

当 uobject 销毁时，会调用 uobject 的 `BeginDestroy` 回调，进一步调用 `UObjectBase::LowLevelRename`，这个函数会调用 `UnhashObject`，负责将这个 uobject 从 hash 表中删除掉

不过 ue 这粗暴的 hash 实现显得有点傻逼，例如我可能游戏中需要 new 出很多临时的 actor，例如子弹等等，它们的生命周期可能很短，用户可能并不需要从 hash 表中去搜索，这样频繁地将 actor 从 hash 表中移入和移出实际上是不必要的开销
### External Package
`NewObject` 可以指定一个 external package 参数，用来重载 object 属于哪个 package
```c++
UPackage* UObjectBaseUtility::GetPackage() const
{
	const UObject* Top = static_cast<const UObject*>(this);
	for (;;)
	{
		// GetExternalPackage will return itself if called on a UPackage
		if (UPackage* Package = Top->GetExternalPackage())
		{
			return Package;
		}
		Top = Top->GetOuter();
	}
}
```
### Garbage Collection
这一节我们讨论 UE 的 GC 机制，我对 GC

GC 的入口函数 `CollectGarbage` 或者 `TryCollectGarbage` 应该总是从 game thread 发起的。这很好理解，如果 GC 从其它线程发起，同时 game thread 还在自由地对 uobject 进行修改，这就发生竞争了。那么反过来说，我们通常也不能在其它线程上对 uobject 进行修改。如果确实有必要，例如 async package loader，需要在修改前持有 GC 锁，来避免与 GC 发生竞争

GC 锁，也即 `FGCCSyncObject` 这个全局单例，可以大概看作是一把读写锁。读者通过定义一个 `FGCScopeGuard` 以 RAII 的方式获取读者锁，而写者调用 `AcquireGCLock` 来获取写者锁

TODO：需要弄明白下面的问题
* 增量 GC 如何实现？虽然有 TObjectPtr 带来的写屏障，但那些 pre gc delegate 的，以及通过 add reference object 回调来添加引用的是怎么处理的
* 多线程 GC 大概是个什么思路
* gc 是如何将引用置空的，哪些引用会被置空，mark pending kill 的功能是什么，object 的销毁流程是怎样的
* cluster gc 是怎么做的
* TObjectPtr 在编辑器下的 lazy loading

UObject 的 `AddReferencedObjects` 静态函数存储在对应 uclass 的 `CppClassStaticFunctions` 中
例如 ulevel 的 `AddReferencedObjects` 函数将 level 中所有的 actor 加入到引用中，而 actor 的 `AddReferencedObjects` 函数将自己的所有 component 加入到引用中
uobject 的 ARO 可以通过 `UE::GC::RegisterSlowImplementation` 标记为 slowARO，通过 `FSlowAROManager` 这个全局单例来管理

TODO：测试 FGCObject 的 ARO 不会在建立 cluster 寻找引用时调用？
#### Object Cluster
cluster root 的 outer，class 也会加入到这个 cluster 中

**TODO：看看 [UE4 垃圾回收（二）GC Cluster](https://zhuanlan.zhihu.com/p/133293284)，解释 `ClusterRootIndex`**
**TODO：[用UObjectHashTables管理UObjectHash](https://zhuanlan.zhihu.com/p/464960701) 中写道UObjectBase::EmitBaseReferences中有专门对Outer生成Reference 来保证 object 在的时候它的 outer 就不会被 gc，看完 GC 后再理解一下这段话**