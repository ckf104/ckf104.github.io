
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
--> `FTimerManager::Tick`
--> `FTickableGameObject::TickObjects`
--> `FTickTaskManager::RunTickGroup`（`TG_PostUpdateWork`，`TG_LastDemotable`）

整个 tick group 的实现是基于 task graph，每个 `FTickFunction` 会被包装为一个 task 塞到 scheduler backend 的 game thread 的 queue 中。因此 `FTickFunction` 间的依赖关系会表现为 task 间的依赖关系，而根据 task 间的依赖调度和执行 task 的逻辑已经在 scheduler backend 中实现好了

每个 `FTickFunction` 可以设置 start tick group 和 end tick group，start tick group 指定应该在哪个 tick 阶段将 `FTickFunction` 压入 scheduler backend 的 queue 中，end tick group 指定在哪个阶段一定得执行该 tick 函数。这样设计的原因是如果设置 `CVarAllowAsyncTickDispatch` 为 true，dispatch tick 和 execute tick 可以并行执行（一个 worker thread 负责将 tick function 压入 scheduler backend 的 queue 中，而 game thread 负责执行）

TODO：解释因为 spawn 以及 依赖导致 start tick group 和 end tick group 是 soft
TODO：解释 tick interval
### Game Pause
`UGameplayStatics::SetGamePaused` 接口调用 `APlayerController::SetPause` 来设置游戏暂停。最终的效果是设置了 `AWorldSettings` 的 `PauserPlayerState` 字段

`UWorld::Tick` 函数中根据 `AWorldSettings` 的 `PauserPlayerState` 非空来检查 game pause。如果发现 game pause，将跳过运行 tick group，而是执行 `FTickTaskManagerInterface::RunPauseFrame`

game mode 里 set game pause 具体对游戏有哪些影响，哪些 pause 了，哪些没有 pause。我测试起来 UMG 在暂停后仍然会 tick

例如 actor 中的 `SetTickableWhenPaused` 使得 actor 可以在 pause game 时继续 tick