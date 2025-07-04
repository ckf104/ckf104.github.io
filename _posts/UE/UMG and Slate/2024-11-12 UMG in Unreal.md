### Overview
创建蓝图资产时，需要继承 `UUserWidget` 或者它的子类（可以是 C++ 类也可以是蓝图类，这和创建通常的蓝图资产是一样的）。资产对应的 object 类型是 `UWidgetBlueprint`，它自然是 `UBlueprint` 的子类，然后它的 generated class 是 `UWidgetBlueprintGeneratedClass`，这也是 `UBlueprintGeneratedClass` 的子类

创建完成后，我们在 UMG 编辑器中添加需要的 UI 控件，可以在右上角中勾选或者取消 `Is Variable` 这个选项来控制这个 UI 控件是否要作为蓝图变量。作为蓝图变量的 UI 控件就可以在蓝图中正常使用逻辑去控制（这对应 C++ 中 `UWidget` 的 `bIsVariable` 字段）
#### Color Inheritance
有许多 UI 控件，例如 button 和 user widget，会有 foreground color 之类的字段，它不是用来指示自身的颜色的，而是用来设置子控件的颜色的，如果子控件的颜色字段勾选了 `Inherit`，就会使用祖先控件的 foreground color，而不是该字段的颜色值
### Slate Brush
这个结构体来指定一个 UI 元素的外观。例如 button 就包含 normal，pressed，hovered，disabled 四个 slate brush 来指定各种状态下 button 的外观

Draw As 字段用来控制如何绘制该 image，其中 box 和 border 是基于 [9-slice scaling](https://en.wikipedia.org/wiki/9-slice_scaling) 进行缩放的。margin 控制四个角上不进行缩放的 image 的占比，具体效果见 [WTF Is? Slate Brush in Unreal Engine 4](https://www.youtube.com/watch?v=kYxGC0WV0Uk) 中的实验

TODO：解释 slate brush 中各个字段的含义，以及它如何控制渲染效果
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
`INamedSlotInterface` 提供了另一种以名称来标记子节点的方式（相比于 panel widget 通过序号来标记）。它最典型的子类就是 user widget。我们在 umg editor 中新定义的 user widget A 作为 ui 节点放到另一个 user widget B中时，默认情况下 ser widget A 是不能作为父节点，添加额外的 widget 挂在它下面的，因为它没有继承 panel widget（因此使用 widget tree 提供的 `ForWidgetAndChildren` 函数对 B 进行遍历时也看不到 A 内部的子节点）。但由于它是 named slot interface 的子类，因此可以使用 named slot 来提供子节点

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
举一个例子，假设我们在设计 user widget A 时使用了 named slot 作为占位符，然后在设计 user widget B 时将 user widget A 作为子节点添加进去，并在 user widget A 的 named slot 下挂了一个 button C。那么现在 user widget A 的蓝图产生类中 `InstanceNamedSlots` 就包含 named slot 的名字。并且实例化一个 user widget B 时，得到的 user widget A 实例的 `NamedSlotBindings` 会包含 named slot 的名字和 button C 这个 pair。并且 button C 作为子节点挂载在 named slot 下

此时在调用 user widget B 的 widget tree 的 `ForEachWidget` 遍历时，会遍历到 user widget B 自己的节点（包括 user widget A）以及 button C，但是不会遍历到 user widget A 内部的节点（包括 named slot）。而调用 user widget A 的 widget tree 的 `ForEachWidget` 遍历时，会遍历到 user widget A 内的所有节点（包括 button C，因为 named slot 是 `UPanelWidget` 的子类

TODO：理解 widget tree 为啥是 `INamedSlotInterface` 的子类
### HUD
player controller 三剑客 HUD，camera manager 和 input component。我也没咋看明白 `AHUD` 类本身有啥东西，一般可能我们自己继承这个类，然后在这个类里面添加管理 widget 的逻辑吧
### Interaction with Others
要动态修改 UI 的内容，一种是获取到 widget 的引用，然后直接修改。另外一种是使用 [property/function binding](https://dev.epicgames.com/documentation/en-us/unreal-engine/property-binding-for-umg-in-unreal-engine)。function binding 的开销显然是最大的，因为每帧都会调这个蓝图函数。我不太确定 property binding 的开销如何
感觉用得最广泛的还是 event driven update。其实本质上就是直接进行修改，只是说现在绑定在了一个 delegate 上，每次变量值被修改了就只需要广播一下就好了。例如我需要显示 character 的生命值，那就额外地有一个 `OnHealthChanged` 多播代理，然后绑定一个修改 UI 的回调就好了

TODO：了解 property binding/function binding 的实现，如何声明哪些变量是可以绑定的，在 C++ 的 UProperty 声明咋看不出来呢
### Implement Widget Logic in C++
我们可以在编辑器中可视化地调整布局，然后在蓝图编辑中编写相应的响应逻辑，但蓝图中的逻辑运行效率较低。也可以继承 `UWidget` 和 `UUserWidget` 类，用 C++ 直接定义 UI 布局和 UI 逻辑。但这样就失去了可视化布局的优势了。bind widget 方法就是将两者的优势结合起来

TODO：meta bindwidget bindwidget optional
bindwidgetanim transient
### Widget Animation
[Ryan Laley, Widgets Part 4: Animations](https://www.youtube.com/watch?v=LMZoRSqoJ74) 讲得挺好的

### Input and Focus Managements
`UWidget` 的 `Visibility` 字段控制该 widget 是否能够显示与交互
```c++
/** Is an entity visible? */
UENUM(BlueprintType)
enum class ESlateVisibility : uint8
{
	/** Visible and hit-testable (can interact with cursor). Default value. */
	Visible,
	/** Not visible and takes up no space in the layout (obviously not hit-testable). */
	Collapsed,
	/** Not visible but occupies layout space (obviously not hit-testable). */
	Hidden,
	/** Visible but not hit-testable (cannot interact with cursor) and children in the hierarchy (if any) are also not hit-testable. */
	HitTestInvisible UMETA(DisplayName = "Not Hit-Testable (Self & All Children)"),
	/** Visible but not hit-testable (cannot interact with cursor) and doesn't affect hit-testing on children (if any). */
	SelfHitTestInvisible UMETA(DisplayName = "Not Hit-Testable (Self Only)")
};

class UWidget : public UVisual, public INotifyFieldValueChanged
{
	/** The visibility of the widget */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, FieldNotify, Getter, Setter, BlueprintGetter="GetVisibility", BlueprintSetter="SetVisibility", Category="Behavior")
	ESlateVisibility Visibility;
};
```
如果不是 visible 的，那么就在界面上不可见。`Hidden` 和 `Collapsed` 的区别在于这个 widget 不可见的时候还要不要占位置。例如一个 widget 在一个 vertical widget 中，如果该 widget 设置为 `Hidden`，那么即使该 widget 不可见，还是会占着 vertical widget 中的一个位置。视觉上就是该 vertical widget 中间某一项被跳过去了，没有显示出来。而 hit-testable 主要说这个 widget 能不能交互，例如一个 button，即使设置了鼠标点击事件的回调函数，如果 button 被设置为了 `SelfHitTestInvisible`，那么这个回调函数也不会被调用

[Ryan Laley, Widgets Part 5: Controller Support](https://www.youtube.com/watch?v=kPVqewOgmNo) 是一个很好的管理 user focus 的例子。关于 user focus 和 input routing 的底层实现，见 Slate in Unreal

TODO：`FCharacterEvent` 和 `FKeyEvent` 有什么区别
### TODO: Owner 的影响，UserWidget 的 Owner 设置为 PlayerController 时会在切换关卡时挂掉，Owner 设置为 GameInstance 是不是就好了
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

TODO：`AddToViewport` 和 `AddToPlayerScreen` 用于将 user widget 显示在屏幕上，但具体的实现就感觉水很深了
### Initialization Timing
user widget 中定义的下列初始化函数的调用时机是怎样的，和蓝图中的 PreConstruct，Construct，Event On OnInitialized 等的关系是什么
```c++
UMG_API virtual void NativeOnInitialized();
UMG_API virtual void NativePreConstruct();
UMG_API virtual void NativeConstruct();
UMG_API virtual void NativeDestruct();
UMG_API virtual void NativeTick(const FGeometry& MyGeometry, float InDeltaTime);
```
`NativePreConstruct` 会调用 `PreConstruct` 这个在蓝图中可实现的函数，`NativeConstruct` 会调用 `Construct` 这个在蓝图中可以实现的函数，其它是类似的

而具体的调用时机，在 design time 时，只有 `NativePreConstruct` 会被调用。而在非 design time 时，`NativeOnInitialized` 是在 user widget 创建时调用，而 `NativePreConstruct` 和 `NativeConstruct` 是在 user widget 创建内部的 swidget 时调用（通常是调用 `AddToViewport` 函数时）。而 `NativeDestruct` 是在该 user widget 的 `MyGCWidget` 析构时调用，关于 `MyGCWidget` 的讨论，见 Widget Management 一节

根据 [Widget construct vs preconstruct vs initiliazed events](https://forums.unrealengine.com/t/widget-construct-vs-preconstruct-vs-initiliazed-events/475397)，`PreConstruct` 可以理解为构造函数，并且它设置的值是在编辑器中可见的（覆盖编辑器中原有的设置），而 `Construct` 类似于 `BeginPlay` 回调，在游戏开始时调用。不过没看明白它说的这个 `OnInitialized` 的调用时机

TODO：解释 add to view port
### Widget Construction Flow
在 C++ 中使用 `CreateWidget` 来产生新的 user widget
```c++
template <typename WidgetT = UUserWidget, typename OwnerType = UObject>
WidgetT* CreateWidget(OwnerType OwningObject, TSubclassOf<UUserWidget> UserWidgetClass = WidgetT::StaticClass(), FName WidgetName = NAME_None)
```
实际的工作在 `UUserWidget::CreateInstanceInternal` 中完成
* 使用 `NewObject` 创建 user widget，根据输入参数的不同，outer 可能是 game instance，world，另一个 user widget，或者 widget tree
* 设置 local player context
* 调用 `UUserWidget::Initialize`，如果不是 design time，这里会触发蓝图中的 event on initialized 回调
### Widget Management
uwidget 的 `MyWidget` 指向了它对应的 swidget，它一般是子类重载 `RebuildWidget`，然后使用 `SNEW` 那一套语法生成的
```c++
	/** The underlying SWidget. */
	TWeakPtr<SWidget> MyWidget;

	/** The underlying SWidget contained in a SObjectWidget */
	TWeakPtr<SObjectWidget> MyGCWidget;
```
通常 uwidget 的子类会有自己的指向 swidget 的指针，例如 button 的 `MyButton` 字段，但它和父类的 `MyWidget` 字段指向的是同一个 swidget，不知道为什么这么设计
```c++
	/** Cached pointer to the underlying slate button owned by this UWidget */
	TSharedPtr<SButton> MyButton;
```
因为 uworld 中没有对 uwidget 的引用，因此额外引入了通常只用于 user widget 的 `MyGCWidget` 字段，来避免 uwidget 被垃圾回收。`SObjectWidget` 是 `FGCObject` 的子类，会为它包含的 user widget 添加引用。在 uwidget 添加到 viewport 时会调用的 `UWidget::TakeWidget` 函数中如果发现该 widget 是 user widget，并且 `MyGCWidget` 还未指向一个合法的 `SObjectWidget`，那就会创建一个新的 `SObjectWidget`，并把这个 `SObjectWidget` 作为 `TakeWidget` 函数的结果

总的来说，一个 user widget 在加入 viewport 时，会创建对应 `SObjectWidget`，它保证了该 user widget 不被垃圾回收，然后 user widget 对 widget tree 的引用，widget 中父类包含的 slot，slot 对子类的引用，这些引用都有 uproperty 标记，这样保证了 user widget 下面的所有 widget 都不会被回收，而当 `SObjectWidget` 析构时，这些 uwidget 也随之被垃圾回收掉（如果一个 user widget A 被包含在另一个 user widget B 中，为 user widget A 生成对应的 `SObjectWidget` 感觉就有些多余了，此时 `SObjectWidget` 的作用就只剩下在析构时调用 user widget 的 `NativeDestruct` 回调了吧）

而 swidget 这边则总是使用共享指针。因此只要有地方持有 `SObjectWidget` 的共享指针，`SObjectWidget` 就不会被析构
#### Show Widget in Viewport
`UGameViewportSubsystem` 是属于 `UEngine` 的 subsystem 类，它提供了把 uwidget 添加到 viewport 的接口，并且它的 `ViewportWidgets` 字段负责对 uwidget 进行管理
```c++
class UGameViewportSubsystem : public UEngineSubsystem
{
	struct FSlotInfo
	{
		FGameViewportWidgetSlot Slot;
		TWeakObjectPtr<ULocalPlayer> LocalPlayer;
		TWeakPtr<SConstraintCanvas> FullScreenWidget;
		SConstraintCanvas::FSlot* FullScreenWidgetSlot = nullptr;
	};
	
	using FViewportWidgetList = TMap<TObjectKey<UWidget>, FSlotInfo>;
	FViewportWidgetList ViewportWidgets;
};
```
在我们调用 user widget 的 `AddToViewport` 函数时，会转发到 `UGameViewportSubsystem` 的 `AddToScreen`
```c++
	bool AddToScreen(UWidget* Widget, ULocalPlayer* Player, FGameViewportWidgetSlot& Slot);
```
`FGameViewportWidgetSlot` 的定义如下，主要是用来控制 user widget 在 viewport 上的相对位置的。如果 `UGameViewportSubsystem` 的 `ViewportWidgets` 中不包含该 uwidget，那么函数的 `Slot` 的参数就会使用默认构造函数初始化的 `FGameViewportWidgetSlot`，从下面的定义可以看出，这样 uwidget 会覆盖整个屏幕
```c++
USTRUCT(BlueprintType)
struct FGameViewportWidgetSlot
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "User Interface")
	FAnchors Anchors = FAnchors(0.f, 0.f, 1.f, 1.f);

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "User Interface")
	FMargin Offsets;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "User Interface")
	FVector2D Alignment = FVector2D(0.f, 0.f);

	/** The higher the number, the more on top this widget will be. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "User Interface")
	int32 ZOrder = 0;

	/**
	 * Remove the widget when the Widget's World is removed.
	 * @note The Widget is added to the GameViewportClient of the Widget's World. The GameViewportClient can migrate from World to World. The widget can stay visible if the owner of the widget also migrate.
	 */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "User Interface")
	bool bAutoRemoveOnWorldRemoved = true;
};
```
可以在调用 `AddToViewport` 前先调用 user widget 的 `SetPositionInViewport` 等函数来调整 user widget 在 viewport 上的相对位置
```c++
	/**
	 * Sets the widgets position in the viewport.
	 * @param Position The 2D position to set the widget to in the viewport.
	 * @param bRemoveDPIScale If you've already calculated inverse DPI, set this to false.  
	 * Otherwise inverse DPI is applied to the position so that when the location is scaled 
	 * by DPI, it ends up in the expected position.
	 */
	UFUNCTION(BlueprintCallable, BlueprintCosmetic, Category="User Interface|Viewport")
	UMG_API void SetPositionInViewport(FVector2D Position, bool bRemoveDPIScale = true);

	/*  */
	UFUNCTION(BlueprintCallable, BlueprintCosmetic, Category="User Interface|Viewport")
	UMG_API void SetDesiredSizeInViewport(FVector2D Size);
```
回到 `AddToScreen` 的实现，它调用传入的 uwidget 的 `TakeWidget` 函数，获取到对应的 swidget，然后新建一个 `SConstraintCanvas`，将该 swidget 作为一个 slot 添加到 `SConstraintCanvas` 里。然后调用 `UGameViewportClient` 类的 `AddViewportWidgetContent` 函数，将新建的 `SConstraintCanvas` 又作为一个 slot 添加到 `UGameViewportClient` 的 `ViewportOverlayWidget` 这个 `SOverlay` 中。这样就把 swidget 添加到全局的 swidget tree 中，slate 的渲染模块就会绘制它了
```c++
void UGameViewportClient::AddViewportWidgetContent( TSharedRef<SWidget> ViewportContent, const int32 ZOrder )
{
	TSharedPtr< SOverlay > PinnedViewportOverlayWidget( ViewportOverlayWidget.Pin() );
	if( ensure( PinnedViewportOverlayWidget.IsValid() ) )
	{
		PinnedViewportOverlayWidget->AddSlot( ZOrder )
			[
				ViewportContent
			];
	}
}
```
如果我们希望将 C++ 编写的 swidget 添加到屏幕上，略去前面的步骤，直接调用 `UGameViewportClient` 的 `AddViewportWidgetContent` 即可
#### Slate in Level Transition
在 `UGameViewportSubsystem` 的初始化中注册了下面三个回调
```c++
void UGameViewportSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);
	
	//FWorldDelegates::LevelRemovedFromWorld.AddUObject(this, &ThisClass::HandleLevelRemovedFromWorld);
	FWorldDelegates::OnWorldCleanup.AddUObject(this, &ThisClass::HandleWorldCleanup);
	FWorldDelegates::OnWorldBeginTearDown.AddUObject(this, &ThisClass::HandleRemoveWorld);
	FWorldDelegates::OnPreWorldFinishDestroy.AddUObject(this, &ThisClass::HandleRemoveWorld);
}
```
这三个回调的调用时机分别是（不知道为啥这三个代理都注册了回调）
* `UWorld::BeginTearingDown` 中会广播 `OnWorldBeginTearDown`，而这个函数在 `UWorld::LoadMap` 中具体执行 level transition 的逻辑前会被调用
* `UWorld::CleanupWorldInternal` 中会在实际进行 world cleanup 前广播 `OnWorldBeginTearDown`。这个函数也是在 `UWorld::LoadMap` 执行 level transition 的时候调用，调用它之前各个 actor 已经执行过 endplay 的逻辑了
* `OnPreWorldFinishDestroy` 回调是在 world 的 `FinishDestroy` 中执行具体的 destroy 操作前调用的

`HandleWorldCleanup` 就是 `HandleRemoveWorld` 的 wrapper。而 `HandleRemoveWorld` 的实现也很简单，就是遍历 `ViewportWidgets` 字段，然后移除所有的 slot 的 `bAutoRemoveOnWorldRemoved` 为 true 的 uwidget，同时将其从 `UGameViewportClient` 的 `SOverlay` 中删除。因此 level transition 后 UI 会消失，需要重新创建

如果需要 UI 跨 level 存在，需要将 slot 的 `bAutoRemoveOnWorldRemoved` 设置为 false，并使用 C++ 的 `CreateWidget` 来创建 user widget，并设置 user widget 的 outer 为 game instance
### Other Tutorials
[unreal ben ui](https://benui.ca/unreal/#ui) 中有很多 UI 相关的教程，涵盖了下面 TODO 的许多主题，值得一看。比如 [Introduction to C++ UIs in Unreal](https://benui.ca/unreal/ui-cpp-basics/) 讨论了如何使用 C++ 构建 UI
TODO：跳过了官方文档中的 [UMG Best Practices](https://dev.epicgames.com/documentation/en-us/unreal-engine/umg-best-practices-in-unreal-engine)
TODO：官方文档中一些其它的教程 [Tutorials and Examples](https://dev.epicgames.com/documentation/en-us/unreal-engine/tutorials-and-examples-for-user-interfaces-in-unreal-engine)
TODO：[虚幻5UI系统（UMG）基础（已完结）](https://www.bilibili.com/video/BV1gT41137Vp/)，b 站上的一个 umg 系列教程，主要后面讨论了 UI 动画的东西
TODO：[UE5 UMG的SDF字体渲染](https://zhuanlan.zhihu.com/p/3295334910)，以及 UMG 中的字体设置
### Widget Component and Interaction
TODO：了解 widget component 以及 widget interaction component
### SWidget
TODO：什么是 slate widget
### Rendering
TODO：解释这个布局，通过 slot，我们有子节点的 desired size，有父节点希望子节点的 desired size，与编辑器右上角的 desired screen，fill screen 等选项有关，控制到底用子节点的 desired size，还是父节点希望子节点的 desired size。即理清楚布局算法是如何工作的
TODO：解释它与 rendering 子系统如何交互


### ActionRPG UI Notes
button 的 normal, hovered 等四个 `FSlateBrush` 的 `DrawAs` 设置为 None，来实现一个透明的 button
