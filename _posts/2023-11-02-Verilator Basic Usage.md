---
title: Verilator Basic Usage
date: 2023-11-02 21:54:39 +0800
categories: [tools usage]
---

## Verilator 使用

```shell
verilator -Wall -Wno-fatal --cc --exe --build test_top.sv test_top.cpp
```

解释：`-Wall` 启用所有类型的 warnings，`-Wno-fatal` 表示检测到 warnings 不要终止 verilator（默认情况下会报错退出）。`--cc` 使用 C++ 作为输出语言。`--build` 表示当 verilator 将 systemverilog 翻译为 C++ 后马上编译生成相应的库，如果有额外的 `--exe` 则还会链接生成可执行文件。

* `--main` 会自动生成一个不驱动任何信号的带 main 函数的 cpp 文件，可以用这个文件作为接下来修改的基础。

* 使用 thread context -> timeInc(1) 函数去递增当前模拟的时间，verilog 中的 \$time 函数会回调这个，但小心这里加的是 time precision，如果 time unit 是 time precision 的 100 倍的话，timeInc(100) 才表示过了 1 个 cycle。verilator 默认的 timescale 是 1ps / 1ps
* --trace-fst 相比于 --trace，前者生成 fst 格式的 waveform，后者生成 vcd 格式的，但前者是二进制，体积更小，**而且枚举类型保留了枚举名（而不是像 vcd 格式中显示一串数字），不知道 vcd 中如何做到这一点**。启用 --trace-structs 使得波形图中保留结构体信息
* error: cannot convert ‘Vaddrgen_mmu_tb_addrgen_mmu_tb__DOT__axi_rw_data__struct263’ to ‘IData’ --> 使用 packed struct，对 packed 和 unpacked 进行一些阐述，https://www.amiq.com/consulting/2019/01/30/how-to-call-c-functions-from-systemverilog-using-dpi-c/
* verilator 会在 obj_dir 中生成 Makefile，默认也是用 Makefile 来控制编译过程。为了加速翻译和编译过程，`-j N`参数开启多线程（包括翻译和编译两个过程），直接连着写 `-j4` 这样 verilator 不能识别 。
* DPI的简单使用：systemverilog 的 structure 前面的字段在高位字节，与 C 语言的 structure 正好相反。因此使用 DPI 传输 structure 信号时需要注意结构体字段反向排列。见 https://github.com/verilator/verilator/issues/1191
* **! access signal after deasserting rst**
* `--Mdir` 设置输出目录
* --waiver-output`` *filename* ，来 disable warning（生成的文件是注释掉的，需要手动去掉注释）
* --assert 参数启用断言，verilator 支持简单的 SVA，要求断言语句在一个周期内完成，不支持 sequence 关键字。verilator 简单地将断言语句转换为 if (..) error 的形式，断言失败后模拟马上结束，因此也不支持 concurrent assertion 的 action block。
* `/*verilator public*/` 可以用来暴露 design 中的一些信息给 c++ 接口，除了文档中描述的暴露 signal，还可以暴露 parameter，enum 等，不过 struct 目前貌似还不支持。见 https://github.com/verilator/verilator/issues/860
* VerilatedContext 需要在 VTop 之后 delete （注意 C++ 规定了局部变量的析构顺序与构建顺序相反）
* verilator 对于 x value 的处理：verilator 内部对信号的表示并不包含 x value，但提供了一些命令行参数来控制 x value 如何转化为 0, 1。`--x-assign` 参数后有四个可选的值，`0`, `1`, `fast`, `unique`，默认情况下是 fast，前两者表示将所有的 x value 转化为 0 或 1，`fast` 表示由 verilator 决定。`unique` 表示将所有 x value 转化为同一个随机数。随机数种子由可以由运行时参数 `+verilator+seed+<value>` 决定，这同时要求 `+verilator+rand+reset+2`



## 方法论

1. 搭建调试，运行的环境
2. 明确整个项目的输入输出
3. 对项目运行的过程进行切分，从运行顺序上，或者从具体的模块的功能上能有一个大致的划分。对划分出的各个模块，我感兴趣的点在哪个模块，每个模块的输出输入输出又是怎样的？
4. 设计模式，看懂了不等于理解了（visit pattern, double dispatch）





* AstBasicDType, Packed Union / Struct, ~~AstDefImplicitDType~~ , ~~AstConstraintRefDType~~, ~~AstEmptyQueueDType~~, AstEnumDType, ~~AstStreamDType~~,  ~~AstVoidDType~~, AstPackArrayDType,

* verilator 对结构体的处理：结构体根据最终宽度的大小可能转化为 8bits, 16bits, 32bits, 64bits 整数或者 VlWide 类。结构体的低位 bit 对应整数的 LSB，

* TODO: 

  * 修改 bithelper 函数，没有必要按 byte 来处理
  * 写一篇关于 macro 的博客
  * 理解 c++ string literal
    * ~~s 后缀什么意思，这个像是 constexpr 的 string 的内存怎么分配？~~
    * 字符串加上 s 后缀有什么好处吗
    * ~~一些返回 std::string 的函数为什么会被标为 constexpr，例如 https://en.cppreference.com/w/cpp/string/basic_string/operator%22%22s~~
    * [user defined literals](https://en.cppreference.com/w/cpp/language/user_literal)

* 需要处理的临时变量

  * __v：返回值或者参数
  * __data_c：嵌套的结构体的参数或者返回值
  * __i：循环参数

* 没有被引用的`DType`会被 v3dead.cpp 删除掉

* 要做的核心事情是两件

  * 递归地给所有的 typedef 加上 public 标签（如果是给 DType 加上 public 标签的话，会破坏一些其它的逻辑，因为 typedef 没有标签的话会被误删，然后 DType 对应的 package 也会被删除）
  * 在删除 package 时将 structdtype 对应的 classpackage 指针置空
  * 在 export packed struct 时需要判断 typedef 是否有 public 吗？（加个测试就知道了，一个 public package 中包含非 public 的 struct）
  * 另外可以考虑的测试：hier block 中用到的 public packed struct，packed struct in class

* v3width 中会把 structdtype 从 typedef 子树中移到 typetable 中

* v3class 中会新建 classpackage 类，将 class 中的东西都移动 classpackage 中（例如变量，typedef ，函数，等等），而 v3dead 目前不会删除 dead class，因此 classpackage 也不会被删除

* 一些 systemverilog 概念在 verilator 中的实现

  * unpacked struct 会被翻译为 C++ struct 来进行模拟，因此无论如何 unpacked struct 都会被 export 出来（除非是 unused 被删除了）
  * class 会被翻译为 C++ class 来进行模拟，因此无论如何 class 都会被 export 出来（除非是 unused 被删除了）

* 在 `V3dead.cpp`中，如下修改会导致测试 `t_hier_block_struct.v`崩掉（emitcfunc说什么不能识别 typedef），为什么，需不需要最后测试中加入 -fno-inline 进行测试？（来表明模块中包含 typedef 也不会崩掉）s

  ```cpp
          if (auto* const structp = VN_CAST(typedefp->subDTypep(), NodeUOrStructDType)) {
              if (structp->user1()) return false;
              //if (structp->user1() && !structp->packed()) return false;
          }
  ```

* struct module 中存在的调用

  * struct 的 classOrPackagep 指针实际上目标存储的是该 struct 将来会被发射到哪个头文件中
  * inline 消除了其他module，因此简单情况下 packed struct 的modulep 指向 root，如果 struct 全局声明，则指向 unit

  * CUseVisitor pass  --> 这个主要用来向语法树中插入本模块需要的 forward declaration 和 include 头文件，在EmitCHeader pass 中输出头文件中使用
  * EmitCGatherDependencies pass --> 分析依赖，在输出 cpp 文件中时用这个 pass 的信息输出 cpp 文件的信息
  * EmitCHeader pass

* 在 package 中放置 unpacked struct ，package 和 unpacked struct 都没被删除

  * 在 pass17 deadmodule 中，refdtype 增加了 package 的计数
  * 后面在 pass23 wraptop 中，package 作为一个 cell 加入到 __024root 中，以后 cell 为 package 计数
  * 而为 package 计数的 cell 能不被删除是因为 cell 对应的 package 中非空，因为有这个 TYPEDEF，而 unpacked struct 中的 hacking 在于只要 TYPEDEF 对应的 struct 计数不为空，就不删除这个 TYPEDEF

* verilator 如何关闭部分的 warnings



op1: 

* 0: 0x40c2045
* 1: 0xffffbffe
* 2: 0x7fff



* 0: 0x40c2045
* 1: 0x48d159e
* 2: 0x7f80

