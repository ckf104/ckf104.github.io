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

**TODO：但是 `IMPLEMENT_CORE_INTRINSIC_CLASS` 和 `IMPLEMENT_INTRINSIC_CLASS` 还会额外定义一个静态对象 `FCompiledInDefer`**


`DeferredClassRegistration` 在 `UClassRegisterAllCompiledInClasses` 函数中使用，该函数调用 `Class::StaticClass` 接口，将这些类的 uclass 都创建出来

`UClassRegisterAllCompiledInClasses` 在两个地方调用
* `ProcessNewlyLoadedUObjects`
* `FCoreUObjectModule::StartupModule`

但是 `Class::StaticClass` 接口只是创建出了 UClass 类和初始化了它的一些字段，然后创建一个 `FPendingRegistrant` 加入到全局链表中

`UObjectProcessRegistrants` 会使用 `FPendingRegistrant` 构成的单链表，它又在两个地方被调用
* `UObjectBaseInit`
* `ProcessNewlyLoadedUObjects`



参考
* [UObject（五）类型系统信息收集](https://zhuanlan.zhihu.com/p/26019216)
* [UObject（七）类型系统注册-第一个UClass](https://zhuanlan.zhihu.com/p/57005310)

