### Slot
解释：每个子节点都插在父节点的 slot 中，有没有 anchor 依赖于 父节点 slot 的类型

### Component
为什么 button component 底下有个 event 栏可以直接绑定 event，普通的蓝图类怎么没看到这玩意。普通的蓝图类中会有

### Anchor
因为我们通常设计 UI 时，总需要一个参考的屏幕的屏幕分辨率来将其可视化。anchor 这个概念要解决的问题是当屏幕分辨率变化时，如何确定新的 UI 布局。首先我们定义什么是 UI 布局：我们使用一个矩形来标定 UI 元素的位置。给定长宽的画布，我们清楚了每个 UI 矩形在画布中的位置和大小，那么就清楚了 UI 布局

假设我们在分辨率 A 下设计了一套 UI 布局。我们需要一种方法，它能够计算出另外给定的分辨率 B 下的 UI 布局。一种很容易想到的方法是，直接等比缩放就行了。UI 矩阵在 A 下有一个坐标以及大小，然后根据分辨率 A 和 B 的长宽比例，同比地得到 UI 矩阵在 B 下的坐标以及大小。但这种方法不适应多样的需求，例如一张图片我们可能不希望修改它的大小比例，但希望它的位置随着分辨率相对变化。因此我们希望有一种办法将相对和绝对大小综合起来使用

anchor 就是标定了画布上的相对位置，每个 UI 矩形都有一个 anchor。anchor 可以是一个点，一条水平或垂直的线段，一个矩形。每个点的坐标都是 (0,0) - (1,1) 之间的二维坐标，表示它在画布上的相对坐标。然后矩形的位置和大小描述为相对于 anchor 的绝对距离。那么最终矩形相对于画布的位置和大小就是 anchor 的相对值叠加上矩形相对于 anchor 的绝对值，这样就把相对大小和绝对大小结合起来了

如果 anchor 是一个点，那么 UI 矩形描述为相对于 anchor 的位置和它的大小，这里的位置和大小都是绝对大小。当分辨率从 A 切换到 B 时，anchor 的位置会移动，从而矩阵的位置随之移动，但矩形左上角顶点到 anchor 的距离和矩形的大小不依赖分辨率（因此如果 anchor 的坐标就是 (0,0) 的话，矩形的位置和大小都不依赖于分辨率了）

如果 anchor 是一条水平或垂直的线段，不妨假设它是水平的。此时 UI 矩形描述为它的左竖线到 anchor 线段左顶点的距离，右竖线到 anchor 线段右顶点的距离，这两个量在 ue 中称为 Offset Left 和 Offset Right（对于垂直的情况则称为 Offset Top 和 Offset Bottom），这样就描述清楚了矩形顶点的 x 轴坐标以及矩形的长度。然后还需要描述 UI 矩形的左上顶点相对于 anchor 线段的距离，以及 UI 矩形的宽度。在这种设定下，例如 anchor 的线段表示为 (0, 0) 和 (1, 0)，那么此时矩形的坐标和宽度不依赖于分辨率，但是矩形的长度随分辨率而变化

如果 anchor 是一个矩形，那么 UI 矩形就通过 Offset Left，Offset Right，Offset Top，Offset Bottom 来描述。此时矩形的长宽都依赖于分辨率，取决于 anchor 矩形的位置，UI 矩形的位置可能依赖于分辨率，也可能不依赖于分辨率

使用 widget blueprint 创建资产都是 user widget 的子类

TODO：Create Widget 这个蓝图节点，看起来它是 `UK2Node_CreateWidget` 这个自定义的蓝图节点，但没看明白是如何定义这个蓝图节点的行为的，我主要关心 Owning Player 参数是干嘛的。不过感觉 Owning player 这个参数并不重要，断点试了一下，这个蓝图节点最后会调用 `UWidgetBlueprintLibrary::Create` 函数， Owning Player 就是它的第三个参数，它用于提供 widget 的 OuterPrivate，虽然我测试的结果是不论有没有 Owning Player，它的 OuterPrivate 都是 game instance

TODO：调用 `APlayerController::SetShowMouseCursor` 后就能在游戏里看到鼠标了，但三人称模板中要切换视角得按住左键拖着了，为啥

TODO：`AddToViewport` 和 `AddToPlayerScreen` 用于将 user widget 显示在屏幕上，但具体的实现就感觉水很深了。

334