### Collision and Trace
每个 primitive component 有自己的 collision channel 和 trace channel，以及对每个 collision channel 和 trace channel 的 response，response 有三种类型：ignore，overlap，block，这指示了与对应 channel 物体发生重叠时的处理。这些在文档 [Collision Overview](https://dev.epicgames.com/documentation/en-us/unreal-engine/collision-in-unreal-engine---overview) 中总结得非常好了，以及 [Collision Response Reference](https://dev.epicgames.com/documentation/en-us/unreal-engine/collision-response-reference-in-unreal-engine) 中记录了各个 collision channel 约定俗成的用法
唯一需要注意的是，对于 blocking hit，设置物体的 `Simulation Generates Hit Events` 属性为 true 就能产生 hit event，但对于 overlap，需要物体自身和 overlap 物体的 `bGenerateOverlapEvents` 属性同时为 true 才能产生 overlap event

trace channel 主要用于 ray cast，文档 [Traces Overview](https://dev.epicgames.com/documentation/en-us/unreal-engine/traces-in-unreal-engine---overview) 已经做了较好的总结
### API
scene component 提供的外部接口
```c++
ENGINE_API void SetWorldLocation(FVector NewLocation, bool bSweep=false, FHitResult* OutSweepHitResult=nullptr, ETeleportType Teleport = ETeleportType::None);
ENGINE_API void AddWorldOffset(FVector DeltaLocation, bool bSweep=false, FHitResult* OutSweepHitResult=nullptr, ETeleportType Teleport = ETeleportType::None);
ENGINE_API void AddWorldRotation(const FQuat& DeltaRotation, bool bSweep=false, FHitResult* OutSweepHitResult=nullptr, ETeleportType Teleport = ETeleportType::None);
// 等等类似的接口
```
这些函数最终都会调用 `SetRelativeLocationAndRotation`

这里有一个 `bComponentToWorldUpdated`，我感觉是用来表示 `ComponentToWorld` 成员是否与 `relativexxx` 成员保持一致，看起来就是用来做一个 lazy 的 initialize，虽然很怀疑这是否有必要

Component 的移动最核心的函数是
```c++
ENGINE_API virtual bool MoveComponentImpl(const FVector& Delta, const FQuat& NewRotation, bool bSweep, FHitResult* Hit = NULL, EMoveComponentFlags MoveFlags = MOVECOMP_NoFlags, ETeleportType Teleport = ETeleportType::None);
```
scene component 默认的实现非常简单，就是更新该 component 和子 component 的变换就行了

在讨论 primitive component 的 `MoveComponentImpl` 实现前，下面是用蓝图移动 primitive component 时观察到的现象
* 如果 `bsweep` 为 false，在碰撞到物体后还发生了转动（这看起来更加真实），但我没理解这个转动是如何发生的，我猜测应该和 overlap 的检测有关，就是 UpdateOverlaps 相关的函数，但不太确定。而 `bsweep` 为 true 时则不会有转动
* 如果 `bsweep` 为 true，且有重力和物理碰撞，cube 移动时会直接与地板碰撞，导致 cude 没法移动，一个相同问题的帖子 [Moving objects with sweep enabled not working if they are touching the floor and gravity enabled](https://forums.unrealengine.com/t/moving-objects-with-sweep-enabled-not-working-if-they-are-touching-the-floor-and-gravity-enabled/1814530)，但没人回复。但我发现如果移动的方向稍微向上一点（z > 0），就能够动起来了，不知道 UE 里面是咋搞的

现在我们看一下 primitive component 的实现 ，它的流程大概是
* 首先是确认并将 component 移动到终点位置
	* 对于 non sweep 的情形，类似于 scene component，就直接设置为终点坐标即可
	* 而对于 non sweep 情形，会调用 `UWorld::ComponentSweepMulti` 函数来获取一路上的 hit 物体。这里的 hit 有 blocking hit 和 overlap hit，如果 hit result 的 `bStartPenetrating` 为真，说明在 sweep 前这俩物体就有重叠了，但如果移动的方向是两物体分离的趋势，即 hit result 的 `impactNormal` 与移动方向的夹角小于 90 度，那么就会忽略这个 hit result，这就是为什么上面观察到 cube 的移动方向稍微向上一点就能够动起来了。因为 ue 判定贴在地面的物体与地面有初始重叠，当设置移动方向向上一点时才能使其忽略这个初始的碰撞结果。然后 overlap hit 的结果保存在 `PendingOverlaps` 中。component 的终点坐标设置为最早发生 blocking hit 的位置
* 然后是调用 `UpdateOverlaps` 函数更新 component 此时的 overlap 状态。这里一个优化是对于 sweep 的情形，由于已经知道一路上有哪些 overlap hit 了，因此只需要检测这些 overlap hit 对应的 primitive component 此时是否还和本 component 有 overlap 就行了。否则需要调用 `UPrimitiveComponent::ComponentOverlapMultiImpl` 函数来走一遍完整的 overlap 检测。primitive component 的 `OverlappingComponents` 字段保存了当前有 overlap 的物体，如果更新位置后有新的 overlap，那么调用 `BeginComponentOverlap` 将新的 overlap 物体加入到 `OverlappingComponents` 中并触发各种 overlap 回调，对称地，会调用 `UPrimitiveComponent::EndComponentOverlap` 来将不再 overlap 的物体从 `OverlappingComponents` 中移除并触发各种 overlap 回调。`UpdateOverlaps` 函数最后会递归地对子 component 调用 `UpdateOverlaps` 函数
* 最后如果有 blocking hit，调用 blocking hit 相关的回调

与 overlap 相关的回调包括 `Actor::NotifyActorBeginOverlap`，`Actor::NotifyActorEndOverlap` 这两个可重载的虚函数，它们在 actor 中默认是实现是分别调用 `Actor::ReceiveActorBeginOverlap`，`Actor::ReceiveActorEndOverlap` 函数，后者这俩是 `BlueprintImplementableEvent` 的，可以在蓝图中重载。然后是 `Actor` 的 `OnActorBeginOverlap` 与 `OnActorEndOverlap` 字段，它们是两个动态多播。再者是 primitive component 的 `OnComponentBeginOverlap` 与 `OnComponentEndOverlap` 字段，它们也是两个动态多播

与 blocking hit 相关的回调包括 `Actor::NotifyHit` 这个可重载的虚函数，它在 actor 中默认是实现是调用 `Actor::ReceiveHit` 函数，后者是 `BlueprintImplementableEvent` 的，可以在蓝图中重载。然后是 actor 的 `OnActorHit` 字段以及 primitive component 的 `OnComponentHit` 字段，它们俩都是动态多播

然后区分 hit result 中一些容易混淆的字段，`impactNormal` 是碰撞点的被碰撞物体的法线，而 `Normal` 在大部分情况就是 `imapctNormal`，只有在 sphere trace 和 capsule trace 时表示这个 trace object 在碰撞点的法线。`impactPoint` 表示碰撞点，而 `Location` 则表示碰撞时物体所在的位置

前面提到当 `bsweep` 为 false 时，一个 cube 在碰撞到物体后还发生了转动，这并不是在 `MoveComponentImpl` 函数中实现的，这个函数就只会把 cube 移动到目标的位置，不管它现在是否发生重合了。断点调试发现物理系统那边的 `FPhysScene_Chaos::OnSyncBodies` 函数又调用 `MoveComponent` 函数把 cube 给挤出来了。而 `bsweep` 为 true 时不会发生转动是因为此时 cube 都不会移动到物体内部了，物理系统那边自然也不会把它给挤出来了，从而也没有旋转了

TODO：scene component 中的 ScopedMovementStack 是干嘛的 
TODO：捋清移动有子节点的 primitive component 时碰撞逻辑，多个 component 时碰撞盒又是怎样的？如何设置 component 的碰撞盒（我直观上还是觉得应该是父子的碰撞，overlap 检测是相互独立的才对）
* 我把两个 cube 作为父子节点串一块，发现移动父节点时能够正常检测到子节点的碰撞，但好像 collision preset 用的是父节点的设置？即使子节点设置为 overlap 也依然发生的是 blocking hit。但尝试移动子节点时却发现没有检测到碰撞？子节点直接就飞了
* 说到底，多个 component 时 ue 是怎么选的碰撞盒
* 以及 `MoveComponentImpl` 的实现里会递归地调用子节点的 `UpdateOverlaps`，这里的碰撞盒又用的谁的呢
* 每个 mesh 的 simple / complex collision 又存储在哪的呢
TODO：skeletal mesh component 的 `MoveComponentImpl` 实现
### Movement Component
TODO