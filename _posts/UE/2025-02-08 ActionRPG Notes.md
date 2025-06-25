`FSlateBrush` 是什么，我看 `RPGItem` 中用了它

`URPGAbilitySystemComponent`

`URPGAttributeSet`

`UAbilitySystemGlobals::Get().InitGlobalData();`
### USaveGame
官方的 tutorial [Saving and Loading Your Game](https://dev.epicgames.com/documentation/en-us/unreal-engine/saving-and-loading-your-game-in-unreal-engine?application_version=5.4) 讲得很好了

### 游戏逻辑
#### 初始化
GameMode 的 beginplay 中包含播放 Sequencer 动画以及 UI 和 UI 动画的逻辑。并且 GameMode 中重载了 `PlayerCanRestart` 函数，这个函数默认会在 `AGameModeBase::PostLogin` 中调用，判断是否能够 spawn 新的 character。这使得在一开始 GameMode 不会 spawn 一个 character 出来

Sequencer 播放完毕后，player controller 中调用 GameMode 的 start game 函数，这个函数负责
* 调用 `AGameModeBase::RestartPlayer` 来 spawn character。在最后这个函数会调用 `AGameModeBase::FinishRestartPlayer` 来通知 player controller 去 possess 这个新的 character
	* player controller 在蓝图中重载了 `OnPossess` 函数，这个函数中又负责
		* 创建 WB_HUD_PC 这个 HUD 然后赋值给 on screen control 字段
		* 将 `HandleInventoryItemChanged` 这个蓝图定义的函数绑定到 `OnInventoryItemChanged` 这个 C++ 中定义的动态多播
		* 延迟 0.025 秒后，调用 characater 的 create all weapons 函数，并设置 input mode 为 game only
* 调用 start play timer 函数，这个函数会使用蓝图节点 set timer by event 来创建一个 timer，它负责每秒钟递减 battle time，然后调用 player controller 的 on screen control 字段的 update timer 函数，当时间递减到 0 时，调用 rpg game mode 的 game over 函数
#### Game Over
设置 `AWorldSettings` 的 `TimeDilation` 可以快或者慢放游戏逻辑，我觉得逻辑就是真实时间乘以 `TimeDilation` 来得到游戏中的时间之类的吧，以及设置 game pause（这个讨论见 Tick in Unreal）
#### Main Menu World
camera actor 设置 auto activate for player 为 player 0，这样会自动将该 camera 作为 view target

game mode 的 pawn class 设置为 none，避免产生 player

TODO：接下来看看 AI 的部分