---
title: Gem5 Src Reading(2)
date: 2023-12-24 7:58:21 +0800
categories: [tools usage]
---

## SEWorkloads

python 中，继承 SEWorkload 的子类需要实现 `_is_compatible_with` 方法，该方法接收一个 `ObjectFile` 对象，返回一个布尔值。该 `ObjectFile` 对象是 C++ 中的 `ObjectFile` 在 python 中的绑定，绑定的代码在`src/python/pybind11/object_file.cc` 中。

## BaseCPU

`BaseCPU` 中重要的属性

```python
workload = VectorParam.Process([], "processes to run")
mmu = Param.BaseMMU(NULL, "CPU memory management unit")
isa = VectorParam.BaseISA([], "ISA instance")
decoder = VectorParam.InstDecoder([], "Decoder instance")

icache_port = RequestPort("Instruction Port")
dcache_port = RequestPort("Data Port")
```

在 `RiscvCPU.py` 中

```python
class RiscvCPU:
    ArchDecoder = RiscvDecoder
    ArchMMU = RiscvMMU
    ArchInterrupts = RiscvInterrupts
    ArchISA = RiscvISA

class RiscvTimingSimpleCPU(BaseTimingSimpleCPU, RiscvCPU):
    mmu = RiscvMMU()
```

这里在 `RiscvCPU` 基类中定义了若干字段，但它们并没有直接放在 `RiscvTimingSimpleCPU` 中。在上一篇中讨论了，可以新创建一个子类来继承父类，然后设置默认参数。但实际上 `BaseCPU` 中并没有这些 `ArchISA` 这些参数，因此这些字段放到 `RiscvTimingSimpleCPU` 类中会引发异常（因为 `MetaSimObject` 在类对象创建时会进行检查）。在 BaseCPU 的源码中可以看到它已经假定了这四个字段的存在，因此我们可以认为 `ArchDecoder`，`ArchMMU`，`ArchInterrupts`，`ArchISA` 是类似 `BaseCPU` 的接口要求。

learning gem5 教程中的 `simple.py` 配置脚本中调用了 `BaseCPU.createThreads` 函数，该函数利用已经假定存在的`ArchDecoder` 和 `ArchISA`，设置好了 `isa`，`decoder` 字段。

从初始化中看到 system 类的一些作用

* getRequestorId 函数分配全局的 RequestorID，每个需要发起内存访问的 SimObject 都需要申请
  * 内部的 PhysicalMemory 类实例使用 mmap 申请模拟需要的物理内存，每个 ddr 类其实是 AbstractMemory 的子类，它们有一个指向 PhysicalMemory 申请的内存的指针（目前我看到的 system 类构造函数唯一的显著作用）
* 调用 SEWorkload::setSystem，SEWorkload 内部有一个 MemPool，它把 PhysicalMemory 内的地址范围都拿到，负责分配物理地址。在 Process::initState 函数中要把 ElfObject 对应的 MemoryImage 写入到物理内存中，它首先会调用 MMU 的地址翻译（使用 functional 接口进行翻译，该接口最后是调用 Process 中的 EmulationPageTable 类来进行翻译的），翻译失败后就会找 SEWorkload 分配物理内存，然后在 EmulationPageTable 中加入新的表项。

cpu 类的初始化

* ThreadContext 由 BaseCPU 的子类的构造函数进行创建（因为 ThreadContext 是一个只定义了接口的抽象基类），它对应 CPU 的一个线程
* 在 BaseCPU::init() 函数中，将子类创建的 ThreadContext 注册到 System 中。每个 ThreadContext 有 ContextID 和 ThreadID，前者由 system 统一分配，后者是在 CPU 上的线程编号。

process.initstate 根据 elf 文件内容初始化虚拟内存。

哪些地方有 PCStateBase？

* Fetch1ThreadInfo.pc，这个值只有在 branch 发生跳转时才会改变为跳转目标，并且传递到 ForwardLineData.pc 中。而实际取指的地址是 fetchAddr
* Fetch2ThreadInfo.pc，表示需要译码的指令的地址。Fetch2ThreadInfo.havePC 表示 pc 的值是否有效（当产生 branch 时 havePC 变为 false，此时 Fetch1ThreadInfo.pc 的值又变为有效，通过 ForwardLineData.pc 传递过来）。每次译码成功后 Fetch2ThreadInfo.pc->advancePC，并且通过 MinorDynInst 传递到下一级。值得注意的是 npc 的值的确定需要 decoder 的协助，因为只有 decoder 才知道 npc 应该对应 +2 还是 +4（对于变长指令集更是如此，这也是 advancePC 中是设置 pc = npc 而不是 pc + 4 这样），在 decoder->decode 函数中，会根据译码结果调整 npc 的值。
* DecodeThreadInfo.microopPC，主要用来跟踪 macroop 的 micropc，当遇到 macroop 时，microopPC 的值设置为 macroop.pc，然后将该 macroop 分解为 microop，递增 microopPC，传递给 microop.pc
* 然后我们最关心的 ThreadContext->PCState，它在每次指令提交时更新（跳转指令会修改 npc），因此它的值实际代表了 CPU 的 pc 值（即发生中断或异常时应该使用它的值），在指令提交前（执行后）与待提交指令的 pc 值比较即可知道该指令是否为跳转指令（因为跳转指令会修改 npc），然后据此产生 BranchData

minorCPU 的各个阶段

* fetch1：ITLB 翻译 + ICache 访问
* fetch2：Decode
* decode：将 macro 指令拆分为多条 micro 指令
* execute：evaluate 函数包含以下的内容
  * insn issue：execute 中有两个队列，inFlightInsts 和 inFUMemInsts，每条指令都会在前者中，访存类指令还会在后者中。issue 保证严格的 in order 发射，如果某一条指令因为没有 funcunit 满足发射条件，那么它后面的指令都不会发射。因此所有指令的顺序由 inFlightInsts 决定，内存相关的指令的顺序由 inFUMemInsts 决定。
  * Scoreboard 用来判断需要发射的指令是否满足依赖，Scoreboard 中估计指令完成的 returnCycle = opLatency + timing->extraCommitLat + timing->extraAssumedLat，当一条指令的每个源操作数对应的写指令都满足 returnCycle <= now + timing->srcRegsRelativeLats 时就可以发射。但实际上指令的 commit 时间是 opLatency + timing->extraCommitLat + timing->extraCommitDelayExpr，因此 returnCycle 只是一个估计。但只要我们保证指令的严格按序提交，就不会产生依赖错误。对于内存指令的 earlyIssue，额外使用 execSeqNum 来记录最大的依赖，合理吗？
  * advance func pipeline，这个没什么好说的
  * commit：
    * 提交指令的选择：默认选择 inFlightInsts 队列中的第一条指令，这保证 in-order 提交，但如果 inFUMemInsts 非空，且第一条结束 func pipeline 的指令激活了 earlyissue，并满足 execSeqNum 依赖，那么提交该条指令（因此 minorCPU 中存在乱序提交）。
    * 提交指令的执行：对于非内存的指令，执行它的 execute 函数即可。而内存相关指令的处理比较复杂，我们可以先考虑一个简单的模型，然后逐步地将其复杂化，来接近 minorCPU 中的实现。由于每条内存指令都有地址翻译，访存两个阶段。因此 LSQ 中有 requests 和 transfers 两个队列，前者表明指令地址翻译完成，但还未开始访存（这里我们考虑的是 SE mode，地址翻译总是瞬间完成），后者表明指令处于访存阶段。在这个简单模型中，LSQ.step 函数每次调用 tryToSendToTransfers 尝试取出 requests 队列中的第一条指令进行访存，如果成功，就把该指令移动到 transfers 队列中。指令访存完成后，回调函数会把指令从 transfers 队列中删除，并将指令标记为完成。minorCPU 有一些额外的东西，首先是引入了 storebuffer，对于 store 指令，从 transfers 队列中删除不代表指令完成，而是表示指令进入了 storebuffer，不过 minorCPU 的角度确实认为 storebuffer 中的指令已经完成了（会将其从 inFlightInsts 和 inFUMemInsts 中删除）。为了满足依赖顺序，这需要引入额外的 store value forward，即 load 指令进行访存前需要先检查 storebuffer 中是否有地址与 load 的地址有重叠。再者，storebuffer 中的 store 数据都是发送到 cache 中，但是有些 store 指令是 uncacheable 的（原子指令，条件存储指令等），因此这些指令不会送到 storebuffer 中，而是和 load 指令一起待着 transfers 队列中。然后就是 minorCPU 如何和 LSQ 互动，从 minorCPU 的角度看，内存指令的提交分为两阶段，一阶段调用 staticinst->initiateAcc 来进行内存指令的地址翻译，并压入 LSQ.requests 或者 LSQ.transfers，此时将内存指令从 inFUMemInsts 中删除。二阶段调用 staticinst->completeAcc 来结束内存指令，然后将其从 inFlightInsts 中删除，同时清除 scoreboard 中记录的该指令的读写效果（此时从 minorCPU 的角度看已经完成了该指令）。实际从 LSQ 的角度看，内存指令的二阶段完成时是 cacheable 的 store 指令被压入 storebuffer，或者 uncacheable 的 store 指令访存完成或者 load 指令访存完成

system 的 system_port 拿来干嘛？

目前不清楚的结构体

```c++
class SEWorkload;
class system->threads[contextIds[0]]; // system 下都有些啥
class ThreadContext;  // Process 用 elf 文件初始化内存时调用了这个类的 sendFunctional 函数（其实就是调用 它所在 cpu 的 data port 的 sendFunctional 函数），然后虚拟地址到物理地址的翻译也调用了这个类下的 mmu
class SimpleThread: public ThreadState, public ThreadContext;

class EmulationPageTable; // 每个 process 中有一个，用于
class MemoryImage;  // 一个 memory segment 列表，表达 ElfObject 在虚拟内存中的排布

class ElfObjectFormat: public ObjectFileFormat; // 根据文件，创造出 ObjectFile 对象，针对这种格式，其实是 ElfObject
class ElfObject: public ObjectFile; // 包含 elf 文件的各种信息，包含一个 MemoryImage 对象和 interpreter 指针
class SymbolTable;  // 包含在 ElfObject 中，elf 文件的符号表

class PCState; // 在 RISCV ISA 中，有 pc, next pc(npc), upc, nupc, compressed 这几个字段，表达 pc 状态
class Fault; // 表达指令异常
```

TODO：

* 在 mmu 的 translatingFunctional 中，页表表项是存放在 Process 的 EmulationPageTable 中，这和 tlb 表项是否存在一致性问题？
* 为什么 simple-riscv 例子中没有连接 walkerPorts
* ~~MinorCPU 的 fetch1FetchLimit 参数默认是 1，是指最多只能有一条指令在跑吗？~~（是指最多取一行，如果一行取完了，下个 stage 还没处理完这一行，不要接着取下一行）

* Scoreboard 以及 execute 阶段的 evaluation，尤其关心 memory 相关的。以及，minor cpu 是按序提交吗，中断和异常是如何处理的
* ~~在 MinorCPU 执行中，thread->pcState 是如何变化的？~~（每提交一条指令就 advancePC）

## RVV related

虽然 VL，Vtype 寄存器名义上划分到 miscRegClass，但实际上它的值在 PCState 中，这意味着 vset 系列的指令会改变 PCState，即会被 minorCPU 认为发生跳转，flush 掉后续指令。

两个关心的问题

* ~~写 CSR 会 flush 后续指令吗~~，目前看起来不会，只要写的 CSR 不影响 PCState
* ~~ExtMachInst 什么时候读取 vl，vtype 这两个寄存器~~，并且目前并不支持 vstart ？（会在 `Decoder::decode` 函数中读取指令 PCState 对应的 vl，vtype 值，写入到 ExtMachInst 中）
