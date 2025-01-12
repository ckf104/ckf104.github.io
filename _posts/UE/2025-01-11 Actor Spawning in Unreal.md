
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
			* 

### Actor PostSpawnInitialize
对当前所有的 component 调用 `OnComponentCreated` 这个可回调的函数

OnComponentCreated
bHasDeferredComponentRegistration
RegisterAllComponents
 PostActorCreated

### SCS Execution
对于 scene component，simple construction script 以树的形式组织 scs node，它的 `RootNodes` 中包含了本层级的 scs node 根节点，而每个 scs node 的 `ChildNodes` 字段指定了它的子节点，在从 scs node 中创建新的 component 时，从根节点往下遍历，来保证 scene component 的父节点先于自己注册。同时 scs node 的 `ParentComponentOrVariableName` 记录了该以哪个 scene component 为 parent（用于 root scs node），而 `AttachToName` 指定 attach 到父类的哪个 socket 或者 bone 上

新 component 是以 scs node 中的 component template 或者是该蓝图子类的 `UInheritableComponentHandler` 中包含的重载的 component template 作为模板，调用 `StaticDuplicateObjectEx` 来创建

component 创建完成后，调用 `OnComponentCreated` 回调，对于 scene component 会调用 `SetupAttachment`，然后为 `bAutoRegister` 为 true 的 component 进行注册，这个流程与在构造函数中创建的 native component 几乎一致
### Component
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
试了一下，`Native` 对应的是 C++ 构造函数中创建的 default subobject，`SimpleConstructionScript` 对应的是蓝图编辑器中添加的 component，而 `Instance` 是在 level editor 中编辑实例添加的 component，而 `UserConstructionScript` 就是蓝图动态创建的 component（ construction script 也属于此例），但我发现直接创建 C++ NewObject 创建的 component 标记为 Native 的。。。


construct object from class，试了一下，actor 和 component 都不行，但是 user widget 成功了
[WTF Is? Construct Object From Class in Unreal Engine 4 ( UE4 )](https://www.youtube.com/watch?v=vA9K7kXOi8U) 中谈到这个节点的 class 不能设置为 actor 的子类。我试了一下，也不能设置为 actor component 的子类，[Why is the ‘Construct Object from Class’ node not accepting (any) classes?](https://forums.unrealengine.com/t/why-is-the-construct-object-from-class-node-not-accepting-any-classes/125652) 中谈到 class 必须标记为 blueprint type
TODO：看下这个节点的源码，看看它具体怎么检查的