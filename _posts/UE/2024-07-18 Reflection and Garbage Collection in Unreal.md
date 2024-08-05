TODO：反射部分的笔记从 UE Notes 中挪到这里

TODO：理解 FGCObject 的作用

## Garbage Collection

> When an `AActor` or `UActorComponent` is destroyed or otherwise removed from play, all references to it that are visible to the reflection system (`UProperty` pointers and pointers stored in Unreal Engine container classes such as `TArray`) are automatically nulled. 

TODO: [Unreal Object Handling](https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-object-handling-in-unreal-engine) 里说当 AActor 或者 UActorComponent 被销毁时，所有指向它的指针会被置空，不太理解这是怎么做到的，有两点很奇怪

* 为什么仅限于 AActor 和 UActorComponent
* 是如何做到让 TArray 这种容器置空的

> One practical implication here is that you typically need to maintain a `UPROPERTY` reference to any Object you wish to keep alive, whether it's a simple Object pointer or an Unreal Engine container class that contains Object pointer types, such as `TArray<UObject*>`.

后文的这段话可能是对置空 TArray 容器指针的解释，即也得用 UProperty 标记才行。[UE4 垃圾回收](https://zhuanlan.zhihu.com/p/67055774) 中讨论了将指向被回收的 UObject 的指针更新为 null 的实现思路，虽然我奇怪它这里怎么没限定类型为 AActor 或者 UActorComponent

> An Object reference stored in a raw pointer will be unknown to the Unreal Engine, and will not be automatically nulled, nor will it prevent garbage collection. Note this does not mean that all `UObject*` variables must be `UProperties`. If you want an Object pointer that is not a `UProperty`, consider using `TWeakObjectPtr`. This is a "weak" pointer, meaning it will not prevent garbage collection, but it can be queried for validity before being accessed and will be set to null if the Object it points to is destroyed.

TODO: 这段话也值得思考一下，如果不使用弱引用，是不是意味着每个 UObject 指针都应该用 UProperty 标记？

> Another case where a referenced UObject UProperty will be automatically null'ed is when using 'Force Delete' on an asset in the editor. As a result, all code operating on UObjects which are assets must handle these pointers becoming null.

TODO: 这里也需要再看看

> When the **Class Default Object** (or CDO) of a `UClass` has changed, the engine will try to apply those changes to all instances of the class when they are loaded. For a given Object instance, if the updated variable's value matches the value in the old CDO, it will be updated to the value it holds in the new CDO. If the variable has any other value, the assumption is that the value was set intentionally, and those changes will be preserved.

TODO: 这段话也看得云里雾里

### FGCObject

[UE4实验使用 FGCObject 引用UObject](https://blog.csdn.net/u013412391/article/details/108089684) 中对 FGCObject 的讲解非常好。从动机上讲，引入 FGCObject 就是为了让非 UObject 子类的类也能够引用 UObject，只需要实现其 `AddReferencedObjects` 函数即可。这个函数会在每次 GC 发生时被调用，FGCObject 的子类实现 `AddReferencedObjects` 函数，这个函数告知 UE 哪些 UObject 被该类引用。**UE 在每次 GC 时调用该函数，获取引用关系**
