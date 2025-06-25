TODO：解释 `TObjectPtr` 等指针模板的含义
### Smart Pointers
#### Smart Pointers in C++
首先可以看看 [std::shared_ptr](https://en.cppreference.com/w/cpp/memory/shared_ptr) 在 implements notes 一节的描述。每个被追踪的 pointer 都有个与之对应的，在堆上分配的 _control block_。值得注意的是，_control block_ 中除了包含 shared pointer 的引用计数，还包含了 weak pointer 的引用计数。当 shared pointer 的引用计数归零时，调用 pointer 指向对象的析构函数。当 weak pointer 和 shared pointer 的引用计数都归零后，才能释放 _control block_。明白了这个事情，就能想清楚 weak pointer 的 `expired`，`lock` 函数是怎么实现的了

另一个有趣的事情是，implements notes 中以及 [std::make_shared](https://en.cppreference.com/w/cpp/memory/shared_ptr/make_shared) 的 notes 中提到 `std::make_shared` 相比于 `std::shared_ptr<T>(new T(args...))` 的写法，会节省一次堆内存分配，因为 `std::make_shared` 会把类型 `T` 和 _control block_ 的内存一块申请了。但这样不好的地方在于，shared pointer 的引用计数归零后，类型 `T` 占用的内存也不会被释放，直到 weak pointer 的引用计数也归零后，类型 `T` 和 _control block_ 占用的内存会一起释放（这要求 `std::make_shared` 不能使用 custom deleter，否则就没办法把对象的析构和内存的释放这两步分离开了）。另外就是 `std::make_shared` 必须使用 public constructor，因为函数内部显然没办法调用 non-public 的类型 `T` 的构造函数。另一方面，这也说明 intrusive reference counting 可能提供更高的性能，因为它不再需要堆内存分配了

继承了 [std::enable_shared_from_this](https://en.cppreference.com/w/cpp/memory/enable_shared_from_this) 的类会额外地有一个 `mutable std::weak_ptr<T> weak_this` 字段，在 `std::shared_ptr` 的构造函数中会进行检测类型 `T` 是否继承了 `std::endable_shared_from_this`，如果是，就会设置 `weak_this` 为指向对应 _control block_ 的 weak pointer，这样就可以从 raw pointer 中增加引用计数，产生新的 shared pointer
#### Smart Pointers in Unreal
文档 [Unreal Smart Pointer Library](https://dev.epicgames.com/documentation/en-us/unreal-engine/smart-pointers-in-unreal-engine) 介绍了 UE 里的 smart pointer，这些结构可以从 C++ 中对应过来。`TSharedPtr` 就是 `std::shared_ptr`，而 `TSharedRef` 表示一个非空的 `TSharedPtr`，`TWeakPtr` 就是 `std::weak_ptr`。`MakeShareable` 就类似于 `std::shared_ptr<T>(new T(args...))` 的写法，`MakeShared` 就相当于 `std::make_shared`。`TSharedFromThis` 就是 `std::enable_shared_from_this`
### Object Reference
右击 Asset，打开 reference viewer，可以看到 asset 的引用与被引用情况，可以过滤掉 hard reference 或者 soft reference。在蓝图变量中，object reference 和 class reference 是 hard reference，它引用的资产需要一起加载进来，而 soft object reference 以及 soft class reference 是 soft reference，需要手动加载资产
```c++
TObjectPtr<MyType> MyName;  // object reference
TSubclassOf<MyType> MyName;  // class reference
TSoftObjectPtr<MyType> MyName; // soft object reference
TSoftClassPtr<MyType> MyName; // soft class reference
```
`TObjectPtr<T>` 的说明见 [Unreal Engine 5 Migration Guide](https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-5-migration-guide?application_version=5.0) ，据说这样可以实现 editor 下的 dynamic resolution and access tracking，但我没看出来这是怎么实现的，[Why should I replace raw pointers with TObjectPtr?](https://forums.unrealengine.com/t/why-should-i-replace-raw-pointers-with-tobjectptr/232781) 中的讨论也感觉含糊其辞，TODO：解释 `TObjectPtr<T>` 与 incremental GC 的关系。`TSubclass<T>` 是 `TObjectPtr<UClass>` 的封装，来保证赋值的 uclass 对应的类是模板参数 `T` 的子类

`TSoftObjectPtr<T>` 则不再是 8 字节，而是 48 字节，因为它除了存储一个弱引用指针 `FWeakObjectPtr` 外，还需要存储这个 object 的资产路径 `FSoftObjectPath`，这个路径分为三部分，`PackageName`，`AssetName`，`SubPathString`。例如路径 `/Game/MyAsset.MyAsset_C:DefaultSubobject` 中`PackageName` 就是 `/Game/MyAsset`，`AssetName` 是 `MyAsset_C`，而 `SubPathString` 为 `DefaultSubobject`。`TSoftClassPtr<T>` 是类似的

这里什么时候应该用 object reference，什么时候用 class reference 稍微有些微妙
* 对于一些数据类型的资产，我们使用 object reference，这样在编辑器中设置好引用后，我们会得到 `/Game/MyAsset.MyAsset`
* 而对于蓝图类蓝图类这样的类型，我们通常会使用 class reference，对应 object 路径为 `/Game/MyAsset.MyAsset_C`。当然也可以用 object reference，对应的 object 路径为 `/Game/MyAsset.MyAsset`（也就是 `UBlueprint`）
 
注：`FWeakObjectPtr` 是 `TWeakObjectPtr` 的内部表示，`TWeakObjectPtr` 的描述见 UObject Management in Unreal 一文

TODO：解释 `TObjectPtr<T>`
* [简析UE5的对象指针FObjectPtr与TObjectPtr](https://zhuanlan.zhihu.com/p/504115127) 讨论了 `TObjectPtr<T>` 在 editor 下 dynamic resolution and access tracking 的功能，但我其实还没理解到底该怎么用这玩意。因为我自己测试的时候添加了 `AddObjectHandleReferenceResolvedCallback` 回调后，这函数一次都没执行过。不知道是不是我的代码太简单了之类的
* 解释 `TObjectPtr<T>` 在 GC 的增量可达性分析中的作用