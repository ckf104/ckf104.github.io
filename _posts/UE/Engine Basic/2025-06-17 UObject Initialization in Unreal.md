### Flow
* 加载 CoreUObject 模块时，触发 uobject 类的 uclass  构造，以及静态数据的注册
* 随后 `FCoreUObjectModule::StartupModule` 中调用 `UClassRegisterAllCompiledInClasses`，创建出各个类的 uclass，并把这些 uclass 注册到 `FPendingRegistrant` 单链表中
* 后续回调函数 `InitUObject` 在 `FEngineLoop::AppInit`（它是在 `PreInitPreStartupScreen` 阶段）中被调用
	* 初始化 `GUObjectAllocator`（它负责分配 UObject 占用的内存），`GUObjectArray`（它负责分配 `FUObjectItem` 占用的内存），这之后就可以使用 `NewObject` API 了
	* 调用 `UObjectProcessRegistrants` 使用 `FPendingRegistrant` 构成的单链表（注意，SuperStruct 指针在一开始创建 uclass 的时候就设置好了。因为子类的 uclass 创建依赖于父类的 uclass 创建）
		* 将 uclass 注册到全局的 object array 中（这下有了 `NamePrivate`，`InternalIndex`）
		* 创建 uclass 的 package（`OuterPrivate` 指向该 package）
		* 将 `ClassPrivate` 指向 uclass 类的 uclass（因此 uclass 类的 uclass 的 `ClassPrivate` 指向自己）
	* 创建 global transient package
* 在 `FEngineLoop::PreInitPostStartupScreen` 中会调用 `ProcessNewlyLoadedUObjects`，这个函数就是一个全家桶，它除了调用 `UClassRegisterAllCompiledInClasses` 和 `UObjectProcessRegistrants` 来创建和注册各个类的 uclass 之外，会最终将所有 uproperty 和 ufunction 的信息写入到 uclass 中，并创建 CDO
* 在 `FEngineLoop::PreInitPostStartupScreen` 中会调用 `FUObjectArray::CloseDisregardForGC`，这个函数中也会调用一次 `ProcessNewlyLoadedUObjects`
### Note 1
gen.cpp 中的 `IMPLEMENT_CLASS` 宏定义了 static 的 uclass 指针，这是我们能通过 `Class::StaticClass` 接口拿到 uclass 指针的原因

整个 CoreUObject 模块的生成信息是特化的，源代码中没有出现 `include xxx.generated.h` 等，查看 Intermediate 目录中 CoreUObject 的生成信息包括
```
CoreNetTypes.gen.cpp      CoreOnline.gen.cpp      CoreUObject.init.gen.cpp  NoExportTypes.generated.h
CoreNetTypes.generated.h  CoreOnline.generated.h  NoExportTypes.gen.cpp 
```
其中 `NoExportTypes.gen.cpp` 中包含了  `IMPLEMENT_CLASS(UObject, 356851929)`，这定义了 UObject 的 uclass 的生成方式（主要是定义 `GetPrivateStaticClass` 函数）。而 CoreUObject 模块中其它 UObject 子类的 uclass 生成由 `IMPLEMENT_CORE_INTRINSIC_CLASS` 宏定义 

`IMPLEMENT_CORE_INTRINSIC_CLASS` 和 `IMPLEMENT_INTRINSIC_CLASS` 都是对 `IMPLEMENT_CLASS` 宏的封装，定义了静态对象 `TClassCompiledInDefer` 这个延迟注册类。这个类的构造函数会把自己注册到 `DeferredClassRegistration` 这个全局信息中
```c++
static TArray<FFieldCompiledInInfo*> DeferredClassRegistration;
```
 另外一个全局信息是 `FCompiledInDefer`（这俩在 UE5 里变为了 Inner Register 和 Outer Register，不过充当的角色都是一样的）

`DeferredClassRegistration` 在 `UClassRegisterAllCompiledInClasses` 函数中使用，该函数调用 `Class::StaticClass` 接口，将这些类的 uclass 都创建出来

`UClassRegisterAllCompiledInClasses` 在两个地方调用
* `ProcessNewlyLoadedUObjects`
* `FCoreUObjectModule::StartupModule`

但是 `Class::StaticClass` 接口只是创建出了 UClass 类和初始化了它的一些字段，然后创建一个 `FPendingRegistrant` 加入到全局链表中

`UObjectProcessRegistrants` 会使用 `FPendingRegistrant` 构成的单链表，它又在两个地方被调用
* `UObjectBaseInit`
* `ProcessNewlyLoadedUObjects`

uobject 的 uclass 也是一个 uobject，因此这个 uclass 也有 `ClassPrivate` 指针，它指向的是 uclass 的 uclass，但 uclass 又是 uobject 的子类。因此这里会存在一个循环依赖的问题。UE 里是先构建 uobject 的 uclass，此时这个 uclass 的 `ClassPrivate` 指针为空



TODO：解释 UE::GC::DeclareIntrinsicMembers

参考
* [UObject（五）类型系统信息收集](https://zhuanlan.zhihu.com/p/26019216)
* [UObject（七）类型系统注册-第一个UClass](https://zhuanlan.zhihu.com/p/57005310)

