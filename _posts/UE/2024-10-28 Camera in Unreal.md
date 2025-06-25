
根据 [cameras-in-unreal-engine](https://dev.epicgames.com/documentation/en-us/unreal-engine/cameras-in-unreal-engine) 解释 ViewTarget，`bFindCameraComponentWhenViewTarget`，`bTakeCameraControlWhenPossessed`
解释 playerController 和 actor 的 `CalcCamera` 函数，`PlayerCameraManager`
### CameraComponent
TODO：解释它的 `GetCameraView` 函数
### CameraActor
在 PIE 模式下，`UGameInstance::StartPlayInEditorGameInstance` 函数调用 `ULocalPlayer::SpawnPlayActor`，这个函数中调用了 player controller 的 `onPossess` 函数，触发了后面的设置 view target 的逻辑。但是 `UWorld::BeginPlay` 是在 `ULocalPlayer::SpawnPlayActor` 后才调用的，因此设置初始的 view target 时 player controller 调用 `GetAutoActivateCameraForPlayer` 寻找 world 中的 camera actor 时总是找不到的，因为此时 camera actor 的 `BeginPlay` 还没被调用，它还没把自己注册到 world 的 `AutoCameraActorList` 中去。不太确定 game 模式下会不会不太一样

### SpringArmComponent
spring arm component 的主要作用是作为一个弹簧臂，实现第三人称视角。直观一想可能会觉得没必要，因为直接修改 camera component 相对于 actor 的位置就可以了。但 spring arm component 额外实现了一些功能，一个是相机方位，朝向的渐变（当然是通过插值之类的来实现，但我感觉用处没那么大，因为通常相机的方位改变就是渐变的，只要帧率够高看起来就是连续的了）。另外一个很符合它的名称，就是弹簧臂的伸缩。因为对于第三人称视角，有可能相机和人之间存在障碍物。如果 `bDoCollisionTest` 为真，那么 spring arm 会每个 tick 中检查这一点，如果发现了障碍物，那么就将弹簧臂缩短，保证相机和人之间没有障碍物

它重载了 scene component 的 `QuerySupportedSockets` 和 `GetSocketTransform` 方法。实际上也就一个 socke name
```c++
/** The name of the socket at the end of the spring arm (looking back towards the spring arm origin) */
static ENGINE_API const FName SocketName;
```
而它重载的 `GetSocketTransform` 方法返回的不再是自己的 `ComponentToWorld` 成员，而是由 spring arm 的端点的坐标和旋转构成的 `FTransform`，因为通常 spring arm 会挂一个 camera component 作为子节点，而通常 camera component 不会还相对于父节点做旋转变换，而 camera component 的 `GetCameraView` 方法使用 camera component 的位置和旋转设置 `ViewTarget.POV`，这使得最终 spring arm 返回的 `GetSocketTransform` 作为相机的位置和旋转

spring arm 的核心逻辑在 `UpdateDesiredArmLocation` 函数中，这个函数在每个 tick 都会被调用。它负责对相机位置进行更新，其中调用 `GetTargetRotation` 函数获取旋转朝向，当 `bUsePawnControlRotation` 为 true 时，使用 controller 的 control rotation，否则使用 spring arm 自身的旋转朝向（这通常不是第三人称视角所希望的控制，因为 spring arm 通常会 attach 到 pawn 身上，pawn 旋转之后它跟着转，容易把玩家转晕了）。另外 `UpdateDesiredArmLocation` 还会处理障碍物检测以及相机方位，朝向的渐变等逻辑（这里的渐变和 player camera manager 中的渐变有些区别，player camera manager 中的渐变是处理 view target 的切换）
#### Lagging
有时候人物的位置，或者旋转方向发生迅速的变化，我们不希望摄像机也跟着迅速变，否则画面看着就很晕。一个典型的例子是人物上台阶，上一个台阶的时候，人物在 z 轴的位置会迅速变化，如果摄像机始终对准人物的话，会导致画面抖动。因此 spring arm 的 `bEnableCameraLag` 和 `bEnableCameraRotationLag` 参数控制是否启用 location 和 rotation 的 lagging，而 `CameraLagSpeed` 和 `CameraRotationLagSpeed` 指定摄像机位置和朝向变化的最大速度

对于第三人称视角，如果使用 spring arm + camera component 的设置，应该将 spring arm 的 `bUsePawnControlRotation` 设置为 true（同时记得设置 `bInheritPitch`，`bInheritYaw`，`bInheritRoll` 为 true，否则不会生效），而 camera component 的 `bUsePawnControlRotation` 值设置为 true/false 都不影响。因为不论 camera component 的此字段是 true 还是 false，只要 spring arm 的此字段为 true，最终相机的旋转方向就会与 controller 的 control rotation 一致。如果把 spring arm 和 camera component 的此字段值都设置为 false，那表现就是上面提到的 camera 跟着 pawn 一块转。但如果是 spring arm 的此字段值设为 false，而 camera component 为 true，最终的表现就会很奇怪。主要的原因在于此时 spring arm 的 rotation 是跟着 pawn 走的，如果移动时改变了朝向，那 spring arm 的朝向也跟着改，使得 camera 的位置发生大幅变化，但 camera 的 rotation 又没变，这操作起来就很奇怪了
#### Target Offset vs Socket Offset
从名字上就能看出来，target offset 就是相对于摄像机的对象的偏移，而通常 camera component 会作为 spring arm component 的子节点挂着，因此 socket offset 就是摄像机的位置偏移
因此这俩 offset 实际上指定了 spring arm 的两个端点的偏移，用代码表示为（具体的逻辑在 `UpdateDesiredArmLocation` 函数中）
```c++
FVector Origin = GetComponentLocation() + TargetOffset;
FVector EndPoint -= DesiredRot.Vector() * TargetArmLength + FRotationMatrix(DesiredRot).TransformVector(SocketOffset);
```
其中 `TargetArmLength` 指定 spring arm 的长度，而 `DesiredRot` 是 spring arm 相对于世界坐标的旋转方向。这也可以看到另外一个区别，即 target offset 指定的偏移是世界坐标的偏移，而 socket offset 指定的偏移是局部坐标的偏移

一种直观理解两个 offset 的区别的方法是，设想 spring arm 绕着 z 轴旋转，那么 target offset 实际上偏移了旋转的中心，而 socket offset 不改变旋转中心，只是偏移一下 spring arm 的末端点的值。不过这两个 offset 最终影响的是 camera 的位置，camera 的旋转方向由这里的 `DesiredRot` 决定

### 第三人称模板的实现
TODO






`UWorld` 的以下字段记录了游戏中所有的 controller
```c++
/** List of all the controllers in the world. */
TArray<TWeakObjectPtr<class AController> > ControllerList;
/** List of all the player controllers in the world. */
TArray<TWeakObjectPtr<class APlayerController> > PlayerControllerList;
```
在 `UWorld` 的 tick 函数中，执行完所有 tick group，TimerManager，以及 tickable objects 的 tick 后，会执行所有 player controller 的 `UpdateCameraManager` 函数

player controller 中默认的实现就是调用自己的 player camera manager 的 `UpdateCamera` 函数，player camera manager 的类型由 `PlayerCameraManagerClass` 字段决定，默认是 `APlayerCameraManager`
```c++
/** Camera manager associated with this Player Controller. */
UPROPERTY(BlueprintReadOnly, Category=PlayerController)
TObjectPtr<APlayerCameraManager> PlayerCameraManager;

/** PlayerCamera class should be set for each game, otherwise Engine.PlayerCameraManager is used */
UPROPERTY(EditAnywhere, BlueprintReadOnly, Category=PlayerController)
TSubclassOf<APlayerCameraManager> PlayerCameraManagerClass;
```
### PlayerCameraManager
`UpdateCamera` 函数的核心任务就是更新 `ViewTarget`，它内部调用 `DoUpdateCamera` 实际地对 `ViewTarget` 进行更新
```c++
/** Current ViewTarget */
UPROPERTY(transient)
struct FTViewTarget ViewTarget;
```
`DoUpdateCamera` 首先调用 `FTViewTarget::CheckViewTarget` 根据当前的 player controller 以及一些规则，检查 `ViewTarget` 的 `Target` 以及 `PlayerState` 字段的值是否合理或者做一些调整。然后调用了 `UpdateViewTarget`，首先会根据自己的字段来设置 `ViewTarget.POV` 的默认值，例如 `ViewTargetPOV.AspectRatio` 的值设置为 `PlayerCameraManager.DefaultAspectRatio`。然后根据当前的 `CameraStyle` 的设置进行不同的处理，默认的情况下调用 `UpdateViewTargetInternal` 函数
而在 `UpdateViewTargetInternal` 中首先调用 `BlueprintUpdateCamera` 函数，这是一个由蓝图重载的函数
```c++
/** 
* Blueprint hook to allow blueprints to override existing camera behavior or implement custom cameras.
* If this function returns true, we will use the given returned values and skip further calculations to determine
* final camera POV. 
*/
UFUNCTION(BlueprintImplementableEvent, BlueprintCosmetic)
ENGINE_API bool BlueprintUpdateCamera(AActor* CameraTarget, FVector& NewCameraLocation, FRotator& NewCameraRotation, float& NewCameraFOV);
```
如果蓝图子类重载了该函数，并且返回 true，那么 `ViewTarget.POV` 就会使用它返回的 `NewGetViewRotationCameraLocation` 等参数作为相机的 location, rotation 以及 fov，`ViewTarget.POV` 中其它的字段则使用 Player Camera Manager 中相应的成员字段，例如 `ViewTarget.POV.AspectRatio` 的值设置为 `PlayerCameraManager.DefaultAspectRatio`

否则，调用 `ViewTarget.Target` 的 `CalcCamera` 函数，`Actor::CalcCamera` 是一个虚函数。我们先看看 Actor 中的默认实现。如果 Actor 的 `bFindCameraComponentWhenViewTarget` 字段为 true，那么它会寻找第一个 Actor 中的 Camera Component，然后调用 Camera Component 的 `GetCameraView` 函数来设置 `ViewTarget.POV`。如果没有找到 Camera Component 或者`bFindCameraComponentWhenViewTarget` 为 false，那么调用 `GetActorEyesViewPoint` 这个虚函数来设置 `ViewTarget.POV` 的 location 和 rotation。这个虚函数默认的实现是使用 actor 自身的 location 和 rotation 对 `ViewTarget.POV` 进行更新，pawn 类型对其进行了重载，它设置 location 还额外考虑了 `BaseEyeHeight` 参数，rotation 则使用 controller 的 `ControlRotation` 字段

一个典型的重载是 `APlayerController::CalcCamera`，它调用 `GetFocalLocation` 和 `GetControlRotation` 来设置 `ViewTarget.POV` 的位置和旋转，前者返回的是 player controller 控制的 pawn 的位置，后者返回的是 controller 的 `ControlRotation` 字段

`UpdateViewTarget` 在调用完 `UpdateViewTargetInternal` 函数后，还调用了 `ApplyCameraModifiers` 与 `UpdateCameraLensEffects`，前者是调用 `UCameraModifier` 类的接口对 `ViewTarget.POV` 进行用户自定义的调整。后者与 `ICameraLensEffectInterface` 相关

在游戏开始时，会调用 `APlayerController::OnPossess`，如果 `bAutoManageActiveCameraTarget` 为 true，那么经过一系列的调用堆栈，最终会调用 `APlayerController::AutoManageActiveCameraTarget` 函数，这个函数接受一个 `SuggestedTarget` 参数，通常就是 pawn。该函数选择 view target 的逻辑是：调用 `GetAutoActivateCameraForPlayer` 函数，如果返回的 camera actor 不为空，那么使用这个 camera actor 作为 view target。否则选择 `SuggestedTarget` 作为 view target。`GetAutoActivateCameraForPlayer` 函数的逻辑也很简单，它遍历场景中的 camera actor，如果某个 camera actor 的 `AutoActivateForPlayer` 字段的值为自己的 player controller 编号，那么就返回这个 camera actor，否则返回空

`APlayerController::SetViewTarget` 函数负责设置 view taregt，它只是 `APlayerCameraManager::SetViewTarget` 的 wrapper
```c++
/** 
* Sets a new ViewTarget.
* @param NewViewTarget - New viewtarget actor.
* @param TransitionParams - Optional parameters to define the interpolation from the old viewtarget to the new. Transition will be instant by default.
*/
ENGINE_API virtual void SetViewTarget(class AActor* NewViewTarget, FViewTargetTransitionParams TransitionParams = FViewTargetTransitionParams());
```
`APlayerCameraManager::SetViewTarget` 除了接收 view target 参数外，还接受一个 transition params，指明在切换 view target 时 camera animation 如何做。如果不考虑 camera animation 相关的逻辑，这个函数主要是调用 `AssignViewTarget` 实际地设置 `ViewTarget.Target`，然后调用 `BecomeViewTarget` 等回调，广播函数。然后调用 `CheckViewTarget`，它负责对 `ViewTarget.Target` 的合理性进行检查和设置 `ViewTarget.PlayerState`
### View Target Blending
在 `APlayerCameraManager::DoUpdateCamera` 函数的最后，调用了 `APlayerCameraManager::FillCameraCache` 函数来将更新的 view target 的 POV 信息填入 `CameraCachePrivate` 字段中。实际上 player camera manager 会 cache 两帧的 pov 信息
```c++
	/** Cached camera properties. */
	UPROPERTY(transient)
	struct FCameraCacheEntry CameraCachePrivate;

	/** Cached camera properties, one frame old. */
	UPROPERTY(transient)
	struct FCameraCacheEntry LastFrameCameraCachePrivate;
```
为什么不直接使用 `ViewTarget.POV` 呢，还要额外引入这个 cache 字段。我认为这和 view target blending 有关。当切换 view target 对象，且启用 blending 时，新的 view target 的信息存在 `PendingViewTarget` 中，在 blending 过程中，每次 `DoUpdateCamera` 会同时更新 `PendingViewTarget` 和 `ViewTarget` 的信息。除非 transition param 中 `bLockOutgoing` 为 true，那么 `ViewTarget` 将不会被更新。直到 blending 结束，`PendingViewTarget` 的信息更新到 `ViewTarget` 中，然后将 `PendingViewTarget` 置空。那么在 blending 过程中，实际的 POV 信息实际上是 `ViewTarget` 和 `PendingViewTarget` 的插值，这个结果我们就保存在 `CameraCachePrivate` 中
### Interaction with Rendering System
local player 是与 rendering system 沟通的桥梁，它在 `ULocalPlayer::CalcSceneView` 函数中创建 `FSceneView`，并将 player camera manager 的 `CameraCachePrivate` 的 pov 信息也存入到 `FSceneView` 中
### FTViewTarget

`FViewTarget` 的组成
```c++
/** Target Actor used to compute POV */
UPROPERTY(EditAnywhere, BlueprintReadWrite, Category=TViewTarget)
TObjectPtr<class AActor> Target;

/** Computed point of view */
UPROPERTY(EditAnywhere, BlueprintReadWrite, Category=TViewTarget)
struct FMinimalViewInfo POV;

/** PlayerState (used to follow same player through pawn transitions, etc., when spectating) */
UPROPERTY(EditAnywhere, BlueprintReadWrite, Category=TViewTarget)
TObjectPtr<class APlayerState> PlayerState;
```
TODO：camera animation

TODO：`UWorld` 的 player controller 从哪来的，我可以继承重载吗

TODO：
```c++
/** UPlayer associated with this PlayerController.  Could be a local player or a net connection. */
UPROPERTY()
TObjectPtr<UPlayer> Player;
```
`UPlayer` 的作用是啥

TODO：看看 component 的 register 和 activate 函数（我感觉场景中一开始就有的 actor 会自动 register 它所有的 component，但 activate 是这样吗

TODO：解释 `ICameraLensEffectInterface`，以及 `UCameraModifier`，UE 中有许多已经实现好的 `UCameraModifier`，例如 `UCameraModifier_CameraShake`

TODO：对这些出现的类的功能定位进行总结：player controller, player camera manager, camera component, view target, camera modifier 等等

TODO：看看 UE 的 stereo rendering 的实现，它需要 camera 等做哪些额外的事情（standford 的课 [ EE267: Virtual Reality](https://stanford.edu/class/ee267/)