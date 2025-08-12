---
title: UObject Initialization in Unreal
date: 2025-01-06 12:26:30 +0800
comments: true
categories:
  - UE5
---

### GENERATED_BODY vs GENERATED_UCLASS_BODY
我认为这俩货的主要区别在构造函数的声明上，GENERATED_UCLASS_BODY 是一个 legacy 的宏，它始终生成如下的构造函数
```c++
AABroadcastActor(const FObjectInitializer &ObjectInitializer = FObjectInitializer ::Get());
  static void __DefaultConstructor(const FObjectInitializer &X) {
    new ((EInternal *)X.GetObj()) AABroadcastActor(X);
  }
```
因此用户如果使用 `GENERATED_UCLASS_BODY` 宏，不能再声明自己的构造函数，只需要在 cpp 里实现这个签名的构造函数即可
而使用 `GENERATED_BODY` 是推荐的做法，它相对来讲更灵活一些：
* 如果用户声明了自己的构造函数（带或者不带 `FObjectInitializer` 参数），那么该宏不再生成构造函数的声明，并且生成的 `__DefaultConstructor` 是下面的哪种取决于用户声明的构造函数是否带 `FObjectInitializer` 参数，如果用户两种都声明了，那么生成第二种 `__DefaultConstructor`
```c++
  // 1
  static void __DefaultConstructor(const FObjectInitializer &X) {
    new ((EInternal *)X.GetObj()) AABroadcastActor(X);
  }
  // 2
  static void __DefaultConstructor(const FObjectInitializer &X) {
    new ((EInternal *)X.GetObj()) AABroadcastActor(X);
  }
```
* 而如果用户没有声明自己的构造函数，首先该宏会生成与 GENERATED_UCLASS_BODY 一样的构造函数声明与 `__DefaultConstructor` 定义。此外，它还会在 `*.gen.cpp` 中额外生成构造函数的定义
```c++
AABroadcastActor::AABroadcastActor(const FObjectInitializer& ObjectInitializer) : Super(ObjectInitializer) {}
```
至于 [GENERATED_BODY vs GENERATED_UCLASS_BODY](https://forums.unrealengine.com/t/generated-body-vs-generated-uclass-body/322489) 中谈到的影响该宏后面的字段默认是 public 还是 private 都是次要的事情了

另外可能疑惑的是下面俩构造函数有啥区别
```c++
MyClass(const FObjectInitializer &ObjectInitializer);
MyClass();
```
如果我们希望 MyClass 的子类能够重载 MyClass 或者它的父类中的 default sub object 的类型的话，那么 MyClass 就需要有带 object initializer 的构造函数声明。因为子类通常会调用 object initializer 的 `SetDefaultSubobjectClass` 函数来指定需要重载的 sub object 的名称以及它的类型（当然需要是默认类型的子类），见 [UE4：FObjectInitializer相关](https://zhuanlan.zhihu.com/p/383812803)
```c++
ACatProjCharacter::ACatProjCharacter(const FObjectInitializer& ObjectInitializer)
: Super(ObjectInitializer.SetDefaultSubobjectClass<UCatProjMovementComponent>(ACharacter::CharacterMovementComponentName))  
{
}
```
如果父类不支持带 object initializer 参数的构造函数就没法这样做了。为什么不把这个 `SetDefaultSubobjectClass` 函数的调用写到子类的构造函数里面呢？因为子类的构造函数调用时已经晚了，父类的构造函数都已经执行完了，因此这里实际上是巧妙地塞了一些逻辑，它在父类的构造函数执行前被执行
实际上 ue 也不允许 `SetDefaultSubobjectClass` 在构造函数中被调用，因为 uobject 的构造函数中会将 object initializer 的 `bSubobjectClassInitializationAllowed` 字段设置为 false，`SetDefaultSubobjectClass` 函数中会检查该字段，如果为 false，那么会报错

另外，这个重载机制并不局限于只能重载父类的 sub object，还可以是 sub object 的 sub object。重载信息记录在 object initializer 的 `SubobjectOverrides` 字段
```c++
/**  List of component classes to override from derived classes **/
mutable FOverrides SubobjectOverrides;
```
这个 `FOverides` 的类型是一个树状的结构，树节点的父子关系就是 object 和 sub object 的关系，节点通过名字索引，保存了这个 object 需要重载的新类型。然后在 object initializer 的 `CreateDefaultSubobject` 函数中，会在 `SubobjectOverrides` 字段中进行查找，看看是否即将创建的这个 sub object 的类型有被重载
### NewObject and CreateDefaultSubobject
`NewObject` 的大概流程
* 首先做了一个 check，如果这个 object 的 name 为 none，并且通过 `FObjectInitializer` 检测到此时的逻辑处于 Outer 的构造函数，报错
* 然后将逻辑转发给 `StaticConstructObject_Internal` 函数
在 `StaticConstructObject_Internal` 函数里，
* `StaticAllocateObject` 分配内存，TODO：如果 `bSubObject` 为 false，call `UObjectBase` 的构造函数？为什么？
* 在 `StaticAllocateObject` 分配的内存上调用该 object 的构造函数，同时初始化新的 `FObjectInitializer`，将这个 object initializer 推到 `FUObjectThreadContext` 这个全局单例的 `InitializerStack` 的栈顶
* 在 `FObjectInitializer` 的析构函数中，会把自己从栈顶弹出，然后调用 `PostConstructInit` 函数
* 在 `PostConstructInit` 函数中
	* 会对结束构造的 obj 调用 `InitProperties`，来 copy CDO 中的一些数据到当前的 obj 里
	* 对当前的 obj 调用完 `InitProperties`，又调用 `InitSubobjectProperties` 函数，这个函数又对这个 obj 的所有 sub object 调用 `InitProperties`
	* 然后又对每个 sub obj 调用 `PostReinitProperties`
	* 对当前的 obj 调用 `PostInitProperties`
`CreateDefaultSubobject` 的流程是类似的，核心的构造也是通过 `StaticConstructObject_Internal` 完成的，只是在调用 `StaticConstructObject_Internal` 前会在当前的 object initializer 中查找这个需要构造的 default sub object 是否有被重载了，另外在调用 `StaticConstructObject_Internal` 后会将返回的 sub object 加入到 object initializer 的 `ComponentInits` 字段中，这样在 object initializer 的析构函数中通过遍历 `ComponentInits`，就能对每个 sub object 调用上面提到的 `InitProperties` 等函数了

因此大概的图像是，调用链的顶层是 `NewObject`，要构造的 object 的构造函数内部可能进一步调用 `CreateDefaultSubobject`，整个调用链形成了一颗树结构，树的每个节点对应一个 object，以及一个 object initializer，`FUObjectThreadContext` 单例的 initializer stack 反映了当前 `CreateDefaultSubobject` 的递归调用状态。object initializer 的入栈出栈过程实际上是对这颗树结构深度优先遍历的过程

object initializer 的 `PostConstructInit` 函数中对象构建调用了下面五个函数
* `FObjectInitializer::InitProperties`
* `FObjectInitializer::InitSubobjectProperties`
* `FObjectInitializer::InstanceSubobjects`
* `UObject::PostInitProperties`
* `UObject::PostReinitProperties`
#### Object Archetype
在这一节我们对三个概念进行区分：default subobject, object archetype, class default object

我们先讨论什么是 object archetype。archetype 顾名思义，就是指这个 object 是以哪个 object 为基准构造出来的。`UObject::GetArchetype` 函数实现了获取 uobject 的 archetype 的接口。根据该函数的实现，我们知道 uobject 的 archetype 有几种可能：
1. 如果 object 是 CDO，那么它的 archetype 是该 CDO 的父类。这看起来比较合理，因为子类的一部分数据是由父类初始化的
2. 否则，获取该 object 的 outer 的 archetype，如果有以该 archetype 作为 outer 并且名称和类型与 object 相符的 obj，那么这个 obj 就是 object 的 archetype
3. 而如果该 object 的 outer 是一个蓝图类，那么会调用 `UBlueprintGeneratedClass::FindArchetype` 进行寻找，这是因为蓝图类可以用 SCS 构建 component。如果能找到，那么 object 的 archetype 是对应 `USCS_Node` 的 `ComponentTemplate` 字段
4. 因为蓝图子类不会存储蓝图父类的 SCS，因此如果该 object 是由蓝图父类的 SCS 引入的话，在子类的 SCS 中是找不到的。但 ue 允许用户编辑子类中的 component 属性，并于父类的 component 属性相互独立，因此 ue 在这里额外引入了一个 `UInheritableComponentHandler`，它存储了父类的 `USCS_Node` 到一个新的 component template 的映射。因此我们编辑子类的从父类继承来的 component 的属性时，实际上是在编辑 `UInheritableComponentHandler` 对应的 component template。然后这里如果名字和类型对上了的话，它就是我们要找的该 object 的 archetype
5. 如果以上的方法都找不到，那这个 object 的 archetype 就是 它的 CDO

TODO：在 `UBlueprintGeneratedClass::FindArchetype` 中，如果在该类的 SCS 和 `UInheritableComponentHandler` 中都没有找到 archetype 的话，会循环地在蓝图父类的 SCS 和 `UInheritableComponentHandler` 中找，什么时候子类中找不到，但是父类却能找到呢

我们举一些例子来具体的理解一下一个 object 的 archetype。现在我们有 Native Class A，A 的构造函数中调用了 create default subobject 函数生成了 SUB，然后 Native Class B 继承自 A，同时还有蓝图类 C，它通过 SCS 将 A 作为它的一个 component
现在我们通过 new object 得到 Class A，B，C 的实例 A_TMP，B_TMP，C_TMP
* A_TMP 的 archetype 显然是类 A 的 CDO，这也符合我们对 archetype 的直觉，因为 A_TMP 的原型应该是这个类的 CDO
* A_TMP 的 subobject A_TMP_SUB 的 archetype 呢？它的 outer 的 archetype 是 Class A 的 CDO，然后这个 CDO 的 subobject A_CDO_SUB 以 A_CDO 为 outer，因此根据规则 2，A_TMP_SUB 的 archetype 是 A_CDO_SUB。换句话说，一个类实例的默认子对象的原型是该类 CDO 的对应默认子对象。请注意，A_CDO_SUB 不是 SUB 类的 CDO，而它的 archetype 是 SUB 类的 CDO
* 同样地，B_TMP 的 archetype 自然也是类 B 的 CDO，而 B_TMP_SUB 的 archetype 是 B_CDO_SUB。那 B_CDO_SUB 的 archetype 呢，根据上面的逻辑，它的 outer 是 B_CDO，outer 的 archetype 是 A_CDO，因此 B_CDO_SUB 的 archetype 是 A_CDO_SUB。换句话说，CDO 的默认子对象如果是从父类继承而来，那么它的原型就是父类的 CDO 的默认子对象，否则原型是该默认子对象类的 CDO
* 由于 A 通过 SCS 加入到蓝图类 C 中，因此 C_TMP_A 的 archetype 是类 C 的 SCS 中的 component template。进一步，这个 component template 的 outer 是蓝图类 C 的 class，因此它的 archetype 是 A_CDO，而 C_TMP_A 的默认子对象 C_TMP_A_SUB 的 archetype 则是 component template 的默认子对象
在 [UObjcet & UClass基础（四）— DefaultSubobject、Archetype Object、Instance Object](https://zhuanlan.zhihu.com/p/679598557) 中有类似的阐述

此时再来看 [一文搞懂 UE5 用C++编辑蓝图资产全方法](https://zhuanlan.zhihu.com/p/9413775239) 就好理解了。这实际阐述的是，当我们在蓝图编辑器中修改类的属性值时，到底修改的是哪个类。根据这篇文章或者自己测试会发现，修改的实际上就是对应实例的 archetype。比如对于上面举例的蓝图类 C，我们修改蓝图类 C 的 details 面板中的属性值，实际上修改的是蓝图类 C 的实例 C_TMP 的 archetype。例如我们修改 component A 的某个 uproperty 值，就修改的是类 C 的 component template

现在我们来看看什么是 default subobject。但首先需要定义什么是 subobject，根据 [Subobjects vs Components.](https://forums.unrealengine.com/t/subobjects-vs-components/232)，如果一个 object 的 outer 不是 UPackage，那么这个 object 就是 outer 的 subobject。而 default subobject 的判断逻辑如下
```c++
bool UObjectBaseUtility::IsDefaultSubobject() const
{
	// For historical reasons this behavior does not match the RF_DefaultSubObject flag.
	// It will return true for any object instanced using a non-CDO archetype, 
	// but it will return false for indirectly nested subobjects of a CDO that can be used as an archetype.
	
	return !HasAnyFlags(RF_ClassDefaultObject) && GetOuter() &&
		(GetOuter()->HasAnyFlags(RF_ClassDefaultObject) || ((UObject*)this)->GetArchetype() != GetClass()->GetDefaultObject(false));
}
```
要求是自己不是 CDO，且 outer 是 CDO 或者自己的 archetype 不是 CDO。现在我们通过 new object 创建一个 object，这个 object 的 default subobject 有哪些呢？可以看到，不仅仅是在 C++ 中通过 create default subobject 中创建出来的对象，还包括了在 SCS 中创建出来的对象。直观上来讲，default subobject 是 object 初始化完成后就包含的 subobject

关于 CDO 和 SCS 以及 `UInheritableComponentHandler`，[UE4源码剖析——Actor蓝图之CDO与SCS](https://zhuanlan.zhihu.com/p/681252301) 也值得一读
#### Property Initialization
现在我们看看 `FObjectInitializer::InitProperties` 的实现，它将 `Obj` 中用 uproperty 标记的字段 copy 到 `DefaultData` 中
```c++
static COREUOBJECT_API void InitProperties(UObject* Obj, UClass* DefaultsClass, UObject* DefaultData, bool bCopyTransientsFromClassDefaults);
```
对于不同的输入 obj，它的表现稍有不同。首先，如果 `DefaultData` 不是 `Obj` 的 CDO 或者 `bCopyTransientsFromClassDefaults` 为 true，那么它会从 `DefaultData` 中 copy 所有的 uproperty 的值到 `Obj` 中，反之，则只 copy 在 post construct link 上的 uproperty。那么哪些是在 post construct link 上呢?
```c++
// Link references to properties that require their values to be initialized and/or copied from CDO post-construction. Note that this includes all non-native-class-owned properties.
if (OwnerClass && (!bOwnedByNativeClass || (Property->HasAnyPropertyFlags(CPF_Config) && !OwnerClass->HasAnyClassFlags(CLASS_PerObjectConfig))))
{
	*PostConstructLinkPtr = Property;
	PostConstructLinkPtr = &(*PostConstructLinkPtr)->PostConstructLinkNext;
}
```
这个 link 在 `UStruct::Link` 中构建，即只有用 config 标记或者这个 uproperty 被蓝图而非 native c++ class 定义时，会被加入到 post construct link 中
从这里我们可以一窥 ue 中是怎么理解 C++ 的构造函数的。它希望用户在构造函数中的逻辑仅仅是为成员赋上默认值，以及创建默认子对象（下面会谈到构建中处理默认子对象的逻辑），所以它认为对于一般的 uproperty，执行完构造函数的 `Obj` 中包含的值应与 CDO 一致，作为一个优化，就不必将这些 uproperty 加入到 post construct link 上了。唯一例外的是用 config 标记的 uproperty，我们希望它的值从配置文件中来，所以将 config 标记的 uproperty 加入到 post construct link。`PostConstructInit` 函数在执行完 `InitProperties` 后，对于 CDO，它会从 config 中读取数据
```c++
if (bIsCDO || Class->HasAnyClassFlags(CLASS_PerObjectConfig))
{
	Obj->LoadConfig(NULL, NULL, bIsCDO ? UE::LCPF_ReadParentSections : UE::LCPF_None);
}
```
由此 config value 从配置文件中 copy 到 CDO 的字段中，然后再经由 post constructor link，copy 到 obj 实例上

而蓝图类的 post construct link 就长很多了，因为在蓝图中定义的 uproperty 都要添加进 post construct link 中。这也很好理解，这样保证了我们在蓝图编辑器中设置的数据值就是实例的默认值，符合 ue 提供给我们的直觉
但这样还有些问题，例如蓝图类可能有个 C++ 父类，我们实际上也可以在蓝图编辑器中编辑 C++ 父类的 uproperty，如何保证 C++ 父类的 uproperty 也会作为实例的默认值呢？ ue 的做法是给 `InitProperties` 函数开了个洞，最后调用了 UClass 的一个虚函数回调
```c++
// This step is only necessary if we're not iterating the full property chain.
if (bCanUsePostConstructLink)
{
	// Initialize remaining property values from defaults using an explicit custom post-construction property list returned by the class object.
	Class->InitPropertiesFromCustomList((uint8*)Obj, (uint8*)DefaultData);
}
```
`UBlueprintGeneratedClass` 中重载了 `InitPropertiesFromCustomList`，这个函数会读取 `UBlueprintGeneratedClass` 此前构建的链表结构 `CustomPropertyListForPostConstruction`，这个链表中保存了 C++ 父类中需要 copy 的 uproperty，然后这个函数将 `DefaultData` 中对应 uproperty 中的数据 copy 到 `Obj` 中
```c++
/** List of native class-owned properties that differ from defaults. This is used to optimize property initialization during post-construction by minimizing the number of native class-owned property values that get copied to the new instance. */
TIndirectArray<FCustomPropertyListNode> CustomPropertyListForPostConstruction;
```
构建这个链表结构的代码在 `UBlueprintGeneratedClass::BuildCustomPropertyListForPostConstruction` 中，如果一个 uproperty 定义在 C++ 父类中，同时蓝图子类 CDO 中该 uproperty 的值还与 C++ 父类中的值不相同，那么就会加入到该链表中

TODO：我是感觉完全没必要引入这个 `CustomPropertyListForPostConstruction` 链表，修改一下 post construction link 的构建逻辑就好了
#### Subobject Property Initialization
在之前的讨论中我们只考虑了 uproperty 为 int，float 等基本数据的情况。现在我们将 default subobject 加入讨论范围，这里的 default subobject 不包含 SCS，仅包括构造函数中调用 create default subobject 产生的 subobject。因为 SCS 是在 `AActor::FinishSpawning` 阶段被执行的，此时 `NewObject` 产生 actor 已经调用结束了

在蓝图编辑器中，我们可以编辑 default subobject 的默认值。ue 提供的保证是，当创建一个新的蓝图对象时，它的 default subobject 的值应该与蓝图编辑器中我们编辑的默认值相同。那 `PostConstructInit` 函数中哪里执行了 default subobject 的 copy 操作呢？这就是`FObjectInitializer::InitSubobjectProperties` 负责的了
在 `FObjectInitializer::CreateDefaultSubobject` 中，对于刚创建出的 default subobject `Result`，如果它的 outer 的 archetype 位于蓝图中，就会将 `Result` 和它的 archetype 加入到 object initializer 的 `ComponentInits` 字段中，为在 `PostConstructInit` 中进行二次初始化做准备
```c++
Result = StaticConstructObject_Internal(Params);

else if (!bIsTransient && Outer->GetArchetype()->IsInBlueprint())
{
	UObject* MaybeTemplate = Result->GetArchetype();
	if (MaybeTemplate && Template != MaybeTemplate && MaybeTemplate->IsA(ReturnType))
	{
		ComponentInits.Add(Result, MaybeTemplate);
	}
}
```
然后在 `PostConstructInit` 中调用了 `InitSubobjectProperties` 函数，这个函数为每个 subobject 调用 `InitProperties` 函数，将这个 subobject 的 archetype 中的所有 uproperty 的值 copy 到这个 subobject 中（根据前面讨论的 archetype 的寻找规则，subobject 的 archetype 是它的 outer 的 CDO 的 subobject，而这通常不是一个 CDO，因此根据 `InitProperties` 的逻辑，会执行一个 fully uproperty copy，而不仅仅是 post construction link 上的 uproperty），而这个 subobject 的 archetype 正是我们在蓝图编辑器中编辑的对象。这就保证了我们在蓝图编辑器中设置子对象的默认值会被 copy 到新构建的蓝图实例的子对象中

这里马上会想到两个问题
* 蓝图编辑器中还可以编辑 default subobject 的 default subobject 的 uproperty 的值，那岂不是得递归地调用 `InitProperties` 来继续初始化 default subobject 的 default subobject？
* 如果 `InitProperties` 进行了 fully uproperty copy，岂不是把指向 default subobject 的指针也给覆盖了？那我的默认子对象不就没了？

第一个问题的答案显然是肯定的，那递归的逻辑在哪呢？就在上面代码递归构建子对象以及判断 Outer 的 archetype 是否位于蓝图中这里
```c++
Result = StaticConstructObject_Internal(Params);

else if (!bIsTransient && Outer->GetArchetype()->IsInBlueprint())
{
	UObject* MaybeTemplate = Result->GetArchetype();
	if (MaybeTemplate && Template != MaybeTemplate && MaybeTemplate->IsA(ReturnType))
	{
		ComponentInits.Add(Result, MaybeTemplate);
	}
}
```
举一个例子，我们创建蓝图类 C 的实例 C_TMP，然后类 C 有个默认子对象 B，称为 C_TMP_B，而 B 里又有一个默认子对象 A，称为 C_TMP_B_A，创建实例 C_TMP 的调用栈是：
* 首先类 C 的构造函数执行，它的 C++父类中调用 create default subobject 构造 C_TMP_B
* 由此 C_TMP_B 的构造函数执行，在这个构造函数里又调用 create default subobject 构造 C_TMP_B_A
* 在 `StaticConstructObject_Internal` 将 C_TMP_B_A 构造完毕返回后，它会将 C_TMP_B_A 和它的 archetype，即蓝图类 C 的 CDO 的美容子对象 B 的默认子对象 A（这正是我们在蓝图编辑器中编辑的对象），加入到 object initializer 的 `ComponentInits` 字段中
* 然后在 C_TMP_B 的 object initializer 析构时，调用 `PostConstructInit`，然后在 `InitSubobjectProperties` 中将 C_TMP_B_A 的 uproperty 初始化为蓝图类 C 的 CDO 的美容子对象 B 的默认子对象 A 的 uproperty（请注意，此时 C_TMP_B 的 uproperty 值是由 B 的 CDO 初始化的，是在 C_TMP  的 object initializer 析构时调用 `InitSubobjectProperties`，C_TMP_B 的 uproperty 才会初始化为我们想要的 C 的 CDO 的默认子对象 B 的 uproperty 值，虽然我也不知道为啥要这样设计）

然后是 ue 是如何处理 default subobject 的指针被 `InitProperties` 覆盖的问题的，这就引出了 `FObjectInitializer::InstanceSubobjects`
#### Object Instantiation
在 `InstanceSubobjects` 中，会遍历 obj 和 `ComponentInits` 中保存的 default subobject 的 uproperty ref link，这是避免遍历完整的 uproperty link 的一个小优化，ref link 除了基本的指针类型引用，还可能是 TArray 或者 TMap 之类的。对于需要 instance 的 uproperty，即 uproperty 中指定了 `Instanced` 关键字，或者引用的类型的 uclass 中指定了 `DefaultToInstanced` 关键字，会调用该 uproperty 的 `InstanceSubobjects` 函数
```c++
for ( FProperty* Property = RefLink; Property != NULL; Property = Property->NextRef )
{
	if (Property->ContainsInstancedObjectProperty() && (!InstanceGraph || !InstanceGraph->IsPropertyInSubobjectExclusionList(Property)))
	{
		Property->InstanceSubobjects( Property->ContainerPtrToValuePtr<uint8>(Data), (uint8*)Property->ContainerPtrToValuePtrForDefaults<uint8>(DefaultStruct, DefaultData), Owner, InstanceGraph );
	}
}
```
例如我们最常见的 default subobject `ActorComponent` 就有 `DefaultToInstanced` 标记。这个函数干的事情也很直观，基本上就是根据提供的 Outer 以及 archetype 中的 ref uproperty 的名称，调用 `StaticFindObjectFast` 将之前已经创建好，但是指针被 `InitProperties` 覆盖的 default subobject 从全局的 uobject 哈希表中又捞出来了

TODO：调试看了一下，在蓝图类的 CDO 创建时，这里调用 `StaticFindObjectFast` 会找不到 subobject，然后调用 `StaticConstructObject_Internal` 重新创建一个新的 default subobject，这其实挺离谱的，因为我已经在构造函数里调用 create default subobject 创建了这个子对象了，这导致白创建了一个 default subobject，不知道 ue 是咋想的
TODO：这其实引入另一个我更关心的问题，蓝图类的 CDO 获取默认值的代码是在哪，毕竟修改后的蓝图是需要序列化到磁盘的
#### Instanced and DefaultToInstanced Property
[UObjcet & UClass基础（四）— DefaultSubobject、Archetype Object、Instance Object](https://zhuanlan.zhihu.com/p/679598557) 中举的例子特别好：如果 UProperty 的对象没有 Instanced 或者 class 不是 DefaultToInstanced，就没有办法在编辑器中编辑它的值，因为我不是它的 owner

我们前面的讨论都假定了这个 default subobject 的 uproperty 引用都有 `Instanced` 标记，或者对应的 uclass 有 `DefaultToInstanced` 标记。但我们可以排列组合出四种情况
* instanced uproperty，创建 default subobject
* uproperty，创建 default subobject
* instanced uproperty，不创建 default subobject  --> 看看 new object with template 这条路径
* uproperty，不创建 default subobject

[UObjcet & UClass基础（四）— DefaultSubobject、Archetype Object、Instance Object](https://zhuanlan.zhihu.com/p/679598557) 中尝试了第二种情况，然后对外的表现是
* 蓝图类的 CDO 的 default subobject 指向 Native C++ 父类的 CDO 的 default subobject，而不是自己有一个单独的 default subobject
* 蓝图类的实例仍能创建出自己单独的 default subobject，但它的 `IsDefaultSubobject` 函数返回 false
`IsDefaultSubobject` 函数返回 false 很好理解，因为这个函数内部查找该 default subobject 的 archetype，由于此时蓝图类的 CDO 不再有自己单独的 default subobject，最终导致该 default subobject 的 archetype 返回的是本类的 CDO，进而 `IsDefaultSubobject` 函数返回 false
蓝图类的实例仍会创建出自己单独的 default subobject 是因为 `UBlueprintGeneratedClass::BuildCustomPropertyListForPostConstruction` 中构建 `CustomPropertyListForPostConstruction` 链表时，会比较蓝图子类的 CDO 和 native c++ class 的 CDO 的 property 是否相同，如果不相同的话才加入到 InitPropertiesFromCustomList 中，而蓝图子类的 class default object 直接使用了 native c++ class 的中 sub object，导致这里判断发现蓝图子类的 CDO 和 native c++ class 的 CDO 的 property 相同，因此这个 uproperty 没有被加入到链表中，进而在构造函数中创建出的 default subobject 没有在 `InitProperties` 函数中被覆盖掉
至于为什么蓝图子类的 class default object 直接使用了 native c++ class 的中 sub object，是因为蓝图的 CDO 初始化时设置的 init property from archetype 为 true，导致在 `PostConstructInit` 中调用了 `InitProperties` 函数，而它的 archetype 是其父类的 CDO，不是本类的 CDO，因此在 InitProperties 中会做一个完整的 property copy，导致蓝图子类的 class default object 直接使用了 native c++ class 的中 sub object，而 native c++ 的 CDO 初始化时设置的 init property from archetype 为 false，因此不会调用 InitProperties

我认为第二种情况不属于 ue 的 uobject system 允许的对外接口。至于第四种情况，也是很常见的，就大家共享一个实例呗。稍微需要试一下的是第三种情况，需要确认 `NewObject` 是否会自动实例化新的对象出来。试了一下，不会，返回的对象相应的 instanced uproperty 的值仍然会 nullptr，即使手动地为 CDO 的 instanced uproperty 设置了一个对象
```c++
void FObjectPropertyBase::InstanceSubobjects(void* Data, void const* DefaultData, UObject* InOwner, FObjectInstancingGraph* InstanceGraph )
{
	for ( int32 ArrayIndex = 0; ArrayIndex < ArrayDim; ArrayIndex++ )
	{
		UObject* CurrentValue = GetObjectPropertyValue((uint8*)Data + ArrayIndex * ElementSize);
		if ( CurrentValue )
		{
			UObject *SubobjectTemplate = DefaultData ? GetObjectPropertyValue((uint8*)DefaultData + ArrayIndex * ElementSize): nullptr;
			UObject* NewValue = InstanceGraph->InstancePropertyValue(SubobjectTemplate, CurrentValue, InOwner, HasAnyPropertyFlags(CPF_InstancedReference) ? EInstancePropertyValueFlags::CausesInstancing : EInstancePropertyValueFlags::None);
			SetObjectPropertyValue((uint8*)Data + ArrayIndex * ElementSize, NewValue);
		}
	}
}
```
没有实例化出新对象的原因在于 `FObjectPropertyBase::InstanceSubobjects` 中会奇妙地检查一下此时新的对象的 instanced uproperty 的值是否为空，如果是，就直接返回了，没看明白为啥会这么搞

从上面的这些表现我们可以总结出 instanced uproperty 是干嘛的了，它不会自动地帮我们进行 deep clone（但是在构造函数中默认创建的对象需要是 instanced uproperty），而是用来表达外面的对象对这个 instanced uproperty 的主权，使得在序列化时可以一起序列化，并且可以在编辑器中 instanced uproperty 引用的 uobject 的 uproperty

TODO：看看为什么 UI 部件中大量使用 `Instanced` 标记
#### Post Initialization
最后还有两个 uobject 的回调函数
* `UObject::PostInitProperties`
* `UObject::PostReinitProperties`
当 uobject 完成的前面一系列的初始化后，`FObjectInitializer::PostConstructInit` 会调用构建出的 uobject 的 `PostInitProperties` 回调，以及对该 uobject 的 default subobject 调用 `PostReinitProperties`

例如 actor component 重载了 `PostInitProperties` 方法，将自己加入到 owner actor 的 `OwnedComponents` 字段中
### Object Duplication
流程梳理 `StaticDuplicateObjectEx`
* uobject 的 `PreDuplicate` 虚函数回调


TODO：uobject 的管理与内存分配