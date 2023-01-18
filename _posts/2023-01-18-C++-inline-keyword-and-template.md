---
title: cpp inline keyword and template
date: 2023-1-18 22:07:30 +0800
categories: [cpp]
---

## 1. inline keyword in C++

虽然C和C++中**inline**关键字的含义不完全一样（比如C中并不要求当**inline**函数中包含静态变量时，该函数的每一处调用都使用同一个静态变量，但C++要求最终只能有一个静态变量被使用），不过核心要义都在于允许在链接时有多个相同的定义，然后取其中一个就行了（而不是内联！）。具体的实现方法依赖于最终可执行文件的格式，在ELF中，实现依赖于ELF中的**group section**以及**GRP_COMDAT**标志。

**inline**最重要的影响在于成员函数。C++规定：

> A function defined entirely inside a [class/struct/union definition](https://en.cppreference.com/w/cpp/language/classes), whether it's a member function or a non-member friend function, is implicitly an inline function

所以成员函数的定义有两种方法，要么完全定义在类内部作为**inline function**，定义也就放在头文件中，或者定义挪到类外边去，这时候就必须定义在源文件中（因为不再具有**inline**属性）。前者提供给了编译器更多的优化空间，后者则加快了编译速度并减少了目标文件的体积。

导致的另外一个细微的影响是，如果该成员函数定义在类中而且在该翻译单元中并不包含对该函数的调用，生成的目标文件将不会包含定义该成员函数的代码。

## 2. template instantiation

模板函数和模板类某种意义上和**inline function**很类似，因为它们都会出现在多个源文件中，并需要保证副本的唯一性（虽然我并没有在**cppreference**上看到明确地说明它们也具有**inline**）。

模板的实例化有显式和隐式之分，如果我们希望多个目标文件中只有一个同类型的模板实例，可以使用模板的显式实例化进行控制。(1)，(2)为显式定义，（3），（4）为显式声明

```
template return-type name < argument-list > ( parameter-list ) ; (1)
template return-type name ( parameter-list ) ;	(2)	
extern template return-type name < argument-list > ( parameter-list ) ;	(3)	(since C++11)
extern template return-type name ( parameter-list ) ;	(4)	(since C++11)
```

对于函数模板，C++规定：

> An explicit instantiation declaration (an extern template) prevents implicit instantiations: the code that would otherwise cause an implicit instantiation has to use the explicit instantiation definition provided somewhere else in the program.

因此只需要在一个源文件中显式实例化，其它源文件中显式声明，就可以保证只有显式实例化对应的目标文件中包含模板函数的代码。同样的，这样也许会降低生成代码的质量。

类模板有类似的语法：

```
template class-key template-name < argument-list > ;	(1)	
extern template class-key template-name < argument-list > ;	(2)	(since C++11)
```

> An explicit instantiation declaration (an extern template) skips implicit instantiation step: the code that would otherwise cause an implicit instantiation instead uses the explicit instantiation definition provided elsewhere (resulting in link errors if no such instantiation exists). This can be used to reduce compilation times by explicitly declaring a template instantiation in all but one of the source files using it, and explicitly defining it in the remaining file.

与函数模板的实例化不同的是，类模板的实例化可以更细粒度地操纵。

如果用上面的语法显式实例化类模板，则会实例化类的所有静态成员变量和成员函数。我们也可以选择显式实例化类模板的成员函数和静态成员变量。**cppreference**上的一个例子

```cpp
namespace N 
{
    template<class T> 
    class Y // template definition
    { 
        void mf() {} 
    }; 
}
 
// template class Y<int>; // error: class template Y not visible in the global namespace
using N::Y;
// template class Y<int>; // error: explicit instantiation outside 
                          // of the namespace of the template
template class N::Y<char*>;       // OK: explicit instantiation
template void N::Y<double>::mf(); // OK: explicit instantiation
```

实例化类模板的成员函数和静态成员变量时只会按需实例化（不论隐式还是显式实例化），比如在上面的示例中，如果类Y包含静态成员变量S，成员函数mf不使用S变量，那么显式实例化成员函数mf时不会实例化静态成员变量S。

> When code refers to a template in context that requires a completely defined type, or when the completeness of the type affects the code, and this particular type has not been explicitly instantiated, implicit instantiation occurs. For example, when an object of this type is constructed, but not when a pointer to this type is constructed.
>
> This applies to the members of the class template: unless the member is used in the program, it is not instantiated, and does not require a definition.

这样的成员按需实例化的特性也与第一节中描述的**inline**成员函数的特性相一致。

## 3. application of features of template instantiation

模板类成员函数的按需实例化的一个应用是结合**static_assert**进行静态检查，保证该函数不能被调用。例如LLVM的**iterator_facade_base**类，这个类作用是实现作为的迭代器的基类，避免许多重复的代码，`operator-(DifferenceTypeT n)`只有在子类的**tag**为**random_access**时才能调用，因此在该函数中设置了静态检查。当且仅当子类的**tag**不是**random_access**且调用了`operator-`时，该函数被实例化，并且静态检查不通过。

```cpp
template <typename DerivedT, typename IteratorCategoryT, typename T,
          typename DifferenceTypeT = std::ptrdiff_t, typename PointerT = T *,
          typename ReferenceT = T &>
class iterator_facade_base {
   /* some other code */
protected:
  enum {
    IsRandomAccess = std::is_base_of<std::random_access_iterator_tag,
                                     IteratorCategoryT>::value,
    IsBidirectional = std::is_base_of<std::bidirectional_iterator_tag,
                                      IteratorCategoryT>::value,
  };
public:
    DerivedT operator-(DifferenceTypeT n) const {
    static_assert(
        IsRandomAccess,
        "The '-' operator is only defined for random access iterators.");
    DerivedT tmp = *static_cast<const DerivedT *>(this);
    tmp -= n;
    return tmp;
  }
  /* some other code */
```

另外一个例子是LLVM中实现plugin机制的**Registry**类。作为插件的动态库引入**Registry.h**头文件时，只会拿到该模类各成员的声明，而没有定义。而在**executable**中使用**LLVM_INSTANTIATE_REGISTRY**宏补充定义，并显式实例化各成员函数和静态变量。使得只有**executable**有一份**Registry**的实例。

PS：不太清楚这样做是否有实际的意义，我觉得即使动态库中含义额外的静态成员变量实例等，动态链接器的重定位也会保证最终只会用到**executable**中的实例。
