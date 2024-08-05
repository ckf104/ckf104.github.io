## Pymtl

* operator:
  * non-blocking assignment:  <<=
  * blocking assignment: @=
  * continuous assignment: //=
* clock, reset
  * multiple clock / reset ?
  * trigger edge ?
  * async reset ? TODO 测试 chisel 的 async reset
  * pymtl 可以通过 no_synthesis_no_clk，no_synthesis_no_reset 来控制是否生成 clk 和 reset 信号，**renaming clk and reset?（用于blackbox）**
  * 从 `VBehavioralTranslatorL1.py` 中的 `visit_SeqUpblk` 函数看，应该只有上升沿的 clk，和同步的 reset，以及在 `Component.py` 中，调用的 `_construct` 将父节点的 clk 和 reset 传给子节点，看起来只有一个全局时钟
  * pymtl 通过 ast 模块分析 comb 或者 ff block 的 python 语法树，来将其转换为 verilog，这是否不利于参数化？
* Modeling level，in https://www.csl.cornell.edu/courses/ece5745/handouts/ece5745-tut3-pymtl.pdf，讨论了 FL, CL, RTL 三种模拟

## Comopy

* **设计目标：写的每一行 comopy，能够知道翻译成 systemverilog 是长啥样的**
* 对 HDL 逻辑使用装饰器 `build` 和 `comb`，使得 `MethodRegistry` 中包含了模块名，类名，方法名的映射
* `Module` 继承自 `TaggedMethodClass` 和 `CircuitObject`
  * `CircuitObject` 好理解，每个硬件元素都会继承这个

  * `TaggedMethodClass` 为自己的子类提供了一种方法，来建立一个 (tag, method) 字典，`Module` 子类用这个方法来收集所有的 HDL 逻辑块。在调用 `init_tagged_methods` 后，所有 `cls` 的子类 `_tagged_methods` 域都拿到了自己所有的 HDL 块，而 `_bound_methods` 则不仅包含自己的逻辑块，还包含自己所有子类的逻辑块（根据名字去重）
* `AssemblyHDL` 是第一个 Pass，它将 `Module` 转化为 `CircuitNode`，可以将 `CircuitNode` 理解为第一级的 IR，它用 `owner`，`level`，`elements` 等字段表达了模块间的层级关系。
* `GenerateIR` 是第二个 Pass，它由 `StructurePass`，`BehaviorPass`，`TypePass`，`DependencePass` 四个子 pass 组成
  * 第一个 `StructurePass` 将 comopy 的信号转换到 asdl 语言定义的 IR 类型上。在这个 IR 类型中，最上层的是 `Module`，然后基本的信号类型为 `Port` 和 `Logic`。每个 `Module` 的 `_info` 字段是 `ModuleInfo`，`ModuleInfo.symbols` 包含了该模块所有的信号和子模块
  * 第二个 `BehaviorPass` 对 `conn_blocks` 和 `comb_blocks` 进行语法分析得到 asdl IR 中的 `Connect` 和 `CombBlock`，现在整个 comopy 类型都转到 asdl IR 上了，`NetInfo.inst_node` 表示该节点对应的信号，例如某个 `Logic` 等等
  *  第三个 `TypePass` 做类型推断和类型检查，还有其它的语法检查，例如一种典型的检查是 `a + b /= c`，assign 的左值不能有运算，然后 slice 的越界检查等等
  * 第四个 `DependencePass` 做依赖分析，判断每个 `CombBlock` 和 `Connect` 读写了哪些信号，方便后面做调度
* 第三个 Pass 可能是 `SchedulePass`，它由 `SetupPass`，`SchedulePass` 和 `CheckPass` 组成，最主要的是 `SchedulePass`，根据 `Depdence` 对 `Connect` 和 `CombBlock` 做拓扑排序
* 如果是翻译到 SystemVerilog 上，那么第三个 Pass  是 `TranslateVerilog`，这个 Pass 遍历 `IR.Module`，使用 jinja 模板将 asdl IR 翻译为 Systemverilog

* comopy 类型系统
  * 最上层的是 `BitsData`，它重载了许多逻辑运算符，并提供了抽象的接口 `data`，`nbits`，`immutable`，它代表了有固定位宽的数据
  * `bits` 类型继承自 `BitsData`，实现了上面的三个抽象接口，`nbits` 用来表示位宽，`_uint` 来表示信号的无符号值。代表了实际的数据值。而 `bitsK` 是继承自 `bits` 的动态创建的类型，其中 `K` 是位宽
  * **`Connectable` 类型继承自 `BitsData`**，表示硬件中的信号。它的 `_data` 域是 `bits` 类型，代表信号实际的值
  * `SignalBundle` 作为 `Cat` 函数的返回值，它继承自 `Connectable`，代表了对若干 `BitsData` 的引用。注意它不是一个独立的数据结构体，而是一个引用，对 `SignalBundle` 的赋值都会反馈到它引用的 `BisData` 中

* `bits` 中的 `_immutable` 是拿来干嘛的，`_next` 是拿来干嘛的
* TODO：slice，cat
* immutable 是用在哪的

## Review

* `ParseFunction.py` 的 `visit_Constant` 函数直接返回常量值，而没有包裹为 BaseIR
* 为什么需要 `_data_dry_run`
* 为什么 `SignalSlice` 的 `_key` 是 any 类型
* ~~什么时候会有 mutable 的 bits？~~，做一些运算测试检查什么的有用
* 按照声明顺序调用 `build` 的函数会不会好些
* 检查 logic 被多个信号驱动？
* 为啥有些 IR 模块由 asdl 生成，有些 IR 定义又是手写的
* `_has_overlapped_parts` 函数需要注释
* `DependencePass` 里为啥读写依赖是用信号名字来表示，而不是信号本身
* dataclass 中全部采用命名参数的初始化
* `SetupPass.py` 的 `install_sim_eval_comb` 函数，为什么要检查 `node._info.module_node == ir_root`，是目前假定了没有子模块吗
* ~~`SchedulePass.py` 在调度时，为啥要临时生成一个 `graph_root`~~：`graph_root` 是一个假想的外部模块，没有输入并提供了 top port input，只是为了拓扑排序和后面检查的时候方便
* 区分内部异常和用户错误导致的异常，例如 `CheckPass.py` 中抛出的异常应该认为是内部异常
* `BlockInfo.Symbol` 是拿来干嘛的，看起来一直为空
* `Signal.py` 的 `data_driven` 函数中，设置 `data_driven` 的类型为 int 会不会更好一点？看起来 `data_driven` 是一个 mask 的感觉，只是用来表示该信号的 bits 有没有被连续赋值 driven
* 把 IRStage 放到 Simulation 里好吗？因为 Simulation 的 block 中可以使用许多不可综合的代码
* `ParseFunction.py` 中 `visit_Subscript` 函数对 `Cat(...)[:]` 做了特殊判断，要求 `start == 0`，为什么？如果 `Cat(...)[:]` 在等号右边呢
* 目前连续赋值的实现感觉过于复杂了？目前的做法是通过反射获取到调用 `@=` 的 `inspect.Frameinfo`，然后根据 `inspect.Frameinfo` 获取到调用 `@=` 的函数对象，然后进一步拿到该函数的源码。由于 `inspect.Frameinfo` 中包含 `@=` 的行号，与函数源码的行号对比就可以拿到 `@=` 处的语法树和源码，然后将 `@=` 替换为 `/=`，创建一个 `ConnectBlock`，放置到 `CircuitNode._conn_blocks` 中。不支持一行多个 `@=` 也是为了避免行号判断时发生混淆
* 是否需要 `bitsK` 类型

## Execution

* 尽可能早的知道用户要模拟还是翻译？

* 简单情况，不考虑 Slice 和 Bundle 时

  * 在 `BehaviorPass` 中执行所有 comb 块

  * `data_driven` 表示一颗 asdl IR 的语法树，表示了该信号的值如何产生

  * `BisData` 重载 `__and__` 等运算符

  ```python
  def __and__(self, other: BitsData) -> Bits:
      if context == verilog and others is Connectable or self is Connectable:
          return Signal(data_driven=BinOp(left=self, op=BitAnd, right=other), Immutable=True)
      return self.data & other # constant folding
  
  def __getitem__(self, key) -> Bits:
      if context == verilog and others is Connectable or self is Connectable:
          if key is Constant:
              Signal(data_driven=Index(value=self, idx=key))
          elif key is Slice:
              Signal(data_driven=Slice(value=self, start=..., stop=...))
          raise error?
      return self.data & other # constant folding
  
  def cat(*parts: BitsData) -> SignalBundle:
      return SignalBundle(*parts, data_driven=Catenate(parts=parts.data_driven))
  
  def __itruediv__(self, value: BitsData | int) -> Bits:
      stmtStack.getActive().append(Assign(target=self.data_driven, value=value.data_driven, blocking=True))
  ```

* If else 的实现

  * 能否与 python 使用同一套 if else？我感觉不行

  ```python
  if e == 0:
      a /= b
  else:
      c /= d
  # how to execute both?
  ```

  * 使用一套自己的 if else？如何在模拟时跳过分支执行？[python-goto](https://github.com/snoack/python-goto)

  ```python
  myif( e == 0 );
  a /= b;
  myelse();
  c /= d;
  ```

  * 不追求直接执行 comb 块，而是用虚拟机模拟，毕竟都有 IR 了

* for 循环：

  * 在 verilog 中不产生 for 循环

  * 能否使用 python 的 for 循环？需要额外的标记符告知这行代码处于 for 循环中？或者是通过反射获得？

  ```python
  #ForLoopContext();
  for i in range(10):
      a[i] /= b1(1)
  ```

  * 使用自己的 for 循环？类似使用 python-goto 的方法？

  ```python
  myloop(i for i in range(10));
  a[i] /= b1(1);
  endmyloop();
  ```

  

  

