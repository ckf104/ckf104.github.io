### Slate Brush
TODO：解释 slate brush中各个字段的含义，以及它如何控制渲染效果
### UPanelWidget and UPanelSlot
`UPanelWidget` 的子类才有子节点，有 1 个还是多个子节点取决于 `bCanHaveMultipleChildren` 字段的值，在 `UPanelWidget` 的构造函数中默认为 true

`UPanelSlot` 类用来组织父子节点关系。`UPanelWidget::GetSlotClass` 虚函数表示这个 widget 使用的 slot 类，默认是 `UPanelSlot`。子类可以重载来表示实际使用的 slot 类。例如 Canvas 实际使用的是 `UCanvasPanelSlot`，当然这些新定义的 slot 类必须是 `UPanelSlot` 的子类
```c++
UCLASS(BlueprintType, MinimalAPI)
class UPanelSlot : public UVisual
{
	UPROPERTY(Instanced)
	TObjectPtr<class UPanelWidget> Parent;

	UPROPERTY(Instanced)
	TObjectPtr<class UWidget> Content;
};
```
父子节点的组织方法是，`UWidget` 的 `Slot` 字段表示了这个 widget 在父节点的中的位置。而 panel widget 的 slots 字段则记录了所有的子节点。查看 `UPanelWidget::AddChild` 方法可知，每当添加一个新的子节点，就实例化一个新的 slot 赋值给 child widget 的 slot，同时将这个 slot 加入到父节点的 slots 中
##### Widget Tree
user widget 包含一个 widget tree 字段
```c++
/** The widget tree contained inside this user widget initialized by the blueprint */
UPROPERTY(Transient, DuplicateTransient, TextExportTransient)
TObjectPtr<UWidgetTree> WidgetTree;
```
然后 widget tree 包含一个 root widget 字段
```c++
/** The root widget of the tree */
UPROPERTY(Instanced)
TObjectPtr<UWidget> RootWidget;
```
这个 root widget 就是整个层次节点的根了，然后非叶子节点都是 panel widget 或者 `INamedSlotInterface` 的子类，它可以继续延伸出子节点，由此展开成了一整棵树
### Named Slot
`INamedSlotInterface` 提供了另一种以名称来标记子节点的方式（相比于 panel widget 通过序号来标记）。它最典型的子类就是 user widget。我们在 umg editor 中新定义的 user widget A作为 ui 节点放到另一个 user widget B中时，默认情况下是不能作为父节点的，因为它没有继承 panel widget（因此使用 widget tree 提供的 `ForWidgetAndChildren` 函数对 B 进行遍历时也看不到 A 内部的子节点）。但由于它是 named slot interface 的子类，因此可以使用 named slot 来提供子节点

具体来说，我们在自定义 user widget A 时加入 named slot 作为占位符。这样在将 A 放入正在定义的 user widget B 时就可以将子节点加入到 A 的 named slot 下了。对应到 C++ 中的字段，`UWidgetBlueprintGeneratedClass` 的 `InstanceNamedSlots` 字段记录了它的 user widget 类有哪些 named slot（`UWidgetBlueprintGeneratedClass` 是 UClass 的子类）
```c++
UPROPERTY()
TArray<FName> InstanceNamedSlots;
```
然后每个 user widget 实例的 `NamedSlotBindings` 字段则记录了每个 named slot 上挂的 widget
```c++
/** Stores the widgets being assigned to named slots */
UPROPERTY()
TArray<FNamedSlotBinding> NamedSlotBindings;
```

TODO：理解 widget tree 为啥是 `INamedSlotInterface` 的子类
### HUD
player controller 三剑客 HUD，camera manager 和 input component。我也没咋看明白 `AHUD` 类本身有啥东西，一般可能我们自己继承这个类，然后在这个类里面添加管理 widget 的逻辑吧
### Interaction with Others
要动态修改 UI 的内容，一种是获取到 widget 的引用，然后直接修改。另外一种是使用 [property/function binding](https://dev.epicgames.com/documentation/en-us/unreal-engine/property-binding-for-umg-in-unreal-engine)。function binding 的开销显然是最大的，因为每帧都会调这个蓝图函数。我不太确定 property binding 的开销如何
感觉用得最广泛的还是 event driven update。其实本质上就是直接进行修改，只是说现在绑定在了一个 delegate 上，每次变量值被修改了就只需要广播一下就好了。例如我需要显示 character 的生命值，那就额外地有一个 `OnHealthChaned` 多播代理，然后绑定一个修改 UI 的回调就好了

TODO：了解 property binding/function binding 的实现
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

### Other Tutorials
[unreal ben ui](https://benui.ca/unreal/#ui) 中有很多 UI 相关的教程，涵盖了下面 TODO 的许多主题，值得一看。比如 [Introduction to C++ UIs in Unreal](https://benui.ca/unreal/ui-cpp-basics/) 讨论了如何使用 C++ 构建 UI
TODO：跳过了官方文档中的 [UMG Best Practices](https://dev.epicgames.com/documentation/en-us/unreal-engine/umg-best-practices-in-unreal-engine)
TODO：官方文档中一些其它的教程 [Tutorials and Examples](https://dev.epicgames.com/documentation/en-us/unreal-engine/tutorials-and-examples-for-user-interfaces-in-unreal-engine)
### Widget Component and Interaction
TODO：了解 widget component 以及 widget interaction component
### SWidget
TODO：什么是 slate widget
### Rendering
TODO：解释这个布局，通过 slot，我们有子节点的 desired size，有父节点希望子节点的 desired size，与编辑器右上角的 desired screen，fill screen 等选项有关，控制到底用子节点的 desired size，还是父节点希望子节点的 desired size。即理清楚布局算法是如何工作的
TODO：解释它与 rendering 子系统如何交互
### Input
TODO：解释它如何接收 input，以及如何与 enhanced input 系统协作
### Animation
TODO：试试 UI 动画