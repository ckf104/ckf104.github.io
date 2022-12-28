---
title: Understanding c++ operator new and delete
date: 2022-12-28 20:25:30 +0800
categories: [cpp]
---

看LLVM源码时发现许多重载`new`和`operator`运算符的操作，查了一些资料后才发现自己以前对这两个运算符有许多误解，遂记录如下。

### 1. Understanding placement new

在正式讨论`placement new`之前，我们先回忆一下`new`运算符干了哪些事

* 分配内存
* 调用构造函数

分配内存的任务，对应的是C++内置函数`operator new`和`operator new[]`（取决于分配单个对象还是数组）。而通过`operator new`的返回指针调用构造函数的代码，则由编译器自动生成。例如`new A(2)`这样的代码可能转换为如下的LLVM IR

```c
%1 = call operator new(sizeof(A))   // 分配内存
%2 = call A::A(%1, 2)              // 调用构造函数
```

而所谓的`placement new`，只是[new expression](https://en.cppreference.com/w/cpp/language/new)的一种语法形式（即链接中表达式的3,4），作用是给`operator new`提供额外的参数。[operator new](https://en.cppreference.com/w/cpp/memory/new/operator_new)中罗列了C++中所有内置的或用户可自定义的`operator new`。C++中谈到重载`new`运算符的含义就是重载负责分配内存的`operator new`函数。

C++中仅有一种内置的`placement new`函数(即接收额外参数的`operator new`)

```cpp
void* operator new  ( std::size_t count, void* ptr );   // (9)	
void* operator new[]( std::size_t count, void* ptr );  // (10)	
```

该内置的函数什么也不做，仅仅返回第二个参数。哎？这有什么用呢？在阐述完`new`和`delete`的含义后，我们以LLVM中实际使用的例子来展示，现在我们先看一个应用得不太恰当的例子。

```cpp
#include <new>

class A{
 public:
    A(){}
    ~A(){}
};

int main(){
    char buf[20];
    A* a = new (buf) A(); // placement new expression
    a->~A();   // call destructor manually
    return 0;
}
```

这里我们通过`placement new`表达式提供额外参数给`operator new`，因此编译器查找的函数签名为`operator new(size_t, char[20])`，因此不是分配内存的`operator new`，而是仅仅返回第二个参数的接收额外指针参数的`operator new`被调用了。回顾整个`new expression`的工作，因此它将在这个buf指针指向的内存区域上调用`A`的构造函数。这下明白这个不分配内存的`operator new`的作用了，使得我们能够在自己分配的内存上构建对象！

当然，也可以提供一些稀奇古怪的参数，例如：

```cpp
int a = 5;
int b = 6;
A* f = new (a, b) A(); // error! can't find operator new(size_t, int, int)
```

这样的代码能运作的前提是用户定义好了自己的`void* operator new(size_t, int, int)`函数。

### 2. Customize operator new

所谓重载`operator new`，其实就是要么覆盖默认的`operator new`实现，要么定义新的`operator new`签名（例如上面的接收额外两个Int类型的签名），具体重载的位置可以选择**Global replacements**或者**Class-specific overloads**（就是定义`operator new`为类的成员函数，这样仅在`new`表达式的对象为该类且函数签名相符时才会调用）。

有额外的两点注意事项

```cpp
void* operator new  ( std::size_t count, void* ptr );   // (9)	
void* operator new[]( std::size_t count, void* ptr );  // (10)
```

一个是上面的俩类型的`operator new`不能被**Global replacements**。[cppreference.com](https://en.cppreference.com/w/cpp/memory/new/operator_new)上的描述如下：

> The standard library's non-allocating placement forms of operator new (9-10) cannot be replaced and can only be customized if the placement new-expression did not use the ::new syntax, by providing a class-specific placement new (19,20) with matching signature: void* T::operator new(size_t, void*) or void* T::operator new[\](size_t, void*).

以及

> Even though the non-allocating placement new (9,10) cannot be replaced, a function with the same signature may be defined at class scope as described above. In addition, global overloads that look like placement new but take a non-void pointer type as the second argument are allowed, so the code that wants to ensure that the true placement new is called (e.g. [std::allocator::construct](https://en.cppreference.com/w/cpp/memory/allocator/construct)), must use ::new and also cast the pointer to void*.

另外一点注意是C++的分配内存形式的`operator new[]`内部实现是直接调用`operator new`，因此在**Global replacements**的情况下，重载分配内存形式的`operator new`实际上已经重载了`operator new[]`：

> The standard library implementations of the nothrow versions (5-8) directly calls the corresponding throwing versions (1-4). The standard library implementation of the throwing array versions (2,4) directly calls the corresponding single-object version (1,3). Thus, replacing the throwing single object allocation functions is sufficient to handle all allocations.

但在**Class-specific overloads**的情况下，如果希望重载`operator new[]`的话就必须给出相应实现（这也很好理解，因为如果编译器在类内部找不到`operator new[]`，就会使用全局的`operator new[]`，而全局的实现内部当然是调用的全局的`operator new`）。

### 3. Understanding delete expression

有意思的是，[delete expression](https://en.cppreference.com/w/cpp/language/delete)和[new expression](https://en.cppreference.com/w/cpp/language/new)并不对称，在析构时并没有`placement delete`这样的语法。 `delete`的工作是`new`的反转：

* 调用析构函数
* 回收内存

回收内存的工作由内置的`operator delete`或`operator delete[]`来完成，同样的，重载`delete`的意思即为定义新的`operator delete`函数。

虽然在[cppreference.com](https://en.cppreference.com/w/cpp/memory/new/operator_delete)给出了30种`operator delete`的函数签名，不过大概可以按照如下的维度对它们进行分类：

* **Global replacements** VS **Class-specific overloads**
* **size-unaware** VS **size-aware**
* **placement** VS **non-placement** 

**Global replacements**和**Class-specific overloads**的区别和`operator new`的情况完全一致，包括作用域范围（`delete`该类时才调用类内部的`delete`重载），全局重载`operator delete(void*)`时就相当于也重载了`operator delete[](void*)`等

**size-unaware**和**size-aware**版本的`operator new`的区别在于函数签名中是否接收一个`size_t`参数（如果编译器选择了带`size_t`的`operator delete`，则在该参数位置传入之前`operator new`时申请的内存大小）。关于具体选择哪个版本，编译器有一些偏好性，例如：

> If the deallocation functions that were found are class-specific, size-unaware class-specific deallocation function (without a parameter of type [std::size_t](https://en.cppreference.com/w/cpp/types/size_t)) is preferred over size-aware class-specific deallocation function (with a parameter of type [std::size_t](https://en.cppreference.com/w/cpp/types/size_t))

带`size_t`的`operator new`会影响编译器进行内存优化，我们等会讨论`delete expression`的细节工作原理时会看到。

虽然`delete expression`没有`placement`形式来提供额外参数，不过确有接收额外自定义参数的`operator delete`。这样的`operator delete`仅用于异常处理时（即`new expression`的构造阶段抛出了异常）。[new expression - cppreference.com](https://en.cppreference.com/w/cpp/language/new)上的详尽描述如下：

> If initialization terminates by throwing an exception (e.g. from the constructor), if new-expression allocated any storage, it calls the appropriate [deallocation function](https://en.cppreference.com/w/cpp/memory/new/operator_delete): [operator delete](http://en.cppreference.com/w/cpp/memory/new/operator_delete) for non-array `type`, [operator delete](http://en.cppreference.com/w/cpp/memory/new/operator_delete)[] for array `type`. The deallocation function is looked up in global scope if the new-expression used the ::new syntax, otherwise it is looked up in the scope of `T`, if `T` is a class type. If the failed allocation function was usual (non-placement), lookup for the deallocation function follows the rules described in [delete-expression](https://en.cppreference.com/w/cpp/language/delete). For a failed placement new, all parameter types, except the first, of the matching deallocation function must be identical to the parameters of the placement new. The call to the deallocation function is made the value obtained earlier from the allocation function passed as the first argument, alignment passed as the optional alignment argument (since C++17), and `placement-params`, if any, passed as the additional placement arguments. If no deallocation function is found, memory is not deallocated.

简而言之，如果是`placement new`的形式在构造阶段抛出了异常，那么会调用相应的`operator delete`函数释放内存，这个`operator delete`接收和`placement new`收到的一致的额外参数。

一个内置的例子如下，这其实是前面看到的内置的`placement new`的对应版本，当`new (void*) obj(...)`发生构造异常时，就会调用如下的`operator delete`，可以预想，该函数的功能就是什么也不干。另外，它遵循的重载规则也与第2节中所述的内置的`void* operator new(std::size_t count, void* ptr )`相一致。

```cpp
void operator delete  ( void* ptr, void* place ) noexcept;    // (13)
void operator delete[]( void* ptr, void* place ) noexcept;    // (14)
```



因此重载`operator delete`时，根据上面三个维度的属性各自的作用，选择合适的函数签名，定义好相应的`operator delete`函数即可（当然，`operator delete`和`operator delete[]`的区别是显而易见的）。

### 4. Delete expression under the hood

这一节讨论`delete expression`实现机理和一些常见的易错点。

#### 4.1 Dark sides of delete[]

我们从一个**cppreference**上的一个例子引入：

```cpp
#include <iostream>
 
// sized class-specific deallocation functions
struct X
{
	static void* operator new[](std::size_t sz){
	    std::cout << "custom new for size " << sz << '\n';
        return ::operator new[](sz);
	}
    static void operator delete(void* ptr, std::size_t sz)
    {
        std::cout << "custom delete for size " << sz << '\n';
        ::operator delete(ptr);
    }
 
    static void operator delete[](void* ptr)
    {
       // std::cout << "custom delete for size " << sz << '\n';
        ::operator delete[](ptr);
    }
};
 
int main()
{
    X* p1 = new X;
    delete p1;
 
    X* p2 = new X[10];
    delete[] p2;
}
```

输出如下：

```
custom delete for size 1
custom new for size 10
```

看着挺合理的，但是我们对`operator delete[]`稍作修改，使得它变为**size-aware**的版本

```cpp
static void operator delete[](void* ptr, std::size_t sz)
{
   std::cout << "custom delete for size " << sz << '\n';
   ::operator delete[](ptr);
}
```

输出如下，有意思的是，这次额外多出了8字节的分配开销！

```
custom delete for size 1
custom new for size 18
custom delete for size 18
```

为了回答其中的原因，我们需要回顾编译器如何实现`delete []var`。和`new var[n]`时显式提供了数组长度不同，在`delete`数组时编译器如何得知数组长度呢，这里得知数组长度有两方面的作用

* 如果`delete`一个有自定义析构函数的对象，编译器需要得知数组长度来为每个数组元素调用析构函数（在调用`operator delete`函数释放内存之前）。
* 如果选择的`oprator delete`接收额外的表征释放内存大小的`size_t`，编译器需要知道数组长度来计算释放内存的大小。

通常`new obj[n]`会被编译器翻译为如下语句（至少clang是这样的）：

```cpp
size_t housekeep = max(alignof(obj), sizeof(size_t));
char* p = operator new[](n * sizeof(obj) + housekeep);
*(size_t*)p = n;
return p + housekeep;  // 实际用来构建obj的内存区域是 p + housekeep
```

然后在`delete []obj`时就可以通过`*(size_t*)(obj - housekeep)`来获得实际的数组长度，当然传给`operator delete`的参数也是`obj - housekeep`。

这里存在一个可以进行优化的点，如果选择的`operator delete`不需要知道释放的内存大小，同时`delete`的对象不是一个类或者没有自定义析构函数，就不需要额外的空间来存储了数组长度了。我想这下能够完全理解前面例子的输出了。

#### 4.2 Deleting an array through a pointer to base is UB

翻译成代码的意思是

```cpp
base* a = new derived[10];
delete[] a;  // undefined behavior!
```

造成这个现象的本质原因在于`sizeof(*a)`的大小是编译时静态计算，而不是根据`*a`的动态类型来计算，导致`(base*)a + 1`不能够指向正确的派生类地址。[C++ FAQ](https://isocpp.org/wiki/faq/proper-inheritance#array-derived-vs-base)上对该问题有更详尽的阐述。

#### 4.3 Why no placement-delete

[c++11 - Why there is no placement delete expression in C++? - Stack Overflow](https://stackoverflow.com/questions/5857240/why-there-is-no-placement-delete-expression-in-c)上的高赞回答已经解释得很好了，但是省略了许多重要的细节，这里将其扩充一下。

`delete expression`在多态的背景下也有一些额外需要考虑的地方，C++规定，`delete expression`需要从动态类型往下查找`operator delete`（再一次，`new`并不需要考虑这些复杂性，因为`new`时显式指定了类型）

> If the static type of the object that is being deleted differs from its dynamic type (such as when deleting a [polymorphic](https://en.cppreference.com/w/cpp/language/object) object through a pointer to base), and if the destructor in the static type is virtual, the single object form of delete begins lookup of the deallocation function's name starting from the point of definition of the final overrider of its virtual destructor. Regardless of which deallocation function would be executed at run time, the statically visible version of operator delete must be accessible in order to compile. In other cases, when deleting an array through a pointer to base, or when deleting through pointer to base with non-virtual destructor, the behavior is undefined.

这里并不需要考虑`delete[]`的情况，因为4.2中已经阐述了传入基类指针是UB的。另外上述引用中提到如果基类的析构函数不是虚函数这也是UB（当然，因为这时析构函数静态绑定，就不会调用派生类的析构函数了）

如果我们考虑`delete expression`类似于`new expression`的实现，即将`delete a`翻译为如下代码

```cpp
a->~a();
operator delete(dynamic_cast<void*>(a)); // 这里至少需要进行动态转发，来拿到指向最派生类的指针，当然如果a没有虚函数表dynamic_cast就也不需要了
```

这里存在一个难题是上面的标准要求`operator delete`从实际的动态类型开始查找，这本质上要求`operator delete `具有类似虚函数的属性。但`operator delete`如果定义为成员函数，那么一定是静态成员函数。这说明`operator delete`类似于一个静态虚函数（当然，通常是不允许`static virtual`这样的声明的），**reference**上也有如下论述

> The call to the class-specific T::operator delete on a polymorphic class is the only case where a static member function is called through dynamic dispatch.

如果要实现上面所设想的翻译，就需要把`operator delete`这个静态函数放入虚函数表中，这与虚函数表通常的功能相违。编译器通常的做法是（至少clang是这样做的）编译时生成两个析构函数，`in-charge destructor`即正常的析构函数，以及`in-charge deleting destructor`在正常析构结束后还会调用合适的`operator delete`（如果还有该类含有虚基类的话，还需要一个额外的析构函数`not-in-charge destructor`，该析构函数不会调用虚基类的析构函数）。

举一个例子：

```cpp
// 继承关系  a-> b -> c (子类), a,b,c都有虚析构函数，均重载了operator delete
// b的两个析构函数大概长这样
b::~b1(){   // in-charge destructor
    // some code to destruct b
    a::~a1();  // call in-charge destructor of a
}
b::~b2(){  // in-charge deleting destructor
    // the same code to destruct b
    a::~a1();  // call in-charge destructor of a
    operator delete(this);
}
// in-charge deleting destructor of c
c::~c2(){
    // some code to destruct c
    b::~b1();  // call in-charge destructor of b
    operator delete(this);
}
```

这样我们就可以在`in-charge deleting destructor`中静态指派`operator delete`（因为这时可以安全地假定自己是最派生类）。

现在我们可以考虑如何实现`placement delete`了，有两种可以考虑的方向

* 将`operator delete`加入虚函数表，对`operattor delete`进行动态转发
* 每定义一个新的有额外参数的`placement delete`，就生成一个新的带相应参数的析构函数，该析构函数负责把额外参数传给`operator delete`

不论哪种实现，都需要增加一些额外的复杂度，标准委员会也许是考虑到这一点才没有加入`placement delete`吧。

### 5. An real example in LLVM

最典型的就是`User`类的实现吧，源代码中在`User`类内部对`operator new`进行了重载，新的`operator new`除了分配`User`类的空间，还额外分配了该`User`的`Operand`数的`Use`类的空间，来追踪该`User`使用了哪些`Value`。因此对于那些固定操作数的`Instruction`，`new Instruction`后实际的内存布局为

```
     共 Operand个Use
   | Use | Use | ... | Instruction |
                     ↑__ ret ptr
```

### 6. Others

* 因为`new`和`delete`语法上的不对称性，通常使用`placement new`分配得到的内存没有办法直接通过`delete`释放，[Stroustrup: C++ Style and Technique FAQ, placement-delete](https://www.stroustrup.com/bs_faq2.html#placement-delete)提供了一个良好实践。
* 在讨论`operator new`和`operator delete`时，忽略了一个额外的对齐参数`std::align_val_t`，这个对齐参数是可选的，当编译器希望找一个具有对齐参数的版本而找不到时，便会转而寻找对应的没有该对齐参数的版本。

> If the type's alignment requirement exceeds `__STDCPP_DEFAULT_NEW_ALIGNMENT__`, alignment-aware deallocation functions (with a parameter of type [std::align_val_t](https://en.cppreference.com/w/cpp/memory/new/align_val_t)) are preferred. For other types, the alignment-unaware deallocation functions (without a parameter of type [std::align_val_t](https://en.cppreference.com/w/cpp/memory/new/align_val_t)) are preferred.

### 7. Refs

* [new expression - cppreference.com](https://en.cppreference.com/w/cpp/language/new)
* [operator new, operator new[] - cppreference.com](https://en.cppreference.com/w/cpp/memory/new/operator_new)

* [delete expression - cppreference.com](https://en.cppreference.com/w/cpp/language/delete)
* [operator delete, operator delete[] - cppreference.com](https://en.cppreference.com/w/cpp/memory/new/operator_delete)
* [Stroustrup: C++ Style and Technique FAQ, placement-delete](https://www.stroustrup.com/bs_faq2.html#placement-delete)

* [C++ FAQ array-derived-vs-base](https://isocpp.org/wiki/faq/proper-inheritance#array-derived-vs-base)
* [c++11 - Why there is no placement delete expression in C++? - Stack Overflow](https://stackoverflow.com/questions/5857240/why-there-is-no-placement-delete-expression-in-c)