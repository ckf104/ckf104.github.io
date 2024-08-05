---
title: Gem5 Src Reading(3)
date: 2024-01-08 7:58:21 +0800
categories: [tools usage]
---

## ISA Parser related

## format

format 指定的输出分为四部分

* header output：该指令类的声明
* decoder output：指令类的成员函数实现，这些成员函数与指令执行无关，例如各个指令类的构造函数的实现
* decode block：当指令匹配成功时，`Decoder::decodeInst` 函数会执行这其中的代码，这部分代码需要返回对应的指令类
* exec output：指令类中与指令执行相关的成员函数的实现，包括 execute，initiateAcc，completeAcc，generateDisassembly 等

它们对应在四个文件中

* `decode-method.cc.inc`：实现了 `Decoder::decodeInst` 函数，将二进制指令翻译为一条 `StaticInst`
* ``decode-ns.hh.inc`：包含 header output
* `decode-ns.cc.inc`：包含 decoder output
* ``exec-ns.cc.inc`：包含 exec output

## operands

`def operands` 关键词定义了一个字典，字典的键是一个字符串，表示可以在 code 中可以使用的 operand，字典的值是一个 python 类，它是 `src/arch/isa_parser/operand_types.py` 中的 `Operand` 的子类。这个类包含了若干和该 operand 有关的信息，例如它的 `makeDecl` 函数表示在 `op_decl` 中如何声明该 `operand`，它其中也包含了该 operand 在指令中的编码位置，然后在指令类的构造函数中写入到 srcRegArray 或 dstRegArray 中。另外，operand 还包含 flags，每条指令的 flags 的来源有两种，一种是这条指令的 operand 包含的 flags，以及实例化 InstObjParams 类时提供的 opt_flags 参数。

* reg_idx_arr_decl：声明指令的 srcRegArray 和 dstRegArray
* constructor：包含指令类在 constructor 中通用的代码，例如将指令的 RegOperand 写入到 srcRegArray 和 dstRegArray 中，将指令包含的相应 flags 设置为 true 
* op_decl：声明指令执行时需要用到的 operand，
* op_rd：对 op_decl 中用到的 src operand  进行赋初值，例如指令为 `add x1, x2, x3`，那么 op_rd 就是读取寄存器 `x2`，`x3` 的值然后赋值给 op_decl 中声明的变量。
* op_wb：将 dst operand 的值写入到相应的寄存器中。

