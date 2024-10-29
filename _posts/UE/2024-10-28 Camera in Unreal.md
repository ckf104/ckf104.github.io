
根据 [cameras-in-unreal-engine](https://dev.epicgames.com/documentation/en-us/unreal-engine/cameras-in-unreal-engine) 解释 ViewTarget，`bFindCameraComponentWhenViewTarget`，`bTakeCameraControlWhenPossessed`
解释 playerController 和 actor 的 `CalcCamera` 函数，`PlayerCameraManager`
### CameraComponent

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

`UpdateCamera` 函数内调用 `DoUpdateCamera` 实际地对 `ViewTarget` 进行更新
其中调用了 `UpdateViewTarget`，其中有一堆 CameraStyle，默认的情况下调用 `UpdateViewTargetInternal` 函数，BlueprintImplementableEvent 没实现就返回 false
```c++
/** Current ViewTarget */
UPROPERTY(transient)
struct FTViewTarget ViewTarget;
```
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