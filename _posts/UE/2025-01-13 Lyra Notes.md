### Start
如果看一个新项目，看看 project setting 中默认的 game mode，再看看 default level map



### Engine Loop
主要参考 [The Unreal Engine Game Framework: From int main() to BeginPlay](https://www.youtube.com/watch?v=IaU2Hue-ApI)
TODO：自己再根据源码梳理一下
```c++
FEngineLoop GEngineLoop;
```
`FEngineLoop::PreInit`：Load game and plugin modules，load 一个模块的过程
* 模块的 CDO 初始化
* `StartupModule` callback
PreInitPostStartupScreen
`FEngineLoop::Init`：
* 初始化 GEngine，根据是否包含 editor，类型为 `UGameEngine` 或 `UUnrealEdEngine` 的子类。实际的类型记录 config 文件中的（虽然我看 `FEngineLoop::PreInit` 里 call 的 `FEngineLoop::PreInitPostStartupScreen` 也会 new 一个 GEngine，但断点发现这里的逻辑没有被执行）
* 然后调用 GEngine 的 `Init` 函数，对于 `UGameEngine`，该函数中会创建 `UGameInstance`，然后调用 `UGameInstance` 的 `InitializeStandalone`，这个函数中就会创建一个 world context，并调用我们常见的 `UGameInstance::Init` 回调
* 然后调用 GEngine 的 `Start` 函数，对于 `UGameEngine`，它会调用 `UGameInstance::StartGameInstance`，这个函数从 config 中获取 default game map，然后调用 `UEngine::Browse` 加载地图

`UEngine::LoadMap` 包含下面的内容：

cleanup 之前的 world（如果有的话），cleanup 之后，会调用 `UEngine::TrimMemory` 做垃圾回收，因此即使 open level 当前的 map，也会重新加载一次 world

load umap package
* world 的构造函数
* PostLoad

`UWorld::InitWorld`
* `UWorld::InitializeSubsystems` 

`UWorld::SetGameMode` 创建 game mode

`UWorld::InitializeActorsForPlay`
* `AGameModeBase::InitGame`，在这里 game mode 创建了自己的 game session，并设置到 `GameSession` 字段
* 然后初始化所有的 actors，即调用它们的 pre, initailize component 以及 post 回调，其中 `AGameModeBase::PreInitializeComponents` 在这个时候创建了自己的 game state，将其设置在自己和 world 的 `GameState` 字段。同时调用 `AGameModeBase::InitGameState` 回调

`UWorld::SpawnPlayActor`
* `AGameModeBase::Login` 回调，spawn 出新的 player controller
	* player controller 的 `PostInitializeComponents` spawn 出 `PlayerState`
* `AGameModeBase::PostLogin` 回调
	* 调用 `AGameModeBase::RestartPlayer` 回调，默认是根据当前场景找到 player start actor，然后调用 `AGameModeBase::RestartPlayerAtPlayerStart` 来 spawn default pawn

`UWorld::BeginPlay`
* `AGameModeBase::StartPlay`
	* 各个 actor 以及 component 的 begin play 调用

TODO：在 `InitializeActorsForPlay` 中 spawn 出来的 actor 以及它的 component 回调会执行到哪个阶段，后续的回调又由谁来执行
### ULevel
```c++
UPROPERTY()
TObjectPtr<AWorldSettings> WorldSettings;

/** The level scripting actor, created by instantiating the class from LevelScriptBlueprint.  This handles all level scripting */
UPROPERTY(NonTransactional)
TObjectPtr<class ALevelScriptActor> LevelScriptActor;
```
TODO：world settings 是逐关卡一个吗，谁创建和保存的呢？
```
UWorld::InitializeNewWorld()
```
看起来在 `UWorld::InitializeNewWorld` 中创建的 world settings
### UWorld
AWordSettings 是什么,

AInfo 是怎么用的

ALevelScriptActor：ULevel 中的一个字段，用来执行关卡蓝图

game mode 的 init game 回调是什么时候调用的


启用 game features 时需要设置的这个 asset manager 选项是什么