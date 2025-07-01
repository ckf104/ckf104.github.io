### Collision and Trace
每个 primitive component 有自己的 collision channel 和 trace channel，以及对每个 collision channel 和 trace channel 的 response，response 有三种类型：ignore，overlap，block，这指示了与对应 channel 物体发生重叠时的处理。这些在文档 [Collision Overview](https://dev.epicgames.com/documentation/en-us/unreal-engine/collision-in-unreal-engine---overview) 中总结得非常好了，以及 [Collision Response Reference](https://dev.epicgames.com/documentation/en-us/unreal-engine/collision-response-reference-in-unreal-engine) 中记录了各个 collision channel 约定俗成的用法
唯一需要注意的是，对于 blocking hit，设置物体的 `Simulation Generates Hit Events` 属性为 true 就能产生 hit event，但对于 overlap，需要物体自身和 overlap 物体的 `bGenerateOverlapEvents` 属性同时为 true 才能产生 overlap event

trace channel 主要用于 ray cast，文档 [Traces Overview](https://dev.epicgames.com/documentation/en-us/unreal-engine/traces-in-unreal-engine---overview) 已经做了较好的总结

TODO：trace by channel 和 trace by object types 有啥区别，解释 sweep by channel，sweep by object type 和 sweep by profile 有什么区别，以及相应的参数 `FCollisionQueryParams`，`FCollisionResponseParams`，`FCollisionObjectQueryParams` 的各个字段的含义。`FCollisionQueryParams` 中有一个 `IgnoreMask`，它是怎么使用的，是不是和 body instance 中的 `MaskFilter` 一起用的。我看到一个汇总的函数是 `FBodyInstance::BuildBodyFilterData`，它会根据 `MaskFilter`，`CollisionResponses`，`ObjectType` 等等信息，创建出了 `FCollisionFilterData`
### Collision Setup
simple collision 保存在 `UBodySetup` 中，primitive component 函数提供了一个 `GetBodySetup` 虚函数，子类可以重载
```c++
virtual class UBodySetup* GetBodySetup();
```
文档 [Setting Up Collisions With Static Meshes](https://dev.epicgames.com/documentation/en-us/unreal-engine/setting-up-collisions-with-static-meshes-in-unreal-engine) 对如何在 static mesh editor 中设置 collision 讲得挺好
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
* 然后是调用 `UpdateOverlaps` 函数更新 component 此时的 overlap 状态。除了一路 sweep 过来得到的 `PendingOverlaps`，我们还需要知道在停止的位置上有哪些 overlaps，这里一个优化是说，在大部分情况下，停止位置的 overlaps 是包含在 `PendingOverlaps` 里的（除非用户还修改了 rotation，并且 `AreSymmetricRotations` 返回 false，表明旋转后可能引入了新的 overlaps），因此只需要检测 `PendingOverlaps` 中的物体是否还与自己有 overlap 即可（此时 `bIncludesOverlapsAtEnd` 为 true）。否则需要调用 `UPrimitiveComponent::ComponentOverlapMultiImpl` 函数来检测在当前位置还与哪些物体 overlap
* primitive component 的 `OverlappingComponents` 字段保存了当前有 overlap 的物体，如果更新位置后有新的 overlap，那么调用 `BeginComponentOverlap` 将新的 overlap 物体加入到 `OverlappingComponents` 中并触发各种 overlap 回调，对称地，会调用 `UPrimitiveComponent::EndComponentOverlap` 来将不再 overlap 的物体从 `OverlappingComponents` 中移除并触发各种 overlap 回调。`UpdateOverlaps` 函数最后会递归地对子 component 调用 `UpdateOverlaps` 函数
* 最后如果有 blocking hit，调用 blocking hit 相关的回调
* 在 `InternalSetWorldLocationAndRotation` 更新 component 的位置时，会触发 `UPrimitiveComponent::OnUpdateTransform` 回调，这个回调将 component 当前的位置同步给物理世界

与 overlap 相关的回调包括 `Actor::NotifyActorBeginOverlap`，`Actor::NotifyActorEndOverlap` 这两个可重载的虚函数，它们在 actor 中默认是实现是分别调用 `Actor::ReceiveActorBeginOverlap`，`Actor::ReceiveActorEndOverlap` 函数，后者这俩是 `BlueprintImplementableEvent` 的，可以在蓝图中重载。然后是 `Actor` 的 `OnActorBeginOverlap` 与 `OnActorEndOverlap` 字段，它们是两个动态多播。再者是 primitive component 的 `OnComponentBeginOverlap` 与 `OnComponentEndOverlap` 字段，它们也是两个动态多播

与 blocking hit 相关的回调包括 `Actor::NotifyHit` 这个可重载的虚函数，它在 actor 中默认是实现是调用 `Actor::ReceiveHit` 函数，后者是 `BlueprintImplementableEvent` 的，可以在蓝图中重载。然后是 actor 的 `OnActorHit` 字段以及 primitive component 的 `OnComponentHit` 字段，它们俩都是动态多播

然后区分 hit result 中一些容易混淆的字段，`impactNormal` 是碰撞点的被碰撞物体的法线，而 `Normal` 在大部分情况就是 `imapctNormal`，只有在 sphere trace 和 capsule trace 时表示这个 trace object 在碰撞点的法线。`impactPoint` 表示碰撞点，而 `Location` 则表示碰撞时物体所在的位置

前面提到当 `bsweep` 为 false 时，一个 cube 在碰撞到物体后还发生了转动，这并不是在 `MoveComponentImpl` 函数中实现的，这个函数就只会把 cube 移动到目标的位置，不管它现在是否发生重合了。断点调试发现物理系统那边的 `FPhysScene_Chaos::OnSyncBodies` 函数又调用 `MoveComponent` 函数把 cube 给挤出来了。而 `bsweep` 为 true 时不会发生转动是因为此时 cube 都不会移动到物体内部了，物理系统那边自然也不会把它给挤出来了，从而也没有旋转了
#### Scoped Movement Stack
它主要是对移动逻辑的优化，在例如 character movement component 等组件的移动中，为了找到合理的移动位置，可能会进行多次移动，每次移动都更新物理世界的位置之类的太费了，声明一个 `FScopedMovementUpdate` 后，child transform update，物理世界的坐标更新，以及 overlaps 和 blocking hit 事件的广播，都会推迟到 `FScopedMovementUpdate` 析构的时候进行

TODO：捋清移动有子节点的 primitive component 时碰撞逻辑，多个 component 时碰撞盒又是怎样的？如何设置 component 的碰撞盒（我直观上还是觉得应该是父子的碰撞，overlap 检测是相互独立的才对）
* 我把两个 cube 作为父子节点串一块，发现移动父节点时能够正常检测到子节点的碰撞，但好像 collision preset 用的是父节点的设置？即使子节点设置为 overlap 也依然发生的是 blocking hit。但尝试移动子节点时却发现没有检测到碰撞？子节点直接就飞了
* 说到底，多个 component 时 ue 是怎么选的碰撞盒
* 以及 `MoveComponentImpl` 的实现里会递归地调用子节点的 `UpdateOverlaps`，这里的碰撞盒又用的谁的呢（看起来就是根据子节点的碰撞盒更新子节点的 overlaps）
* 每个 mesh 的 simple / complex collision 又存储在哪的呢
#### Skeletal Mesh Component
skeletal mesh component 不处理 overlaps，但是它下边可能挂一些需要处理 overlaps 的子 component（例如武器），因此 `MoveComponentImpl` 的实现就是调用子 component 的 update overlaps 函数，更新它们的 overlap 情况（这样的实现的一个缺点就是子 component 的 overlap info 没有详细的几何数据，例如最初发生碰撞的位置，法线等等），另外，在动画改变了 skeletal mesh component 的 transform 后，子 component 的 overlaps 会类似地更新
### Movement Component
scene component 以及它的子类已经实现了关键的 `MoveComponentImpl` 函数。movement component 则负责管理和按照一些规则更新 scene component 的速度和加速度，并根据 scene component 的速度来调用 `MoveComponentImpl` 更新物体的位置。它的 `UpdatedComponent` 字段指定了需要管理的 scene component
```c++
	/**
	 * The component we move and update.
	 * If this is null at startup and bAutoRegisterUpdatedComponent is true, the owning Actor's root component will automatically be set as our UpdatedComponent at startup.
	 * @see bAutoRegisterUpdatedComponent, SetUpdatedComponent(), UpdatedPrimitive
	 */
	UPROPERTY(BlueprintReadOnly, Transient, DuplicateTransient, Category=MovementComponent)
	TObjectPtr<USceneComponent> UpdatedComponent;

	/** Current velocity of updated component. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category=Velocity)
	FVector Velocity;
```
`Velocity` 字段指明了当前的速度
#### Projectile Movement Component
通常用于投射物的移动。`InitialSpeed` 指明 spawn 出来后的初速度，速度方向由父类的 `Velocity` 字段控制。然后受到重力影响进行运动。默认没有空气阻力和摩擦等的模拟
```c++
	/** Initial speed of projectile. If greater than zero, this will override the initial Velocity value and instead treat Velocity as a direction. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category=Projectile)
	float InitialSpeed;
```
`bShouldBounce` 控制发生碰撞时应该反弹还是停止模拟。`Bounciness` 和 `Friction` 控制反弹时垂直碰撞平面方向的速度和平行平面方向的速度
```c++
	/** If true, simple bounces will be simulated. Set this to false to stop simulating on contact. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category=ProjectileBounces)
	uint8 bShouldBounce:1;

	/**
	 * Percentage of velocity maintained after the bounce in the direction of the normal of impact (coefficient of restitution).
	 * 1.0 = no velocity lost, 0.0 = no bounce. Ignored if bShouldBounce is false.
	 */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category=ProjectileBounces, meta=(ClampMin="0", UIMin="0"))
	float Bounciness;

	/**
	 * Coefficient of friction, affecting the resistance to sliding along a surface.
	 * Normal range is [0,1] : 0.0 = no friction, 1.0+ = very high friction.
	 * Also affects the percentage of velocity maintained after the bounce in the direction tangent to the normal of impact.
	 * Ignored if bShouldBounce is false.
	 * @see bBounceAngleAffectsFriction
	 */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category=ProjectileBounces, meta=(ClampMin="0", UIMin="0"))
	float Friction;
```
可以通过设置 `bIsHomingProjectile` 为 true 使得 projectile 跟踪目标
```c++
	/**
	 * If true, we will accelerate toward our homing target. HomingTargetComponent must be set after the projectile is spawned.
	 * @see HomingTargetComponent, HomingAccelerationMagnitude
	 */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category=Homing)
	uint8 bIsHomingProjectile:1;

	/**
	 * The current target we are homing towards. Can only be set at runtime (when projectile is spawned or updating).
	 * @see bIsHomingProjectile
	 */
	UPROPERTY(VisibleInstanceOnly, BlueprintReadWrite, Category=Homing)
	TWeakObjectPtr<USceneComponent> HomingTargetComponent;
```
#### Character Movement Component
参考了
* [Exploring in UE4：移动组件详解](https://zhuanlan.zhihu.com/p/34257208)
* [UE4的移动碰撞](https://zhuanlan.zhihu.com/p/33529865)：它里面获取碰撞以及 resolve penetration 的讨论再看看。TODO：他认为 `UPrimitiveComponent::MoveComponentImpl` 是优先选取非 start penetration 的 hit result？

Character Movement Component 中已经定义了若干移动模式，如果要禁止移动，可以调用 `UMovementComponent::StopMovementImmediately` 后将 movement mode 设置为 `MOVE_None`
##### Jump
character movement component 的 jump 逻辑受 character 的 `JumpKeyHoldTime` 和 `JumpMaxCount` 字段影响。`JumpKeyHoldTime` 是指一次 jump 的持续时间的最大值。所谓持续时间，就是在这段时间里会维持 jump 的初速度，不会受重力影响而减小。而 `JumpMaxCount` 指定可以在空中连续跳多少次
```c++
	/** 
	 * Jump key Held Time.
	 * This is the time that the player has held the jump key, in seconds.
	 */
	UPROPERTY(Transient, BlueprintReadOnly, VisibleInstanceOnly, Category=Character)
	float JumpKeyHoldTime;

    /**
     * The max number of jumps the character can perform.
     * Note that if JumpMaxHoldTime is non zero and StopJumping is not called, the player
     * may be able to perform and unlimited number of jumps. Therefore it is usually
     * best to call StopJumping() when jump input has ceased (such as a button up event).
     */
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Replicated, Category=Character)
    int32 JumpMaxCount;
```
以第三人称模板中 jump 的实现为例。每次按下空格键，就会调用 `ACharacter::Jump` 函数，它会将 `bPressedJump` 设置为 true
```c++
	/** When true, player wants to jump */
	UPROPERTY(BlueprintReadOnly, Category=Character)
	uint32 bPressedJump:1;
```
然后在 character movement component 进行 tick 时，检测到 `bPressedJump` 为 true，如果此时 `bWasJumping` 为 false，表明要触发新的跳跃，那么 `JumpCurrentCount` 加 1
```c++
	/** Tracks whether or not the character was already jumping last frame. */
	UPROPERTY(VisibleInstanceOnly, BlueprintReadOnly, Transient, Category=Character)
	uint32 bWasJumping : 1;

    /**
     * Tracks the current number of jumps performed.
     * This is incremented in CheckJumpInput, used in CanJump_Implementation, and reset in OnMovementModeChanged.
     * When providing overrides for these methods, it's recommended to either manually
     * increment / reset this value, or call the Super:: method.
     */
    UPROPERTY(VisibleInstanceOnly, BlueprintReadOnly, Category=Character)
    int32 JumpCurrentCount;
```
无论是触发新的跳跃了并且跳跃次数小于 `JumpMaxCount` 或者是 `bWasJumping` 为 true 但距离上一次触发新跳跃的时间还在 `JumpKeyHoldTime` 之内，都会执行 `UCharacterMovementComponent::DoJump` 函数，这个函数将 character 的 z 方向速度设置为 `JumpZVelocity`，并且将 movement mode 切换为 Falling
```c++
	/** Initial velocity (instantaneous vertical acceleration) when jumping. */
	UPROPERTY(Category="Character Movement: Jumping / Falling", EditAnywhere, BlueprintReadWrite, meta=(DisplayName="Jump Z Velocity", ClampMin="0", UIMin="0", ForceUnits="cm/s"))
	float JumpZVelocity;

	/**
	 * Actor's current movement mode (walking, falling, etc).
	 *    - walking:  Walking on a surface, under the effects of friction, and able to "step up" barriers. Vertical velocity is zero.
	 *    - falling:  Falling under the effects of gravity, after jumping or walking off the edge of a surface.
	 *    - flying:   Flying, ignoring the effects of gravity.
	 *    - swimming: Swimming through a fluid volume, under the effects of gravity and buoyancy.
	 *    - custom:   User-defined custom movement mode, including many possible sub-modes.
	 * This is automatically replicated through the Character owner and for client-server movement functions.
	 * @see SetMovementMode(), CustomMovementMode
	 */
	UPROPERTY(Category="Character Movement: MovementMode", BlueprintReadOnly)
	TEnumAsByte<enum EMovementMode> MovementMode;
```
一旦到达 `JumpKeyHoldTime` 或者用户松开空格键触发 `ACharacter::StopJumping` 回调或者落地结束 Falling 状态时，都会调用 `ACharacter::ResetJumpState`，重置 jump 的状态（不过仅有落地时会重置 `JumpCurrentCount`）
##### Walking
TODO：学了物理之后再来看看 `UMovementComponent::ResolvePenetrationImpl` 怎么处理的
TODO：看看 ``UCharacterMovementComponent` 中是怎么处理 Root Motion 的
TODO：一些尝试的实现：恒定速度，世界翻转，平台移动，斜坡上下滑

首先是 walking 的速度控制，`UCharacterMovementComponent::CalcVelocity` 中会更新 character 速度，主要有三个方面
* 当玩家按键指示移动方向时，我们调用 `AddMovementInput` 将这个移动方向更新到 `ControlInputVector` 中，它作为一个长度为 0 到 1 之间的向量会乘以 `MaxAcceleration`，作为这一帧的加速度，然后乘以 delta 时间更新到速度上
* `GroundFriction` 字段控制一个与速度成正比的摩擦力的大小
* `BrakingDecelerationWalking` 字段控制当加速度为 0（即玩家停止输入时）额外的减速大小
```c++
	/**
	 * Setting that affects movement control. Higher values allow faster changes in direction.
	 * If bUseSeparateBrakingFriction is false, also affects the ability to stop more quickly when braking (whenever Acceleration is zero), where it is multiplied by BrakingFrictionFactor.
	 * When braking, this property allows you to control how much friction is applied when moving across the ground, applying an opposing force that scales with current velocity.
	 * This can be used to simulate slippery surfaces such as ice or oil by changing the value (possibly based on the material pawn is standing on).
	 * @see BrakingDecelerationWalking, BrakingFriction, bUseSeparateBrakingFriction, BrakingFrictionFactor
	 */
	UPROPERTY(Category="Character Movement: Walking", EditAnywhere, BlueprintReadWrite, meta=(ClampMin="0", UIMin="0"))
	float GroundFriction;

	/**
	 * Deceleration when walking and not applying acceleration. This is a constant opposing force that directly lowers velocity by a constant value.
	 * @see GroundFriction, MaxAcceleration
	 */
	UPROPERTY(Category="Character Movement: Walking", EditAnywhere, BlueprintReadWrite, meta=(ClampMin="0", UIMin="0"))
	float BrakingDecelerationWalking;

	/** Max Acceleration (rate of change of velocity) */
	UPROPERTY(Category="Character Movement (General Settings)", EditAnywhere, BlueprintReadWrite, meta=(ClampMin="0", UIMin="0"))
	float MaxAcceleration;
```
具体如何进行移动在 [UE4的移动碰撞](https://zhuanlan.zhihu.com/p/33529865) 中已经讲得很清楚了。我额外再补充一些 character movement component 中与移动行为有关的字段
```c++
	/**
	 * Max angle in degrees of a walkable surface. Any greater than this and it is too steep to be walkable.
	 */
	UPROPERTY(Category="Character Movement: Walking", EditAnywhere, meta=(ClampMin="0.0", ClampMax="90.0", UIMin = "0.0", UIMax = "90.0", ForceUnits="degrees"))
	float WalkableFloorAngle;

	/** If true, Character can walk off a ledge. */
	UPROPERTY(Category="Character Movement: Walking", EditAnywhere, BlueprintReadWrite)
	uint8 bCanWalkOffLedges:1;

	/**
	 * Don't allow the character to perch on the edge of a surface if the contact is this close to the edge of the capsule.
	 * Note that characters will not fall off if they are within MaxStepHeight of a walkable surface below.
	 */
	UPROPERTY(Category="Character Movement: Walking", EditAnywhere, BlueprintReadWrite, AdvancedDisplay, meta=(ClampMin="0", UIMin="0", ForceUnits=cm))
	float PerchRadiusThreshold;
	/**
	 * When perching on a ledge, add this additional distance to MaxStepHeight when determining how high above a walkable floor we can perch.
	 * Note that we still enforce MaxStepHeight to start the step up; this just allows the character to hang off the edge or step slightly higher off the floor.
	 * (@see PerchRadiusThreshold)
	 */
	UPROPERTY(Category="Character Movement: Walking", EditAnywhere, BlueprintReadWrite, AdvancedDisplay, meta=(ClampMin="0", UIMin="0", ForceUnits=cm))
	float PerchAdditionalHeight;
```
`WalkableFloorAngle` 用于设置最大能走上的斜面坡度。`IsWalkable` 函数用它来判断该 floor 是否 walkable。`bCanWalkOffLedges` 用于指示 character 能否走下悬崖，当移动使得 floor 切换到 unwalkable 状态时，会调用 `CanWalkOffLedges` 函数来判断这个移动是否合法。`PerchRadiusThreshold` 和 `PerchAdditionalHeight` 限制栖息条件。下面两个条件同时满足时我们认为当前的 floor 不再 walkable 了（需要进入 falling 状态）
* 胶囊体向下 sweep 时碰撞点到胶囊体外侧的距离小于 `PerchRadiusThreshold`，这说明我们当前处于 floor 的边上
* 一个半径为角色胶囊体半径减去 `PerchRadiusThreshold` 的小胶囊体向下 sweep 时没有找到 walkable floor，`PerchAdditionalHeight` 参数提供了 sweep 的额外距离的控制。这说明我们睬的 floor 前面没有 floor 了（排除台阶这种情况）

floor 切换后，`AdjustFloorHeight` 函数会对胶囊体的高度进行调整，使其到 floor 在重力方向上的距离在 `MIN_FLOOR_DIST` 和 `MAX_FLOOR_DIST` 之间。不紧贴 floor 使得下次移动时不会马上就发生碰撞
##### Movment Base
然后我们讨论对 movement base 的处理，floor 切换时会调用 `SetBase` 并进一步调用 `SaveBaseLocation`（另外，`SetBase` 还会将 movement base 的 tick 函数设置为自己的依赖，这样保证 movement base 的 tick 函数总是在自己之前执行）以及在每帧 tick 调用的 `PerformMovement` 也会调用 `SaveBaseLocation`。`SaveBaseLocation` 中会将 movement base 的 location 和 rotation 设置到自己的 `OldBaseLocation` 和 `OldBaseQuat` 字段中
```c++
	/** Saved location of object we are standing on, for UpdateBasedMovement() to determine if base moved in the last frame, and therefore pawn needs an update. */
	FQuat OldBaseQuat;

	/** Saved location of object we are standing on, for UpdateBasedMovement() to determine if base moved in the last frame, and therefore pawn needs an update. */
	FVector OldBaseLocation;
```
在每帧调用的 `PerformMovement` 中会调用 `MaybeUpdateBasedMovement`，该函数根据新的 movement base 的新 location 和 rotation，结合之前保存的 `OldBaseQuat` 和 `OldBaseLocation`，就能对 character 的 location 和 rotation 进行更新，保持它们的相对位置和旋转不变

movement base 通常是当前的 floor。但如果 `bStayBasedInAir` 为 true，那么在空中也不会 clear base（这样在移动平台上原地跳的时候不至于落下去）。此时处于 falling 状态时会额外进行地板检测，向下 sweep 的距离由 `StayBasedInAirHeight` 指定，一旦检测到的 floor 和 movement base 不同，就将 movement base 置空
```c++
	/** Property to set if characters should stay based on objects while jumping */
	UPROPERTY(Category = "Character Movement: Jumping / Falling", EditAnywhere, BlueprintReadWrite)
	bool bStayBasedInAir = false;

	/** Property used to set how high above base characters should stay based on objects while jumping if bStayBasedInAir is set */
	UPROPERTY(Category = "Character Movement: Jumping / Falling", EditAnywhere, BlueprintReadWrite, meta = (editcondition = "bStayBasedInAir"))
	float StayBasedInAirHeight = 1000.0f;
```
当离开 movement base 时，会调用 `ApplyImpartedMovementBaseVelocity` 将 movement base 的速度和角速度加到 character 上
##### Falling
character 在空中时玩家的移动控制能力由 `AirControl` 指定，`AirControl` 越小，玩家对 character 的控制越弱
```c++
	/**
	 * When falling, amount of lateral movement control available to the character.
	 * 0 = no control, 1 = full control at max speed of MaxWalkSpeed.
	 */
	UPROPERTY(Category="Character Movement: Jumping / Falling", EditAnywhere, BlueprintReadWrite, meta=(ClampMin="0", UIMin="0"))
	float AirControl;
```
水平速度的更新同样使用 `CalcVelocity` 函数，不过现在摩擦系数和刹车速度由 `FallingLateralFriction` 和 `BrakingDecelerationFalling` 指定
```c++
	/**
	 * Friction to apply to lateral air movement when falling.
	 * If bUseSeparateBrakingFriction is false, also affects the ability to stop more quickly when braking (whenever Acceleration is zero).
	 * @see BrakingFriction, bUseSeparateBrakingFriction
	 */
	UPROPERTY(Category="Character Movement: Jumping / Falling", EditAnywhere, BlueprintReadWrite, meta=(ClampMin="0", UIMin="0"))
	float FallingLateralFriction;
	
	/**
	 * Lateral deceleration when falling and not applying acceleration.
	 * @see MaxAcceleration
	 */
	UPROPERTY(Category="Character Movement: Jumping / Falling", EditAnywhere, BlueprintReadWrite, meta=(ClampMin="0", UIMin="0"))
	float BrakingDecelerationFalling;
```
与 walking 状态不同，falling 状态会调用 `NewFallVelocity` 将重力加速度也考虑进来。其它部分就和 walking 差不多了，根据速度进行移动，然后如果碰撞了，要么找到 floor 切换到 walking 状态，要么像 walking 那样根据碰撞的法线调整移动方向