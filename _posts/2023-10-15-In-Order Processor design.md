---
title: In-Order Processor Design
date: 2023-10-15 21:44:33 +0800
categories: [IC]
---

参考 ethz 的 顺序流水线处理的设计框架（见 [Lecture 16](https://www.youtube.com/watch?v=4b9i2Ndxr7I&list=PL5Q2soXY2Zi97Ya5DEUpMpO2bbAoaG7c6&index=17review) 的 review 部分），大概有 decode and issue，execution，reorder buffer and commit 这些要素。

在 decode and issue 中，观察对应的 function unit 是否 ready，以及相应的冒险是否已经消除了。在 execution 中实际上可以乱序，因为不同指令的复杂度不同，可能后发射的指令会先完成，因此引入 reorder buffer 来顺序提交指令结果。

在顺序发射，顺序提交的处理器中不存在 WAW，WAR 冒险，~~但依然有寄存器重命名的用武之地。考虑如何实现 data forwarding：即将 reorder buffer 中的结果但如果需要支持 data forwarding，我们依然需要寄存器重命名的支持。寄存器重命名的本质在于跟踪 RAW 依赖，即~~，

**~~疑问：寄存器重命名的本质是什么，OOO 处理器是否需要重命名？寄存器重命名是否需要增加物理寄存器的数量？**~~

~~目前的观点：寄存器重命名本质是为追踪 RAW 依赖，使得该指令知道它需要的操作数从前面的哪个指令来，而不受限制于用 ISA 规定的寄存器 ID 数量来追踪 RAW。寄存器重命名会增加物理寄存器的数量，但不一定需要显式指定出来，因为指令完成后，提交前，一定需要将结果保存在某处，这个保存的地方就是我们说的物理寄存器（所以这本质上是一个设计上的 tradeoff，要把结果保存在 rob 中，或者乱序执行的保留站中，亦或者设计出物理的寄存器堆--future register file）。在 cva6 中，就是 reorder buffer 中。**TODO：看看 mips R10000 中寄存器重命名的逻辑**~~

在 [Lecture 16](https://www.youtube.com/watch?v=4b9i2Ndxr7I&list=PL5Q2soXY2Zi97Ya5DEUpMpO2bbAoaG7c6&index=17) 的最后，课程阐述了 OoO 处理器的一个问题是 value 会大量复制（在 regfile，reservation，ROB 中）。因此现在的 OoO 处理器采取的做法是

* 设计一个很大的物理寄存器堆
* 在 rename table 中保留指针，指向物理寄存器堆的表项（指针需要的位数），同样，对于 ISA 层面体现的 regfile，也是指向物理寄存器堆的表项
* reservation station 中也是存储指向物理寄存器堆的指针，issue 时进行读取。

但这样的存储指针的设计又会重新导致 WAR，WAW 等等冒险（即需要考虑物理寄存器名称冲突等等）。在 mips R10000 中采取的做法是：维护额外的 free list，表明当前可用的物理寄存器。当第二次写该物理寄存器对应的逻辑寄存器的指令 retire 后，才将该物理寄存器加入到 free list（此时该物理寄存器的值不再需要，可以被重新分配了）。这样保证了物理寄存器值的稳定性，从而消除 RAW, WAW 冒险。**就是说，物理寄存器作为一种资源，在重命名时也需要一定的分配策略，才能合理地解决 WAR，WAW 冒险（例如这里说的 free list）** 

下面主要记录 cva6 中是如何对上述的要素进行实现的。

## Issue Module

* issue 模块的第一部分是 re_name 子模块，负责对寄存器进行重命名

* issue 模块中有一个 scoreboard 子模块，其中包含了 instruction buffer，buffer 中每个元素是 scoreboard entry。记录了已经发射，但尚未提交的指令的信息。然后有一个 commit pointer，指示按照顺序，下一条该 commit 的指令。因此该 buffer 实际充当了 reorder buffer 的作用。每条指令执行完成时，scoreboard 会收到相应的结果，然后写入 buffer 中该指令对应 entry 的相应字段，并置高该 entry 的 valid 的字段，表示该指令可以提交了（当然每周期提交的指令还是由 commit pointer 说了算）
* issue 模块中的 issue_read_operands 子模块则实际决定要不要发射 decoder 传来的指令（如果决定发射，该指令就会被写入到 scoreboard 中的 instruction buffer 中）。影响指令是否发射的因素：该指令相应的 function unit 是否 busy？该指令的所有 operand 是否已经准备就绪（已经提交在 regfile 中或 已在 instruction buffer 中或本周期正准备写入 instruction buffer）？instruction buffer 中是否有其他已发射指令与该指令写同一目的寄存器（这里杜绝 WAW 冒险的原因是，简化判断 operand 是否就绪的逻辑，保证 instruction buffer 中至多一个待写入目的寄存器的结果，不然还得根据buffer中指令的先后顺序选择后发射的）？

## Load/Store Unit

* store unit 中，在成功翻译 store 指令的地址后，便认为该指令执行完成（即可以提交了），并将其加入 store buffer，对应为 speculative 和 non-speculative 两个 fifo，speculative 中的 store 表示该指令还没有到 reorber buffer 的顶部（如果前面的指令发生了异常，就可能被 flush 掉，所以称为 speculative），一旦该 store 指令到达顶部，则说明该指令必定执行，直接从 ROB 中 retire，将其从 speculative fifo 中删除，并加入到 non-speculative fifo 中，该 fifo 中的 entry 向 cache 发起写请求。因此 store 指令在 tlb 命中时能很快 retire 。
* load unit 中 load 指令运行就很慢了，因为它一定需要等到数据传来时才能 retire。在有新的 load 指令进来时，除了翻译地址，还需要与 store buffer 中的地址进行比较，如果相同则需要 stall 直到该 store 指令将数据写入。如果翻译成功，并且与 store buffer 中没有地址碰撞，就可以向 dcache 请求数据了（因此 cva6 中存在 load/store 指令换序的情况）。dcache 数据来了之后，回到 idle，可以接收新的 load 指令。因此 in-flight 的 load 指令只有一条，虽然 in-flight 的 store 指令可以有很多。
* **cva6 中不处理错误的物理地址，因此直接忽略总线错误（是否符合 ISA ），这加速了 load / store 指令的执行效率（一旦地址翻译成功，就认为不再产生异常）。**

## CSR

* CSR 的读写指令的读写时间发生在指令位于 ROB 顶部时，并且如果指令有副作用的话（例如修改了 fcsr.frm），需要将整个 pipeline flush，然后重新从 commit.pc + 4 开始取指。这样避免了CSR指令带来的隐式依赖：例如读 fcsr.fflags 的 CSR 指令隐式依赖于前面的浮点运算指令，而后面浮点运算指令也隐式依赖于前面写 fcsr.fflags 的指令。
* Ara 中的向量浮点运算带来浮点异常也会影响到 fcsr.fflags，但 cva6 + ara 并没有做到精确的浮点异常（因为浮点向量指令 retire 太早了）

## Frontend && Branch Prediction

* 取指令节点并没有想象中那么简单，不一定能够快速完成。这里涉及到的逻辑包括：虚拟地址翻译（可能有tlb miss），从 cache 中取数据，再比较 tag 是否相等，然后 miss 的话又得到下一级去取，还有 next pc 预测等等。因此 cva6 中总共花了 3 个周期来完成取指操作。
* 通常的处理器设计课程中讲 btb，2bit predictor 等分支预测技术时，是直接使用当前 pc 值来预测 next pc，预测时没有使用当前 pc 的对应的指令值。这通常是因为取指没法在一个周期内完成，等取出指令时再进行预测已经太晚了。**但是 cva6 确实是这样做的，即在取出的指令后再进行预测。由于 cva6 从 cache 中取出指令最少也需要两个周期（cache, tlb hit），因此这种指令预测在指令预测成功并且发生跳转时也会损失一个周期**。
  * 周期 0 的逻辑包括：从当前 pc 寄存器中，和两级流水线后的预测 pc 值中选择一个 pc 值，向 icache 发起请求，在同一周期，icache 收到请求后向内部的 sram 发起读操作（这里用到了 csapp 讲的技巧，因为虚拟地址和物理地址的低 12 位是相同的，因此如果 cache 的 index 宽度 + offset 宽度不超过 12 位，可以直接用虚拟地址访问 sram），另外，在 cva6 中，sram 的读有一个周期时延。
  * 周期 1 的逻辑包括：icache 在此时向 tlb 发起翻译请求，tlb 翻译是完全的组合逻辑，因此如果 tlb 命中，在同一周期 icache 会收到 tlb 返回的物理地址，icache 使用该地址进行 tag 比较，如果对比成功，将指令数据返回给 frontend。frontend 会将该指令数据写入流水线寄存器。
  * 周期 2 的逻辑包括：从寄存器中拿到指令数据，首先进行指令的对齐（主要是压缩指令带来的问题，有可能取出的 32 bits 数据的前 16 位其实是上一条指令的高 16 bits）。然后对指令进行初步的译码，主要是为了判断是否为 branch 指令，然后进行分支判断，pc 预测，并将预测的 pc 值发送到周期 0 的逻辑中。最后将指令写入 fifo。在下一个周期该指令从 fifo 中被取出，就进入译码阶段了。
* 在 cva6 中使用的分支预测技术包括 btb，2bit predictor, ras。如果该指令是直接跳转，且使用 pc + 立即数进行偏移，那么在周期 2 会直接计算出跳转地址，作为预测的 pc 值。如果指令是使用寄存器偏移跳转，那么周期 2 会使用 btb 中的对应表项（该指令对应的 pc 值进行索引）作为预测 pc 值，但如果判定该跳转是一条 ret，则使用 ras 预测 pc 值。如果指令是比较后跳转，那么会使用该指令对应的 pc 值进行索引得到的 2bit predictor 预测是否跳转，如果预测跳转，会直接计算出跳转地址，并作为预测的 pc 值。
* 可以看到，预测的 pc 值最早也得在两个周期后才能到达，由于 frontend 默认情况下 nextpc = pc  + 4，因此如果预测的结果是发生跳转逻辑，也需要 flush 掉周期 1 从 icache 返回的指令数据（即代码中的 `kill_s2 = 1`）。
* 另外，如果周期 2 写入的 fifo 满且还有新的指令尝试写入的话（因为周期 0 的发起请求和周期 2 的写入 fifo 存在时序差，即使在 fifo 满时停止请求指令也无法保证 fifo 不会溢出），flush 周期 0，1 的流水线，重新进行取指（`kill_s1 = 1, kill_s2 = 1`），代码中称其为 replay。
* 周期 3 译码，周期 4 发射指令，在周期 5 时指令进入 alu，branch_unit 这些功能单元，在这些功能单元的组合逻辑结束后才知道分支预测是否正确，生成对应的 `resolved_branch`，如果分支预测错误，在同一周期拉高 flush 信号，刷新取指，译码，发射阶段共 5 个周期的流水线。并对 btb，2bit predictor 进行更新。**能够如此简单地刷新流水线得益于 cva6 是顺序发射的，并且 branch 指令的执阶段只有一个周期，因此由预测错误而取出的指令此时都还未发射。但对于 OoO 处理器来说，部分在 branch 指令后的指令可能先发射，甚至先执行完成，boom 中是如何处理这个问题的？**



## MV 指令实现

在 riscv spec 的第 24 章，谈到了目前 riscv 大体的编码规则，我们使用 custom-0（7'b00_010_11） 作为目前指令拓展的 opcode

mv 指令编码：类似于 ADD 指令的编码方式 

func7                                 rs2           rs1                   func3               rd                 opcode

0000000                          rs2            rs1                  000                  rd                  0001011         custmv v1,  r1 向量->标量

0000000                          rs2            rs1                  001                   rd                 0001011         custmv r1, v1  标量->向量

0000001                          rs2            rs1                  000                   rd                 0001011          vadd2

0000010                          rs2            rs1                  000                   rd                 0001011          NV12toCAG444

0000011                          rs2            rs1                  000                   rd                 0001011          CAG444toRGB888

对于向量到标量的 mv 指令，rs1 指定访问的向量寄存器，rs2 指定访问该向量寄存器的第几个 word

对于标量到向量的 mv 指令，rd 指定访问的向量寄存器，rs2 指定访问该向量寄存器的第几个 word

这样 10 位索引最多支持长度为 2048bits 的向量寄存器

首先实现一条从标量寄存器堆搬运到向量寄存器堆的指令

