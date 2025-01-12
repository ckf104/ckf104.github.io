
TODO：解释 `UChildActorComponent` 的用法，以及 actor 中的下面字段
```c++
/** The UChildActorComponent that owns this Actor. */
UPROPERTY()
TWeakObjectPtr<UChildActorComponent> ParentComponent;	
```
TODO：解释 actor 间的父子关系
```c++
/** Array of all Actors whose Owner is this actor, these are not necessarily spawned by UChildActorComponent */
UPROPERTY(Transient)
TArray<TObjectPtr<AActor>> Children;

/**
 * Owner of this Actor, used primarily for replication (bNetUseOwnerRelevancy & bOnlyRelevantToOwner) and visibility (PrimitiveComponent bOwnerNoSee and bOnlyOwnerSee)
 * @see SetOwner(), GetOwner()
 */
UPROPERTY(ReplicatedUsing=OnRep_Owner)
TObjectPtr<AActor> Owner;
```
感觉和 primitive component 中的下面字段有些关系的
```c++
/** If this is True, this component won't be visible when the view actor is the component's owner, directly or indirectly. */
UPROPERTY(EditAnywhere, AdvancedDisplay, BlueprintReadOnly, Category = Rendering)
uint8 bOwnerNoSee:1;

/** If this is True, this component will only be visible when the view actor is the component's owner, directly or indirectly. */
UPROPERTY(EditAnywhere, AdvancedDisplay, BlueprintReadOnly, Category = Rendering)
uint8 bOnlyOwnerSee:1;
```
TODO： Actor 的 Owned Component 是在哪设置的
```c++
/**
 * All ActorComponents owned by this Actor. Stored as a Set as actors may have a large number of components
 * @see GetComponents()
 */
TSet<TObjectPtr<UActorComponent>> OwnedComponents;
```
这与 NewObject 和 CreateDefaultSubObject 有关系吗
### Spawn Actor Flow
UWorld::SpawnActor 的大概流程是
* 根据用户提供的 actor transform，调用 `EncroachingBlockingGeometry` 函数判断这个位置是否会与其它 actor 发生重叠，如果提供的 `ESpawnActorCollisionHandlingMethod` 为 `DontSpawnIfColliding` 且有位置重叠，那么会 spawn 失败
* 调用 `NewObject` 生成一个 actor，其中 Outer 设置为这个 actor 要添加进的 level
* 根据用户提供的 `FActorSpawnParameters` 参数设置好一些目前不太关心的 actor 的字段，并将 actor 加入到相应 level 的 actor 数组中。这里有两处可以设置的回调，一个是 `FActorSpawnParameters` 的 `CustomPreSpawnInitalization` 字段，以及 `UWorld` 的 `OnActorPreSpawnInitialization` 字段。前者是一个 func ref，后者是一个静态多播
* 然后是调用 actor 的 `PostSpawnInitialize` 函数，在这个函数中
	* 首先为每个 component 调用了 `OnComponentCreated` 这个虚函数回调（注意此时 SCS 还没有执行的，因此这里的 component 不包括 SCS 中的）
	* 然后是调用 actor 的 `PreRegisterAllComponents` 这个虚函数回调
	* 随后调用 actor `IncrementalRegisterComponents`
		* 它为每个 `bAutoRegister` 为 true（这个字段默认值即为 true）的 component 调用 `RegisterComponentWithWorld` 函数，这个函数负责调用 `OnRegister` 回调，以及为 component 创建渲染数据和物理数据。这里的代码逻辑保证 scene component 的父节点一定比子节点先调用 `RegisterComponentWithWorld`（更常见的 `RegisterComponent` 是该函数的一个 wrapper）
		* component 注册完毕后，调用 actor 的 `PostRegisterAllComponents` 虚函数回调
		* 调用 world 的 `NotifyPostRegisterAllActorComponents` 回调
	* 然后是调用 actor 的 `PostActorCreated` 虚函数回调
	* 然后调用 actor 的 `FinishSpawning`
		* 首先是从父类到子类，依次执行它们的 SCS 脚本，即 SCS 的 `ExecuteConstruction` 函数
		* 执行 construction script，即调用 `UserConstructionScript` 函数
		* 执行 actor 的 `OnConstruction` 虚函数回调
		* 最后是调用 actor 的 `PostActorConstruction` 函数
			* 调用 `PreInitializeComponents` 这个虚函数回调，它的默认实现是如果这个 actor 设置了 auto receive input，那么初始化这个 actor 的 input component
			* 调用 actor 的 `InitializeComponents` ，这个函数会调用每个 `bAutoActive` 为 true（默认为 false 的 component 的 `Activate` 虚函数回调，以及每个 `bWantsInitializeComponent` 为 true（默认为 false）的 `InitializeComponent` 虚函数回调
			* 最后是 actor 的 `PostInitializeComponents` 虚函数回调
			* 如果此时已经 begin play 了，那么调用 actor 的 `DispatchBeginPlay` 函数。这个函数主要是为 actor 自己和 component 注册 tick function，以及调用自己和 component 的 begin play 函数
* 最后是调用 uworld 的 `OnActorSpawned` 这个多播

接下来我们对这个流程中某些模块做更详细的说明
### SCS Execution
这一节我们展开说明 SCS 的执行

对于 scene component，simple construction script 以树的形式组织 scs node，它的 `RootNodes` 中包含了本层级的 scs node 根节点，而每个 scs node 的 `ChildNodes` 字段指定了它的子节点，在从 scs node 中创建新的 component 时，从根节点往下遍历，来保证 scene component 的父节点先于自己注册。同时 scs node 的 `ParentComponentOrVariableName` 记录了该以哪个 scene component 为 parent（用于 root scs node），而 `AttachToName` 指定 attach 到父类的哪个 socket 或者 bone 上

新 component 是以 scs node 中的 component template 或者是该蓝图子类的 `UInheritableComponentHandler` 中包含的重载的 component template 作为模板，调用 `StaticDuplicateObjectEx` 来创建

component 创建完成后，调用 `OnComponentCreated` 回调，对于 scene component 会调用 `SetupAttachment`，然后为 `bAutoRegister` 为 true 的 component 进行注册，这个流程与在构造函数中创建的 native component 几乎一致
### Component 回调梳理
按时间顺序，component 中包含的回调函数有
* `OnComponentCreated`，这是最早的回调函数，表示 component 创建好了
* `OnRegister`，这个回调函数发生在 component 创建渲染数据和物理数据时
* `Activate`，仅对 `bAutoActivate` 为 true（默认为 false）的 component 调用，它的默认实现会将 tick function 的 `TickState` 设置为 enable
* `InitializeComponent`，仅对 `bWantsInitializeComponent` 为 true（默认为 false）的 component 调用
* `RegisterComponentTickFunctions`，该函数的默认实现是为 component 注册 tick function
* `BeginPlay`
这个回调流程也可以从 `UActorComponent::RegisterComponentWithWorld` 的实现看出来。这是因为 `RegisterComponentWithWorld` 除了在 actor 创建时会调用该函数来注册 component，在运行时动态创建的 component 也会调用该函数来进行注册。因此该函数会根据该 component 的 owner actor 的状态来判断需要调用哪些回调函数。对于运行时动态创建的 component，此时 owner actor 已经 begin play 了，那么该函数会依次调用上面所有的回调
### Actor and Component Tick
这一节我们梳理 component 和 actor 与 tick 有关的字段

对于 component，我们最熟悉的是设置 `PrimaryComponentTick.bCanEverTick` 来指示该 component 是否可以进行 tick，这个字段默认为 false。另外一个有关的字段是 `PrimaryComponentTick.bStartWithTickEnabled`，它用来指示在注册 tick function 时要不要同时将 tick function 的 `TickState` 状态设置为 enable。如果 `TickState` 为 disable，那么即使注册了 tick function，它也不会被执行
```c++
/** Main tick function for the Component */
UPROPERTY(EditDefaultsOnly, Category="ComponentTick")
struct FActorComponentTickFunction PrimaryComponentTick;

/** Whether the component is activated at creation or must be explicitly activated. */
UPROPERTY(EditAnywhere, BlueprintReadOnly, Category=Activation)
uint8 bAutoActivate:1;

/** Whether the component is currently active. */
UPROPERTY(transient, ReplicatedUsing=OnRep_IsActive)
uint8 bIsActive:1;
```
这里一个尴尬的地方是，`PrimaryComponentTick.bStartWithTickEnabled` 的默认值为 true，而 `bAutoActivate` 的默认值为 false。因此如果我们仅仅在构造函数中将 `PrimaryComponentTick.bCanEverTick` 设置为 true，那么在 begin play 后确实 component 的 `TickComponent` 回调会被调用，但是它的 `bIsActive` 仍为 false。此时调用 `DeActivate` 函数不能够关闭掉 tick

因此如果需要 tick component，要么在构造函数中额外将 `bAutoActivate` 设置为 true，或者将 `PrimaryComponentTick.bStartWithTickEnabled` 设置为 false，后面需要 tick 时再调用 `Activate` 激活 component

但 actor 并没有这样的不一致性，因为它没有在外面包一层冗余的 activate 字段
```c++
UPROPERTY(EditDefaultsOnly, Category=Tick)
struct FActorTickFunction PrimaryActorTick;
```
### SetupAttachment vs AttachToComponent
一般的说法是 `SetupAttachment` 用于在构造函数中使用，而 `AttachToComponent` 用来 attach 动态创建的 component。不过实际上查看 `AttachToComponent` 源码会发现，它在开始时会检查调用位置是否位于构造函数中，如果是的话，就退化为 `SetupAttachment`

`SetupAttachment` 的实现只设置了该 component 的 `AttachParent`，`AttachSocketName` 等字段，但没有实际地将该 component 加入到 parent 的 `AttachChildren` 中。那这个操作是在哪被执行的呢？实际上 scene component 重载了 `OnRegister` 回调，在这里如果它发现自己的 `AttachParent` 非空，就会调用 `AttachToComponent` 来实际地将自己 attach 到 parent 上

值得一提的是，`AttachToComponent` 中会在子 component 的 tick function 的添加一个 prerequisites，来保证子 component 的 tick 一定在父 component 之后
### Component Creation Method
```c++
enum class EComponentCreationMethod : uint8
{
	/** A component that is part of a native class. */
	Native,
	/** A component that is created from a template defined in the Components section of the Blueprint. */
	SimpleConstructionScript,
	/**A dynamically created component, either from the UserConstructionScript or from a Add Component node in a Blueprint event graph. */
	UserConstructionScript,
	/** A component added to a single Actor instance via the Component section of the Actor's details panel. */
	Instance,
};
```
使用 C++ 代码创建的 component 默认为 `Native`（在构造函数中创建或者使用 `NewObject` 动态创建），`SimpleConstructionScript` 对应的是蓝图编辑器中添加的 component，而 `Instance` 是在 level editor 中编辑实例添加的 component，而 `UserConstructionScript` 就是蓝图中使用 `AddComponent` 等函数动态创建的 component



construct object from class，试了一下，actor 和 component 都不行，但是 user widget 成功了
[WTF Is? Construct Object From Class in Unreal Engine 4 ( UE4 )](https://www.youtube.com/watch?v=vA9K7kXOi8U) 中谈到这个节点的 class 不能设置为 actor 的子类。我试了一下，也不能设置为 actor component 的子类，[Why is the ‘Construct Object from Class’ node not accepting (any) classes?](https://forums.unrealengine.com/t/why-is-the-construct-object-from-class-node-not-accepting-any-classes/125652) 中谈到 class 必须标记为 blueprint type
TODO：看下这个节点的源码，看看它具体怎么检查的