## Delegates
代理的作用和 std::function 差不多，只是前者还有多播之类的额外变体。两者实现的核心技术都是 type erasure。type erasure 的关键难点在于消除对象的类型后（例如通过一块动态分配的内存存储对象），在调用时该如何把对象的类型又拿回来。[How is std::function implemented?](https://stackoverflow.com/questions/18453145/how-is-stdfunction-implemented) 中提供了两种思路，一种是通过父类虚函数+模板子类的方式，另一种是通过模板成员函数的方式。ue 的代理实现使用的是前者的方法
### 单播代理
* 单播代理相关的宏 `DECLARE_DELEGATE` 实际上 typedef 了一下 `class TDelegate<>` 模板，默认情况下，`TDelegate` 的父类是 `class TDelegateBase<>`，而它内部有一个 `DelegateAllocator`，这个 allocator 提供了核心的泛化能力。简而言之，对于不同的 BInd 情况，内部会存储不同的 `DelegateInstance` 类型（创建 `DelegateInstance` 模板类型的函数当然也是一个模板函数）。如何存储不同的类型呢，调用 allocator 分配 `DelegateIntance` 大小的堆内存，然后利用 new 运算符在这块内存上调用 `DelegateInstance` 构造函数即可（每次绑定新代理函数时，调用原来的 `DelegateInstance` 的析构函数）
  * 总的说来，`TDelegate` 内部只有来自基类 `TDelegateBase` 的两个成员变量 `DelegateAllocator` 和 `DelegateSize`，前者作为一个分配器，存储了指向堆上 `DelegateInstance` 的指针，后者表示实际分配的大小
  * 不同的 `DelegateInstance` 都继承自基类 `IBaseDelegateInstance<FuncType, UserPolicy>`，这个基类提供了 `Execute` 等接口。而调用 `TDelegate`  的 `Execute` 等函数时，都是获取到堆上的 `DelegateInstance`（强转为它们的共同基类 `IBaseDelegateInstance` 的指针），调用 `DelegateInstance` 的 `Execute` 函数来执行。这里的 `IBaseDelegateInstance::Execute` 就是实现 type erasure 需要的父类虚函数，而后面提到的 BindRaw 等函数用到的它的子类就是实现 type erasure 需要的模板子类
  * 能否将 `TDelegate<>` 泛化得可以绑定任何参数和返回值的函数，而不需要把参数和返回值类型写在类模板参数里面？可以，但我觉得没必要（例如目前 `TDelegate<>` 中的 `Execute` 函数不是一个模板函数，因为参数类型都给在类模板里了，如果希望 `TDelegate<>` 类能够绑定任何函数，那么就需要将 `Execute` 函数变成一个模板函数，参数类型作为模板参数）

* BindRaw
  * 实际的 `DelegateInstance` 为 `TBaseRawMethodDelegateInstance`
  * 绑定一个成员函数和它的类实例指针，这俩参数保存在 `TBaseRawMethodDelegateInstance` 的 `UserO bject` 和 `MethodPtr` 成员变量中
  * 可以额外绑定一些参数值，这些参数值存储在 `TBaseRawMethodDelegateInstance` 的父类 `TCommonDelegateInstanceState` 的 `TTuple` 成员中（作为一个元组）。这些参数值在成员调用时会被添加到参数末尾。**一个微妙的使用细节是，例如希望绑定的函数类型是 `int(float, int)`，并且我们希望绑定时添加默认参数 int，那么在代理声明时应该将函数声明为一个 int 返回值，一个 float 参数（即使用 `DECLARE_DELEGATE_RetVal_OneParam` 宏），这适用于任何 Bind 函数**

* BindStatic
  * 实际的 `DelegateInstance` 为 `TBaseStaticDelegateInstance`
  * 和 BindRaw 相似，不过绑定的是正常的函数，而不是类成员函数，因此不需要额外的 `UserObject` 成员变量

* BindLambda
  * 实际的 `DelegateInstance` 为 `TBaseFunctorDelegateInstance`
  * 和 BindStatic 没啥区别，不过绑定的是 lambda 函数（我想有这个函数的主要原因是 lambda 函数的类型比较复杂，实际上  `TBaseFunctorDelegateInstance` 中专门用了一个模板参数来表示 lambda 的类型）

* BindUobject
  * 实际的 `DelegateInstance` 为 `TBaseRawMethodDelegateInstance`
  * 感觉和 BindRaw 区别不大，只是说该函数限定了类实例是 UObject 的子类，然后存储该 UObject 时不是使用裸指针，而是用的 `TWeakObjectPtr`，**TODO：理解 UObject 的垃圾回收之后，回来理解这个类的实现**

* 还有其它的 BindSP，BindUFunction .... 等等
  * **TODO：理解 ue 的反射后再回来看 BindUFunction 是如何实现的**

### 多播代理
* 多播代理能够同时绑定多个需要调用的函数。`DECLARE_MULTICAST_DELEGATE` 系列宏实际上 typedef 了一下 `TMulticastDelegate<>` 模板，它内部也只有来自基类的 `TMulticastDelegateBase` 的成员变量 `InvocationList`，`CompactionThreshold`，`InvocationListLockCount`
  * 最核心的是这个 `InvocationList`，它是一个由 `TDelegateBase` 组成的动态列表。调用代理的 `Broadcast` 时，会遍历这个 `InvocationList` 中的 `TDelegateBase`，获取它的 `DelegateInstance`，然后调用 `DelegateInstance` 的 `ExecuteIfSafe` 函数
* 当我们调用 `TMulticastDelegate` 的 `AddStatic`，`AddUObject` 等函数时（它们对应单播情况的 `BindStatic`，`BindUObject`），`TMulticastDelegate` 会创建一个 `TDelegate`，它内部的 `DelegateInstance` 保存了调用需要的所有信息（具体保存了哪些信息已经在单播代理中讲过了）。然后将这个 `TDelegate` 加入到 `InvocationList` 中
* 每个 `DelegateInstance` 都有一个唯一的 `FDelegateHandle`，调用 `AddStatic` 等函数时，会将创建的 `DelegateInstance` 的 `FDelegateHandle` 作为返回值返回。如果要移除某一个函数，调用 `Remove` 函数时传入这个 Handle（**可以在回调函数内调用 `Remove`，多播内部有个 counter 来避免 for 循环过程中删除元素产生错误**）
* 多播代理不保证各个函数的调用顺序

### 动态代理（Dynamic Delegates）
* 动态代理也分单播和多播。
* 与普通代理不同，声明单播的系列宏 `DECLARE_DYNAMIC_DELEGATE` 不是一个 typedef，而是定义了一个新的类，它继承自 `TBaseDynamicDelegate` 类。而 `TBaseDynamicDelegate` 又继承自 `TScriptDelegate`。整个类中唯一的成员变量是 `TScriptDelegate` 中的 `Object` 和 `FunctionName`。前者是一个指向 `UObject` 的弱引用，后者是绑定的函数名。每次调用 `Execute` 函数时，都会根据函数名和 `Object`，利用反射进行查找得到 `UFunction` 进行调用。因此动态代理的执行速度更慢x
  * 调用 `BindDynamic` 函数会绑定 `Object` 和 `FunctionName`。实际上 `BindDynamic` 是一个宏，会根据传入的函数来获取函数名（因为我们只需要 `FunctionName`）。这里是一个极其精彩的使用模板进行编译期计算的例子，具体可以查看 `STATIC_FUNCTION_FNAME` 宏
* 类似地，声明多播的系列宏 `DECLARE_DYNAMIC_MULTICAST_DELEGATE` 定义了一个新的类，它继承自 `TBaseDynamicMulticastDelegate`，而该父类又继承自 `TMulticastScriptDelegate`，整个类仅有一个成员变量 `InvocationList`。类似于普通代理的多播，这个 `InvocationList` 是一个 `TScriptDelegate` 数组。每次调用 `AddDynamic` 函数（宏）时，就会利用 `Object` 和 `FunctionName` 创建一个 `TBaseDynamicDelegate`，然后加入到 `InvocationList` 中。唯一的区别是，普通多播是通过返回的 Handle 来区分绑定的函数，而动态多播是根据 `Object` 指针和 `FunctionName` 来区分绑定的函数
* 当多播的动态代理的 uproperty 包含 BlueprintAssignable 时可以从蓝图中绑定事件，当包含 BlueprintCallable 时可以从蓝图中调用 broadcast。对于单播的动态代理，设置 uproperty 包含 BlueprintReadWrite。但貌似没办法在蓝图中 call 它。相关的讨论见: [How to setup Dynamic Single Delegate (with RetVal) to make it bindable from Blueprints?](https://forums.unrealengine.com/t/how-to-setup-dynamic-single-delegate-with-retval-to-make-it-bindable-from-blueprints/764150)
* 蓝图中的 event dispatcher 其实就是动态多播代理。如果一个成员包含 BlueprintAssignable 的动态多播，或者是 event dispatcher，那么在蓝图编辑器中属性栏中的 event 部分可以看到它，点击旁边的加号就可以快速绑定 event（这其实是 bind xxx 的简洁表示了）
* TODO：区分普通代理的 `BindUFunction` 和动态代理（两者都用函数名，通过反射来查找要执行的函数）
* TODO：[UE4 Delegate 实现原理分析](https://zhuanlan.zhihu.com/p/165126317) 中谈到相比于普通代理，动态代理支持序列化，因此能够在蓝图中使用。如何理解这段话，支持序列化和在蓝图中使用有什么必然联系吗？