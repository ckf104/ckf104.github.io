GameStatics 这个 blueprint function library 中提供了 `OpenLevel` 函数用来做 level transition

level transition 的请求在下一次 tick 时调用

`UGameEngine::Tick` 会调用 `UEngine::TickWorldTravel`，它会检查 word context 的 `TravelURL` 是否为空，如果不为空将开始 level transition
```c++
	/** URL to travel to for pending client connect */
	FString TravelURL;
```

哪些类会销毁？例如 `UWidget` 会被销毁吗，另外 `UWidget` 和 `SWidget` 是怎么注册到屏幕上的

整个 world 是如何序列化的，又是如何被加载上来的。解释 world 和 package 的 fully load 含义，包括 world context 的 `PackagesToFullyLoad` 字段
### World Creation
`UEngine::LoadMap` 是 world creation 的核心，flow 已经在 lyra notes 中讨论过了

可以看到 world，game mode，player controller 等等都重新创建了，并走了一遍完整的初始化流程，然后 game instance 和 local player 是依然存在的
### Current World Tracking
`FWorldContext` 为在 level transition 时不会被销毁，并且希望追踪当前的 world 的类提供了接口。用户可以调用 world context 的 `AddRef` 添加一个对 world 的引用，这些引用保存在 world context 的 `ExternalReferences` 字段中。当 world 改变时，world context 会更新这些引用，使其指向新的 world
```c++
	/** Outside pointers to CurrentWorld that should be kept in sync if current world changes  */
	TArray<TObjectPtr<UWorld>*> ExternalReferences;
```
例如 `UGameViewportClient` 类在它的 `Init` 函数中就调用 `AddRef` 注册了自己的 `World` 字段的引用
### Example
[Unreal Engine 4 Tutorial - Level Travelling Part 2: Transition Effects](https://www.youtube.com/watch?v=BGkUrmlcc4c) 的例子非常好，实现了下面的功能
* 在切换关卡前切换为 AI Controller，固定地移动一段距离，同时利用 player camera manager 的 `StartCameraFade` 进行游戏画面的淡出，使游戏逐渐变为黑屏
* 游戏变为黑屏后调用 open level 切换关卡
* 在 begin play 时播放蒙太奇，同时利用 player camera manager 的 API 进行游戏画面的淡入

这里调用 open level 的逻辑能和切换为 AI Controller 进行移动同时进行吗，我觉得是不行的，因为 `UEngine::LoadMap` 是先 clean up 当前的 world，再调用 load package 加载新的 world。可行的是把 load package 的逻辑提前，但是这样做对内存不怎么友好

额外地，我们使用 movie player 模块制作一个 loading screen。我希望这个 loading screen 能和原关卡的画面怎么混合一下，这个怎么实现

TODO：player camera manager 的 fade 相关字段在 `ULocalPlayer::CalcSceneViewInitOptions` 函数中使用，看看这个进一步是如何工作的
### Seamless Travel
world partition + seamless travel 会 crash，见 [Crash when seamlessly travelling from World Partition map (UE-214626)](https://forums.unrealengine.com/t/crash-when-seamlessly-travelling-from-world-partition-map-ue-214626/1914873)

debug 发现问题出在，`FSeamlessTravelHandler::Tick` 中
* 首先会 `UNetDriver::NotifyActorLevelUnloaded` 将需要 remove 的 actor 从 net driver 中移除
* 但是在后续调用 `UWorld::CleanupWorld` 中，world partition 在 uninitialize 时又把它的 data layer actor 加回来了，导致 net driver 里会存有一个野指针
* 然后才会调用 `UWorld::MarkObjectsPendingKill`

[Removed unnecessary call to AWorldDataLayers::ResetDataLayerRuntimeStates](https://github.com/EpicGames/UnrealEngine/commit/81f7d78d5fe24a447dacc59da52e8ad95c502a5d) 修复了这个问题，不过得等到 5.6 版本了


看看 [What is everything I need to know about seamless travel?](https://www.reddit.com/r/unrealengine/comments/1g1gqfs/what_is_everything_i_need_to_know_about_seamless/)

