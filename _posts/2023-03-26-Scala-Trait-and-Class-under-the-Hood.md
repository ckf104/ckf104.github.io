---
title: Scala Trait and Class under the Hood
date: 2023-03-26 21:02:45 +800
categories: [Scala]
---

**Scala**的**class**和**trait**的区别和使用是该语言中相当迷惑的一部分了。本文希望通过**Scala**编译后得到的**Java ByteCode**来探究其内部机理（**基于Scala 2**）

## 1. Overview

我们先来看看**Scala**的一些语言机制给上层提供的抽象

```scala
class A{
    val a = 5
    def pr : this.type = {  // return acutual sub type 
        println("hello")
        this
    }
    class H{   // nesting type
        def pr = A.this.pr  // bound with instance of outer class
    }
}
trait B extends A  // trait can extend from class if the class constructor don't have parameter
trait C extends A{
   	override val a = 7  // override existing member
    override def pr = {
        println("i am C")
        super.pr         // override with call of super method 
    }
}

class D extends B with C // equally `class D extends A with B with C`
```

现在我们关心的问题是，给上层展现的复杂机制如何翻译为朴素的**Java ByteCode**

## 2. Basic Translation Ideas

**Rule 1**：**trait**被翻译为**java interface**，`trait extends trait`被翻译为`interface extends interface`. 

**Rule 2**：**class**被翻译为**java class**，`class extends class`被翻译为`java class extends class`, `class extends trait`被翻译为`class implements interface`

如果暂不考虑`trait extends class`，应用上面两条规则，我们将**Scala**中的继承分为以下三种情况

```scala
class A extends sc with tr1 with ... with trn // sc is a class, tr1 ... trn is a trait
// case 1: 翻译为 class A extends sc implements tr1, ... trn
class A extends tr1 with ... with trn
// case 2: 翻译为 class A implements tr1, ... trn
trait B extends tr1 with ... with trn
// case 3: 翻译为 interface B extends tr1, ... trn

trait B extends sc with tr1 with ... with trn
// case 4: explained below
```

现在我们来考虑`trait extends class`的情况，首先由于**trait**的构造函数不能含有参数，因此相应的子类的构造函数也不能含有参数。现在我们重新考虑**case 2**的翻译，[Scala spec](https://www.scala-lang.org/files/archive/spec/2.13/05-classes-and-objects.html)规定

> It is possible to write a list of parents that starts with a trait reference, e.g. `tr1 with …… with trn`. In that case the list of parents is implicitly extended to include the supertype of tr1 as the first parent type. The new supertype must have at least one constructor that does not take parameters.

换句话说，如果`tr1`继承过某个父类**sc**，那么`A extends tr1 ...`将被拓展为`A extends sc with tr1 ...`，这样**case 2,3**的翻译化归为**case 1,4**

对于**case 1,4**，[Scala spec](https://www.scala-lang.org/files/archive/spec/2.13/05-classes-and-objects.html)中有如下限制

> The list of parents of a template must be well-formed. This means that the class denoted by the superclass constructor sc must be a subclass of the superclasses of all the traits tr1 ... trn. In other words, the non-trait classes inherited by a template form a chain in the inheritance hierarchy which starts with the template's superclass.

直白地理解就是，如果`tr1 ... trn`有继承某个父类`sc'`，那么要求`sc`必须是`sc'`的子类。它隐含地表明，在**case 2,3**中如果`tr1`没有继承任何父类（`class`），那么`tr2 ... trn`也不能继承任何父类。例子

```scala
class A
trait B
trait C extends A
trait D extends B with C   // compile error!
trait E extends C with B // ok, equally `trait E extends A with B with C`
```

这条规则本质上是为了避免出现多继承，即一个`class`至多有一个`class`的直接父类，例如

```scala
class A
class B
trait C extends A
class D extends B with C // compile error, because B is not subclass of A
// 如果没有上面的限制，将会导致D实际上是A，B的共同子类，没办法翻译了
// 如果修改为 class B extends A
// `class D extends B with C` 就能被翻译为 `class D extends B implements C`
// 因此现在加入 `trait extends class`的情况后，case 1的翻译规则依然适用
```

最麻烦的是**case 4**，因为在**java**中并不存在`interface extends class`的语法，**Scala**采取的做法是在翻译时直接忽略这个子类`sc`。即翻译为`interface B extends tr1, ... trn`。这自然会产生如下问题

```scala
trait B extends sc with tr1 with ... with trn
def func(b: B) = b.method_of_sc // call method of sc
```

上面的`func`在**Scala**语法层面自然没有任何问题，但是翻译到**ByteCode**时就糟糕了，因为`Interface B`并没有定义`sc`内方法的接口。因此**Scala**在翻译为**java**时插入了额外的**casting**

```java
public ret_type func(B b) { return ((sc)b).method_of_sc;}
// 将 interface B 强转为 sc type
```

这样的转换安全吗，回顾上面提到的[Spec](https://www.scala-lang.org/files/archive/spec/2.13/05-classes-and-objects.html)中的两条限制，会发现如果`trait B`继承了某个父类`sc'`，那么继承了`trait B`的子类`sc`必然是`sc'`的子类。因此我们得到

**Rule 3**：`trait extend class`的继承关系不体现在**ByteCode**中，该`trait`要使用父类接口时在**ByteCode**中表达为类型强转。这样的强转一定是安全的。

为了验证这一点，我们来看实际的例子

```scala
class M1{
  def pr = println("M1")
}
trait M2 extends M1
trait M3 extends M1
class M4 extends M2 with M3{
  def pr(m: M2): Unit ={
    m.pr
  }
}
```

将上述代码翻译为**class**文件后，使用`javap`反汇编为字节码查看

```bash
$ javap -p target/scala-2.13/classes/M2.class 
Compiled from "Main.scala"
public interface M2 {
}

$ javap -p target/scala-2.13/classes/M3.class 
Compiled from "Main.scala"
public interface M3 {
}
# M2,M3 接口中并没有M1.pr函数

$ javap -p target/scala-2.13/classes/M4.class
Compiled from "Main.scala"
public class M4 extends M1 implements M2,M3 {
  public void pr(M2);
  public M4();
}
# Scala将 class M4 extends M2 with M3 重写为 class M4 extends M1 with M2 with M3

$ javap -c target/scala-2.13/classes/M4.class # check bytecode
Compiled from "Main.scala"
public class M4 extends M1 implements M2,M3 {
  public void pr(M2);
    Code:
       0: aload_1
       1: checkcast     #4                  // class M1
       4: invokevirtual #18                 // Method M1.pr:()V
       7: return

  public M4();
    Code:
       0: aload_0
       1: invokespecial #24                 // Method M1."<init>":()V
       4: return
}
# 可以看到在M4.pr的字节码中，interface M2被强转为了class M1，这正是我们所预期的
```

而如果我们将上面的例子稍作修改，将`class M1`改为`trait M1`，那么`M4.pr`中的`checkcast, invokevirtual`将合并为一条`invokeinterface`

## 3. Definition in Trait

在第2节中只讨论了基本的翻译规则，即继承关系是如何翻译到**ByteCode**中的，但`trait`除了和`Interface`一样可以声明函数接口，还能声明数据成员，甚至定义函数接口和数据成员，这是如何办到的呢？

**Rule 4**：数据成员的声明与定义翻译为相应的`setter`, `getter`函数接口声明，`setter`和`getter`的实现以及具体的数据定义在继承该`trait`的子类中

**Rule 5**：函数接口的定义翻译为`Interface`中的`default method`

额外的一点是，定义数据成员意味着还有初始化这一环，即`trait`实际上是有构造函数的（虽然没有参数）

**Rule 6**：`trait`的构造函数翻译为`Interface`的`static method`，接收一个参数，即该`interface`本身

这样，当子类初始化时，调用该`Interface`的`static method`，传入`this`指针作为参数，那么在该`static method`中就可以调用声明的`setter`, `getter`来进行数据成员的初始化。

## 4. Class Linearization and Initialization Order

这一节借助**Class Linearization**的概念来讨论`trait`与`class`的构造函数的初始化顺序问题，这个概念还会在讨论`super reference`时派上用场

**Class Linearization**定义在**Spec[5.1.2]**，简单来说，对于`c extends sc with tr1 ... trn`，我们需要给它的所有父类以及`trait`安排一个顺序，记为$L(c)$，即一个有序集合。$L(c)$的实际计算公式为
$$
L(c) = \{c\} + L(tr_n) + L(tr_{n-1}) + \dots +L(tr_1) + L(sc)
$$
这里的$+$表示有序集合的拼接，且如果$A + B$时$A, B$存在共同元素$q$，那么只保留$B$中的$q$，即$\{a, b\} + \{b, c\} = \{a, b, c\}$

看一个例子

```scala
class A
trait B extends A
trait C extends A
class D extends B with C { /* some stats */ }
// class D extends A with B with C
// L(D) = {D} + L(C) + L(B) + L(A) = {D} + {C, A} + {B, A} + {A} = {D, C, B, A}
```

$L(c)$的一个重要性质在于如果$sc$是$c$的直接父类，那么$L(sc)$是$L(c)$的后缀，由此**Spec[5.1]**中定义了如下初始化顺序（$c$的构造函数）

* First, the superclass constructor $sc$ is [evaluated](https://www.scala-lang.org/files/archive/spec/2.13/05-classes-and-objects.html#constructor-invocations).
* Then, all base classes in the template's [linearization](https://www.scala-lang.org/files/archive/spec/2.13/05-classes-and-objects.html#class-linearization) up to the template's superclass denoted by $sc$ are mixin-evaluated. Mixin-evaluation happens in reverse order of occurrence in the linearization.
* Finally, the statement sequence $stats$ is evaluated.

用上面的菱形继承的例子来看，D的构造函数首先会执行A的构造函数，然后在$L(D)$中除掉$L(A)$的元素，反序执行这些`trait`的构造函数，即先执行B的构造函数，然后执行C的构造函数，最后执行D中的$stats$部分。

看一个具体的例子

```scala
trait M1{
  val name: String
  val msg: String = "hello, " + name
}
trait M2 extends M1{
  val mB = "hello, " + name
}
trait M3 extends M1{
  val mC = "hello, " + name
}

class M4 extends M2 with M3{
  val name = "D"
  def prA = println(msg)
  def prB = println(mB)
  def prC = println(mC)
}
// L(M4) = {M4, M3, M2, M1}
```

反汇编得到的字节码如下，可以看到，这正是我们所预期的构造函数执行顺序

```shell
  public M4();
    Code:
       0: aload_0
       1: invokespecial #56                 // Method java/lang/Object."<init>":()V
       4: aload_0
       5: invokestatic  #62                 // InterfaceMethod M1.$init$:(LM1;)V
       8: aload_0
       9: invokestatic  #65                 // InterfaceMethod M2.$init$:(LM2;)V
      12: aload_0
      13: invokestatic  #68                 // InterfaceMethod M3.$init$:(LM3;)V
      16: aload_0
      17: ldc           #70                 // String D
      19: putfield      #33                 // Field name:Ljava/lang/String;
      22: invokestatic  #75                 // Method scala/runtime/Statics.releaseFence:()V
      25: return
```

顺便也可以看看M1, M2的接口声明

```shell
$ javap -p target/scala-2.13/classes/M1.class 
Compiled from "Main.scala"
public interface M1 {
  public abstract void M1$_setter_$msg_$eq(java.lang.String);
  public abstract java.lang.String name();
  public abstract java.lang.String msg();
  public static void $init$(M1);
}
# 数据成员的初始化翻译为$init$ static method
# M1$_setter_$msg_$eq -> setter函数
# msg , name -> getter函数

$ javap -p target/scala-2.13/classes/M2.class 
Compiled from "Main.scala"
public interface M2 extends M1 {
  public abstract void M2$_setter_$mB_$eq(java.lang.String);
  public abstract java.lang.String mB();
  public static void $init$(M2);
}
```

值得注意的是，**上面定义的执行顺序表明，所有的`trait`的构造函数都由`class`来调用，即`trait A extends B`，那么`A`的构造函数是不会调用`B`的构造函数的。**我认为这是要求`trait`的构造函数没有参数的本质原因（因为如果有参数的话，`class a extends b with tr`时则需要显式地给非直接继承的`trait`提供参数，实在有些古怪。虽然C++实际上就是这么干的，需要显式调用虚基类的构造函数）。

另外，上面的**Scala**代码执行时会发现`msg`中`name`为空，因为根据构造函数执行顺序`val name = "D"`的赋值会在最后执行。因此**Scala**提供了**Early Definition**机制，将`M4`的定义修改为

```scala
class M4 extends {val name = "D"} with M2 with M3{
  def prA = println(msg)
  def prB = println(mB)
  def prC = println(mC)
}
```

代码段`{val name = "D"}`将在调用子类构造函数前执行

## 5. Override Rules

首先，`override`是针对`val`数据的，因为可变数据直接修改就可以了。我们主要关心的有两点，在**Scala**语义规范层面多个`override`如何确定最终的值和`override`语义如何翻译为字节码

[Spec[5.1.4]](https://www.scala-lang.org/files/archive/spec/2.13/05-classes-and-objects.html#overriding)规定了`override`的语义规范。首先值得注意的是`private`修饰的变量是不可`override`的，因为它对子类不可见，因此子类可以直接定义重名的变量，而父类中的引用该`private`变量都静态绑定。例如

```scala
trait A{
    private val b = "a"
    def pr = println(b)
}
class B extends A{
    val b = "b"
    pr  // print "a"
}
```

在生成的字节码中，`class B`除了有一个`b`成员变量，还有一个`A$$b`变量，对应`trait A`中定义的数据

**Spec**中核心的论述如下，即在**Linearization**中靠前的类或者`trait` 的定义覆盖后面的定义

> First, a concrete definition always overrides an abstract definition. Second, for definitions *M* and *M*' which are both concrete or both abstract, *M* overrides *M*' if *M* appears in a class that precedes (in the linearization of *C*) the class in which *M*′ is defined.

例如

```scala
trait base{
    val m = 1
}
class A extends base{
  override val m = 2
  println(m)  // m = 0
}

trait B extends base {
  override val m = 7
  println(m)   // m = 0
}

trait E extends base {
  override val m = 9
}

class C(q:Int) extends A with B with E{
  println(m)   // m = 9, 因为E是Linearization中最靠前的
}
// new C 输出为 0, 0, 9  而 new A 输出为 2
```

具体在字节码上的实现就简单了，函数的重载没什么好说的。对于数据成员的重载，有两种情况

如果`override`重载发生在`trait`中，每个定义了该变量的`trait`对应的`interface`中都会生成相应`setter`函数，例如上面的例子，在生成的字节码中，`trait B, E`都有自己的`setter`函数（这些方法的实现自然定义在`class C`中），在编译时我们就能够知晓`class C`中最终`m`的定义来自`trait E`，那么`class C`中为`trait E`生成的`setter`函数会实际修改`m`的值，而为`trait B`生成的`setter`函数则是空操作。注意这种情况最终`m`只有一份副本

而如果`override`重载发生在`class`中，例如上面的`override val m = 2`，构造函数中对这里的赋值是实现为`putfield`，而不是`invokevirtual`来调用`setter`（这也是为什么在`trait B`中`println(m)`输出为`0`），而在后续获取`m`的值时则使用`invokevirtual`会获取到`class C`中的副本（这也是为什么在`class A`中`println(m)`输出也为`0`）。此时`class C`中实际上有两份`m`，一份来自`class A`，一份来自`trait E`中的重载

## 6. Nested Class

参考https://docs.scala-lang.org/tour/inner-classes.html即可。与**C++**中的**nested class**，**Scala**中的嵌套类的成员变量中隐含了外部类的引用，在嵌套类中，我们可以通过`C.this`来引用外部类，其中`C`是外部类的名字。

另外就是，在链接的例子中`graph1.Node`这样一种变量类型只是一种高层次的抽象，翻译为字节码时，类型都是`Graph#Node`。另外，编译器也不会进行任何的别名检查，例如`val graph2 = graph1`，编译器仍会认为`graph1.Node`和`graph2.Node`不是同一种类型

## 7. This Type

使用`this.type`时，上层提供的抽象是返回实际的`this`指针类型，比如我们在通常的链式操作时，希望成员函数返回类自身来实现`A.set().set()`这样的操作。但如果`class B extends A`，当`B`调用`A`的成员时，`A`的成员函数只能返回`A`类型，导致需要手动强转`asInstanceOf`，`this.type`本质上是一个语法糖，翻译为字节码时，返回类型在字节码中还是`A`，当**caller**的类型是`A`的子类，但是调用的是`A`中的函数时，**caller**的代码会额外插入一条强转，将返回值又转回**caller**原本的类型（**而在C++中则需要手动在子类中重载这个方法**）

## 8. Super Reference

**Super Reference**通常与**override**搭配，因为`override`虽然会覆盖`trait`中的数据成员，但不会覆盖其方法，我们可以借此来实现叠加操作，即重载的新函数内部会调用被覆盖的旧函数。看下面的例子

```scala
trait Ball {
  def properties(): List[String] = List()
  override def toString() = "It's a" +
    properties.mkString(" ", ", ", " ") +
    "ball"
}

trait Red extends Ball {
  override def properties() = super.properties ::: List("red")
}

trait Shiny extends Ball {
  override def properties() = super.properties ::: List("shiny")
}
class MM extends Red with  Shiny{
  println(this)  // It's a red, shiny ball
}
```

同样的，我们关心的是`super`的语义以及底层的实现机制。[Spec[6.5]](https://www.scala-lang.org/files/archive/spec/2.13/06-expressions.html#this-and-super)中规定

> A reference `super.m` refers statically to a method or type *m* in the least proper supertype of the innermost template containing the reference. It evaluates to the member *m*′ in the actual supertype of that template which is equal to *m* or which overrides *m*. The statically referenced member *m* must be a type or a method.

**Spec[5.1]**中定义*least proper supertype*

> The *least proper supertype* of a template is the class type or [compound type](https://www.scala-lang.org/files/archive/spec/2.13/03-types.html#compound-types) consisting of all its parent class types.

在**Spec[5.4]**中有如下论述

> Assume a trait *D* defines some aspect of an instance *x* of type *C* (i.e. *D* is a base class of *C*). Then the *actual supertype* of *D* in *x* is the compound type consisting of all the base classes in *L*(*C*) that succeed *D*. The actual supertype gives the context for resolving a [super reference](https://www.scala-lang.org/files/archive/spec/2.13/06-expressions.html#this-and-super) in a trait.

将上面这些翻译为人话就是，对于一个`class A extends sc with tr1 ... trn`，在`class A`中引用`super.m`，那么这个`super`可以理解为`sc with tr1 ... trn`，而在一个`trait A`中，这个`super`没有办法静态决定，依赖于继承它的类，假设继承它的类`C`的**Linearization** $L(C) = \{C, ... A, B, K\}$，那么在`A`中的`super`可以理解为`B with K`

现在回头看上面的例子，我想应该能理解输出为什么是这样了。

了解了`super`的语义，那么实现也容易想到了，`class`中的`super`不用说，麻烦的是`trait`中的`super`，因为它的语义依赖于继承该`trait`的类。那么自然的想法就是对每个需要解析的`super.m`引用，在`trait`中新增一个接口，让继承该`trait`的类来实现该接口即可。我们来查看上面的`trait Shiny`对应的`Interface`定义

```shell
$ javap -p target/scala-2.13/classes/Shiny.class 
Compiled from "Main.scala"
public interface Shiny extends Ball {
  public abstract scala.collection.immutable.List Shiny$$super$properties();
  public static scala.collection.immutable.List properties$(Shiny);
  public default scala.collection.immutable.List<java.lang.String> properties();
  public static void $init$(Shiny);
}
```

注意到新增的`Shiny$$super$properties`接口，该接口在`class MM`中实现为调用`Interface Red`中的静态方法，最终会调用`Red`中的`Properties`方法

```shell
  public scala.collection.immutable.List Shiny$$super$properties();
    Code:
       0: aload_0
       1: invokestatic  #18                 // InterfaceMethod Red.properties$:(LRed;)Lscala/collection/immutable/List;
       4: areturn
```

另外值得一说的是，我们也可以静态指定`super`的类型，例如改为下面这样，即静态绑定到`Ball.properties`上，此时就不需要生成额外的接口函数

```scala
trait Red extends Ball {
  override def properties() = super[Ball].properties ::: List("red")
}
```

最后一点，`super`不能用来引用数据，这也很好理解，因为`trait`中即使`override`，数据成员只有一份。

## 9. Others

一些其他尚未讨论到的点，例如`type parameter`, 泛型等等

## 10. Refs

* [Scala 2.13 spec](https://www.scala-lang.org/files/archive/spec/2.13/05-classes-and-objects.html)
* [Scala Tour: Inner Class](https://docs.scala-lang.org/tour/inner-classes.html)
* [StackOverflow: This Type](https://stackoverflow.com/questions/4313139/how-to-use-scalas-this-typing-abstract-types-etc-to-implement-a-self-type) 