slate 的官方文档：[Slate UI Framework](https://dev.epicgames.com/documentation/en-us/unreal-engine/slate-user-interface-programming-framework-for-unreal-engine)

[UE4 Slate基础](https://zhuanlan.zhihu.com/p/692551733) 也讲得不错，但是它主要关心的是渲染
### Input Routing
这一节我们讨论 slate 是如何处理用户输入的，我们希望捋清楚输入什么时候会发送到 UI，什么时候又会发送到 game logic
#### Basic Concepts
在 GUI 程序处理鼠标和键盘输入时会涉及两个基本的概念：user focus 和 mouse capture
* user focus 指当前哪个 UI 控件应该接收用户的键盘输入。比如我同时打开了多个 window，键盘输入应该送到哪个 window 里呢，这就由 user focus 当前的值决定
* mouse capture 是指当前鼠标的输入是否有被某个 GUI 控件捕获。通常情况下，鼠标放在哪个 GUI 控件上，哪个 GUI 控件就负责接收鼠标的输入，但如果某个 UI 控件捕获了鼠标，那么无论鼠标的位置在哪，它的输入都会传给该 GUI 控件

这两个概念并不是硬件固有的，而是需要 GUI 软件去实现的。另外，不同层级的 GUI 软件看到的 UI 控件的粒度是不一样的。最底层的 GUI 桌面看到的就是应用程序申请的一个个窗口。它维护自己的 user focus 和 mouse capture，决定鼠标和键盘的输入应该传递给哪个窗口。而申请该窗口的 GUI 软件则知道窗口里有哪些 UI 控件，并维护自己的 user focus 和 mouse capture，然后将自己收到的输入向下传递

由于本地可能有多个玩家，因此 UE 需要为每个玩家维护 user focus 和 mouse capture。每个玩家对应一个 `FSlateUser`，所有的 `FSlateUser` 记录在 `FSlateApplication` 中
```c++
	/**
	 * All users currently registered with Slate.
	 * Normally there's just one, but any case where multiple users can provide input to the same application will register multiple users.
	 * 
	 * Note: The array may contain invalid entries. Users have associated indices that they expect to maintain, independent of the existence of other users.
	 */
	TArray<TSharedPtr<FSlateUser>> Users;
```
而 slate user 的 `WeakFocusPath` 和 `PointerCaptorPathsByIndex` 字段则记录了当前 user 的 focus 和 mouse capture。这里 mouse capture 是一个 map 可能是考虑到多个光标的情况吧
```c++
	/** A weak path to the widget currently focused by a user, if any. */
	FWeakWidgetPath WeakFocusPath;
	/** Weak paths to widgets that are currently capturing a particular pointer */
	TMap<uint32, FWeakWidgetPath> PointerCaptorPathsByIndex;
```
UE 的 viewport 里的 UI 控件以树的形式组织的，所以它的 user focus 和 mouse capture 是树上的一条路径。路径上的第一个元素是顶层的 UI 控件 `SWindow`，路径上最后一个 `SWidget` 是用户设置的需要 focus 或者 capture 的 UI 控件，并不一定是树上的叶子节点
#### Routing for UI
抛开 OS 相关的部分，接收输入的函数来自 `FSlateApplication` 的各种回调，例如
```c++
	SLATE_API virtual bool OnKeyChar( const TCHAR Character, const bool IsRepeat ) override;
	SLATE_API virtual bool OnKeyDown( const int32 KeyCode, const uint32 CharacterCode, const bool IsRepeat ) override;
	SLATE_API virtual bool OnKeyUp( const int32 KeyCode, const uint32 CharacterCode, const bool IsRepeat ) override;
	SLATE_API virtual void OnInputLanguageChanged() override;
	SLATE_API virtual bool OnMouseDown( const TSharedPtr< FGenericWindow >& PlatformWindow, const EMouseButtons::Type Button ) override;
	SLATE_API virtual bool OnMouseDown( const TSharedPtr< FGenericWindow >& PlatformWindow, const EMouseButtons::Type Button, const FVector2D CursorPos ) override;
	SLATE_API virtual bool OnMouseUp( const EMouseButtons::Type Button ) override;
	SLATE_API virtual bool OnMouseUp( const EMouseButtons::Type Button, const FVector2D CursorPos ) override;
	SLATE_API virtual bool OnMouseDoubleClick( const TSharedPtr< FGenericWindow >& PlatformWindow, const EMouseButtons::Type Button ) override;
	SLATE_API virtual bool OnMouseDoubleClick( const TSharedPtr< FGenericWindow >& PlatformWindow, const EMouseButtons::Type Button, const FVector2D CursorPos ) override;
```
我们先以 `OnKeyDown` 的处理作为一个例子，看看键盘输入是如何处理的。这个函数的逻辑大概是
* 根据输入对应的 slate user，拿到对应的 user focus 的 slate path
* 先根据 tunnel policy 从上到下遍历一遍该 slate path，调用每个 SWidget 的 `OnPreviewKeyDown` 回调，然后调用 slate application 的 `ProcessReply` 来处理回调返回的 `FReply`
* 然后又根据 bubble policy 从下往上遍历一遍该 slate path，调用每个 SWidget 的 `OnKeyDown` 回调，然后调用 slate application 的 `ProcessReply` 来处理回调返回的 `FReply`
* 一旦某一个回调返回的 `FReply` 的 `bIsHandled` 字段为 true，表明输入已经被该 `SWidget` consume 掉了，遍历提前结束

`FReply` 是 `SWidget` 与 slate application 交互的桥梁。我们接下来会看到，它除了用来表示该输入是否已经被 consume 外，还可以用来设置 user focus 和 mouse capture 这些

`SWidget` 中定义了这两个相应的回调
```c++
	/**
	 * Called after a key is pressed when this widget or a child of this widget has focus
	 * If a widget handles this event, OnKeyDown will *not* be passed to the focused widget.
	 *
	 * This event is primarily to allow parent widgets to consume an event before a child widget processes
	 * it and it should be used only when there is no better design alternative.
	 *
	 * @param MyGeometry The Geometry of the widget receiving the event
	 * @param InKeyEvent  Key event
	 * @return Returns whether the event was handled, along with other possible actions
	 */
	SLATECORE_API virtual FReply OnPreviewKeyDown(const FGeometry& MyGeometry, const FKeyEvent& InKeyEvent);

	/**
	 * Called after a key is pressed when this widget has focus (this event bubbles if not handled)
	 *
	 * @param MyGeometry The Geometry of the widget receiving the event
	 * @param InKeyEvent  Key event
	 * @return Returns whether the event was handled, along with other possible actions
	 */
	SLATECORE_API virtual FReply OnKeyDown(const FGeometry& MyGeometry, const FKeyEvent& InKeyEvent);
```
`SWidget` 中的默认是实现是返回 `FReply::Unhandled()`。一些 `SWidget` 的子类重载了这些函数，并使其能进一步转发到 UMG 的 widget 中。例如 `SObjectWidget` 中重载了 `OnPreviewKeyDown` 和 `OnKeyDown` 函数，并将其转发到它对应的 `UUserWidget` 的 `NativeOnPreviewKeyDown` 和 `NativeOnKeyDown` 函数，而这两个函数的默认实现就是调用我们可以在蓝图中实现的 `OnPreviewKeyDown` 和 `OnKeyDown`
```c++
FReply SObjectWidget::OnPreviewKeyDown(const FGeometry& MyGeometry, const FKeyEvent& InKeyEvent)
{
	if ( CanRouteEvent() )
	{
		return WidgetObject->NativeOnPreviewKeyDown( MyGeometry, InKeyEvent );
	}

	return FReply::Unhandled();
}

FReply SObjectWidget::OnKeyDown(const FGeometry& MyGeometry, const FKeyEvent& InKeyEvent)
{
	if ( CanRouteEvent() )
	{
		FReply Result = WidgetObject->NativeOnKeyDown( MyGeometry, InKeyEvent );
		if ( !Result.IsEventHandled() )
		{
			return SCompoundWidget::OnKeyDown(MyGeometry, InKeyEvent);
		}

		return Result;
	}

	return FReply::Unhandled();
}
```
另一些例如与 UMG 中 `UVerticalBox` 相关联的 `SVerticalBox` 则没有重载这两个函数，因此 UMG 中 `UVerticalBox` 也就无法响应键盘输入（虽然通常这也是不必要的）

鼠标的点击事件的处理是类似的，分别使用 tunnel policy 和 bubble policy 遍历 widget path，调用 `SWidget` 的 `OnPreviewMouseButtonDown` 和 `OnMouseButtonDown` 回调。widget path 的选择也很自然，如果当前光标被 capture，则使用 slate user 的 `PointerCaptorPathsByIndex`
字段存储好的 widget path。而如果没有被 capture，则使用点击处的叶子 widget 到根节点形成的 widget path

接下来讨论 `FSlateApplication::ProcessReply`，这个函数负责处理 `SWidget` 的输入回调返回的 `FReply`。它主要做下面的事情
* 处理 `FReply` 包含的 release mouse capture 请求。如果 `FReply` 的 `bReleaseMouseCapture` 字段为 true，slate application 需要将相应光标的 mouse capture 的 widget path 置空
* 处理 `FReply` 包含的 release user focus 请求。如果 `FReply` 的 `bReleaseUserFocus` 字段为 true，slate application 需要将对应 user focus 的 widget path 置空
* 处理 `FReply` 包含的 mouse capture 请求。如果 `FReply` 的 `MouseCaptor` 非空，需要计算从 `MouseCaptor` 指定的 `SWidget` 到根节点的 widget path，这将用于下次该光标按键时的响应
* 处理 `FReply` 包含的 navigation 请求。如果 `FReply` 的 `NavigationType` 不为 invalid，那么 slate application 需要根据当前的 focus swidget 和 `NavigationType` 指示的方向，在当前的 UI 布局中寻找下一个 focus swidget
* 处理 `FReply` 包含的 mouse capture 请求 如果 `FReply` 的 `bSetUserFocus` 非空，需要计算从 `RequestedFocusRecepient` 指定的 `SWidget` 到根节点的 widget path，用于下次按键时的响应
* 还有就是例如 `OnMouseCaptureLost`，`OnFocusChanging`，`OnFocusLost` 等各种回调的调用

TODO：解释 `FReply` 包含的一些其它操作，例如 mouse drag and drop operation，mouse lock，set cursor position 等
TODO：解释 `UWidget` 的 `Navigation` 字段是如何影响 slate application 的 navigation 搜索的
#### Routing for Game Logic
我们知道了输入是怎么在 UI 控件中传递的，那输入是怎么传递到游戏逻辑中的呢？

而在 WidgetPath 中路径靠上的位置会有一个类型为 `SViewport` 或者它的子类的 UI 控件，`SViewport` 类重载了 `OnKeyDown`，`OnMouseButtonDown` 等函数，它会将输入转发给 `ViewportInterface`
```c++
class SViewport: public SCompoundWidget
{
	/** Interface to the rendering and I/O implementation of the viewport. */
	TWeakPtr<ISlateViewport> ViewportInterface;
};
FReply SViewport::OnMouseButtonDown( const FGeometry& MyGeometry, const FPointerEvent& MouseEvent )
{
	return ViewportInterface.IsValid() ? ViewportInterface.Pin()->OnMouseButtonDown(MyGeometry, MouseEvent) : FReply::Unhandled();
}
```
断点发现，`ViewportInterface` 的实际类型是 `FSceneViewport`，它会将输入进一步转发给自己的 `ViewportClient` 字段，最后实际类型为 `UGameViewportClient` 的 `ViewportClient` 会把输入转发给相应的 player controller 的 `InputKey` 函数

player controller 的 `PlayerInput` 负责处理输入相关，因此在 `APlayerController::InputKey` 中会进一步调用 `UPlayerInput::InputKey`，这个函数会将输入信息存放到 `UPlayerInput` 的 `KeyStateMap` 中
```c++
	/** Object that manages player input. */
	UPROPERTY(Transient)
	TObjectPtr<UPlayerInput> PlayerInput;  
```
这个 `KeyStateMap` 就是我们熟悉的了。在下一次 player controller 的 tick 时，就会构建 input component stack，然后将 `KeyStateMap` 中待处理的输入派发给这些 input component。这部分的逻辑在 Enhanced Input in Unreal 中已经描述过了
#### Player Controller Input Mode
现在我们来看 player controller 的 `SetInputMode` 函数，蓝图里有三个它的 wrapper 函数，分别是 `SetInputModeUIOnly`，`SetInputModeGameOnly` 和 `SetInputModeGameAndUI`，[WTF Is? Controller: Set Input Mode in Unreal Engine 4](https://www.youtube.com/watch?v=rP0T-pjzyvs) 对这三个函数的各个选项的介绍挺详细的

这些函数最后都归结为对 `UGameViewportClient` 和 `ULocalPlayer` 包含的一个 `FReply` 类型的 `SlateOperations`字段的修改
* 要设置为 input mode 为 UI only，就把 `UGameViewportClient` 的 `bIgnoreInput` 设置为 true，这样 `UGameViewportClient` 就不会再把收到的输入转发给 player controller
* 要设置 input mode 为 game only，就把 `UGameViewportClient` 的 `bIgnoreInput` 设置为 true，mouse capture mode 设置为 permanently capture，这样 `SViewport` 就会一直获取 mouse capture，导致鼠标输入只会传递给 game logic，另外设置 `FReply` 的 user focus 为 `SViewport`，这样键盘输入也只会传递给 game logic
* 要设置 input mode 为 UI and game，就把 `UGameViewportClient` 的 `bIgnoreInput` 设置为 true，mouse capture mode 设置为 `CaptureDuringMouseDown`，这样只有再鼠标按下事件传递给 `SViewport` 后它才会捕获鼠标输入，然后鼠标按键松开时又释放鼠标

以及 input mode 中还有 `UGameViewportClient` 的 mouse lock mode 的选项，或者调用 `UGameViewportClient` 的 api 来直接设置 mouse lock mode，mouse capture mode
```c++
UENUM()
enum class EMouseCaptureMode : uint8
{
	/** Do not capture the mouse at all */
	NoCapture,
	/** Capture the mouse permanently when the viewport is clicked, and consume the initial mouse down that caused the capture so it isn't processed by player input */
	CapturePermanently,
	/** Capture the mouse permanently when the viewport is clicked, and allow player input to process the mouse down that caused the capture */
	CapturePermanently_IncludingInitialMouseDown,
	/** Capture the mouse during a mouse down, releases on mouse up */
	CaptureDuringMouseDown,
	/** Capture only when the right mouse button is down, not any of the other mouse buttons */
	CaptureDuringRightMouseDown,
};

UENUM()
enum class EMouseLockMode : uint8
{
	/** Do not lock the mouse cursor to the viewport */
	DoNotLock,
	/** Only lock the mouse cursor to the viewport when the mouse is captured */
	LockOnCapture,
	/** Always lock the mouse cursor to the viewport */
	LockAlways,
	/** Lock the cursor if we're in fullscreen */
	LockInFullscreen,
};
```

最后，`FEngineLoop::Tick` 会获取到 local player 的 `SlateOperations`，调用 `FSlateApplication::ProcessExternalReply`，这个函数又进一步调用 `ProcessReply` 来处理 game logic 中的设置 user focus 等请求