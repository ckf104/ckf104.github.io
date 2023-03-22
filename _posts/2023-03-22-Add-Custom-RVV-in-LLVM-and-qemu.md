---
title: Add Custom RVV in LLVM And QEMU
date: 2023-03-22 11:45:31 +800
categories: [Architecture]
---

本文记录一下在LLVM和qemu中添加一条自定义的RISCV的V指令的过程

## 1. Overview

我们添加的指令为`vaddsub`，语义是偶数位的标量数据做加法，而奇数位的标量数据做减法。依据V拓展的编码规则，该指令有三种变体`vaddsub.vv`, `vaddsub.vx`, `vaddsub.vi`, **func6**位域的编码设计为`0b000001`。

在LLVM中，我们需要增加一条新的该V指令对应的伪指令，以及相应的**RVV Intrinsic**, 然后增加**pattern match**规则，将该**Intrinsic** lower为对应的伪指令即可。

在qemu中，我们需要在[decodetree](https://qemu.readthedocs.io/en/latest/devel/decodetree.html)中增加新指令的定义，然后在[TCG](https://www.qemu.org/docs/master/devel/tcg-ops.html)的前端增加相应的`trans_*`函数来解释该指令的含义。

## 2. LLVM

LLVM中对应的改动如下

```diff
diff --git a/llvm/include/llvm/IR/IntrinsicsRISCV.td b/llvm/include/llvm/IR/IntrinsicsRISCV.td
index b140cdbe6437..a7a789edd04f 100644
--- a/llvm/include/llvm/IR/IntrinsicsRISCV.td
+++ b/llvm/include/llvm/IR/IntrinsicsRISCV.td
@@ -1147,6 +1147,7 @@ let TargetPrefix = "riscv" in {
   defm vadd : RISCVBinaryAAX;
   defm vsub : RISCVBinaryAAX;
   defm vrsub : RISCVBinaryAAX;
+  defm vaddsub : RISCVBinaryAAX;

   defm vwaddu : RISCVBinaryABX;
   defm vwadd : RISCVBinaryABX;
diff --git a/llvm/lib/Target/RISCV/RISCVInstrInfoV.td b/llvm/lib/Target/RISCV/RISCVInstrInfoV.td
index d1d436bdd12f..9bffcbf8d164 100644
--- a/llvm/lib/Target/RISCV/RISCVInstrInfoV.td
+++ b/llvm/lib/Target/RISCV/RISCVInstrInfoV.td
@@ -1069,6 +1069,7 @@ let Predicates = [HasVInstructions] in {
 defm VADD_V : VALU_IV_V_X_I<"vadd", 0b000000>;
 defm VSUB_V : VALU_IV_V_X<"vsub", 0b000010>;
 defm VRSUB_V : VALU_IV_X_I<"vrsub", 0b000011>;
+defm VADDSUB_V : VALU_IV_V_X_I<"vaddsub", 0b000001>;
 
 def : InstAlias<"vneg.v $vd, $vs$vm", (VRSUB_VX VR:$vd, VR:$vs, X0, VMaskOp:$vm)>;
 def : InstAlias<"vneg.v $vd, $vs", (VRSUB_VX VR:$vd, VR:$vs, X0, zero_reg)>;
diff --git a/llvm/lib/Target/RISCV/RISCVInstrInfoVPseudos.td b/llvm/lib/Target/RISCV/RISCVInstrInfoVPseudos.td
index 45ccbb7dd6ce..3baa8fef7165 100644
--- a/llvm/lib/Target/RISCV/RISCVInstrInfoVPseudos.td
+++ b/llvm/lib/Target/RISCV/RISCVInstrInfoVPseudos.td
@@ -5202,6 +5202,7 @@ defm PseudoVLSEG : VPseudoUSSegLoadFF;
 defm PseudoVADD   : VPseudoVALU_VV_VX_VI;
 defm PseudoVSUB   : VPseudoVALU_VV_VX;
 defm PseudoVRSUB  : VPseudoVALU_VX_VI;
+defm PseudoVADDSUB : VPseudoVALU_VV_VX_VI;
 
 foreach vti = AllIntegerVectors in {
   // Match vrsub with 2 vector operands to vsub.vv by swapping operands. This
@@ -5859,6 +5860,7 @@ let Predicates = [HasVInstructions] in {
 defm : VPatBinaryV_VV_VX_VI<"int_riscv_vadd", "PseudoVADD", AllIntegerVectors>;
 defm : VPatBinaryV_VV_VX<"int_riscv_vsub", "PseudoVSUB", AllIntegerVectors>;
 defm : VPatBinaryV_VX_VI<"int_riscv_vrsub", "PseudoVRSUB", AllIntegerVectors>;
+defm : VPatBinaryV_VV_VX_VI<"int_riscv_vaddsub", "PseudoVADDSUB", AllIntegerVectors>;
 
 //===----------------------------------------------------------------------===//
 // 11.2. Vector Widening Integer Add/Subtract
```

具体解释如下

```shell
defm vaddsub : RISCVBinaryAAX; # 增加新的Intrinsic

defm VADDSUB_V : VALU_IV_V_X_I<"vaddsub", 0b000001>;  # 增加新的V指令定义

defm PseudoVADDSUB : VPseudoVALU_VV_VX_VI;  # 增加新的伪指令，在基类RISCVVPseudo中将自动绑定上面定义的新的V指令

defm : VPatBinaryV_VV_VX_VI<"int_riscv_vaddsub", "PseudoVADDSUB", AllIntegerVectors>;
# 增加pattern match规则，在instruction selection阶段将Intrinsic lower到我们的伪指令上
```

## 3. qemu

首先我们在`target/riscv/insn32.decode`文件中增加如下指令编码定义

```
vaddsub_vv      000001 . ..... ..... 000 ..... 1010111 @r_vm
vaddsub_vx      000001 . ..... ..... 100 ..... 1010111 @r_vm
vaddsub_vi      000001 . ..... ..... 011 ..... 1010111 @r_vm
```

根据我粗浅的理解，qemu在进行动态翻译时，每遇到一条指令，就会调用该指令对应的`trans_xx`函数，`trans_xx`函数负责将该指令翻译为**TCG**的中间表示（具体可以参考代码中`trans_add`等函数的实现）。其中一种重要的翻译方法是利用`gen_helper_xx`接口。该方法把遇到的指令翻译为一条`call`指令，调用自己注册的函数来模拟对应指令的效果（参考`trans_vadd`函数的实现）。

我们也采用`gen_helper_xx`的方法来实现`vaddsub`函数的模拟，类比`vadd`的实现，在`target/riscv/helper.h`中注册helper函数，`DEF_HELPER_x`是qemu提供的辅助宏，`b, h, w, d`分别用来模拟`sew=8, 16, 32, 64`的情况

```
DEF_HELPER_6(vaddsub_vv_b, void, ptr, ptr, ptr, ptr, env, i32)
DEF_HELPER_6(vaddsub_vv_h, void, ptr, ptr, ptr, ptr, env, i32)
DEF_HELPER_6(vaddsub_vv_w, void, ptr, ptr, ptr, ptr, env, i32)
DEF_HELPER_6(vaddsub_vv_d, void, ptr, ptr, ptr, ptr, env, i32)

DEF_HELPER_6(vaddsub_vx_b, void, ptr, ptr, tl, ptr, env, i32)
DEF_HELPER_6(vaddsub_vx_h, void, ptr, ptr, tl, ptr, env, i32)
DEF_HELPER_6(vaddsub_vx_w, void, ptr, ptr, tl, ptr, env, i32)
DEF_HELPER_6(vaddsub_vx_d, void, ptr, ptr, tl, ptr, env, i32)
```

然后在`target/riscv/vector_helper.c`中定义我们刚刚注册的helper函数，`RVVCALL`, `GEN_VEXT_VV`都是qemu的辅助宏，我们模仿着`vadd`实现就可以了。

```
#define DO_ADDSUB(N, M) (i % 2 == 0 ? DO_ADD(N, M) : DO_SUB(N, M))

RVVCALL(OPIVV2, vaddsub_vv_b, OP_SSS_B, H1, H1, H1, DO_ADDSUB)
RVVCALL(OPIVV2, vaddsub_vv_h, OP_SSS_H, H2, H2, H2, DO_ADDSUB)
RVVCALL(OPIVV2, vaddsub_vv_w, OP_SSS_W, H4, H4, H4, DO_ADDSUB)
RVVCALL(OPIVV2, vaddsub_vv_d, OP_SSS_D, H8, H8, H8, DO_ADDSUB)

GEN_VEXT_VV(vaddsub_vv_b, 1)
GEN_VEXT_VV(vaddsub_vv_h, 2)
GEN_VEXT_VV(vaddsub_vv_w, 4)
GEN_VEXT_VV(vaddsub_vv_d, 8)

RVVCALL(OPIVX2, vaddsub_vx_b, OP_SSS_B, H1, H1, DO_ADDSUB)
RVVCALL(OPIVX2, vaddsub_vx_h, OP_SSS_H, H2, H2, DO_ADDSUB)
RVVCALL(OPIVX2, vaddsub_vx_w, OP_SSS_W, H4, H4, DO_ADDSUB)
RVVCALL(OPIVX2, vaddsub_vx_d, OP_SSS_D, H8, H8, DO_ADDSUB)

GEN_VEXT_VX(vaddsub_vx_b, 1)
GEN_VEXT_VX(vaddsub_vx_h, 2)
GEN_VEXT_VX(vaddsub_vx_w, 4)
GEN_VEXT_VX(vaddsub_vx_d, 8)
```

最后是在`target/riscv/insn_trans/trans_rvv.c.inc`中定义`trans_addsub_xx`函数，这里存在一个hack是我们向`do_opivx_gvec`传入了空指针。第三个参数的作用是在允许的情况下，将指令翻译为`TCG`对应的向量指令，因为`vaddsub`是一种NON-SIMD类型的指令，并不好直接翻译到`TCG`中的向量指令，我们就偷懒跳过这个优化了。**这导致我们需要修改`do_opivv_gvec`, `do_opivx_gvec`, `do_opivi_gvec`进行额外的空指针判断**

```c++
static bool trans_vaddsub_vx(DisasContext *s, arg_rmrr *a) {
    static gen_helper_opivx *const fns[4] = {
        gen_helper_vaddsub_vx_b,
        gen_helper_vaddsub_vx_h,
        gen_helper_vaddsub_vx_w,
        gen_helper_vaddsub_vx_d,
    };
    return do_opivx_gvec(s, a, NULL, fns[s->sew]);
}
static bool trans_vaddsub_vv(DisasContext *s, arg_rmrr *a) {
    static gen_helper_gvec_4_ptr *const fns[4] = {
        gen_helper_vaddsub_vv_b,
        gen_helper_vaddsub_vv_h,
        gen_helper_vaddsub_vv_w,
        gen_helper_vaddsub_vv_d,
    };
    return do_opivv_gvec(s, a, NULL, fns[s->sew]);
}
static bool trans_vaddsub_vi(DisasContext *s, arg_rmrr *a) {
    static gen_helper_opivx *const fns[4] = {
        gen_helper_vaddsub_vx_b,
        gen_helper_vaddsub_vx_h,
        gen_helper_vaddsub_vx_w,
        gen_helper_vaddsub_vx_d,
    };
    return do_opivi_gvec(s, a, NULL, fns[s->sew], IMM_SX);
}
```

OK，修改完成

## 4. Others

在修改LLVM后端时，在**pattern match**部分做了大幅度的简化。通常还会有根据`SDNode`的`Opcode`进行匹配的**pattern match**。而针对例如`vwaddu`这样的在**IR**中没有办法直接表示的指令，还应该有匹配指令序列`sext, sext, add`这样的**pattern match**，另外，我们也没有修改**clang**，因此只能在`IR Pass`中生成该`Intrinsic`去lower到汇编，而没有直接的**C**级别的 `Intrinsic`支持



## 5. Refs

* [qemu decodetree](https://qemu.readthedocs.io/en/latest/devel/decodetree.html)
* [TCG IR](https://www.qemu.org/docs/master/devel/tcg-ops.html)
* [White Paper on adding Custom RISC-V Instructions to QEMU](https://www.ashling.com/wp-content/uploads/QEMU_CUSTOM_INST_WP.pdf)

