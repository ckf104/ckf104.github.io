## UE Reflection and GC

### 关于 Reflection 的整体目标

* 每个对象有一个 meta 对象进行描述，**meta 对象具有相同的类型**。在 UE 中 uclass 描述 class，ufunction 描述 function，**fproperty 描述 property？**
* class 能够从 uclass 中动态创建，function 能够从 ufunction 中动态调用
* uclass，ufunction 等 meta 对象应该在什么时候创建？

### 一些重要的，需要回答的问题

* 哪些类型能作为 uproperty 或者 ufunction 的参数？

### Others

* Class Default Object？`FindObject` 函数找到元类型，可以用来枚举类型和字符串互转？我猜这个 CDO 和 static class 方法也有关系，然后 Super 是什么

  * 相应的，`TSubClassOf` 这个模板是在干嘛
  * UClass 继承自 UObject，那么 `UClass::StaticClass` 会得到又一个 UClass 类？递归这样会发生什么？
  * 为什么需要 CDO 呢？据说动态创建新的类型时复制 CDO，为什么不能直接调用构造函数什么的（这可能吗？反射能这么实现吗？毕竟我们要求不同的类型的元类都是 UClass，UClass 不能是一个模板）

* 哪些变量可以用 UProperty 宏进行声明？从 [properties](https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-uproperties) 文档中看来，我猜能用 UProperty 声明的有，基本的 int，float 和 bool 类型，UE 中用的三种字符串 FString，FName，FText，然后就是用 UENUM 包裹的 enum 以及用 UStruct 包裹的 sturct，**TODO：UClass 包裹的 class 类型可以吗？**

* UObject 的引用计数相关的

* UE 的 GC 是如何工作的，在 [Gameplay Classes](https://dev.epicgames.com/documentation/en-us/unreal-engine/gameplay-classes-in-unreal-engine) 文档中：

  >In order to ensure that components are always created, destroyed, and properly garbage-collected, a pointer to every component created in the constructor should be stored in a UPROPERTY of the owning class.

  为什么会有这样的要求？

* `FObjectFinder` 和 `FClassFinder`，以及 `ConstructorStatics` 是怎么工作的

* Cast 类型转换如何工作的

### Reflection 的全局注册（对 xxx.gen.cpp 文件的分析）

* `xxx.gen.cpp` 文件是具有一定层次结构的，顶层（在文件最后）是一个静态全局数据 `FRegisterCompiledInInfo`，这个数据包含了该编译单元内所有的反射信息。它的构造函数由四部分组成

  * 该编译单元所在的 package 的名字
  * `ClassInfo`，对应一个类型为 `FClassRegisterCompiledInInfo` 的数组，每个元素对应一个用 uclass 标记的 c++ class。**我们额外对 `FClassRegisterCompiledInInfo` 包含的内容进行说明，`ScriptStructInfo` 和 `EnumInfo` 待下次再探究**
    * `Info` 字段主要内容是包含 InnerSingleton 和 OuterSingleton 这两个字段，它们是 uclass 指针
    * `Name` 字段表示这个 c++ class 的名字
    * `OuterRegister` 和 `InnerRegister` 是两个函数指针，前者指向 `Z_Construct_UClass_<ClassName>` 函数，该函数根据 `FClassParams` 来构造一个 uclass，结果储存在 `Info.OuterSingleton` 中，后者指向我们熟悉的 `StaticClass` 函数，它内部调用 `GetPrivateStaticClassBody` 来构造一个 uclass，结果储存在 `Info.InnerSingleton` 中

  ```c++
  struct FClassRegisterCompiledInInfo
  {
  	class UClass* (*OuterRegister)();
  	class UClass* (*InnerRegister)();
  	const TCHAR* Name;
  	FClassRegistrationInfo* Info;
  	FClassReloadVersionInfo VersionInfo;
  };
  ```

  * `ScriptStructInfo`，对应一个类型为 `FStructRegisterCompiledInInfo` 的数组，每个元素对应一个用 ustruct 标记的 c++ struct
  * `EnumInfo`，对应一个类型为 `FEnumRegisterCompiledInInfo` 的数组，每个元素对应一个用 uenum 标记的 c++ enum

  这个数据结构的构造函数会调用 `RegisterCompiledInInfo` 函数，`RegisterCompiledInInfo` 会将每个 `FXXXRegisterCompiledInfo` 注册到 `TDeferredRegistry` 的 `Registrations` 中字段中，每个类型的 `TDeferredRegistry` 都有一个对应的静态变量。不同类型对应的 `TDeferredRegistry` 的模板参数不同

  ```c++
  using FClassRegistrationInfo = TRegistrationInfo<UClass, FClassReloadVersionInfo>;
  using FEnumRegistrationInfo = TRegistrationInfo<UEnum, FEnumReloadVersionInfo>;
  using FStructRegistrationInfo = TRegistrationInfo<UScriptStruct, FStructReloadVersionInfo>;
  using FPackageRegistrationInfo = TRegistrationInfo<UPackage, FPackageReloadVersionInfo>;
  
  using FClassDeferredRegistry = TDeferredRegistry<FClassRegistrationInfo>;
  using FEnumDeferredRegistry = TDeferredRegistry<FEnumRegistrationInfo>;
  using FStructDeferredRegistry = TDeferredRegistry<FStructRegistrationInfo>;
  using FPackageDeferredRegistry = TDeferredRegistry<FPackageRegistrationInfo>;
  ```

* 我们以 uclass 为例，自顶向下地说明反射信息是如何存储的。前面提到了 `Z_Construct_UClass_<ClassName>` 中的 `FClassParams`，它包含了一个 c++ class 的全部反射信息。其中一些关键的字段有

  * `PropertyArray`，它是一个 `FPropertyParamsBase` 数组，每个数组元素对应 class 中一个用 uproperty 标记的字段
  * `FClassFunctionLinkInfo`，一个 `FClassFunctionLinkInfo` 数组，每个数组元素对应 class 中用 ufunction 标记的函数
  * `ImplementedInterfaceArray`，它是一个 `FImplementedInterfaceParams` 数组，每个数组元素对应 class 实现的一个 ue interface

* 每个 UFunction 都会有一个对应的 `FClassFunctionLinkInfo` 和 `FFuncionParams` 数据。`FFunctionParams` 保存了一个 UFunction 的全部反射信息。`FClassFunctionLinkInfo` 由两个字段构成，一个是字符串，保存了 UFunction 的名字。一个是函数指针，它指向 `Z_Construct_UFunction_<ClassName>_<UFunctionName>` 函数，这个函数根据 `FFunctionParams` 构造出 UFunction 对象。而 `FPropertyParamsBase`

* 然后我们来看 `FFunctionParams` 的构成，它的一些重要字段包括

  * `NameUTF8`，表示函数名称的字符串

  * `PropertyArray`，它是一个 `FPropertyParamsBase` 数组，每个数组元素对应一个函数参数或者函数返回值
  * `StructureSize`，结构体 `<ClassName>_<UFunctionName>_Parms` 的大小，这个结构体由函数参数和函数返回值组成
  * TODO：outerfunc，superfunc，owningclassname，delegatename 等字段

* 最后我们来看看 `FFunctionParams` 和 `FClassParams` 底下都有的 `FPropertyParamsBase`，它包含一个 uproperty 的全部反射信息。不过 `FPropertyParamsBase` 是一个基结构体，实际上表示各类字段的是它的子类（虽然它们实际上没有继承关系）

  * `FEnumPropertyParams` 和 `FBytePropertyParams` 用来表示枚举类型。具体来说，`FBytePropertyParams` 用来表示 enum，而 `FEnumPropertyParams` 用来表示 enum class，`FBytePropertyParams` 用来表示 enum class 的 underlying type。并不是只有 enum class 对应的 params 有 underlying type 的概念，例如下面谈到的 `FArrayPropertyParams` 同样有一个 underlying type，它来表示 TArray 的元素类型。查看 `ConstructFProperty` 中的 `ReadMore` 变量就知道了
  * `FGenericPropertyParams` 用来表示各种基本的标量类型（int，float 等等）以及 FString，FText 等 ue 内常用的类型
  * `FObjectPropertyParams` 用来表示各种 uobject 类型（例如 weakobject，lazyobject，objectptr 等等）
  * `FInterfacePropertyParams` 用来表示 interface 类型（例如函数参数中的 `TScriptInterface` 就是用这个 params 来表示的）
  * `FClassPropertyParams` 用来表示 UClass 类型（例如 `TSubclassOf`）
  * `FStructPropertyParams` 用来表示用 UStruct 标记过的结构体
  * 还有 `FArrayPropertyParams` 用来表示用 TArray 等等一系列的 `FxxxPropertyParams`

* 这些 `FxxxPropertyParams` 的前面字段都与 `FPropertyParamsBase` 相同。我们重点看下 `FPropertyParamsBase` 都与哪些重要的字段

  * `NameUTF8` 是一个表示字段名称的字符串
  * `PropertyFlags` 是一个 flag 位域，比较重要的例如 `CPF_Parm` 表示该 params 描述的是函数参数，`CPF_OutParm` 表示该参数是引用参数，`CPF_ReturnParm` 表示该参数是返回值
  * `EPropertyGenFlags` 描述了该 params 代表的字段的类型
  * `Offset` 在 `FPropertyParamsBaseWithOffset` 结构体中，表示字段在类中的偏移。如果它表示的是函数参数，那么这个偏移是在参数结构体 `<ClassName>_<UFunctionName>_Parms` 中的偏移

  这样我们就自顶向下地说完了整个 `xxx.gen.cpp` 的内容

### 消耗注册

在 ue 的 CoreUObject 模块中，它的 module 类为 `FCoreUObjectModule`，在它的 `StartupModule` 函数中，调用了 `UClassRegisterAllCompiledInClasses` 函数，大钊的 insideUE4 对这部分流程讲得很清楚了，我主要额外说一些关键的事情。

* uclass 虽然有 innerSingleton 和 outerSingleon 两个，但它们都指向的同一个构建出来的 uclass。首先调用的 InnerRegister 函数，然后调用的是 outerRegister 函数（这个函数最终构建了 ufunction 和 uproperty 到 uclass 中）

* ufunction 的大概调用原理：每个 ufunction 都生成了对应的 params 结构体，**然后我们知道每个参数在 params 结构体中的偏移。每个有 ufunction 有个对应的 `exec<UFunctionName>`，这个函数以 void* 指针的形式接收 params 结构体（因为我们需要保证所有的 `exec<UFunctionName>` 签名相同）**，还原出参数列表，然后调用实际的函数。对于动态代理来说，UHT 为它代理的函数签名生成了一个 wrapper 函数，这个 wrapper 函数就负责将传入的参数转化为函数签名对应的 params 结构体，然后动态查找调用 UFunction

* uclass 是如何构建出 uobject 的：uclass 有一个成员 classconstructor，它是对应 c++ class 的构造函数。具体来说，通常在 `xxx.generated.h` 函数中，会有一个 `DEFINE_DEFAULT_CONSTRUCTOR_CALL` 宏，这个宏定义了一个类的静态函数

  ```c++
  static void __DefaultConstructor(const FObjectInitializer& X) { 	 	      					new((EInternal*)X.GetObj())TClass;        
  }
  #define DEFINE_DEFAULT_OBJECT_INITIALIZER_CONSTRUCTOR_CALL(TClass) \
  	static void __DefaultConstructor(const FObjectInitializer& X) { new((EInternal*)X.GetObj())TClass(X); }
  ```

  它实际上就是利用 placement new，为传入的 uobject，调用它的类的无参构造函数（另一个宏会调用将  FObjectInitializer 作为参数的构造函数）。同时 uclass 的父类 ustruct 的 PropertySize 字段保存了 uclass 对应的 c++ class 的大小。所以 uclass 只需要分配一块 `PropertySize` 大小的内存，然后在这块内存上调用 classconstructor，就得到了新的 uobject

* CreateDefaultSubobject 和 NewObject 最终都是用 uclass 的 classconstructor 来构造出 uobject，区别是前者是 uobject 的成员函数，而后者是全局的一个函数。**前者会设置新的 object 的 outer 为 this（例如我们在 actor 的构造函数中调用前者，this 就为 actor，就是我们说的 component 的 outer 为 actor）。后者的 outer 是手动传参进去的**。**TODO：另一个显著区别在于前者使用的 FObjectInitializer 不同，这块我就不理解了**

* 一些关键字段的含义
  * 在 uclass 的 `FuncMap` 字段，记录了 UClass 中所有的 UFunction
  * 在 ustruct 的 `Children` 字段，将所有的 ufunction 串联成了一个单链表
  * 在 ustruct 的 `ChildProperties` 字段，将所有的 fproperty 串联成了一个单链表

TODO：

* ~~**在 `UStruct::Link` 函数中，调用了 `Property->LinkWithoutChangingOffset(Ar)` 函数，但这个函数内部的实现是 `check(0)`，会直接崩掉？是我哪理解错了吗**~~：**在 vscode 对虚函数点击 show all implementation 并不一定能够把所有的 implmentation 都显示出来，例如这里的模板继承**

  ```c++
  template<typename InTCppType, class TInPropertyBaseClass>
  class TProperty : public TInPropertyBaseClass, public TPropertyTypeFundamentals<InTCppType>
  // clang 没分析出来某一个 TProperty 的实例是我们要的 implementation 之一
  ```

  

* **检查 ue5.3 中是否支持 enum class : uint16 等等类型（我觉得是可以的，网上说只能用 uint8 估计是老版本的限制）**
* 理解 `FUObjectArray GUObjectArray;` 的结构，理解 `FUObjectHashTables` 这个全局静态结构
* **UFunction 是如何调用的（关注它如何处理引用和默认参数）**
* **CDO 是如何创建的，如何从 UClass 中动态创建一个新类型，UCLASS 中的 classconstructor 字段，以及 uclass::bind 是什么时候调用的**
* 如何确定一个编译单元所在的 package，例如，`CameraComponent.gen.cpp` 的 package 名为 `/Script/Engine`
* `ClassWithin` 字段是干什么的，我原本以为是不是 outer 的 uclass 之类的，但发现大部分类的 `ClassWithin` 都对应 UObject 的 uclass。只有少部分使用了 `DECLARE_WITHIN` 或者 `DECLARE_WITHIN_UPACKAGE` 宏的类是例外