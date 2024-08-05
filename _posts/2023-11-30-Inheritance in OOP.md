---
title: Interitance in OOP
date: 2023-11-30 7:23:41 +0800
categories: [misc]
---

多重继承中的重名问题，在子类引用某个成员变量或者函数时，选择哪一个父类中的定义（单继承是比较直观的，多个名称冲突，子类覆盖父类即可），论文 [A Monotonic Superclass Linearization for Dylan](https://dl.acm.org/doi/pdf/10.1145/236338.236343)

* ~~对了，是否需要考虑方法重载呢？至少 C++ 并没有考虑这一点，因为子类有父类的重名方法时，就算声明不同，也会将其覆盖掉。~~ 各个编程语言自己来决定即可，不涉及问题的本质

* C++ 采用的方法是由程序员显示指定？在 C++ 有 [class member lookup](https://stackoverflow.com/questions/3310910/method-resolution-order-in-c) 算法来定义 ambiguous reference，当该算法不能选出唯一的函数和它对应的类时编译器就会报错了。
* Python 使用论文中的 C3 linearization 算法来指定 [Method Resolution Order](https://www.python.org/download/releases/2.3/mro/)。在访问 class method 或者 class attribute 时使用该算法得出的顺序来决定访问哪个 class method or attribute。
* Scala 使用的 linearization 算法保留了 local precedence order，但不具有 monotonicity，例如下面的例子。另外，super 的语义也与 Python 有稍微的不同，在不加类型参数时和 Python 相同，沿着线性序列寻找下一个指定的方法。但是在 super[T] 在 scala 中表示静态绑定，即在父类 T 的 linearization 序列中寻找指定的方法，因此在编译时就知道会调用哪个方法（而并非 python 中的从 T 类型这个位置开始找）

```scala
trait a{
  val msg = "a"
  def pr = println(msg)
}
trait b extends a{
  override val msg = "b"
}
trait c extends a{
  override val msg = "c"
}
trait d extends c with b

trait m extends b 

class DA extends d
class DB extends m
class DC extends m with d

(new DA).pr
(new DB).pr
(new DC).pr
// output: b b c
// DC.pr is `c` is a bit suprising result
```

## Python Import and Metaclass Related

这显然是应该另开一篇文章的东西，但我暂时先放在这里

import mechanism 相关参考

* [The Import System](https://docs.python.org/3/reference/import.html)
* [importlib](https://docs.python.org/3/library/importlib.html)
* [知乎：聊聊 python 的 import system](https://zhuanlan.zhihu.com/p/348559778)

最后一篇知乎的博文有价值的地方在于它从源码的角度，自底向上地去讨论 python 的 import system，顺着查阅相关的源码，就能够轻易地理解 regular package 和 namespace 的 package 的区别，也能够理解为什么说 package 和 module 几乎是一回事。regular package 对应的 python 文件就是 `__init__.py`，而 namespace package 不对应 python 文件，对应的`loader.exec_module`是一个空函数。

另外，关于`__all__`关键字的解释

* [module tutorial](https://docs.python.org/3/tutorial/modules.html#importing-from-a-package)
* [what does all mean in python](https://stackoverflow.com/questions/44834/what-does-all-mean-in-python)

### Metaclass

* [python datamodel](https://docs.python.org/3/reference/datamodel.html)

* [what are metaclasses in python](https://stackoverflow.com/questions/100003/what-are-metaclasses-in-python)

* [behavior of new in a metaclass also in context of inheritance](https://stackoverflow.com/questions/67105633/behavior-of-new-in-a-metaclass-also-in-context-of-inheritance)

理解这个事情比较重要的点在于，通常的 class object 其实是 type 元类的实例。因此实例化类的代码等价于 `Foo(1,2) == type.__call__(Foo, 1, 2)`。另外就是 [python datamodel](https://docs.python.org/3/reference/datamodel.html) 中提到了很重要的一点在于 python 中如何确定 class object 的 metaclass 的算法，这明确了 metaclass 在子类中如何确定。注意，metaclass 不需要是一个 type 元类的实例，只要是一个 callable object 就行了（例如函数，它是 function 类的实例，而 function object 才是 type 元类的实例）。

**TODO**：还有一个涉及的问题是 Python 如何找 attribute 的，目前看起来的结果是，对于`x.foo`，首先查看`x.__dict__`，如果没有，看`x`是不是 class object，如果是的话再去`x`的子类里面找。然后找`x.__class__.__dict__`及其相应的子类。**这里一个重要的事情是如果`x`是 class object，那么它的元类的属性也可能被访问**

### Python C-API

* https://docs.python.org/3/c-api/index.html
* https://docs.python.org/3/extending/index.html

[Extending](https://docs.python.org/3/extending/extending.html#reference-counts) 中对 Python 引用计数相应的约定讨论得很好

garbage collection相关：escape analysis



