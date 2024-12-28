### Collision and Trace

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

现在我们看一下 primitive component 的实现 

当条件为 enable gravity，然后移动时带一点 z 方向的分量时，`UPrimitiveComponent::MoveComponentImpl` 中会判定跳过该 hit，因为它是一个初始的 hit，并且有外逃趋势

移动完成后调用 updateOverlaps 更新 overlap，会递归地调用子 component 的 updateOverlaps 进行更新

FPhysScene_Chaos::OnSyncBodies 函数负责又把 cube 挤出来了

TODO： overlap 部分
TODO：scene component 中的 ScopedMovementStack 是干嘛的 

TODO：在实际测试 primitive component 时观察到的几个现象
* 如果 `bsweep` 为 false，在碰撞到物体后还发生了转动（这看起来更加真实），但我没理解这个转动是如何发生的，我猜测应该和 overlap 的检测有关，就是 UpdateOverlaps 相关的函数，但不太确定。而 `bsweep` 为 true 时则不会有转动（我猜测是因为它是缓缓扫过去的，因此不会像 `bsweep` 为 false 时穿到内部去然后再根据 overlap 机制弹出来了）
* 如果 `bsweep` 为 true，且有重力和物理碰撞，cude 移动时会直接与地板碰撞，导致 cude 没法移动，一个相同问题的帖子 [Moving objects with sweep enabled not working if they are touching the floor and gravity enabled](https://forums.unrealengine.com/t/moving-objects-with-sweep-enabled-not-working-if-they-are-touching-the-floor-and-gravity-enabled/1814530)，但没人回复。但我发现如果移动的方向稍微向上一点（z > 0），就能够动起来了，不知道 UE 里面是咋搞的
### Movement Component
TODO