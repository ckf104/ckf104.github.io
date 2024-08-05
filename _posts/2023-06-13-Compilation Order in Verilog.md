编译顺序影响宏定义

* https://stackoverflow.com/questions/40484990/scope-of-define-macros

verilog 和 systemverilog 在这点上有区别吗？vivado里面区分出了头文件，行为和第二个答案说得不太一样，但是iverilog的行为和第二个答案一致。



RVV ara：

* 5.a) Decoding  --> 修改CVA6的decoder，使其知道V指令
* 5.b) Interface --> CVA6的accelerator接口，将V指令移交到ara核，rsq, resp队列，握手协议
* 5.c) memory coherency -> CVA6 private L1 cache 调整为 write through，vector/scalar load/store 不重叠
* 5.d) mask unit --> cross lane 来获取 mask value

配置

* 原始：341973 （synth）
* L2NumWords = 2**12 -> 342015 (synth)
* L2NumWords = 2**12 with VLEN = 1024   -> 340795 (synth)

* L2NumWords = 2**12 with VLEN = 1024 with Lane = 2  -> 