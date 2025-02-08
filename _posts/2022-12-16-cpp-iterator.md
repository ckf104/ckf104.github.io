---
title: cpp iterator
date: 2022-12-16 22:55:30 +0800
comments: true
categories: [cpp]
---

虽然我写这篇博客的出发点是讨论`Iterator`，不过为了看懂标准库里面`Iterator`相关的代码，我又不得不查了许多其它cpp相关的东西，因此统一记录在这里。

## 1. 模板参数推导规则 

​	这一部分主要摘抄自effective c++

​	分三种情况：没有引用，有引用或者星号（指针），通用引用

```cpp
template <class T>
void f(T p);   // 引发编译错误来判断编译器推导的类型

int main(int, char**) {
  int a = 5;
  int& b = a;
  const int c = 7;
  const int& d = c;
  int * e = &a;
  const int* g = e;
  int array[7] = {0};
  const int array2[7] = {0};
  f(a);  // int    ->    int
  f(b);  // int&   ->    int
  f(3);  // int&&  ->    int
  f(c);  // const int  ->  int
  f(d);  // const int&  -> int
  f(e);  // int*    ->   int*
  f(g);  // const int*  -> const int*
  f(array); // int[]   -> int*
  f(array2); // const int[]  -> const int*
  return 0;
}
```

理解上述结果的关键在于参数中声明T而不带任何引用符号表明希望参数按值传递，因为是按值传递，`const`关键字留着也没用（影响不到外面）。唯一的特例是参数是指针类型，这时候就需要保留`const`关键字了，避免修改常量指针的数据。

```cpp
template <class T>
void f(T& p);  // T -> T&

  f(a);  // int    ->    int
  f(b);  // int&   ->    int
  f(3);  // int&&  ->    报错，不能推导
  f(c);  // const int  ->  const int
  f(d);  // const int&  -> const int
  f(e);  // int*    ->   int*
  f(g);  // const int*  -> const int*
  f(array); // int[7]   -> int[7] (相应的T&为 int(&)[7])
  f(array2); // const int[7]  -> const int[7] (相应的T&为 const int(&)[7])
```

类似地，我们声明的方式就是希望传入左值引用，因此传入一个右值会报错，由于传入的是引用，因此现在推导的T需要保留const关键字。最后值得注意的是传引用时数组类型不再退化为指针类型，这里的原因我不太理解，只能当一个特例记住吧。

```cpp
template <class T>
void f(T&& p);  // T -> T&&

  f(a);  // int    ->    int&
  f(b);  // int&   ->    int& (对应的T&&wei int&)
  f(3);  // int&&  ->    int (对应的T&&为 int&&)
  f(c);  // const int  ->  const int&
  f(d);  // const int&  -> const int&
  f(e);  // int*    ->   int*&
  f(g);  // const int*  -> const int*&
  f(array); // int[]   -> int(&)[7]
  f(array2); // const int[]  -> const int(&)[7]
```

现在我们声明为通用引用，就是希望传入左值时推导出的参数为左值引用，传入右值时推导出的参数为右值引用。上面的推导结果也确实如此，另外，数组的推导结果也与之前保持一致。

另一个涉及参数类型推导的关键字是`auto`，它的推导规则几乎与模板参数完全一致，唯一的例外是`initializer_list`

```cpp
template <class T>
void f(T p);

f({1,2,3});  // 类型推导失败
auto m = {1}  // m的类型为 initializer_list<int>
```

另外，在C++14中，auto可以用于泛型lambda以及返回值推导，这时的auto推导完全等价于模板参数了

```cpp
auto f(){
    return {1, 2, 3}; // error! 不能推导出 initializer_list<int>
}

auto f = [](const auto&){  // 泛型lambda，对应的call成员函数是一个模板
    // ....
}

decltype(auto) m = f() // using decltype rule for type deduction
```

顺便一提，`initializer_list`通常也不能作为返回值，它只是一个`proxy object`，指向的array会因函数的返回而析构。

## 2. 再看右值引用

这一节主要讨论右值引用的本质和一些关于通用引用的误解。

先看一个有意思的例子

```cpp
#include <iostream>
using namespace std;

class G{
	public:
	G(){ cout << "construct" << endl;}
	G(G& m){
		std::cout << "copy" << endl;
	}
	G(G&& m){
		std::cout << "move" << endl;
	}
	~G(){
		std::cout << "destroy" << endl;
	}
};

template<class T>
class F{
public:
void foo(const T& t){
	std::cout << "T" << std::endl;
}
void foo(T&& t){    // rvalue reference!
	std::cout << "T&&" << std::endl;
}
};

int main()
{
    auto a = F<G>();
	auto m = G();
  //a.foo((G)m);      will create a new G object!
	a.foo((G&)m);    // call foo(const T&)
	a.foo((G&&)m);   // call foo(T&&)
	int h = 7;
	(h) = 9;
	cout << h << endl;
   return 0;
}
```

有意思的点在于调用foo函数时的类型强转，m显然是一个左值，这里并没有调用`move`而是用C语言风格的类型强转把m转为了一个右值引用，使得其最终调用了`foo(T&&)`。也许会有这样的疑惑：

* 右值引用本身不是左值吗？所以应该调用`foo(const T&)`才对？
* 为什么可以把一个普通类型的变量强转为引用类型，引用类型类型不是类似于指针吗，这个表达式的结果是什么呢（这感觉类似于`int a=10; (int*)a`这种操作）

先说第二点。对于C风格的强转，编译器会把它诠释为C+类型的强转（`const_cast, static_cast, reinterpret_cast`中的某一个，具体的转换规则可参考[Explicit type conversion](https://en.cppreference.com/w/cpp/language/explicit_cast)）。这样实际对应的是`static_cast<G&&>`。而在reference对`static_cast`的说明中第二条解释了：

> If *new-type* is an rvalue reference type, static_cast converts the value of glvalue, class prvalue, or array prvalue (until C++17)any lvalue (since C++17) *expression* to *xvalue* referring to the same object as the expression, or to its base sub-object (depending on *new-type*).

所以上述转换表达式的结果就是该对象的左值引用（对应到IR或者汇编层面这是一个空操作）。

再看第一点。这个困惑产生的主要原因在于“右值引用是一个左值”这句话说法不太严谨。需要明确，当我们判断左值，右值时，判断的对象是一个表达式。而在C++中，每个表达式有`type`和`value category`两个属性。这在[Value categories](https://en.cppreference.com/w/cpp/language/value_category)明确解释了：

> Each C++ [expression](https://en.cppreference.com/w/cpp/language/expressions) (an operator with its operands, a literal, a variable name, etc.) is characterized by two independent properties: a *[type](https://en.cppreference.com/w/cpp/language/type)* and a *value category*. Each expression has some non-reference type, and each expression belongs to exactly one of the three primary value categories: *prvalue*, *xvalue*, and *lvalue*.

虽然我并不赞同`Each expression has some non-reference type`这个说法（参考[Scott Meyers: Expressions can have Reference Type](https://scottmeyers.blogspot.com/2015/02/expressions-can-have-reference-type.html)）。因此我们说的左值右值，其实是在判断表达式的`value category`，而不是`type`。“右值引用是左值”这句话更严谨的表达是“单独由一个右值引用类型组成的表达式的`value category`是一个左值（虽然表达式的类型依然是右值引用）”。这也来源于[Value categories](https://en.cppreference.com/w/cpp/language/value_category)：

> The following expressions are *lvalue expressions*:
>
> * the name of a variable, a function, a [template parameter object](https://en.cppreference.com/w/cpp/language/template_parameters#Non-type_template_parameter) (since C++20), or a data member, regardless of type, such as [std::cin](https://en.cppreference.com/w/cpp/io/cin) or [std::endl](https://en.cppreference.com/w/cpp/io/manip/endl). Even if the variable's type is rvalue reference, the expression consisting of its name is an lvalue expression;
> * a function call or an overloaded operator expression, whose return type is lvalue reference;

因此，为了解释强转为右值引用的合理性，只需要判断`(G&&)m`的`value categories`即可。`(G&&)m`适用于第二条规则。

> The following expressions are *xvalue expressions*:
>
> * a function call or an overloaded operator expression, whose return type is rvalue reference to object;
>
> * a cast expression to rvalue reference to object type, such as static_cast<char&&>(x);

最后看一下gcc中是怎么实现`move`和`forward`的：

```cpp
  template<typename _Tp>
    constexpr typename std::remove_reference<_Tp>::type&&
    move(_Tp&& __t) noexcept
    { return static_cast<typename std::remove_reference<_Tp>::type&&>(__t); }
```

可以看到，move本质上也就是一个强转。返回该类型的右值引用。根据`xvalue`判断的第一条规则知道表达式`move(m)`是一个右值。

`forward`的实现类似。第二个重载主要是为了能够转发右值，不过大部分情况下使用都是传入左值，所以重点关注第一个版本。当实例化为`forward<G&>`时，表明传入通用引用的参数是一个左值，可以看到，返回的`_Tp&&`被折叠为`G&`，根据上面的左值判断规则，表达式`forward<G&>(m)`是一个左值。当实例化为`forward<G>`时，表明传入通用引用的参数是一个右值，类似分析发现表达式`forward<G>(m)`是一个右值。

```cpp
  template<typename _Tp>
    constexpr _Tp&&
    forward(typename std::remove_reference<_Tp>::type& __t) noexcept
    { return static_cast<_Tp&&>(__t); }

  template<typename _Tp>
    constexpr _Tp&&
    forward(typename std::remove_reference<_Tp>::type&& __t) noexcept  // rvalue reference!
    {
      static_assert(!std::is_lvalue_reference<_Tp>::value, "template argument"
		    " substituting _Tp is an lvalue reference type");
      return static_cast<_Tp&&>(__t);
    }
```

## 3. 通用引用相关的杂项

### 3.1 区分通用引用与右值引用

在第二节中重载的`forward`就是一个很好的例子，那里是一个右值引用，而不是通用引用。通用引用仅出现在函数模板中，且在type参数没有被其它东西修饰时（即以`T&&`的形式出现）。

再看看gcc中是如何实现`remove_reference`的，这里用到了类的偏特化。值得注意的是第二个特化的定义，这里是通用引用吗？不是的，因为通用引用仅发生在函数模板中，编译器只会用第二个特化去匹配右值引用类型。

```cpp
  template<typename _Tp>
    struct remove_reference     // primary template class
    { typedef _Tp   type; };

  template<typename _Tp>
    struct remove_reference<_Tp&>   // partial specialized template class
    { typedef _Tp   type; };

  template<typename _Tp>
    struct remove_reference<_Tp&&>  // partial specialized template class
    { typedef _Tp   type; };
```

一个简单的检验方法是，修改为下面的定义，会发现` remove_reference<int&>::value`结果为true

```cpp
  template<typename _Tp>
    struct remove_reference: true_type{};

  template<typename _Tp>
    struct remove_reference<_Tp&&>: false_type{};

  remove_reference<int&>::value // check whether true or false
```

> 只有模板类才能做偏特化，因为类不能够重载。模板函数只能做全特化
{: .prompt-info }

另一个迷惑性的例子（来自[Multi-paradigm: Rvalue references and function overloading. (yapb-soc.blogspot.com)](https://yapb-soc.blogspot.com/2015/01/rvalue-references-and-function.html)）

```cpp
template<typename T>
struct X { };

template<typename T>
void f(T&&) { cout << "a" << endl;}

template<typename T>
void f(X<T&&>&) {cout << "b" << endl; }   // is it universal reference ?

int main() {
  X<int> x;
  X<int&> xref;
  X<int&&> xxref;
  f(x);          // output a  
  f(xref);      // output a 
  f(xxref);    // output b
}
```

可以看到，第二个重载的f也不是通用引用。

### 3.2. 右值引用与函数重载

下面的例子来源于[Multi-paradigm: Rvalue references and function overloading. (yapb-soc.blogspot.com)](https://yapb-soc.blogspot.com/2015/01/rvalue-references-and-function.html)

```cpp
template<typename T>
void f(T) { }

template<typename T>
void f(T&) { }

template<typename T>
void f(T&&) { }

int main() {
  int x = 0;
  f(0); // (1)
  f(x); // (2)
} 
```

上面的调用会引发编译错误，编译器不知道该使用哪个重载。原因在于编译器认为`T`和`T&`，或者`T`和`T&&`，是同样的精准匹配（这实在是C++标准中一些奇怪的地方，`T&`和`T&&`的优先级当然应该高于`T`，因为它们更加特化）。但如果我们去掉`f(T)`：

```cpp
template<typename T>
void f(T&) { }

template<typename T>
void f(T&&) { }

int main() {
  int x = 0;
  f(0); // call f(T&&)
  f(x); // call f(T&)
} 
```

这个结果也许可以用左值引用比通用引用更特化(`more specialized`)来解释。

## 4. void_t相关

C++17引入了`void_t`

```cpp
template< class ... > using void_t = void;
```

[stackoverflow](https://stackoverflow.com/questions/27687389/how-does-void-t-work)上的看到的一个典型用法是

```cpp
template< class , class = void >
struct has_member : std::false_type
{ };

// specialized as has_member< T , void > or discarded (sfinae)
template< class T >
struct has_member< T , void_t< decltype( T::member ) > > : std::true_type
{ };

has_member<T1>::value // usage
```

用来编译时检测一个类是否有数据成员`member`。这里也用到了类的偏特化。如果`T`有成员`member`，那么`decltype(T::member)`是良构的，因为`void_t`即为`void`，因此此时在保证第二个模板参数为`void`时，编译器总会选择这个偏特化的模板，从而结果为true。反之为false。

不过稍微考虑一下，如何把检测数据成员改为检测成员函数呢？下意识的，似乎只需要把`member`改为相应的成员函数名即可。实际测试发现行不通。原因在于`T::mem_func`并没有相应的类型（`typeid(T::mem_func)`会编译时报错），通常我们说函数的类型对应的是同签名的函数指针的类型，而全局函数可以隐式地退化为指针，但成员函数需要显式地取地址，因此我们需要写成这样

```cpp
template< class T >
struct has_member< T , void_t< decltype( &T::mem_func ) > > : std::true_type
{ };
```

另外，利用`template template parameter`，可以写出更泛化的形式（来源于[C++ Tutorial => void_t (riptutorial.com)](https://riptutorial.com/cplusplus/example/3778/void-t))

```cpp
struct details {  // 表示Z这个参数接收任意数量模板参数的模板
  template<template<class...>class Z, class=void, class...Ts>
  struct can_apply:
    std::false_type
  {};
  template<template<class...>class Z, class...Ts>
  struct can_apply<Z, std::void_t<Z<Ts...>>, Ts...>:
    std::true_type
  {};
};
template<template<class...>class Z, class...Ts>
using can_apply = details::can_apply<Z, void, Ts...>;

template<class T>
using z = decltype(T::member);

template<class T>
using has_member = can_apply<z, T>;  // 与之前的 has_member有同样效果
```

## 5. 自定义iterator

这下终于进入正题了，下面的讨论是基于*LegacyIterator*。C++里共有六种*LegacyIterator*，这里我们主要关心前五种。

* [Input Iterator](https://en.cppreference.com/w/cpp/named_req/InputIterator)（扫描一遍，只读，但每个元素可多次读）
* [Output Iterator](https://en.cppreference.com/w/cpp/named_req/OutputIterator)（扫描一遍，只写，但只允许写一次，多次写可能有副作用）
* [Forward Iterator](https://en.cppreference.com/w/cpp/named_req/ForwardIterator)（可读可写，但只支持++运算）
* [Bidirectional Iterator](https://en.cppreference.com/w/cpp/named_req/BidirectionalIterator)（可读可写，支持++和--运算）
* [Random Access Iterator](https://en.cppreference.com/w/cpp/named_req/RandomAccessIterator)（可读可写，支持加减整散和大小关系运算符）
* [Contiguous Iterator](https://en.cppreference.com/w/cpp/named_req/ContiguousIterator)

每个`Iterator`都有五个需要定义的标准类型：

* `iterator_category` 标识该`Iterator`属于上面六类中的哪一类
* `difference_type` 标识表示该`Iterator`迭代距离时所使用的数据类型（通常用于`advance`这类函数的返回值类型）
* `value_type` 标识该`Iterator`所指向对象的类型
* `pointer` 标识该`Iterator`所指向的对象对应的指针类型
* `reference` 标识该`Iterator`所指向对象对应的引用类型

每种`Iterator`都有相应的`iterator_category`，这里用到的`tag dispatch`的技巧

```cpp
  struct input_iterator_tag { };

  ///  Marking output iterators.
  struct output_iterator_tag { };

  /// Forward iterators support a superset of input iterator operations.
  struct forward_iterator_tag : public input_iterator_tag { };

  /// Bidirectional iterators support a superset of forward iterator
  /// operations.
  struct bidirectional_iterator_tag : public forward_iterator_tag { };

  /// Random-access iterators support a superset of bidirectional
  /// iterator operations.
  struct random_access_iterator_tag : public bidirectional_iterator_tag { };
```

使用继承是因为，任何一个`forward iterator`都是`input iterator`（其它类似），但是`forward iterator`不一定是`output iterator`（后者对同一个元素的写不一定是幂等的）。使用继承会给写算法带来方便（等下刨析`advance`的实现时会看到）。

当然，此外还需要为该`Iterator`定义好`++`，`*`，`->`，`==`等操作，依赖于所选择的`Iterator`类型，也许还需要重载其它的运算符。

看一个从[LLVM源码](https://llvm.org/doxygen/InstIterator_8h_source.html)中摘取的自定义`Iterator`的例子

```cpp
template <class BB_t, class BB_i_t, class BI_t, class II_t> class InstIterator {
   using BBty = BB_t;
   using BBIty = BB_i_t;
   using BIty = BI_t;
   using IIty = II_t;
   BB_t *BBs; // BasicBlocksType
   BB_i_t BB; // BasicBlocksType::iterator
   BI_t BI;   // BasicBlock::iterator
  
 public:  // 定义Iterator需要的五种类型
   using iterator_category = std::bidirectional_iterator_tag;
   using value_type = IIty;
   using difference_type = signed;
   using pointer = IIty *;
   using reference = IIty &;
  
   // Default constructor
   InstIterator() = default;
  
   // Copy constructor...
   template<typename A, typename B, typename C, typename D>
   InstIterator(const InstIterator<A,B,C,D> &II)
     : BBs(II.BBs), BB(II.BB), BI(II.BI) {}
  
   template<typename A, typename B, typename C, typename D>
   InstIterator(InstIterator<A,B,C,D> &II)
     : BBs(II.BBs), BB(II.BB), BI(II.BI) {}
  
   template<class M> InstIterator(M &m)
     : BBs(&m.getBasicBlockList()), BB(BBs->begin()) {    // begin ctor
     if (BB != BBs->end()) {
       BI = BB->begin();
       advanceToNextBB();
     }
   }
  
   template<class M> InstIterator(M &m, bool)
     : BBs(&m.getBasicBlockList()), BB(BBs->end()) {    // end ctor
   }
  
   // Accessors to get at the underlying iterators...
   inline BBIty &getBasicBlockIterator()  { return BB; }
   inline BIty  &getInstructionIterator() { return BI; }
  
   inline reference operator*()  const { return *BI; }
   inline pointer operator->() const { return &operator*(); }
  
   inline bool operator==(const InstIterator &y) const {
     return BB == y.BB && (BB == BBs->end() || BI == y.BI);
   }
   inline bool operator!=(const InstIterator& y) const {
     return !operator==(y);
   }
  
   InstIterator& operator++() {
     ++BI;
     advanceToNextBB();
     return *this;
   }
   inline InstIterator operator++(int) {
     InstIterator tmp = *this; ++*this; return tmp;
   }
  
   InstIterator& operator--() {
     while (BB == BBs->end() || BI == BB->begin()) {
       --BB;
       BI = BB->end();
     }
     --BI;
     return *this;
   }
   inline InstIterator operator--(int) {
     InstIterator tmp = *this; --*this; return tmp;
   }
  
   inline bool atEnd() const { return BB == BBs->end(); }
  
 private:
   inline void advanceToNextBB() {
     // The only way that the II could be broken is if it is now pointing to
     // the end() of the current BasicBlock and there are successor BBs.
     while (BI == BB->end()) {
       ++BB;
       if (BB == BBs->end()) break;
       BI = BB->begin();
     }
   }
 };
// Function::iterator 与 SymbolTableList<BasicBlock> 是相同类型
using inst_iterator =
     InstIterator<SymbolTableList<BasicBlock>, Function::iterator,
                  BasicBlock::iterator, Instruction>;
```

LLVM的`Function`类内部有一个用于遍历`BasicBlock`的迭代器，而`BasicBlock`里有一个用于遍历`Instruction`的迭代器。那想从`Function`中遍历`Instruction`咋办呢？上面的代码定义的`InstIterator`类做的事情其实是封装了这两个迭代器，对外提供了一个直接遍历`Instruction`的接口（实际内部的操作是先遍历第一个`BasicBlock`的所有`Instruction`，遍历完后，再遍历下一个`BasicBlock`...）

相同的算法函数，针对不同的迭代器会可能内部使用不同的算法，因此时间复杂度也不一样，我们来看看gcc里是怎么实现`advance`函数的：

```cpp
  template<typename _InputIterator, typename _Distance>
    inline _GLIBCXX17_CONSTEXPR void
    advance(_InputIterator& __i, _Distance __n)
    {
      // concept requirements -- taken care of in __advance
      typename iterator_traits<_InputIterator>::difference_type __d = __n;
      std::__advance(__i, __d, std::__iterator_category(__i));
    }

// std::__iterator_category 函数作用仅仅是返回一个 iterator_tag实例
  template<typename _Iter>
    inline _GLIBCXX_CONSTEXPR
    typename iterator_traits<_Iter>::iterator_category
    __iterator_category(const _Iter&)
    { return typename iterator_traits<_Iter>::iterator_category(); }


```

有意思的事情是，标准库中不会直接使用`_InputIterator::difference_type`，而是会用`iterator_traits`进行一层封装。我们先假定两者没什么区别，等下看`iterator_traits`实现时再进一步解释。实际的`__advance`有三个重载，它们接收不同类型的`Iterator`。最简单的接收`Input Iterator`，这时候要求`advance`第二个参数得是非负数。算法复杂度是O(n)的。

```cpp
  template<typename _InputIterator, typename _Distance>
    inline _GLIBCXX14_CONSTEXPR void
    __advance(_InputIterator& __i, _Distance __n, input_iterator_tag)
    {
      // concept requirements
      __glibcxx_function_requires(_InputIteratorConcept<_InputIterator>)
      __glibcxx_assert(__n >= 0);
      while (__n--)
	++__i;
    }
```

接下来的一种接收`Bidirection Iterator`，这时候由于`Iterator`支持`--`操作，第二个参数为负数也行了。

```cpp
  template<typename _BidirectionalIterator, typename _Distance>
    inline _GLIBCXX14_CONSTEXPR void
    __advance(_BidirectionalIterator& __i, _Distance __n,
	      bidirectional_iterator_tag)
    {
      // concept requirements
      __glibcxx_function_requires(_BidirectionalIteratorConcept<
				  _BidirectionalIterator>)
      if (__n > 0)
        while (__n--)
	  ++__i;
      else
        while (__n++)
	  --__i;
    }
```

最后一种接收`Random Access Iterator`，这下就可以使用O(1)的算法了。

```cpp
  template<typename _RandomAccessIterator, typename _Distance>
    inline _GLIBCXX14_CONSTEXPR void
    __advance(_RandomAccessIterator& __i, _Distance __n,
              random_access_iterator_tag)
    {
      // concept requirements
      __glibcxx_function_requires(_RandomAccessIteratorConcept<
				  _RandomAccessIterator>)
      if (__builtin_constant_p(__n) && __n == 1)
	++__i;
      else if (__builtin_constant_p(__n) && __n == -1)
	--__i;
      else
	__i += __n;
    }
```

值得注意的是，这里并没有定义`__advance`接收`Forward Iterator`，前面的继承作用就发挥出来了，`Forward Iterator`会被dispatch到第一种`__advance`的实现上。

最后我们来看下`iterator_traits`的实现

```cpp
  template<typename _Iterator>
    struct iterator_traits
    : public __iterator_traits<_Iterator> { };  

  template<typename _Tp>
    struct iterator_traits<_Tp*>  // 当然还有 const _Tp*的特化，因为基本完全一样就不再粘贴了
    {
      typedef random_access_iterator_tag iterator_category;
      typedef _Tp                         value_type;
      typedef ptrdiff_t                   difference_type;
      typedef _Tp*                        pointer;
      typedef _Tp&                        reference;
    };

template<typename _Iterator, typename = __void_t<>>  // __void_t 相当于 void_t
    struct __iterator_traits { };

  template<typename _Iterator>
    struct __iterator_traits<_Iterator,
			     __void_t<typename _Iterator::iterator_category,
				      typename _Iterator::value_type,
				      typename _Iterator::difference_type,
				      typename _Iterator::pointer,
				      typename _Iterator::reference>>
    {
      typedef typename _Iterator::iterator_category iterator_category;
      typedef typename _Iterator::value_type        value_type;
      typedef typename _Iterator::difference_type   difference_type;
      typedef typename _Iterator::pointer           pointer;
      typedef typename _Iterator::reference         reference;
    };
```

实现中用到了前面提到的`void_t`的技巧，可以看出，使用`iterator_traits`的好处有两个：

* 如果一个`Iterator`类没有把`iterator_category`，`value_type`等五个类型全部定义出来，那么对应的`iterator_traits`一个类型都不会生成，这样可以更早地发现错误。
* `iterator_traits`为指针类型自动生成了`iterator_category`等五个类型，因此使用`iterator_traits`的话使得算法除了支持传入迭代器外，同时也支持指针。

## 6. 参考

* [c++ - How does `void_t` work - Stack Overflow](https://stackoverflow.com/questions/27687389/how-does-void-t-work)

* [C++ Tutorial => void_t (riptutorial.com)](https://riptutorial.com/cplusplus/example/3778/void-t)

* [An Introduction to "Iterator Traits" - CodeProject](https://www.codeproject.com/Articles/36530/An-Introduction-to-Iterator-Traits)
* [Writing a custom iterator in modern C++ - Internal Pointers](https://www.internalpointers.com/post/writing-custom-iterators-modern-cpp)
* [c++ - What is the partial ordering procedure in template deduction - Stack Overflow](https://stackoverflow.com/questions/17005985/what-is-the-partial-ordering-procedure-in-template-deduction)
* [Multi-paradigm: Rvalue references and function overloading. (yapb-soc.blogspot.com)](https://yapb-soc.blogspot.com/2015/01/rvalue-references-and-function.html)
* [Expressions can have Reference Type](https://scottmeyers.blogspot.com/2015/02/expressions-can-have-reference-type.html)
