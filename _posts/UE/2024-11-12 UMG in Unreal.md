### Anchor
因为我们通常设计 UI 时，总需要一个参考的屏幕的屏幕分辨率来将其可视化。anchor 这个概念要解决的问题是当屏幕分辨率变化时，如何确定新的 UI 布局

首先我们定义什么是 UI 布局，给定长宽的画布


使用 widget blueprint 创建资产都是 user widget 的子类

anchor 这个概念

TODO：Create Widget 这个蓝图节点，看起来它是 `UK2Node_CreateWidget` 这个自定义的蓝图节点，但没看明白是如何定义这个蓝图节点的行为的，我主要关心 Owning Player 参数是干嘛的。不过感觉 Owning player 这个参数并不重要，断点试了一下，这个蓝图节点最后会调用 `UWidgetBlueprintLibrary::Create` 函数， Owning Player 就是它的第三个参数，它用于提供 widget 的 OuterPrivate，虽然我测试的结果是不论有没有 Owning Player，它的 OuterPrivate 都是 game instance

TODO：调用 `APlayerController::SetShowMouseCursor` 后就能在游戏里看到鼠标了，但三人称模板中要切换视角得按住左键拖着了，为啥

TODO：`AddToViewport` 和 `AddToPlayerScreen` 用于将 user widget 显示在屏幕上，但具体的实现就感觉水很深了。