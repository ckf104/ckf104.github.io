---
title: Cpp Name Lookup Rule
date: 2023-2-22 18:42:30 +0800
categories: [cpp]
---

之前写一段模板代码的时候，遇到了一段奇怪的报错

```cpp
template<class T>
class A{int a;};

template<class T>
class B : public A<T>{
    void f(){
        cout << a << endl;  // error! can't find definition of variable a
    }
};
```

为什么编译器不能查到模板基类中的`a`的声明呢？我们从**cppreference**上解释的[Name Lookup](https://en.cppreference.com/w/cpp/language/lookup)的规则说起。本文涉及到如下**C++**名词的解释

* **Qualified name lookup**
* **Unqualified name lookup**
* **Injected class name**
* **Dependent names vs Non-dependent names**
* **Argument-dependent lookup**

## 1. Qualified name lookup

简单来说，**Qualified name**指的是含有`::`的**id expression**，而**Unqualified name**就是不含`::`的**id expression**

排除掉**cppreference**上描述的一些不常用到的规则（例如根据**injected-class-name**, `struct A::A` 相当于`A`这种操作），剩下有两条比较有用的

> If there is nothing on the left hand side of the `**::**`, the lookup considers only declarations made in the global namespace scope (or introduced into the global namespace by a [using declaration](https://en.cppreference.com/w/cpp/language/namespace)).

这表明

```cpp
#include <iostream>
//int a = 3;
int main()
{
    struct std{};
    int a = 4;
    std::cout << ::a << std::endl; // error: ‘::a’ has not been declared
    ::std::cout << a << std::endl; // right, find std in global namespace 
}
```

> Qualified name lookup can be used to access a class member that is hidden by a nested declaration or by a derived class. A call to a qualified member function is never virtual

典型的用法是调用已经被hidden的子类方法，或者静态地调用虚函数。

```cpp
struct B { virtual void foo(); };
 
struct D : B { void foo() override; };
 
int main()
{
    D x;
    B& b = x;
 
    b.foo();    // calls D::foo (virtual dispatch)
    b.B::foo(); // calls B::foo (static dispatch)
}
```

## 2. Unqualified name lookup

符合直觉的基本原则是从最内层的**scope**开始寻找，直到**global namespace**，一旦在某一个**scope**中找到了该**name**的声明，就不再寻找外层的**scope**。要求在同一个**scope**中，只能找到一个声明。除开以下两点例外

* 函数重载和函数模板重载
* **struct hack or type/non-type hiding**（允许同一个**scope**中）

对第二条的解释如下，这是为了兼容C中`srtuct tm tm`这样的写法（因为在C中`struct tm`才表示完整的类型名）

> Within the same scope, some occurrences of a name may refer to a declaration of a class/struct/union/enum that is not a `typedef`, while all other occurrences of the same name either all refer to the same variable, non-static data member, or enumerator, or they all refer to possibly overloaded function or function template names. In this case, there is no error, but the type name is hidden from lookup (the code must use [elaborated type specifier](https://en.cppreference.com/w/cpp/language/elaborated_type_specifier) to access it)

例子

```cpp
#include <iostream>

using namespace std;

int F = 1;

int main()
{
    struct F{
        int m;
    };
    //F = 4; // error! struct F hides int F
    int F = 5; // "struct hack" or "type/non-type hiding", now struct F is hidden
    struct F f;  // to access hidden "struct F", use elaborated type specifier
    f.m = 7;
    cout << F << f.m << endl; 
}
```

### 2.1 Lookup Set

当然C++除了通常的**scope**导致的**name hiding**，还有**inheritance**，例如

```c++
struct A{
    void f(int){}
};
struct B: A{
    void f(){}
};

int main()
{
    B b;
    b.f(5); // error! void B::f() hides A::f(int)
    // use b.A::f(5) or "using A::f" in class B
}
```

在继承关系复杂时，基于直观的**name hiding**判断就不好用了。实际上，在决定该**name**到底引用哪一个成员时，编译器会构建一个**Lookup Set**

> If `C` is the class in whose scope the name was used, `C` is examined first. If the list of declarations in `C` is empty, lookup set is built for each of its direct bases `Bi` (recursively applying these rules if `Bi` has its own bases). Once built, the lookup sets for the direct bases are merged into the lookup set in `C` as follows
>
> - if the set of declarations in `Bi` is empty, it is discarded
> - if the lookup set of `C` built so far is empty, it is replaced by the lookup set of `Bi`
> - if every subobject in the lookup set of `Bi` is a base of at least one of the subobjects already added to the lookup set of `C`, the lookup set of `Bi` is discarded.
> - if every subobject already added to the lookup set of `C` is a base of at least one subobject in the lookup set of `Bi`, then the lookup set of `C` is discarded and replaced with the lookup set of `Bi`
> - otherwise, if the declaration sets in `Bi` and in `C` are different, the result is an ambiguous merge: the new lookup set of `C` has an invalid declaration and a union of the subobjects earlier merged into `C` and introduced from `Bi`. This invalid lookup set may not be an error if it is discarded later.
> - otherwise, the new lookup set of `C` has the shared declaration sets and the union of the subobjects earlier merged into `C` and introduced from `Bi`

下面这个例子详尽地阐述了这个过程。值得注意的是，上面的规则中术语使用的是**subobject**，而不是**subclass**，因此，如果将下面的例子改为`B1`, `B2`普通继承`X`（因此`D`中有两个`X`的副本），上面过程在合并`B1`的**Lookup Set**和`B2`的**Lookup Set**时会发现`B2`中的`X`不是`B1`的**subobject**，导致最终的`f()`的调用是**ambiguous**，编译错误。

```cpp
struct X { void f(); };
 
struct B1: virtual X { void f(); };
 
struct B2: virtual X {};
 
struct D : B1, B2
{
    void foo()
    {
        X::f(); // OK, calls X::f (qualified lookup)
        f(); // OK, calls B1::f (unqualified lookup), error if non-virtual inheritance
    }
};
// C++11 rules: lookup set for f in D finds nothing, proceeds to bases
//  lookup set for f in B1 finds B1::f, and is completed
// merge replaces the empty set, now lookup set for f in C has B1::f in B1
//  lookup set for f in B2 finds nothing, proceeds to bases
//    lookup for f in X finds X::f
//  merge replaces the empty set, now lookup set for f in B2 has X::f in X
// merge into C finds that every subobject (X) in the lookup set in B2 is a base
// of every subobject (B1) already merged, so the B2 set is discarded
// C is left with just B1::f found in B1
// (if struct D : B2, B1 was used, then the last merge would *replace* C's 
//  so far merged X::f in X because every subobject already added to C (that is X)
//  would be a base of at least one subobject in the new set (B1), the end
//  result would be the same: lookup set in C holds just B1::f found in B1)
```

### 2.2 injected class name

当**unqualified name**在类内部查找时，类名会作为一个**name lookup resolution**

> For the name of a class or class template used within the definition of that class or template or derived from one, unqualified name lookup finds the class that's being defined as if the name was introduced by a member declaration (with public member access).

例如下面的例子

```cpp
int X;
 
struct X
{
    void f()
    {
        X* p;   // OK. X refers to the injected-class-name
        ::X* q; // Error: name lookup finds a variable name, which hides the struct name
    }
};
```

由于**injected class name**表现得像**public member**，因此继承规则也适用

```cpp
struct A {};
struct B : private A {};
struct C : public B
{
    A* p;   // Error: injected-class-name A is inaccessible
    ::A* q; // OK, does not use the injected-class-name
};
```

**injected class name**的主要的作用体现在类模板中，简化我们对**current instantiation**的引用

> Like other classes, class templates have an injected-class-name. The injected-class-name can be used as a template-name or a type-name.

在以下情况，**injected class name**被认为是**template name**，否则被认为是**type name**

* it is followed by `<`
* it is used as a [template template argument](https://en.cppreference.com/w/cpp/language/template_parameters#Template_template_arguments)
* it is the final identifier in the [elaborated class specifier](https://en.cppreference.com/w/cpp/language/elaborated_type_specifier) of a friend class template declaration.

例子

```cpp
template<template<class, class> class>
struct A;
 
template<class T1, class T2>
struct X
{
    X<T1, T2>* p;   // OK, X is treated as a template-name
 
    using a = A<X>; // OK, X is treated as a template-name
 
    template<class U1, class U2>
    friend class X; // OK, X is treated as a template-name
 
    X* q;           // OK, X is treated as a type-name, equivalent to X<T1, T2>
};
```

## 3. Argument-dependent lookup

定义如下，**ADL**会根据参数，额外在类内部，命名空间中查找相应的函数名

> Argument-dependent lookup, also known as ADL, or Koenig lookup [[1\]](https://en.cppreference.com/w/cpp/language/adl#cite_note-1), is the set of rules for looking up the **unqualified function names** in [function-call expressions](https://en.cppreference.com/w/cpp/language/operator_other), including implicit function calls to [overloaded operators](https://en.cppreference.com/w/cpp/language/operators). These function names are looked up in the namespaces of their arguments in addition to the scopes and namespaces considered by the usual [unqualified name lookup](https://en.cppreference.com/w/cpp/language/lookup).

需要额外查找的类和命名空间根据如下规则进行构建（**cppreference**上很长，我仅保留了一些常用的规则）

> for every argument in a function call expression its type is examined to determine the *associated set of namespaces and classes* that it will add to the lookup.
>
> 1) **For arguments of fundamental type, the associated set of namespaces and classes is empty**
>
> 2) For arguments of class type (including union), the set consists of
>
>    a) **The class itself**
>
>    b) All of its direct and indirect base classes
>
>    c) If the class is a [member of another class](https://en.cppreference.com/w/cpp/language/nested_types), the class of which it is a member
>
>    d) **The innermost enclosing namespaces of the classes added to the set**

**ADL**在使用标准库时常常用到

```cpp
#include <iostream>
 
int main()
{
    std::cout << "Test\n"; // There is no operator<< in global namespace, but ADL
                           // examines std namespace because the left argument is in
                           // std and finds std::operator<<(std::ostream&, const char*)
    operator<<(std::cout, "Test\n"); // same, using function call notation
 
    // however,
    std::cout << endl; // Error: 'endl' is not declared in this namespace.
                       // This is not a function call to endl(), so ADL does not apply
 
    endl(std::cout); // OK: this is a function call: ADL examines std namespace
                     // because the argument of endl is in std, and finds std::endl
 
    (endl)(std::cout); // Error: 'endl' is not declared in this namespace.
                       // The sub-expression (endl) is not a function call expression
}
```

**ADL**带来的一些隐患是`using std::swap; swap(obj1, obj2);`与`std::swap(obj1, obj2);`不再相等，因为前者会有**ADL**规则介入，如果`obj1`实现了自己的`swap`函数，那么前者会调用该类特有的`swap`，后者会调用标准库中的`swap`

## 4 Name lookup in template

在**template**中，区分**dependent name**和**non-dependent name**，直观上来讲，前者的**name lookup**依赖于模板参数，后者则不依赖，因此前者的查找发生在**template definition**，后者的查找发生在**template instantiation**

> Non-dependent names are looked up and bound at the point of template definition. This binding holds even if at the point of template instantiation there is a better match

例子

```cpp
#include <iostream>
 
void g(double) { std::cout << "g(double)\n"; }
 
template<class T>
struct S
{
    void f() const
    {
        g(1); // "g" is a non-dependent name, bound now
        H(2); // error! even though S will not be instantiated
    }
};
 
void g(int) { std::cout << "g(int)\n"; }
 
int main()
{
    g(1);  // calls g(int)
 
    S<int> s;
    s.f(); // calls g(double)
}
```

另外，**non-dependent name**的查找也不会查看**dependent base class**

> if a base class depends on a template parameter, its scope is not examined by unqualified name lookup (neither at the point of definition nor at the point of instantiation)

值得注意的是，标准中这里的措辞是**unqualified name lookup**，因此一些**dependent name**也可能不会查看**dependent base class**

例如下面的例子中，虽然`g`是**dependent name**（因为参数类型依赖于模板参数），但仍没有查看**dependent base class**

```cpp
#include <iostream>
using namespace std;

struct F{
        void g(F a){
                cout << "Fa" << endl;
        }
};

void g(F m){
        cout << "global Gm" << endl;
}

template<class T>
struct A: public T{
        void f(T b){
                g(b); // this->g(b), T::g(b) will output "Fa"
        }
};

int main(){
        A<F>().f(F{});  // output "global Gm"
        return 0;
}
```

如果查找的**dependent name**是**function name**且是**unqualified name**，那么在模板实例化时它的**lookup**规则稍有特殊

> - non-ADL lookup examines function declarations with external linkage that are visible from the *template definition* context
> - [ADL](https://en.cppreference.com/w/cpp/language/adl) examines function declarations with external linkage that are visible from either the *template definition* context or the *template instantiation* context

下面是一个非常有意思的例子，注意`g(32)`会调用3次`f(char)`是因为前述的**ADL**规则第一条，基本类型不引入新的**namespace**和**class**

```cpp
void f(char); // first declaration of f
 
template<class T> 
void g(T t)
{
    f(1);    // non-dependent name: lookup finds ::f(char) and binds it now
    f(T(1)); // dependent name: lookup postponed
    f(t);    // dependent name: lookup postponed
//  dd++;    // non-dependent name: lookup finds no declaration
}
 
enum E { e };
void f(E);   // second declaration of f
void f(int); // third declaration of f
double dd;
 
void h()
{
    g(e);  // instantiates g<E>, at which point
           // the second and the third uses of the name 'f'
           // are looked up and find ::f(char) (by lookup) and ::f(E) (by ADL)
           // then overload resolution chooses ::f(E).
           // This calls f(char), then f(E) twice
 
    g(32); // instantiates g<int>, at which point
           // the second and the third uses of the name 'f'
           // are looked up and find ::f(char) only
           // then overload resolution chooses ::f(char)
           // This calls f(char) three times
}
```

关于为什么**dependent name**中**name of function expression**与其它**name**的查找规则不一样，我的理解是这样的。看下面的例子

```cpp
struct A{};

template<class T>
void g(T a){
  f(a);
}

template<class T>
void f(T a){}

template void g<A>(A); // explicit instantiation, find f by ADL rule
```

这个例子能够正常编译通过，即使在定义模板`g`时根本没有`f`的声明，但如果我们把`g`中`f(a)`的调用改为`C<T>()`或者`C<T>::m`这样涉及模板的表达式就不能编译通过了，要求在使用模板`C`前需要声明。这是由语法解析的过程造成的，当编译器看到**token**`<`，无法确定它到底是一个小于号还是用于指定模板参数，因此需要回查符号表判断`<`前的**identifier**是否为模板。因此表达式带`<`就需要提前声明了。

因为模板中的**dependent function name**使用时不需要提前声明，如果采用和其它**dependent name**相同的查找规则，会带来一些隐患。在下面的例子中，如果采用相同的规则，在实例化时查找到**P1::operator<<**和**P2::operator<<**的话，导致不同翻译单元的相同参数的模板却实例化不同。

```cpp
// an external library
namespace E
{
    template<typename T>
    void writeObject(const T& t)
    {
        std::cout << "Value = " << t << '\n';
    }
}
 
// translation unit 1:
// Programmer 1 wants to allow E::writeObject to work with vector<int>
namespace P1
{
    std::ostream& operator<<(std::ostream& os, const std::vector<int>& v)
    {
        for(int n : v)
            os << n << ' ';
        return os;
    }
 
    void doSomething()
    {
        std::vector<int> v;
        E::writeObject(v); // error: will not find P1::operator<<
    }
}
 
// translation unit 2:
// Programmer 2 wants to allow E::writeObject to work with vector<int>
namespace P2
{
    std::ostream& operator<<(std::ostream& os, const std::vector<int>& v)
    {
        for(int n : v)
            os << n <<':';
        return os << "[]";
    }
 
    void doSomethingElse()
    {
        std::vector<int> v;
        E::writeObject(v); // error: will not find P2::operator<<
    }
}
```

**Refs**

* https://stackoverflow.com/questions/57865891/whats-the-struct-hack-and-type-non-type-hiding
* https://stackoverflow.com/questions/25549652/why-is-there-an-injected-class-name
* https://en.cppreference.com/w/cpp/language/injected-class-name
* https://en.cppreference.com/w/cpp/language/adl
* https://en.cppreference.com/w/cpp/language/dependent_name#Lookup_rules
* https://en.cppreference.com/w/cpp/language/unqualified_lookup
* https://en.cppreference.com/w/cpp/language/qualified_lookup