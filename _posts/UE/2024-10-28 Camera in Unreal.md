
根据 [cameras-in-unreal-engine](https://dev.epicgames.com/documentation/en-us/unreal-engine/cameras-in-unreal-engine) 解释 ViewTarget，`bFindCameraComponentWhenViewTarget`，`bTakeCameraControlWhenPossessed`
解释 playerController 和 actor 的 `CalcCamera` 函数，`PlayerCameraManager`
### CameraComponent
TODO：解释它的 `GetCameraView` 函数
### CameraActor


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
`DoUpdateCamera` 首先调用 `FTViewTarget::CheckViewTarget` 更新 `ViewTarget` 的 `Target` 以及 `PlayerState` 字段，然后调用了 `UpdateViewTarget`，首先会根据自己的字段来设置 `ViewTarget.POV` 的默认值，例如 `ViewTargetPOV.AspectRatio` 的值设置为 `PlayerCameraManager.DefaultAspectRatio`。然后根据当前的 `CameraStyle` 的设置进行不同的处理，默认的情况下调用 `UpdateViewTargetInternal` 函数
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

否则，调用 `ViewTarget.Target` 的 `CalcCamera` 函数，`Actor::CalcCamera` 是一个虚函数。我们先看看 Actor 中的默认实现。如果 Actor 的 `bFindCameraComponentWhenViewTarget` 字段为 true，那么它会寻找第一个 Actor 中的 Camera Component，然后调用 Camera Component 的 `GetCameraView` 函数来设置 `ViewTarget.POV`。如果没有找到 Camera Component 或者`bFindCameraComponentWhenViewTarget` 为 false，那么就使用 actor 自身的 location 和 rotation 对 `ViewTarget.POV` 进行更新

一个典型的重载是 `APlayerController::CalcCamera`，它调用 `GetFocalLocation` 和 `GetControlRotation` 来设置 `ViewTarget.POV` 的位置和旋转，前者返回的是 player controller 控制的 pawn 的位置，后者返回的是 controller 的 `ControlRotation` 字段
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


TODO：`UWorld` 的 player controller 从哪来的，我可以继承重载吗

TODO：
```c++
/** UPlayer associated with this PlayerController.  Could be a local player or a net connection. */
UPROPERTY()
TObjectPtr<UPlayer> Player;
```
`UPlayer` 的作用是啥

TODO：实现多相机切换，以及相机切换时的渐变过渡

TODO：看看如何从 `ViewTarget.POV` 得到透视矩阵