## Component Register

```c++
UActorComponent::RegisterComponent();
```

## API

* 创建新对象，`CreateDefaultSubobject` vs `NewObject`
* 类似地，[Components](https://dev.epicgames.com/documentation/en-us/unreal-engine/components-in-unreal-engine) 中区分 `SetupAttachment` 和 `AttachToComponent`，也是一个在构造函数，一个 during play，为什么做这样的区分？另外，在 `SetupAttachment` 中我没有看到将 child 加到 parent 的 AttachChildren 里面，为什么？
  * 看起来在 `SetupAttachment` 中调用了 MARK_PROPERTY_DIRTY_FROM_NAME 宏，涉及ue4.25 加入的 pushmodel，不知道 parent 的 AttachChildren 是不是这样更新的
  * 看起来是在 `USceneComponent::OnRegister` 函数中调用了 `AttachToComponent` 
* `USceneComponent::AddLocalOffset`，给 Component 添加 Offset 的位移，位移向量是参照 Component 的局部坐标系
* `APown::GetViewRotation` 这个函数啥意思，SpringArm 的 `GetTargetRotation` 用到了它

## World

UE 区分 World 的类型，`EngineTypes.h` 中定义了若干 WorldType

* Editor：在 Editor View 中
* PIE
* Game

## Tick

FTickTaskManager

FTickFunction



FEngineLoop

UEditorEngine::Tick 中 PieContext.World()->Tick(LEVELTICK_ALL, TickDeltaSeconds ) 中执行了 UWorld 的 tick 1922 行

2097 行 call sceneCaptureComponent

UEditorEngine::Tick 中 2148 行 PostRenderAllViewPorts 函数中增加了 GFrameNumber

UEditorEngine::Tick 中的 2176 行执行了 GameViewport->Viewport->Draw()，这里 call 了 sceneCaptureComponent

```cpp
GuardedMain(const wchar_t * CmdLine)
  EngineTick()
    FEngineLoop::Tick()
      UGameEngine::Tick(float DeltaSeconds, bool bIdleMode)
        UWorld::Tick(ELevelTick TickType, float DeltaSeconds)
```

## Scene Capture Component

```c++
// SceneCaptureRendering.cpp, 816 行，这里做了一个坐标轴的变换，为什么？
void FScene::UpdateSceneCaptureContents(USceneCaptureComponent2D* CaptureComponent);
// 在这个函数中压入了 render cmd，这个 cmd 会执行渲染操作
```

