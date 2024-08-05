---
title: SystemVerilog Notes
date: 2023-11-01 21:54:39 +0800
categories: [IC]
---

## SystemVerilog

* 对信号的赋值都在一个 block 里
* 只能对最后一维进行切片
* Scheduling semantics（非阻塞赋值在最后完成，就是那个 active 的三个区，第一个区进行计算需要赋值的结果，如果是阻塞赋值，同时就把结果赋给 LHS 了，但如果是非阻塞赋值，就会在第三个区才进行赋值。那么当时钟上升 trigger 时序逻辑时，只要我们在时序逻辑中都使用非阻塞赋值，那么就会在所有的时序逻辑的 RHS 完成后才进行赋值，进一步 trigger 组合逻辑，这避免了 时序 trigger 组合，组合的阻塞赋值修改信号，然后一个待调度的时序事件在计算 RHS 时依赖于该信号 这种冒险）
* SVA(systemverilog assertion)
* generate 语义 vs normal loop，genblk的来历(2012-systemverilog-standard chapter 27 和 https://electronics.stackexchange.com/questions/350078/question-about-synthesizable-for-loop-and-generate 中的解释)
* automatic 语义（chapter 6.21），
* **chapter 10.5 Variable declaration assignment  谈到下面的代码是初始化（在模拟器执行 initial begin 语句之前），而不是连续赋值（是不可综合的？），主要如何区分 net type 和 variable type**

```systemverilog
logic v = consta & constb; // variable with initialization
```

两种基本的握手方式：

* AXI-4形式：ready 可以依赖于 valid，valid 不依赖于 ready，valid 的一旦拉高，直到 ready 拉高后 valid 才能拉低。
* 反式：valid 可以依赖于 ready，ready 一旦拉高，直到 valid 拉高后 ready 才能拉低。



TODO: ~~load vstart 计算错误 and w of insn_proceed_addr 计算错误（vstart 没有 / 2）in lane_sequencer~~

TODO: ~~sim-depth-1 为什么在更早的地方卡死了~~   ---> acc_pnt 等加 1 的时候没有在等于缓冲区深度时归零，因此这实际上要求缓冲区深度为 2 的幂且大于 1，才能保证加 1 时自动归零。

~~**TODO：exp：vaddr地址计算，为啥 0x11的寄存器起始地址是0x100**~~

TODO: addrgen, acc 等接口中 error 改为 4bit

TODO：

* addrgen 修改记录：增加对 vaddr_o 接口，增加对 exception 处理，重命名 addrgen_idx_op_end 为 addrgen_end，所有操作现在都会最终到该状态，该状态拉高 ack_o，并输出 error info。另外，增加 error_vid_o.
* 同步修改 vlsu 接口
* load/store complete 信号的生成，以及 insn_done 信号的生成，当 load/store 指令在中途发生错误时
* 需要某种 flush 机制，当指令发生错误时，相应的 operand_requester等等停止请求，几类：index operand，store operand，mask：当 seuquencer 发现只剩最后的报错指令在运行，并且报错指令 vl 前的结果都成功提交后，拉高 flush 信号若干 cycle，将 operand_requester 和 operand_queue 中的 operand 请求都清理掉
* 如何修改 ara sequencer ？主要是 mask unit 如何处理比较好？

* 

