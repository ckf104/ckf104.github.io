* Automatic translation of FORTRAN programs to vector form：关于 data dependence 论述相当精彩的论文，主要给出了在多重循环背景下，loop carried data dependence 的形式化定义，以及 loop interchangable 的形式化判定方法

* Efficiently Computing Static Single Assignment Form and the Control Dependence Graph：

  * SSA form 的构建算法：课程讲授中忽略了部分算法的正确性证明，本篇论文的讨论补齐了两个重要的证明
    * Join(A) = DF(A)，因为从 SSA 的定义上看，所有需要插入 phi 函数的位置是所有赋值节点和它们的交汇节点构成的闭包，论文中证明了：当赋值节点包括流图入口时，所有赋值节点和它们的控制边界构成的闭包等价于赋值节点和它们的交汇节点构成的闭包。因此找出所有 phi 函数插入位置的问题转化为找到控制边界的闭包。
    * 先序遍历支配树，基于栈的重命名算法的正确性：插入 phi 节点，重命名后的程序显然是 SSA form，但我们要说明该程序与源程序是等价的，即源程序的中每一处对变量 V 的使用时的值与新程序中对应 Vi 的值是相同的。

  * 隐式赋值的问题：论文中谈到一些 IR 指令可能隐式地修改某些变量的值，如果在构建 SSA form 时没有考虑到这些被隐式修改的变量，会导致 SSA form 与原 IR 语义不等价。LLVM 的 IR 形式中也存在这个问题，最典型的可能隐式修改变量的 IR 指令便是 call 指令，子程序可能会修改全局变量，或者传入的参数指针指向的变量。LLVM 中解决这问题的方式是，**所有可能被隐式修改的变量，都不能被 mem2reg promotion 为寄存器形式的变量，相反，我们将这个变量的地址 promotion 为寄存器形式，而这个变量本身以内存形式存在，每次使用这个变量时，对它的地址使用 load 指令，将其 load 到寄存器中（这里的要义在于变量的地址是常量）。隐式修改的变量包括：被取地址的变量，全局变量，数组。这些变量都不会被 mem2reg promotion 到寄存器中，由此来保证 mem2reg 构建的 SSA form 中的寄存器变量都不会被隐式修改**（而被修改的内存并不在 SSA form 的考虑范围之内，会用额外的优化 pass 例如 gvn，来消除多余的内存操作）。**TODO: see mem2reg source code**

* The program dependence graph and its use in optimization

  * 循环在 control dependence graph 中会使得 header 可能控制依赖于 latch，使得控制依赖图上产生圈。这个结果直观上有点意外，因为 latch 执行时 header 必然已经执行过了。**直观上，我认为可以把 control dependence graph 中的边分为两类，一类是前向边（即该边的条件满足后某基本块就会执行），一类是回边（该边条件对应 loop 的回边条件，条件满足时循环继续执行）。例如在 vegen 的代码中，显式地区分了这两类，回边条件`LoopBackEdgeCond`单独保存，用来在数据流重建时重建循环（指令调度时让 header 不依赖于 latch，否则循环依赖，无限递归了）。另外一个可能的误区是，`cond1 or cond2 ...`为真时基本块就会执行，其中 `cond` 是各个控制依赖的跳转条件。这有问题，因为各个控制依赖对应的基本块也有它的执行条件，因此确保一个基本块一定执行的布尔表达式需要递归计算**。

* LLVM Pass

  * gvn：部分冗余消除，消除多余的 load 指令
  * dse: 在一个基本块内进行优化，消除多余的 store 指令