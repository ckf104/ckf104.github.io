## MSBuild

* 在 `.csproj` 文件中 `<Project Sdk="Microsoft.NET.Sdk">` 表示 SDK style project。相比于通常的 `.csproj` 文件，会隐式导入 `Sdk.props` 和 `Sdk.targets`，提供许多额外的 property 和 targets

```xml
<Project>
  <!-- Implicit top import -->
  <Import Project="Sdk.props" Sdk="Microsoft.NET.Sdk" />
  ...
  <!-- Implicit bottom import -->
  <Import Project="Sdk.targets" Sdk="Microsoft.NET.Sdk" />
</Project>
```

* `dotnet new console` 产生的模板包含 top level statements 而不是在类中定义 main 函数等等。这是新的 csharp 的写法，参考 [top level statements](https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/program-structure/top-level-statements) 
* 参考 [理解C#项目构建配置文件——MSBuild csproj文件](https://zhuanlan.zhihu.com/p/509046784)，自定义 target 需要放在 Directory.Build.targets 文件中，试了一下，直接放在 csproj 文件中确实不行，不知道为啥。另外 [.NET project SDKs](https://learn.microsoft.com/en-us/dotnet/core/project-sdk/overview) 中推荐的是放在 build 目录中，没试过，看起来更复杂一些

## sln file

`dotnet new console` 创建的项目中除了 `.csproj` 文件外，还有一个 `.sln` 文件，它包含了所有的 project。参考 [Solution (.sln) file](https://learn.microsoft.com/en-us/visualstudio/extensibility/internals/solution-dot-sln-file?view=vs-2022)，我的理解是这样，project 之间的相互依赖都定义在 `.csproj` 中，该文件定义了最终如何编译整个项目。而 `.sln` 文件的主要目的是创建一个项目视图 `solution explorer`，在 `.sln` 中我们用 `Project, EndProject` 关键字列举出所有的 project 文件（如果 project type 为 2150E333-8FDC-42A3-9474-1A3956D46DE8 则表明是 solution folder，即在 `solution explorer` 下创建新的文件夹，关于所有可能的 project type 可参考 [What is the significance of ProjectTypeGuids tag in the visual studio project file](https://stackoverflow.com/questions/2911565/what-is-the-significance-of-projecttypeguids-tag-in-the-visual-studio-project-fi)），然后在 `GlobalSection(NestedProjects) = preSolution` 中列举各个 project 的层级关系，产生最终的项目视图，而这个项目视图本身不需要和真实的文件结构一致。项目视图的叶子节点是 project，如果展开 project 下面的层级，这些层级对应的就是真实的文件结构了

这样做的好处是创建了一个虚拟的查看项目的视图，而各个 project 本身不需要放在相邻的文件结构中。当然 sln 文件中还有需要其它的 `GlobalSection`，此处没有细究这些是干什么的了

## UBT

* debugging csharp use `coreclr` debug type, instead of `dotnet`, see [csharp debugging](https://code.visualstudio.com/docs/csharp/debugging)
* 源码中的变量 `UnrealBuildTool.RemoteIniPath` 的作用是什么
* Build 模式下的 `-XmlConfigCache=` 参数是干嘛的，和 buildGraph 有关系吗，`BuildConfiguration.xml` 在 UBT 中起到什么样的作用
* 目前看到的基本概貌是：
  * 决定 `UnrealBuildTool` 功能的决定参数是 `-Mode` 选项，每个可选的 mode 在代码中都是 `ToolMode` 的子类，`ToolMode` 有一个 `ExecuteAsync` 函数，`UnrealBuildTool` 会调用这个函数将执行权交给该 mode
  * `GlobalOptions` 中包含了 `UnrealBuildTool` 的一些全局参数，即可以通过 `-Help` 看到的参数。因此 `UnrealBuildTool` 在调用 `ExecuteAsync` 前会使用 `CommandLineArguments` 对象来预处理一波命令行参数，将能识别的值设置在 `GlobalOptions` 中。这个 `CommandLineArguments` 会原封不动地又传给 mode
* `-game` `-engine` 参数都是些啥意思，试了一下，好像 `RunUBT.sh -projectfiles -project=xx.uproject -game -engine` 才能生成相应的 code-workspace 文件

```shell
# Generate vscode project files (workspace file and .vscode directory)
$ ~/src/UnrealEngine-5.3.2-release/GenerateProjectFiles.sh -Vscode -game -engine -project=/home/ckf104/src/TP_ThirdPerson/TP_ThirdPerson.uproject
# After running above command, workspace file and `.vscode`, `Intermediate`, `Saved` folder will be generated. And `Intermediate` folder contain a `.csproj` file. By this `csproj` file, C# dev kit could generate a `sln` file for us(This is triggered when I try to jump into definition in cs file)

# Generate compile_commands.json
$ ~/src/UnrealEngine-5.3.2-release/Engine/Build/BatchFiles/RunUBT.sh TP_ThirdPersonEditor  Development Linux -project /home/ckf104/src/TP_ThirdPerson/TP_ThirdPerson.uproject -Mode=GenerateClangDatabase -OutputDir=/home/ckf104/src/TP_ThirdPerson/

# Run UHT to generate header
$ ~/src/UnrealEngine-5.3.2-release/Engine/Build/BatchFiles/RunUBT.sh -target="TP_ThirdPersonEditor Linux Development /home/ckf104/src/TP_ThirdPerson/TP_ThirdPerson.uproject"  -Mode=UnrealHeaderTool

# Now, a complete project has been created!
# We can package it!
/home/ckf104/src/UnrealEngine-5.3.2-release/Engine/Build/BatchFiles/RunUAT.sh -ScriptsForProject=/home/ckf104/src/TP_ThirdPerson/TP_ThirdPerson.uproject \
Turnkey -command=VerifySdk -platform=Linux -UpdateIfNeeded \
-EditorIO -EditorIOPort=41771 -project=/home/ckf104/src/TP_ThirdPerson/TP_ThirdPerson.uproject \
BuildCookRun -nop4 -utf8output -nocompileeditor -skipbuildeditor -cook \
-project=/home/ckf104/src/TP_ThirdPerson/TP_ThirdPerson.uproject -target=TP_ThirdPerson \
-unrealexe=/home/ckf104/src/UnrealEngine-5.3.2-release/Engine/Binaries/Linux/UnrealEditor -platform=Linux \
-stage -archive -package -build -pak -iostore -compressed -prereqs \
-archivedirectory=/home/ckf104/src/TP_ThirdPerson/ -clientconfig=Development -nocompile -nocompileuat 2 >&1 | tee log.txt
```
* 如果是想生成 UE 本身的 compile_commands.json 的话，可以使用（如果是 Linux 平台的话替换 Win64 即可）
```shell
$ ./Engine/Build/BatchFiles/RunUBT.bat  UnrealEditor Development Win64 -Mode=GenerateClangDatabase
```

* 在 windows visual studio 中需要设置 editor preference 为 vs2022，详见[VisualStudio 2022 Intellisense for engine files not working in UE5](https://forums.unrealengine.com/t/ue-5-1-visualstudio-2022-intellisense-for-engine-files-not-working-in-ue5/551166)
* 如果安装了多个 UE 版本的话，在 windows 上右键 uproject 文件 generate project file 时，会 [找不到 UnrealBuildTool](https://forums.unrealengine.com/t/missing-unrealbuildtool-exe-after-build/242198)，根据 [Generate VS Project Files by Command Line](https://forums.unrealengine.com/t/generate-vs-project-files-by-command-line/277707)，在命令行使用（如果使用的是 launcher 的二进制版本的话）
```
"C:\Program Files (x86)\Epic Games\Launcher\Engine\Binaries\Win64\UnrealVersionSelector.exe" /projectfiles "MyProject.uproject"
```
* target 为 UnrealEditor 的 compile_commands.json 不会包含编辑器默认没有启用的插件。如果 project 使用了默认没有启用的插件，那可以把 project 的 compile_commands.json 搬到引擎目录下，可以使用 clangd 的 if blocks 来合成多个 compile_commands.json，见 [Allow specifying more than one compile_commands.json file](https://github.com/clangd/clangd/issues/1092)
* 如果报错 [Clang X64 must be installed in order to build this target](https://forums.unrealengine.com/t/error-clang-must-be-installed-in-order-to-build-this-target/483325)，需要设置环境变量 `LLVM_PATH` 为 LLVM 安装的目录

TODO：
* [编译UE5.2工程时遇到的MSVC和SDK版本问题](https://zhuanlan.zhihu.com/p/16534167796) 中谈到可以选择 msvc 的版本，如何选择 visual studio 的版本？unreal 是上哪找的 visual studio？
* visual studio 可以安装 llvm 工具链，下次试试用 visual studio 装，而不是手动装
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
## API

* 创建新对象，`CreateDefaultSubobject` vs `NewObject`
* 类似地，[Components](https://dev.epicgames.com/documentation/en-us/unreal-engine/components-in-unreal-engine) 中区分 `SetupAttachment` 和 `AttachToComponent`，也是一个在构造函数，一个 during play，为什么做这样的区分？另外，在 `SetupAttachment` 中我没有看到将 child 加到 parent 的 AttachChildren 里面，为什么？
  * 看起来在 `SetupAttachment` 中调用了 MARK_PROPERTY_DIRTY_FROM_NAME 宏，涉及ue4.25 加入的 pushmodel，不知道 parent 的 AttachChildren 是不是这样更新的
  * 看起来是在 `USceneComponent::OnRegister` 函数中调用了 `AttachToComponent` 
* `APown::GetViewRotation` 这个函数啥意思，SpringArm 的 `GetTargetRotation` 用到了它
## Subsystem

* 每个类型的 subsystem 都可以有多个吗？看起来是可以的

## UE Module

* 模块内的文件夹分布：文档 [Unreal Engine Modules](https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-modules) 讲得很好了
* `IMPLEMENT_MODULE` 宏是干嘛的，`IMPLEMENT_PRIMARY_GAME_MODULE` 呢？

## Movement

* 调用 `Pawn::AddMovementInput` 进行移动，但我没看出来这个是怎么最后反馈到 pawn 的坐标中的，根据网上的说法，一般是 `MovementComponent` 的 `TickComponent` 函数来调用 `ConsumeMovementInputVector` 等函数来获取累积输入的移动数据，进行实际的移动处理，但 `Pawn` 本身应该是没有默认绑定的 `MovementComponent` 的，而 `Character` 子类是有默认的 `CharacterMovementComponent`，看起来它的 `PerformMovement` 函数最终执行了移动操作，但这个函数太长了，完全没看懂
  * `Pawn` 中没有默认的 `MovementComponent` 而 `Character` 有，这样的设计可以理解，定位上来讲，可以说 `Pawn` 相比于 `Actor` 增加了处理输入的能力，但 `Pawn` 如何处理输入并没有定义。而 `Character` 则相比于 `Pawn`，定义了如何处理移动相关的输入
* 在 TP_ThirdPerson 的模板里，移动时调用 `Pawn::AddMovementInput`，位移累积在 `ControlInputVector` 中，但是在旋转时调用 `AddControllerYawInput` 时，累积的旋转积累在 `PlayerController` 的 `RotationInput`？
  * 我理解了，这里的旋转不是说 `Pawn` 的旋转，而是摄像机视角的旋转，可以看到 `RotationInput` 会在 `UpdateRotation` 中被使用，该函数中调用了 `PlayerCameraManager::ProcessViewRotation` 来处理摄像机视角 的旋转

## Global Shader

* global shader 的反射是怎么搞的， layout_field 宏相关

* 声明 shader 变量时，fshaderparameter.bind 干了啥？fshaderparameter 中的字段都是啥意思

* RDG 中的 passParameter 结构体中的 RenderTargets 字段来设置 renderTarget

* FRenderResource 到底是个啥，和 FRHIResource 的区别是什么

* uniform buffer 是全局的shader 参数是啥意思，`BEGIN_UNIFORM_BUFFER_STRUCT` 和 `BEGIN_GLOBAL_SHADER_PARAMETER_STRUCT` 有啥区别呢

* https://zhuanlan.zhihu.com/p/344573382 这篇文章谈到了 `FRHIVertexDeclaration`，它其实就是用来说明顶点属性的排布（在 opengl 里面有对应的函数，比如我现在有一个顶点数据 buffer，然后我就用这个 vertex declaration 说明buffer 中哪些数据是对应 shader 中 layout 0 的数据，哪些对应 layout 1 中的数据）。下面是一个典型

  ```c++
  class FMediaVertexDeclaration : public FRenderResource;
  
  struct FMediaElementVertex
  {
  	FVector4f Position;
  	FVector2f TextureCoordinate;
  
  	FMediaElementVertex() { }
  
  	FMediaElementVertex(const FVector4f& InPosition, const FVector2f& InTextureCoordinate)
  		: Position(InPosition)
  		, TextureCoordinate(InTextureCoordinate)
  	{ }
  };
  
  void FMediaVertexDeclaration::InitRHI(FRHICommandListBase& RHICmdList)
  {
  	FVertexDeclarationElementList Elements;
  	uint16 Stride = sizeof(FMediaElementVertex);
      // `FVertexElement` equals to `glVertexAttribPointer` function in opengl
  	Elements.Add(FVertexElement(0, STRUCT_OFFSET(FMediaElementVertex, Position), VET_Float4, 0, Stride));
  	Elements.Add(FVertexElement(0, STRUCT_OFFSET(FMediaElementVertex, TextureCoordinate), VET_Float2, 1, Stride));
  	VertexDeclarationRHI = PipelineStateCache::GetOrCreateVertexDeclaration(Elements);
  }
  ```

  

* https://logins.github.io/graphics/2021/03/31/UE4ShadersIntroduction.html 这篇文章写得很好

* `FRHIRenderPassInfo` 这个包装了许多渲染时需要用到的资源，我能看懂的是这个 renderTarget 和 depthStencilTarget，前者这个结构体中还有 `ERenderTargetActions` 这个枚举变量，我猜测这个结构体的意思是设置 renderTarget 在渲染前后是否需要做什么（例如 ELoad 表示要在渲染前保留 renderTarget 之前的值，而 EStore 表示渲染后要把结果传回 CPU）

* 那 `GraphicsPSOInit.DepthStencilState` 设置的这个 DepthStencilState 是个啥，和 depthStencilTarget 有啥区别（为啥两个都要设置）

* 切换渲染对象时调用的是 `RHICmdList.Transition`，但我疑惑的是，ue 是怎么知道传入的 `FRHITransitionInfo` 中的纹理是干什么的？（噢，我猜测这是那个枚举变量 `ERHIAccess` 的作用，例如 ERHIAccess::RTV 就是指 render target？）

  * https://blog.csdn.net/a359877454/article/details/78305046 中讲了 D3D11 中的 resource，我感觉 ue 中的 `ERHIAcess` 中的含义就是指的这个相关的
    * Render Target：RenderTargetView（RTV）
    * Depth Stencil：DepthStencilView（DSV）
    * Shader Resource：ShaderResourceView（SRV）
    * Unordered Access：UnorderedAccessView（UAV）

* RHICmdList 中的 BeginRenderPass cmd 和 EndRenderPass cmd 是干什么的

* `OneColorShader.h` 中的例子非常重要

  * multiple render target 中的 TShaderPermutationDomain？

* vetex shader 中的投影矩阵该上哪去找呢

* FRHIResource，FRenderResource，FRDGResource？它们之间的区别和联系？

  * 我觉得 FRHIResource 对应底层的渲染资源相关的，而 FRenderResource 是它的一个封装

现在重点看 CustomDepth 这个 Pass 是怎么实现的！

### Custom Depth Pass

meshProcessor 的 addMeshBatch 函数的调用来自于两种

* 一种是可缓存的 staticMesh，对于新加入场景的 staticMesh，`FPrimitiveSceneInfo::CacheMeshDrawCommands` 中会调用 `addMeshBatch` 函数
* 另一种是动态生成的 mesh，在 `GenerateDynamicMeshDrawCommands` 函数中调用。而在 `DispatchPassSetup` 函数中通过 taskgraph 机制异步调用 `GenerateDynamicMeshDrawCommands` 这个函数
* 还没有梳理得特别清楚 `ComputeRelevance` 函数和 addMeshBatch 的关系，直观上看，如果 ComputeRelevance 中的测试不通过，那么这个 mesh 就不会被调用 addMeshBatch

### ComputeRelevance

该函数中考虑各种 mesh 与 meshpass 的相关性（该 meshpass 是否需要处理该 mesh）

* PrimitiveSceneProxy 的 GetViewRelevance 函数（子类重载）负责从 PrimitiveSceneProxy 中获取需要计算 relevance 相关的属性

### Culling

cpu culling来减少向gpu传输的数据？之前在 learning opengl 中都没做过这种事？



要不要使用 meshmetrial shader，如果用，如何向它传入参数。输出的 renderTarget 插件中如何用上

RDG？

### 问题定位

没有调用 customDepth 是因为需要画的三角形数量为 0

* 没有调用 customDepth 是因为 `FParallelMeshDrawCommandPass::DispatchPassSetup` 中显示需要画的三角形数目为 0

* 从 render 主函数中一路 call 下来的这个 `FVisibilityTaskData::ProcessRenderThreadTasks` 函数中调用了 ComputeRelevance（代码 `Context->Finalize()`） 和 SetupMeshPasses 函数（这个函数最终调用了 DispatchPassSetup 函数）
* 没看明白 FVisibilityViewPacket 中 Relevance 字段是怎么初始化的，明天debug 看看
* FVisivilityTaskData.DynamicMeshElements.ViewCommandsPerView 字段是最终的 viewCommand 输出
* FVisibilityTaskData 的 ViewPackets 字段的类型为 FVisibilityViewPacket，它的 Relevance.Context 字段（类型为 FComputeAndMarkRelevance）和 Relevance.Context.Packets（类型为 FRelevancePacket）都引用的上面那个 viewCommand

### OCam 相机的实现

* 场景中新建了一个 FSceneRenderer，然后注册了，这有什么影响呢

### 实现思路

* shader 中输出的 coloar 必须是 0 到 1 吗
* ~~类比 `CustomDepthStencilValue`，给 primitive component 添加一个新的 property `CustomStencilValue`~~
* ~~类比 `CustomDepthStencilValue`，给 PrimitiveSceneProxy 类添加一个新的成员 `CustomStencilValue`~~
* 添加新的处理 CustomStencil 的 meshProcessor
  * 添加新的枚举变量 EMeshPass::CustomStencil
  * 在 SceneVisibility.cpp 的 ComputeRelevance 函数中处理相关性（即 CustomStencil 是否需要处理这个 meshbatch，这里照着 CustomStencil 写就好了）
  * 类比 FCustomDepthPassMeshProcessor，实现新的 FCustomStencilMeshProcessor
* 在 struct FSceneTextures 中增加一个纹理来作为 custom stencil 的输出，在 FSceneTextures::InitializeViewFamily 中增加 custom stencil 输出纹理的初始化（这个函数也是在大的 Render 函数中被调用）
* **Others**

### Others

我们来看下原来的 CustomStencilValue 都在哪些地方用了

* FViewInfo 的 CustomDepthStencilValues 字段记录了所有 primitive component 的 stencil value 值，不过没看到它用。FSceneRenderer 类负责渲染工作，它的 Views 字段是一个 FViewInfo 的数组（我想应该是每个摄像机视角都对应一个 FViewInfo）

* FPrimitiveUniformShaderParameters 是一个全局的 Uniform Buffer（它在 shader 里面对应 FPrimitiveSceneData 这个结构体，查看 SceneData.h），感觉这个结构体描述了 shader 需要的所有 primitive component 的信息，最后一个参数数组 CustomPrimitiveData，这个可以自定义，我决定用这个作为 stencil value，然后在材质编辑器里面读出来。并且 bHasCustomData 这个 bool 值存放在 primitive shader parameter data 的 flags 中

* 在 primitiveComponent 中设置 CustomPrimitiveData 后，会调用 FScene 的 UpdateCustomPrimitiveData 函数，将更新的 PrimitiveSceneProxy 和 它的 CustomPrimitiveData 作为一对 pair 传递到 UpdatedCustomPrimitiveParams 这个 map 中。然后看下面这个函数调用栈

  FDeferredShadingSceneRenderer::Render

  ​    ->  FSceneRenderer::UpdateScene 

  ​        ->  FScene::UpdateAllPrimitiveSceneInfos

  在这个函数中遍历上面说到的这个 map 中的 pair，实际地将 新的 CustomPrimitiveData 设置在了 SceneProxy 的 CustomPrimitiveData 字段

  最终在函数 FPrimitiveSceneProxy::BuildUniformShaderParameters 函数中，将这个 CustomPrimitiveData 的值暴露给了 

  PrimitiveUniformShaderParametersBuilder 的 FPrimitiveUniformShaderParameters，这个参数将用来构建我们需要的 uniform buffer

  由于 FPrimitiveUniformShaderParameters 的 CustomPrimitiveData 字段是 TStaticArray 类型，后者默认会将数组初始化为 0，因此不用担心 shader 收到的 CustomPrimitiveData 会是未定义的

* FPrimitiveSceneShaderData 存储了 PRIMITIVE_SCENE_DATA_STRIDE（41） 个浮点，以一种更紧凑的方式保存了整个 primitive parameter 的 uniform buffer？具体的 layout 见 FPrimitiveSceneShaderData::Setup 函数。我感觉这个结构体的引入和 GPUScene 之类的有些关系，见 SceneData.ush 中两种 GetPrimitiveData 的定义方式

* GetMaterialPixelParameter 函数的实现，看起来像是每个顶点工厂对应的 usf 文件有这个函数的定义

* 影响 primitiveId 是否为恒为 0 的关键在于 VF_SUPPORTS_PRIMITIVE_SCENE_DATA 宏是否被定义了

* PrimitiveId 的值来源于 vertexShaderInput 的 InstanceIdOffset 和 DrawInstanceId 属性，见 SceneData.ush 的 GetSceneDataIntermediates 函数，不过仅在宏 VF_SUPPORTS_PRIMITIVE_SCENE_DATA 值为 1 时有效



### 问题

**如何传递参数给 meterial shader**

**CustomDepthPass 的 shader 都有一个 GetShaderBindings 函数，这个函数会在 BuildMeshDrawCommand 函数中被调用，在这个时候我们设置 shader 参数**

PrimitiveComponent 的CustomDepthStencilValue 是怎么传递给 PrimitiveSceneProxy 的？（在直接设置 CustomDepthStencilValue 时）我猜是不是因为每一帧都会建一个新的 PrimitiveSceneProxy 之类的？

UE 是如何获得回传的 GPU 数据同时不卡的呢，在 RDG 中调用 rhicmdlist.readsurfacedata 函数会极大地影响帧率，看看 URenderTarget 相关的代码？是如何回传的，以及对应的 EStoreAction 干了什么
