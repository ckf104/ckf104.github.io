
```c++
/** Array of level collections currently in this world. */
UPROPERTY(Transient, NonTransactional, Setter = None, Getter = None)
TArray<FLevelCollection>					LevelCollections;
```
`UWorld` 的 tick 函数中，会执行所有 tick group 的 tick，timer manager 的 tick，以及 tickable objects 的 tick 函数，然后更新 cameras
### Tick 流程
`UWorld::Tick`
-->`FTickTaskManager::StartFrame`
----> `FTickTaskLevel::QueueAllTicks`
----> `FTickTaskLevel::StartFrame`
------> `FTickTaskLevel::ScheduleTickFunctionCooldowns`
--> `FTickTaskManager::RunTickGroup`（`TG_PrePhysics`，`TG_StartPhysics`，`TG_DuringPhysics`，`TG_EndPhysics`，`TG_PostPhysics`）
----> `FTickTaskLevel::QueueNewlySpawned`
--> `FTimerManager::Tick`
--> `FTickableGameObject::TickObjects`
--> `FTickTaskManager::RunTickGroup`（`TG_PostUpdateWork`，`TG_LastDemotable`）
--> `FTickTaskManager::EndFrame`
----> `FTickTaskLevel::EndFrame`
------> `FTickTaskLevel::ScheduleTickFunctionCooldowns`

整个 tick group 的实现是基于 task graph，每个 `FTickFunction` 会被包装为一个 task 塞到 scheduler backend 的 game thread 的 queue 中。因此 `FTickFunction` 间的依赖关系会表现为 task 间的依赖关系，而根据 task 间的依赖调度和执行 task 的逻辑已经在 scheduler backend 中实现好了

每个 `FTickFunction` 可以设置 start tick group 和 end tick group，start tick group 指定应该在哪个 tick 阶段将 `FTickFunction` 压入 scheduler backend 的 queue 中，end tick group 指定在哪个阶段一定得执行该 tick 函数。这样设计的原因是如果设置 `CVarAllowAsyncTickDispatch` 为 true，dispatch tick 和 execute tick 可以并行执行（一个 worker thread 负责将 tick function 压入 scheduler backend 的 queue 中，而 game thread 负责执行）

但 start tick group 和 end tick group 是软性的设置，实际上由于 tick function 之间的依赖，或者 tick object 是在这个 group 新 spawn 出来的，它实际的 start / end tick group（保存在 `FTickFunction::InternalData` 的 `ActualStartTickGroup` 和 `ActualEndTickGroup` 字段中）可能晚于用户设置的 start / end tick group。但不会被放到 `TG_StartPhysics` 和 `TG_EndPhysics` 这俩 group 里。具体的逻辑见 `FTickFunction::QueueTickFunction`

`UWorld::Tick` 由上层的 engine 调用，UWorld 还有额外的两个 `FTickFunction`，它们分别在 `TG_StartPhysics` 和 `TG_EndPhysics` group 中调用，用于启动和结束物理模拟
#### Tick Interval
`FTickFunction` 存在 `TickInterval` 字段，用来指示多久 tick 一次，它的默认值为 0，表示每个 frame 都 tick

如果它的值大于 0，则在 `FTickTaskLevel::QueueAllTicks` 将该 tick function 加入 `FTickTaskSequencer` 后，会将该 tick function 从 `AllEnabledTickFunctions` 队列中移除。然后 `FTickTaskLevel::ScheduleTickFunctionCooldowns` 会将这些 tick function 的状态设置为 `CoolingDown`，并加入到 `AllCoolingDownTickFunctions` 链表中，等待下一次调度
#### Tick in Editor
```c++
	/** Should this component be ticked in the editor */
	uint8 bTickInEditor:1;
```
可以重载 `AActor::ShouldTickIfViewportsOnly` 或者设置 actor component 的 `bTickInEditor` 字段使得在 viewport 中也能 tick
#### Async Tick
```c++
	/** Can we tick this concurrently on other threads? */
	uint8 bAllowConcurrentTick:1;
```
actor component 中存在 `bAllowConcurrentTick` 字段，不过好像没有地方使用它。真正起作用的是 tick function 的 `bRunOnAnyThread` 字段，如果它为 true，则该 tick function 会放到 worker thread 上执行（这也是 end tick group 的用武之地）
### Game Pause
`UGameplayStatics::SetGamePaused` 接口调用 `APlayerController::SetPause` 来设置游戏暂停。最终的效果是设置了 `AWorldSettings` 的 `PauserPlayerState` 字段

`UWorld::Tick` 函数中根据 `AWorldSettings` 的 `PauserPlayerState` 非空来检查 game pause。如果发现 game pause，将跳过运行 tick group，而是执行 `FTickTaskManagerInterface::RunPauseFrame`

game mode 里 set game pause 具体对游戏有哪些影响，哪些 pause 了，哪些没有 pause。我测试起来 UMG 在暂停后仍然会 tick

例如 actor 中的 `SetTickableWhenPaused` 使得 actor 可以在 pause game 时继续 tick