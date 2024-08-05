* round robin的树形arbiter，每次折半处理信号，有的信号沿着树叶流向树根，有的沿着树根流向树叶，额外注意其lock属性，保证了一旦arbiter选择了某个master，在对应的slave的ready信号不拉高前arbiter不会改变其选择（遵循AXI4的valid信号规范）
* uboot中具体如何找kernel是用户的事，即用户指定uboot的bootcmd，在cva6-sdk中使用mmc指令将kernel加载到内存的指定位置，然后用bootm指令启动内核。设备树则选择嵌入在uboot中（CONFIG_DEFAULT_DEVICE_TREE="cv64a6_genesysII"，CONFIG_OF_EMBED=y）。
* 在cva6-sdk的configs目录下提供了buildroot，busybox，linux的默认配置，对于linux配置，选择embedded的initramfs（CONFIG_INITRAMFS_SOURCE=y）
* 修改了u-boot的默认配置（configs/openhwgroup_cv64a6_genesysII_defconfig），现在fw_payload.bin和uImage都在sd卡的第一个分区，第二个分区格式化为ext4文件系统

* cva6的fpga/ariane.cfg文件提供了在openocd中的配置。然后可以用gdb连接openocd，openocd连接fpga的jtag口进行调试。



* RISC-V的Mmode下默认是不使用satp来进行地址翻译的，但如果mstatus.mprv置1，load和store时的地址翻译情况取决于mstatus.mpp的mode值。见https://github.com/riscv/riscv-isa-manual/issues/485



**TODO List**

* axi_riscv_atomics_wrap IP 将CPU传来的读写内存信号进行了一层包装，然后再以AXI4接口的形式向前传递给内存控制器。是为了满足 RISC-V 内存模型的要求？这部分还没细看
* buildroot默认的linux配置中，启动参数只有earlyprintk，然后builtin的initramfs（使用busybox制作），希望能够自动挂载sd卡的第二个分区作为root fs，同时需要把kernel的位置调整到sd卡的第一个分区中。



以下是子模块的一些BUG，在当前跟踪的版本中尚未修复，我手动进行了更改。

在 CVA6 的 [PR#813 ](https://github.com/openhwgroup/cva6/pull/813)中修复了cva6 的 clint axi id width 的问题（在 ara 的 fpga 中添加新的 clint 模块）

在 common_cells 的 [PR#141](https://github.com/pulp-platform/common_cells/pull/141) 中修正了 spill_register_flushable.sv 未添加到 common_cells.core 的问题（手动进行了添加）

ara 综合结果

lane = 2    --> lut usage 93%

lane = 2, VLEN = 1024  -> lut usage 84% ，添加各种 IP 后  --> lut usage 91.19%

Refs

* http://alumni.cs.ucr.edu/~amitra/sdcard/Additional/sdcard_appnote_foust.pdf
* https://docs.xilinx.com/r/en-US/pg153-axi-quad-spi
* [SPI通信协议详解](https://zhuanlan.zhihu.com/p/150121520)
* http://www.landley.net/writing/rootfs-howto.html



WARNING: [DRC PLCK-23] Clock Placer Checks: Sub-optimal placement for a clock-capable IO pin and MMCM pair. 
Resolution: A dedicated routing path between the two can be used if: (a) The clock-capable IO (CCIO) is placed on a CCIO capable site (b) The MMCM is placed in the same c
lock region as the CCIO pin. If the IOB is driving multiple MMCMs, all MMCMs must be placed in the same clock region, one clock region above or one clock region below the
 IOB. Both the above conditions must be met at the same time, else it may lead to longer and less predictable clock insertion delays.
 This is normally an ERROR but the CLOCK_DEDICATED_ROUTE constraint is set to FALSE allowing your design to continue. The use of this override is highly discouraged as it
 may lead to very poor timing results. It is recommended that this error condition be corrected in the design.

        i_ddr/u_xlnx_mig_7_ddr3_mig/u_ddr3_clk_ibuf/diff_input_clk.u_ibufg_sys_clk (IBUFDS.O) is locked to IOB_X1Y76
        i_ddr/u_xlnx_mig_7_ddr3_mig/u_iodelay_ctrl/clk_ref_mmcm_gen.mmcm_i (MMCME2_ADV.CLKIN1) is provisionally placed by clockplacer on MMCME2_ADV_X0Y3



dts 修改后，重新编译得到新的 bootrom.sv



目前发现的问题：

~~**需要设置50MHz，因为bootloader里硬编码了这个（init_uart），建议还是不要修改频率，很多硬编码忘改了防不胜防**~~

~~重新生成bootrom.sv时要注意，make clean 和 make default_target 默认都不会动这个 bootrom.sv，需要make all~~

init process段错误，从报错的mstatus上看，VS并没有启动，以及在启动日志中“riscv: ELF capabilities acdfim” 也没有包含V拓展，是哪出了问题？misa寄存器是否需要动？

为什么linux的日志会被打印两遍。

**ArianeCfg有问题！NonIdempotentAddrBase的设置出了问题，对外设的读写是不能cache的！**

**首要解决目标：目前尝试在 add-ip-gradually 分支（仅添加了bootrom）上尝试跑 hello_world 程序失败。但是模拟能成功通过，原因还不清楚**





----

## Ideal Dispatcher

ariane 和 ara 的握手协议如下，其中 insn 为指令的编码，rs1，rs2 为指令的寄存器操作数（因为部分向量指令需要标量寄存器的值）。

```systemverilog
typedef struct packed {
  riscv::instruction_t      insn;
  riscv::xlen_t             rs1;
  riscv::xlen_t             rs2;
  fpnew_pkg::roundmode_e    frm;
  logic [TRANS_ID_BITS-1:0] trans_id;
  logic                     store_pending;
} accelerator_req_t;

typedef struct packed {
  riscv::xlen_t             result;
  logic [TRANS_ID_BITS-1:0] trans_id;
  logic                     error;
-
  // Metadata
  logic                     store_pending;
  logic                     store_complete;
  logic                     load_complete;

  logic               [4:0] fflags;
  logic                     fflags_valid;
} accelerator_resp_t;
```

在 ideal_dispachter 模式下，ariane 被替换为一个 fifo，fifo 中每个元素为一个 fifo_payload_t 结构，这用来填充握手协议中的 accelerator_req_t 中的相应字段，其余字段填充为 0，fifo 会忽略 ariane 返回的 accelerator_resp_t 结构。

```systemverilog
typedef struct packed {
    riscv::instruction_t insn;
    riscv::xlen_t rs1;
    riscv::xlen_t rs2;
} fifo_payload_t;
```

而 fifo 的初始内容如何获得呢？对于一个需要运行的 elf file，在 ara 的 makefile 中，首先会用 spike 模拟跑一遍。把运行的每条指令和运行时的寄存器状态都 dump 出来，然后剔除掉所有的标量指令，将运行的向量指令的编码，以及此时 rs1, rs2 标量寄存器的值打包为 fifo_payload_t，写入一个临时文件。最后模拟的时候用 readmemh 读入该临时文件，用于初始化 fifo 即可。

---

## wt-cache-system

* 在axi_adapter 中，遇到一个 amo 操作时，首先会生成一个 invalid 请求 返回给 dcache，原因？
* 在 wt_dcache_mem 中，read data 的宽度都是 64bit，这不会出事吗

## ara-vlsu

* mask load 会把 inactive element 也 load 上来？虽然 tail element 不会 load，这和 rvv spec 是否相符？
* **vector load 中，如果 vl * sew 不是 8 byte的倍数，会造成多余的内存访问（load unit中处理得很简单，axi总线总是以64bit为单位的数据传输）。标量的 load ，store是如何处理的？**，额外补充说明关于 misalign load/store 的实现上，这里的 misalign 主要是相对于 axi data width 来说的，如果取 NrLane = 2，则 width = 64，如果 addr 不是 8 的倍数，由 axi spec 可知，第一次传输仅会传输部分的 byte 来使下一次传输地址对齐 8 byte。但是 lane 每次请求的数据又是 8 byte 的倍数，因此会导致 lane 传来的 data 和 axi 传输的 data 会发生错位。store 单元采用了缩小 axi 有效数据宽度的方法来对齐，因此在 addrgen 模块中有一些额外的 misalign 的代码。而 load 单元中则通过额外增加一个 counter 来应对这种 misalign（虽然我也不知道为啥要这样不对称的设计）。
* addrgen模块负责 axi 的 read/write address 通道，根据 pe_req_i 生成相应的访问请求（unit stride access 通过burst访问，但其它步长或者随机访问则生成与访存次数相同的axi请求），并将axi请求转发到vldu和vstu，vldu和vstu根据pe_req_i和axi_req接收和发生数据（处理read/write data通道）
* 观察shuffle_index函数，不难理解ara中数据shuffle的规律。每个lane由8个bank组成，每个bank的word宽度为64bit（与elen保持一致）。每次读写axi过来的数据时，以8\*lane byte为基本单位（即每个lane写一个bank word）。一个byte在8\*lane 中的偏移决定了它在哪个lane中和它在bank word 中的偏移（看shuffle_index函数及其注释）。而该byte位于第多少个8\*lane则决定了它在第几个bank中以及位于该bank的哪个word。总体来讲，固定sew（元素宽度），随着byte地址的升高，位于同一个元素内的byte，处在bank word中的相邻位置，继续升高，变lane值，然后变bank word offset，再变 bank number，最后变bank word addr.
* 看了 mmu 拓展版的代码，感觉两个问题，一个是 AXI_ADDRGEN_WAIT_MMU 状态中 少了一个 else 分支，以及 strided  access 的 next addr 有误，然后还需要修正 vstart 的问题。**关于 indexed load 实现上的一些问题，目前首先需要弄明白mmu 的接口协议！**（那个 arbiter可能没啥问题，主要是因为向量和标量的内存访问请求不会同时发生？）一些重要的测试用例：
  * 简单的 unit stride access, stride access, index access
  * ~~very long unit stride access, longer than max burst length 256~~
  * index access with operand delay
  * misaligned unit/stride load with crossing page boundary
  * non-zero vstart（标准测试已有，uncomment needed）
  * mmu exception （标准测试已有，uncomment needed？）
* TODO：看看 mask 相关地址计算，vl 之类的需不需要改，当 vstart >= vl 时的处理等等，目前的错误：~~vstart 在执行完向量指令后没有归零（这结合 vstu 中没有处理 vstart 导致了目前模拟的死锁），lane_sequencer 的 vstart 计算错误~~，load/store_complete 信号的发送？在 error 时 cva6 侧的异常处理？**有误的地方：non-zero-vstart 如何合理使用？尤其是mask的时候，即使原来的 vstart 很大，到 operand_requester 上就成 0 了，然后是 hazard**
* 这里讨论一下 mmu 的基本工作逻辑：mmu 接收两类的地址翻译，ICache 的翻译请求和 load/store 的翻译请求。`enable_translation_i` 标志着是否需要对 ICache 的地址进行翻译，如果不需要翻译或者 tlb 命中，在同一个周期即可返回结果（组合逻辑）。`en_ld_st_translation_i` 标志着是否需要对 DCache 的地址进行翻译，如果不需要翻译或者 tlb 命中了，在下一个周期返回结果。这意味着，对来自 load/store 的翻译请求，mmu 中有一级寄存器缓冲，但是没有 enable 信号，即该寄存器没有保存功能，无条件接收下一次的信号。如果 tlb 没有命中，那么 mmu 的 ptw 模块会在下一周期进入 walker 状态来循环生成对 DCache 的访问请求，来获取对应的页表数据，最后生成一个 update 请求来更新 tlb 内容。总的来看，在 tlb miss 的情况下，一个 req 如果持续拉高，最终在某个周期 tlb 得到更新，然后命中，在下一周期得到 valid 输出。如果这期间 req 值变化其实也没有影响，因为 ptw 不处于 idle 状态时不接收外部输入，因此不会生成额外的 DCache 访问，如果命中了得到合法输出也皆大欢喜。而在若干周期后 tlb 得到更新，req 再恢复原值时下周期便会得到合法输出。但其实 req 还是不能够随便变，原因在于 ptw 访问时发生异常时（page fault 或者 pmp error），会拉高 valid 的信号并返回 exception，如果 req 变了会被误以为是该 req 引发的异常。总的来说，**mmu 接口逻辑为：请求时拉高 req，并保持不变，在 mmu 拉高输出的 valid 的信号时，请求方同周期拉低 req 信号，否则 mmu 会认为新的 req 到了。并且 mmu 只保证 valid 的信号一个周期的有效时间**。load/store unit 满足该接口要求，**TODO: 接下来看 vector unit 如何操作了**。 **思考 core_st_pending_i 的影响，vstart, 并构建相应的测试用例**

## ara-lane

* 在 lane-sequencer 中，为啥 operand_request_i 中计算该 operand 的 hazard 指令时，要把 vs 和 vd 取或呢？不应该就只有 vs 吗？

* ara sequencer 中为什么只取了 alu_vinsn_done[0]，其他 lane 的 done 信号不管了吗？

* ~~slideup, slidedown 在 ara sequencer 中的 hazard 逻辑？以及lane sequencer 中 vl 的计算想法？~~

* ~~在operand-requester中，request的地址是如何改变的（目前看起来一直是同一个地址）？~~，每次地址会加一

* vector alu 中是完全的组合逻辑，要求在一个周期内做完最多 64bit 的加法，乘法也是完全的组合逻辑

* 一些目前的 bug: 

  * [issue 243](https://github.com/pulp-platform/ara/issues/243)：取 mask bit 时地址计算错误
  * [issue 248](https://github.com/pulp-platform/ara/issues/248)：vstart 计算错误
  * [issue 239](https://github.com/pulp-platform/ara/issues/239)：lmul 带来的隐式的 hazard 没有考虑周全
  * https://github.com/pulp-platform/ara/issues/250
  * masku 中的 bit_enable 信号赋值？为啥根据 vl 来置位，毕竟 vl 一直都不变的？
  * ara 中大部分的代码都忽略了 vstart != 0 的情况。例如在 masku 中，masku 根据从不同 lane 中收到的 mask operand 来进行 reshuffle，但当 vstart != 0 时，mask_pnt_q 的初值和 vrf_seq_byte 的初值应该进行相应的偏移。
  * ara 中执行倍增 sew 相关的指令我认为是有一些问题的，例如 vwaddu，ara 中在 pe_req_t 中设置的 sew 为 2*sew，这导致 masku 生成 mask 时存在问题。
  * reduce operation should be illegal instruction when vstart != 0，and no op when vl == 0
  * reshuffle 的逻辑中，每次只 reshuffle 一个寄存器，但是更新是按照 lmul 的值更新的，这会有问题？另外，**判断是否需要 reshuffle 的逻辑也有些问题？只判断 vd，vs之类的应该不行（当 lmul > 1 时），详细说明：比如先取 lmul=1 修改 v1 寄存器，然后取 lmul=2修改 v0 寄存器，如果此前 v0 寄存器的 eew_q 不 valid，这导致新指令不 reshuffle 就写 v1 寄存器，在 sew 不相等且新指令部分写 v1 时就会出问题**？而且没有考虑 use vd as op 的情况？还有，reshuffle 请求的 ara_req_d.vtype.vsew 的计算有些问题。
  * 在看到 slide 逻辑中的 extra_stride 后，发现除了 slide 指令，其他指令也需要这样一个概念，不然非整的 vstart 叠加 vl 会造成 operand queue 中的错误计数
  * 在 AluB operand queue 中不应该设 SupportReduct = 1，这导致如果 lane 0 的 vfu_operation_t.vl = 0 时（当vstart != 0 时可能出现这种情况）会将 vrf 中取的数拿过来用，本来应该忽略，填充neutral operand才对。
  * ~~冒险逻辑的处理（即依赖指令写一次，我写一次）依赖于 vstart = 0~~，目前修改为 vstart != 0 的冒险指令 stall
  * load, store指令中 addrgen 的逻辑有问题，axi 的 valid 信号依赖于 ready 了。另外，向 sequencer 发送 ack 得太早了，这在添加 mmu 后可能出问题（还没等到 axi 的 resp 就发送 ack 了）。
  * csr 读写中缺少了 vcsr 寄存器
  * ~~测试用例中的 riscv-tests 中缺少对 VLEN 的检查，默认了 VLEN=4096，导致 vl != avl，使得测试失败~~（测试用例里面是对config 里面的配置进行测试的，因此默认了 VLEN >= 2048）
  * ~~测试用例中 vle32.c 的 test_case 15 有误。VSET 将长度设为 15 后应该最后一个测试值应该不变。~~ 已修改

* mask bit 在 vrf 中的摆放逻辑，每 8 个元素对应的 bit 组成一个 byte，该 byte 再按照正常 byte 的摆放顺序放在 vrf 的相应位置（即调用 shuffle_index），因此 mask bit 的 layout 实际上依赖于 sew 的值，这与 spec 中 layout 与 sew 无关相违背。**想想这个摆放挺自然的，因为根据sew的值，自然的layout中哪个 bit 在 lane 中的哪个位置就已经固定好了，这些计算只是在应用已经固定好的 layout 规则而已**

* **目前需要关注的重点：stall 信号如何根据hazard table生成？从 pe_req 到 reg file 取数，再到 alu 计算，整个流程的握手信号逻辑、信号是否持久？**

  * fu_data_t <-->  acc_** 相关信号  :   issue stage <--> ex stage，握手使用 valid, ready信号。valid 信号是依赖于 ready 的，acc dispatcher 中有一个 fifo，当 fifo 满的时候，拉低 ready 信号，issue stage 会相应地拉低 valid 信号（因为拉低valid有一个周期延迟，因此实际是fifo还差一个元素就满的时候拉低 ready 信号），相应的 issue stage 暂停流水线即可。
  * acc_req_t <--> acc_resp_t     :       acc dispatcher <-->  ara dispatcher，使用 valid, ready信号握手，acc dispatcher 中在发送 req 时同样有 fifo，在握手成功时弹出 fifo元素。因此 valid 和 req 信号拉高后就会一直有效，直到握手成功，而 ara dispatcher 的 ready 依赖于 ara sequencer 的 ready 信号，acc dispatcher 的 valid 信号。原因是 ara dispatcher 中并没有 fifo 来临时存储数据，ara dispatcher 的作用是将 acc_req_t 解码为 ara_req_t，valid 信号和 ara_req_t 都有一个寄存器，寄存器的输出送向 ara sequencer，当 ara sequencer 的ready 信号拉高时，ara dispatcher 才会开始解码，并将解码的结果写入寄存器（同时可以认为 ara sequencer 收到了寄存器之前的值）。**对于需要写回结果的指令（例如vmv.x.s等等）或者访存指令，ara dispatcher会解码，并将结果送到 ara sequencer，但直到 sequencer 通知该指令执行完成后才会拉高 ready 信号（我猜想这样做的原因是为了保证 ara 中执行的指令只有一条会写回结果，来保证指令返回的结果是顺序的？那为啥访存指令也限制呢）**

  * ara_req_t <--> ara_resp_t      :       ara dispatcher <--> ara sequencer，ara dispatcher 的valid 信号生成逻辑已经在上面讨论了。ara_sequencer 的 ready 信号依赖于 lane sequencer 的 ready 信号和 各个 function unit 的 fifo 还有空位（与 ara dispatcher 相同，ara sequencer 中也仅有一级的流水线寄存器来帮助传递 pe_req_t，因此需要等到所有 lane sequencer 的 ready 都拉高后才会拉高自己的 ready，从下个列表中可以看出， lane sequencer 的 ready 信号一旦拉高，在 pe_req_t 不变时就不会拉下了）
  * pe_req_t <--> pe_resp_t        :      ara sequencer <--> lane sequencer，使用 valid, ready信号握手，但由于有 NrLane 个 lane sequencer，ara sequencer 会等到所有的 lane sequencer 的 ready 信号都拉高才认为 pe_req_t 传递成功（**为什么忽略了其他功能单元的 ready 信号，而选择自己计数呢**），而 lane sequencer 的 ready 信号依赖于 operand requester（同样因为 lane sequencer 只有一级寄存器），**不过依赖的方式有点奇怪，lane sequencer 是观察流水线寄存器输出的 valid 信号是否拉高，如果拉高且pe_req_t对应的指令需要该 operand（有NrOperandQueues 种 operand），那么就将自己的 ready 信号拉低。这导致 lane sequencer 对同一个 operand 每两个周期才能请求一次，另外，为啥生成 ready 信号时都默认指令需要 mask operand 呢**。
  * operand_request_cmd_t  :   lane sequencer --> operand requester， 使用 valid，ready 信号握手，operand requester 是与 vector register file 打交道的接口，除了接收 NrOperandQueues 个 operand_request_cmd_t 类型的 req 来向 vrf 请求操作数，也会接收 alu result, vld result 等等来写入 vector register file。operand requester 中为每个 operand req 维护了一个状态机，持续不断地生成对 vrf 的请求，直到达到 req 中的 vl，此时 operand requester 拉高对 lane sequencer 的相应 operand 的 ready 信号，表示可接收该 operand 类型的下一个请求。生成的 vrf 请求并不能总是马上响应，有两种阻碍因素，一个是与其它类型的 operand 的 vrf 请求对应的 bank 撞上了（每个 lane 有 8 个 bank，因此每周期最多能出 8 个 64bit），因此这里有个 arbiter 来裁断。然后就是从 vrf 中出来的 operand 会进入相应的 operand queue，因此要求 operand queue 的 ready 信号拉高，此时才能生成新的 vrf 请求。
  * vfu_operation_t   :   lane sequencer --> vector function unit（valu, vmfpu），lane sequencer 除了生成 operand_request_cmd_t 来指示 requester 请求 operand 外，还生成了 vfu_operation_t 来指示 vfu 拿到 operand 后应该如何计算。有意思的是，每个 vfu 内部有 insn queue 来缓冲得到的 vfu，并据此生成传向 lane sequencer 的 ready 信号，但 lane sequencer 发送 vfu_operation_t 时无视了该 ready 信号。原因在于 vfu 内部的 insn queue 与 operand queue 中的 cmd fifo 深度相同，早在 ara sequencer 中就检查了。
  * operand_queue_cmd_t   :   operand requester  --> operand queue，operand requster 除了生成新的 vrf 请求，使得生成新的 operand 发送给对应的 operand queue 外，还会根据 operand_request_cmd_t 生成 operand_queue_cmd_t 发送给 operand queue ，这样 operand queue 才知道如何处理接收的 operand 以及什么时候标志这一组 operand 结束等等。因此每个 operand queue 有两个 fifo，一个 fifo 接收从 vrf 过来的 operand，一个 fifo 接收从 operand requester 过来的 operand_queue_cmd_t。值得一题的是，不需要生成与装 cmd 的 fifo 相关的 ready 信号，因为检查这个 fifo 是否满了的任务提前到了 ara sequencer 中（它的 ready 信号生成除了依赖 lane sequencer 的 ready，内部还有对 operand cmd queue的计数，当 operand cmd queue 没满的时候，才会拉高 ready）。而 检查接收 operand 的 fifo 是否满了的 ready 信号则直接对应输出给 operand requester 的 ready 信号。这个 ready 信号的生成方法与前面提到的 acc dispatcher 的 ready 信号的生成有异曲同工之妙，因为从 operand requester 生成 vrf 请求到 operand queue 收到 operand 有两个周期的延时（从 vrf 中读取，以及穿过 vrf 到 queue 的 crossbar），为了将 ready 信号与 vrf 请求同步，每次 requester 生成一个新的 vrf 请求，就会拉高 issue 信号，这个信号直连到 queue，因此 queue 可以提前模拟地增加 queue 的元素计数，据此来及时生成 ready 信号。operand queue 会根据 operand_queue_cmd_t 的内容，对 operand 进行相应的处理，使运算单元能接收到合理的操作数（例如queue 提前对 operand 进行符号拓展）
  * elen_t operand    :    operand queue <--> valu，vmfpu。valid，ready 信号握手，valid信号不必多说，只要queue中有元素就行（虽然可能由于 widen 操作，queue中元素会生成多个 operand）。在不考虑 reduction 操作时，valu 每周期都能完成 64bit 的加法操作，因此对 aluA，aluB 两操作数是时刻 ready 的。vmfpu由 mul unit，div unit，fpu 组成。乘法操作和加法一样，是一个周期的组合逻辑完成。不过有四个乘法部件，分别进行8，16，32，64位的乘法操作（不太理解为啥不把它们合成为一个）。有一个多周期，无流水的除法部件，它的实现也很简单，就是比较大小，做加减法，移位就完了。**值得一提的是，mask在除法部件中真正发挥了作用，因为每次除法需要很多个周期，因此如果某个操作数的mask位没有置1，那么除法部件会跳过该操作数，在下一个周期处理下一个操作数（加法和乘法都是单周期完成就没这个必要）**。TODO: fpu 的实现（一个比较关心的事情是内部是否有pipeline）。
  * 关于 mask unit 的实现，mask unit 的 insn queue 只支持一条向量指令，为什么（目前的 ara sequencer 在 hazard 中没有考虑指令隐式读取 v0 的情况，因为 mask unit 的 queue 深度为 1 消除了这种 hazard）。mask unit 与许多功能单元都有交互，从 ara sequencer 中接收 pe_req_t，当该指令的 vfu 为 mask unit，即该指令结果生成mask时，或者该指令需要用到mask时，masku 的 queue 会接收该指令。因此 mask unit 有两个功能，如果该指令需要用到 mask，那么 masku 会接收来自 vrf 的 MaskM 操作数（相应的vrf请求由operand requester产生），然后 reshuffle 产生各个 lane 需要的 mask_o（mask_o的每个bit与operand的每个byte一一对应）。如果该指令产生 mask，那么 masku 接收来自 vfu 的 计算结果，然后 reshuffle 产生对 vrf 的写请求。另外，这里也有很多的 valid，ready 握手信号，例如 masku 接收来自 vrf 的 MaskM，MaskB，来自 vfu 的 result。**基本握手原则与前面谈到的许多地方基本一致：发送方 valid 信号一旦拉高，直到握手成功后才能拉低。接收方看见有 valid 数据，可以多个周期处理，处理完成后再拉高 ready 信号，握手完成**。**另外一个值得注意的点是各个 lane 不均衡的 vl 使得不同的 lane 传给 masku 的计算结果次数可能相差1，这是 masku 中的 fake_a_valid 产生的原因。由于 maskM 各个 lane 取的次数一样（因为取出的这个 lane 取出的 maskM 可能会被送到其它 lane 去），可能导致有的 lane 算完了之后还有新的 mask 传来，因此 masku 中有下面的代码来拉低相应 mask 的 valid 信号。**

  ```systemverilog
          // Are there lanes with no valid elements?
          // If so, mute their request signal
          if (read_cnt_q < NrLanes)
            mask_queue_valid_d[mask_queue_write_pnt_q] = (1 << read_cnt_q) - 1;
  ```

  ​		而 vfu 中处理最后一个 operand 中仅有部分元素有效则是通过 be 信号。这里的 be 信号有两种，首先大家在 写入 vrf 		时都会生成 be 信号来屏蔽 tail element 和 masked element。而对于 div 和 fpu 涉及到多个周期的操作，在传入操作		数的时候也会生成相应的 be，不对 tail / masked elment 展开计算。

  * 关于 sldu 的实现：vslideup, vslidedown 的一个特性是写或者读时会从寄存器的某高位元素开始，这导致下面讨论的冒险处理中的每写一次才能读一次的方法失效，因此 ara sequencer 中对这两种指令进行了额外特判，要求不能有相应的 hazard 才能 issue。然后就是 operand_request_i 中 vl 的计算方法，vslideup 这边很简单，主要讨论一下 vslidedown 中 extra_stride 的来由。如果 stride 没有取到相应的整倍数的话，那么读取的实际的有效数据是从 8 * NrLane 的块数据的中间开始算的，但 vrf 请求每次是 8 * NrLane 的，因此实际上会把前面的无效数据也读进来，导致operand queue 中按照 vl 计数时会把前面的无效数据也记进去，导致最后的有效数据被统计漏了。因此要把这段无效数据的长度也加到 vl 中。

  * **关于lane中冒险的处理：每个请求operand 的 request中的hazard字段记录了与该指令有冒险的其他指令，为了保证读写不冲突，比如A指令的vs1 operand 与B,C指令有冲突，那么要求B,C每写回一次后才能生成一次vs1 operand 的请求，如果B指令是会拓宽操作数（读一次会写多次），则要求B写回两次才能生成vs1 operand的请求。这里的设计不理解，一个是hazard产生的判定，最典型的写后读，为啥要寄存器相同才产生hazard，例如在 lmul=1 时 vwadd 指令会写两个寄存器，如果接下来的指令读第二个写的寄存器就导致 hazard 判定失败（[issue 239](https://github.com/pulp-platform/ara/issues/239) 提到了这一点，不过还没改的）？~~以及WAR的hazard判定，为啥hazard_vs1 中会将读 vd 的向量指令对应的 bit 拉高~~（只是为了方便，如果不这样做，就需要在指令的写回阶段添加 hazard 判定）。然后是这个 stall 的逻辑，为啥要求 B,C 指令写了一次的信号同时拉高？以及拓宽操作数的判定，单单 CWT_WIDE 够吗，符号拓展指令可能拓宽4倍甚至8倍，导致读一次会写4次或者8次？**
  * ~~如何保证指令的 operand 同步生成？TODO~~
  * reduction operation 的实现：我们考虑上述的部件中，需要哪些额外的操作。在取操作数上，由于 reduction 的 vs1 只使用第一个元素，因此在 lane sequencer 中生成 vs1 的 operand_request_i 时，vl = 1（更准确说，只需要lane 0 访问 vrf 就行了，但考虑到对称性，其他 lane 也会生成 vrf 访问，但仅有 lane 0 的 operand queue 会用到 vrf 传来的 operand，其他 lane 使用 neutral operand 填充，忽略 vrf 的operand）。对于 vs2 的 operand req，如果说 vl < NrLane，会导致 vl = 0，这时采取与 vs1 同样的处理操作，即取 vl = 1，在 operand queue 中忽略 vrf 传来的 operand，填充 neutral operand。而 vfu_operation_t 中则使用真实的 vl（即 vl 可以为0）。不会有 global vl = 0 的情况，因为 ara dispatcher 中已经判定过这种情况了，不会向后传 ara req。下面考虑整数的 reduction 计算方法：valu 中粗略地有三个状态，intra-reduction, inter-reduction, simd-reduction。首先每个lane 在第一个状态，先把自己手上的数据 reduce，然后进入 inter-reduction 阶段，将手上的数据传给 slide unit，它负责 shuffle 之后再将数据传回 valu，第一次 shuffle 后 lane i 的元素传递给 lane i+1，因此奇数号 lane 再进行一次 reduce，第二次 shuffle 时 lane i 的元素传递给 lane i+2，模4余3的 lane 再进行一次 reduce，以此类推。最后编号最大的 lane 进行 reduce 后所有数据都集中在它手中了，此时会再进行一次 shuffle 把数据传递给 lane 0。只有 lane 0 会进入 simd-reduction 阶段，将64bit 的数据reduce 为 sew 位宽的数据。浮点reduction：由于浮点不存在结合律，因此存在有序 reduction 和无序 reduction 两种情况。对于无序 reduction，基本和整形的情况差不多，但由于浮点运算有多个周期，为了更高效地利用浮点单元的 pipeline 特性，可以浮点单元中塞入多个合法的操作数以加速计算（具体来说，第一次运算当然需要两个 operand 都来了才开始，如果当第一次运算还没结束，下一个 operand 过来了，那将它和另一个 neutral operand 也塞入 pipeline 中运算。出来一个运算结果后，如果新的 operand 来了，马上又可以塞入 pipeline 中。主要使得浮点单元尽可能快地接收 operand，让新的 operand 快过来，加速运算）。而对于有序的 reduction，必须依次计算，使得在 slide unit 和 vmfpu 中都引入了一个新状态 osum。在 slide unit 中，每个 lane 出的结果 valid 了，它就把该结果传递给下一个 lane。因此每次都只有一个 lane 处于计算状态，首先是 lane 0 开始计算，然后结果传递到 lane 1，再传递给 lane 2...直到计算完成，由 lane 0 写回结果。
  * ~~reshuffle 如何做（易错的倍增，缩减sew操作）？reduction operation 如何做？slide operation 如何做？TODO~~

keywords in vetcor related paper

chainable，pipeline，data width of alu，mask，shuffle between lane

----

RVV PATCH: 没有apply的patch

https://marc.info/?l=kvm&m=168632189117256&w=2

3: riscv: hwprobe: Add support for probing V in RISCV_HWPROBE_KEY_IMA_EXT_0

18: riscv: kvm: Add V extension to KVM ISA

19: riscv: KVM: Add vector lazy save/restore support

21: riscv: Add prctl controls for userspace vector management

22: riscv: Add sysctl to set the default vector rule for new processes

23: riscv: detect assembler support for .option arch

---

一些上层的V指令测试：

* 为什么直接写vcsr会爆illegal instruction？而需要写vxrm, vxsat.... **rvv0.8的版本定义中没有vcsr，现在csrr, csrw碰到vcsr就会报错**



degisn automation conference

* 

