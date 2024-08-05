## 看 GPU 源码时值得关注的一些事情

* 不同进程之间是如何共享 GPU 的？（例如 A 进程启动了一个 kernel，B 进程启动了一个 kernel，谁负责为这俩 kernel 分配内存，又如何保证分配的内存不冲突？OS 在这其中起一个什么作用？ventus-gpgpu 中的 page table 指针是干嘛的？），我想重点在于描述清楚 gpu 程序从编译到运行的整个流程
* 多个 workgroup(block) 可以在同一个 stream processor(compute unit) 上吗
* 文档中自定义的 csr 和 gpgpu_top 上的 IO 接口是什么关系
* GPGPU architecture 一书中谈到 SIMT stack 的 branch 和 join，硬件是如何得知实际的 join 位置的 pc 的呢？
* **barrier 的实现**
* **什么时候可以用标量指令？标量指令没有 mask 会不会出问题？**
* 为什么 SIMT_STACK 在一个分支时总共需要三个表项呢（if, else, merge），两个行不行？

## 对源码一些地方的解释

* warp_scheduler 和 icache 的互动：warp_scheduler 每周期选择一个 warp，为这个 warp 向 icache 发送请求，icache 需要两个周期返回结果（hit or miss），如果 miss 了，warp_scheduler 会 invalid 该warp 本周期和上周期发送的 icache 请求，并且重置该 warp 的指针。icache hit 时的指令数据发往 decoder，decoder 解码完成后送往 instruction buffer

* ventus gpu 的 register bank 有两大块，一个是 scalar register，一个是 vector register，两种默认的 register 数目都是 1024，默认都切分为 4 个bank。scalar register 的寄存器宽度为 xlen（32），因此每个 bank 的大小是 256 * xlen。而 vector register 的寄存器宽度为 num_thread*xlen（这个寄存器宽度会不会有点过于夸张），因此每个bank 的大小是 256\*(num_thread\*xlen)。**另外每个 vector register bank 的 0 地址都是特殊的 v0 寄存器（为啥要这么多 v0 寄存器呢？）**

* instruction buffer, scoreboard, issue unit, operand collector 间的互动：每个 warp 都有一个 instruction buffer 和 scoreboard，scoreboard 中记录了该 warp 中对寄存器的读写情况，**当出现 RAW 之类的冒险或者该 warp 有未决的 branch 之类的（这和顺序发射的 cpu 也很像嘛，在分支指令未决定之前不会将后面的指令 issue，这样分支预测错误时只需要flush 前面的流水线就好了）**，该 warp 对应的 instruction buffer 不能发射指令。前面讲到，icache 取指的指令被解码后送到了对应 warp 的 instruction buffer，这里有一个 rrarbiter，选择一个 scoreboard 认为能发射的 warp，将它在 instruction buffer 中的一条指令送到 operand collector，operand  collector 中有若干个 collector unit，每当一条新指令送到 operand collector，它会分配一个 collector unit，这个 unit 负责实际向 scalar / register bank 发出访存请求，当收集到所有的 operand 时，便可以将这条指令和它的 operand 发射到实际的 function unit

* scoreboard 除了在冒险和 branch 时（join 指令也视为 branch，只是不会被同时发射到 valu）会阻塞后面指令，出现 barrier 时也会阻塞，目前 barrier，barriersub，endprg 这三条指令会被视为 barrier，即控制信号的 barrier 为 true，但仅有 endprg 指令的 simt_stack_op 为 true。然后有 vbeq，vbge 等等六条指令加上 join 指令对应的控制信号中 simt_stack 为 true，仅有 join 指令的 simt_stack_op 为 true

* 接下来说说各个 function unit，最简单的 scalar alu，它不需要接收 mask 掩码，处理 int 整形指令和标量的条件跳转指令（即整个 warp 都会跳转），然后结果写回到标量寄存器，**目前暂时不清楚什么时候可以用标量指令，以及一条标量指令可以代表多少（代表一个 warp？代表一个 workgroup？。。。），关键得看上层代码怎么翻译到汇编的**

* 然后是 simt stack unit 的运行逻辑。这里首先需要区分标量跳转指令和向量跳转指令，标量上面已经提到了，它与 simt stack 无关，我想用处比较多的是无条件跳转指令（比如循环的跳转，函数的调用与返回），标量的条件跳转指令有啥用呢（这或许依赖于编译器的优化？如果有些线程无关的判断的话，即这个判断需要的数据可以放在标量寄存器中，例如判定某个全局内存中的变量值之类的）。扯远了，回头看与 simt 相关的 vector 版本的跳转指令 + join 这七条指令（对应的控制信号的 simt_stack 为 true）。v跳转指令会被发射到 valu 和 simt stack 两个功能单元，前者是计算分支跳转的结果。而 join 指令只会被发送到 simt stack 中。如果是v跳转指令，那么产生 ifmask 和 elsemask，分别代表不跳转和跳转的线程。选择其中一个mask（这里假设选择 ifmask），将 （original mask, joinpc, joinpc) 和 (elsemask, joinpc, jumppc) 压入 simt stack 栈，然后接下来以 ifmask 为基准 mask 执行。这里栈中元素的三元组的含义分别是：线程 mask，join位置的 pc，以及弹栈时新 pc 的值。当碰到 join 指令时，比较 join 指令所在的 pc 和栈顶的 joinpc（三元组的第二个元素），如果一致则弹出栈顶元素。如果没有嵌套的分支，那么下一次执行到 join 指令时我们会弹出 elsemask，并跳转到 jumppc，也就是 else 分支开始执行的位置。执行完 else 分支后我们会碰到同一条 join 指令，这会将 original mask 弹出（即线程重新汇聚了），跳转到 joinpc（也就是没有发生跳转），然后再执行该 join 指令时，与栈顶的 joinpc 比较，发现不符合，继续正常执行（此时 join 指令相当于一个 nop）。

* 接下来是 barrier，scoreboard 首先会阻止 barrier 后面的指令发射，直到 barrier 信息回传给了 warp scheduler（为什么这么早？）。warp scheduler 中维护了这样一些变量
  * warp_bar_belong：这个是一个二维数组，第一维下标表示该 SM processor 中的 workgroup，对应的第二维是 bitmap，置1的位表示该编号的 warp 属于该 workgroup
  *  warp_cur：同样的二维数组，当某个 warp 遭遇 barrier 指令时，将该warp对应的位置置1（计数是以 warp 为单位的，这也是为什么 cuda 的 __syncthreads() 函数不能在 warp split 的时候使用）。
  * warp_exp：当 warp_cur[workgroup_id] == warp_exp[workgroup_id] 时，说明这个 workgroup 下的所有 warp 都到齐了。可以释放该 barrier 了
  
* 额外说一下 nvidia 新的 ADD, WAIT, YIELD 机制（independent thread scheduling）是如何解决 simt stack deadlock 的：deadlock 发生的本质原因在于当 warp split 时，stack 使得该 warp 选择某一组线程调度，另一组线程阻塞，但被阻塞的线程可能握有互斥资源，不调度这组线程整个 warp 就没法向前跑了。因此我感觉这个机制就是把 stack 给展平，使得任何一组可调度的线程都可以被调度。具体这三指令的含义
  * 一个 convergence barrier 对应一条 ADD 和一条 WAIT 指令。一个线程执行 ADD 指令后，就会被加入到该 convergence barrier，当线程执行到 WAIT 指令时，就需要阻塞并等待其它在该 convergence barrier 中的线程执行 WAIT 指令，等到所有的在 convergence barrier 中的线程都执行了 WAIT 之后，barrier 释放（warp merged）
  * YIELD 指令也可以指定 convergence barrier，如果线程执行到了 YIELD 指令，那么将该线程从指令对应的 convergence barrier 中剔除，因此其它在 convergence barrier 中的线程不再需要等待该线程（我的猜测：显式的 YIELD 指令通常由 compiler 插入，例如 compiler 如果能够证明这些 warp 内的线程有资源依赖，那就可以插入 YIELD 指令指示 scheduler 这个 warp 在下一个 join point 是没办法 merge 的。但我想 scheduler 内部也必须有某种启发式的算法来决定要不要 yield 当前的线程组才能从根本上解决 deadlock，对应的后果就是在 join point 处本来可以合并的线程组因为被 yield 了没能合并成功。估计这也是 cuda __syncwarp() 的来历，不过我认为 compiler 同样可以缓解这个问题，例如如果能够证明下个 join point 一定能够合并的话，将 WAIT 指令替换为 \_\_syncwarp 之类的）。
  
* 接下来考察 memory，ventus gpu 里面也有 global / share / private memory 这些概念，private memory 是指线程专属的 memory，实际上的存储位置和 global memory 一致，只是计算地址的方式稍微有些不同
  * share memory 在片上有独立的一块存储，占用地址空间中 0 - share memory size 这一块。因此 lsu 通过地址来区分访问的是 off-chip 还是 on-chip
  * 在指令层面上对区分 global / private memory。VLW 系列指令访问私有内存，而 VLW12 系列指令访问全局内存。具体访问私有内存的计算公式为 `Addr=(vs1+imm)*num_thread_in_workgroup+thread_idx+csr_pds`，这个公式不完全对，不过大概是那么回事。每个 workgroup 都有一个 csr_pds，表示访问私有内存时的偏移。在 workgroup 内部，给定一个 4 bytes 对齐的地址 A，每个 thread 在 A 处的 4 bytes 是在物理上连续的，然后物理上下一个 4 bytes 是下一个 thread 在 A 地址的内容。。。大概私有内存的排布是这么一回事。
  * 总的来说，ventus gpu 提供的访存指令总共有这么几类：
    * 一个是标量访存指令，操作标量寄存器和内存
    * 然后是 rvv 中的访存指令，ventus 实现了 sew=32 的单位步长，固定步长，ordered index 这三类基本的访存指令（为什么要 ordered），**不过语义和 rvv 中的定义稍微有点不一样。例如这里基址寄存器是一个向量寄存器，步长也是一个向量寄存器（感觉上语义和下面的自定义访存指令有点重合了）**
    * 然后是自定义的访存指令，就是讨论 global / private memory 时提到的 VLW / VLW12 系列指令。
    * **另外原子访存指令我没细看**
  
* 另一个重点对象是 CTA scheduler，这里面模块挺多的，并且每个模块的逻辑都可以切分为 alloc 和 dealloc 两部分。对于 alloc 的逻辑
  * `inflight_wg_buffer` 中的 host 状态机负责接收 host 请求，并将相关数据写入 `ram_wg_waiting_allocation` 和 `ram_wg_ready_start` 两个数组（它们存放着 host 请求数据的不同部分，但都存入了 wg_id 作为标识）。同时维护这 valid 和 pending 两个 bitmap，一个 host 请求会将 valid bitmap 某一位拉高。
  * `inflight_wg_buffer` 的 alloc 状态机选择待处理的 host 请求（即某一位在 valid bitmap 中拉高了，但没有在 pending bitmap 中拉高），拉高对应的 pending 位，同时拉高 `wg_buffer_alloc_valid` 信号。表示向 `dis_controller` 请求启动 alloc 流程。`dis_controller` 拉高 `start_alloc` 信号表示回应，此时 alloc 流程启动
  * 当 `start_alloc` 被拉高时，`allocator_neo` 会检查 host req 中请求分配的各项资源（寄存器，共享内存的地址范围等等），看能否找到一个 CU 满足，检查完毕后，拉高 `alloc_cu_valid` 信号，如果分配失败，则同时拉高 `allocator_cu_rejected` 信号。我们区分本次 alloc 是否被 reject 进行讨论
  * 如果 alloc 被 reject 了，那么 `dis_controller` 拉高 `wg_rejected_valid` 信号一个周期，并重新回到 IDLE 状态。而当 `inflight_wg_buffer` 发现 `wg_rejected_valid` 被拉高后，将其对应的 pending 位拉低（因此该请求又会被 `inflight_wg_buffer` 视为待处理的，但选择请求时采用了 round robin 的方法，因此如果有多个待处理请求，该请求的优先级会更低）。
  * 如果 alloc 被接收了。那么 `dis_controller` 会拉高 `wg_alloc_valid` 一个周期，并将 `cu_groups_allocating` 中对应的 res table number 位拉高，表明该编号的 res table 正在处理 alloc 请求，然后回到 IDLE 状态（因此该 scheduler 理论上可用同时处理多个 alloc 请求，只要选择不同的 res table 进行资源分配，但目前其实只支持一个 res table）。这个 `wg_alloc_valid` 会被 `inflight_wg_buffer`，`top_resource_table`，`gpu_interface` 三个模块接收，下面分别说这三个模块的动作
  * `inflight_wg_buffer` 发现 `wg_alloc_valid` 拉高后，会清除该请求对应的 valid, pending bitmap 位拉低，同时拉高 `wg_buffer_gpu_valid` 一个周期，将 `ram_wg_ready_start` 数组中保存的该请求的其余数据输出（这些数据与检查 alloc 是否能被满足无关，因此放到这一阶段才输出，虽然我觉得完全没什么必要）。
  * `gpu_interface` 发现 `wg_alloc_valid` 和 `wg_buffer_gpu_valid` 都拉高过之后，就可用把 host 的请求数据传递给 `allocator_neo` 选择的 CU 了（每次握手成功发送一个 warp）。
  * `top_resource_table` 发现 `wg_alloc_valid` 后会将该请求占用的资源记录下来，完成后拉高 `grt_cam_up_valid` 信号，同时输出剩余可用的资源给 `allocator_neo`（这一部分等下还会解释）。对于 alloc 流程，还会额外拉高 `grt_wg_alloc_done` 信号。
  * `allocator_neo` 发现 `grt_cam_up_valid` 拉高后，记录剩余可用的资源，用于下一次分配
  * `dis_controller` 发现 `grt_wg_alloc_done` 信号拉高后，清除 `cu_groups_allocating` 对应 bit，标志着该 alloc 请求彻底完成
  
* 额外解释一下 CTA scheduler 中对资源的管理，核心是 sharemem，scalar register，vector register，free warp slot 这几个。host 每次向 gpu 申请运行一个 workgroup，会告诉 scheduler 该 workgroup 总共需要的 sharemem, sreg, vreg, warp 数目，`allocator_neo` 就是判断这些要求是否满足（我看 host 还提供了 globalmem size，以及 private mem base 之类的，不过这些和分配好像没什么关系）。实际上 `resource_table` 中维护了一个双链表，链表中每个节点保存了一块分配出去的资源（比如对于 reg 来说，就是起始的 reg id 和 size）。每一次分配完成后，就会更新双链表，插入一个新的节点，然后重新扫描整个双链表，找到最大的一块连续的未分配出去的资源，告诉 `allocator_neo` 这块资源的起始地址和大小，因此 `allocator_neo` 可以很快判断该次请求能否满足（虽然这种分配算法不一定是最优的）。

* 再简单说一下 dealloc，CTA scheduler 传递给 CU warp 请求时，有一个标识符 `dispatch2cu_wf_tag_dispatch`，它的高位表示该 warp 所在的 workgroup 使用的 slot，低位表示 warp id。CU 执行完一个 warp 后，会将该标识符回传。每回传一次，`gpu_interface` 中对应 workgroup 的计数器减一，减到 0 之后 `gpu_interface` 拉高 `dealloc_available` 信号。`dis_controller` 接受该信号后，拉高 `wg_dealloc_valid` 信号， 此时 dealloc 过程开始。主要有两个模块响应，一个是 `top_resource_table` 回收它占用的资源（将节点从双链表中删除），然后更新可分配资源给 `allocator_neo`，另外是 `inflight_wg_buffer` 将执行完毕的 workgroup 的 id 告知给 host。

* 对资源管理进行额外的补充说明：CTA scheduler 中分配资源是以 workgroup 为单位，`gpu_interface` 最后将计算命令以 warp 为单位传递给 CU 时，每个 warp 得到的 sreg base 和 vreg base 是不一样的，具体的公式是 `warp_reg_base = workgroup_reg_base + warp_id * use_reg_number_per_warp`。因为寄存器存储通常会划分为多个 bank，这里要求 `workgroup_reg_base` 和 `use_reg_number_per_warp` 都是 bank 数目的倍数。在 `operand collector` 中实际访问寄存器存储时，`bank_id = (warp_id + warp_reg_base + regIdx) % bank_number`，`index = (warp_reg_base + regIdx) / bank_number`。值得注意的是在计算 bank_id 时，额外加入了 warp_id 进行偏移，在 gpgpu architecture 一书的 3.3.1 节讲 operand collector 时也提到了这一点，这可以用来减少不同 warp 的 bank 冲突

  > The idea is to allocate equivalent registers from different warps in different banks

  这也是为什么前面提到 `workgroup_reg_base` 和 `use_reg_number_per_warp` 得是 bank 数目的倍数，不然在偏移时可能越过分配给这个 warp 的寄存器范围的边界。

## 一些代码细节的疑问

* `L1CacheMemReqArb` 这个类继承自 bundle，但里面包含了一些看起来不像 IO field 的字段，~~chisel 中是否有相应的字段进行区分？~~（从 bundle 类的注释看来，应该是只有类型为 Data 类型的子类的成员才会被算进去）
* `warp_schedule`中 warp_bar_exp 和 warp_bar_belong 这俩信号有啥区别
* 一个 SM 的计算能力到底有多大
* **operandCollector 中的 mask 信号，当指令为标量时，会 mask 掉除第一个 thread 外的所有 thread**，实际上传入 issue unit 的 mask 的值是 operand collector 收集的 mask（来自 v0 之类的）与上 simt_stack 输出的 mask。
* ~~在 scoreboard 中有一个 OpColReg，来记录该 warp 是否存在指令在 operand collector 中，如果存在的话，该 warp 暂时不能发射新指令，为啥有这一条规定呢？是希望指令能够按序发射吗？~~补充：在 gpgpu architecture 3.3.1 节中也谈到了这个问题，其实是因为 operand collector 没有办法保证发射顺序，所以可能会导致 WAR 冒险，即一条指令读寄存器 R1，先被发射到了 operand collector，后面一条指令要写 R1，也被发射到了 operand collector，后面的指令可能先执行写回了之后前面读的指令才读到 R1，就发生错误了。scoreboard 没有捕获到这个冒险是因为它只记录了这个寄存器要被写，而没记录被读（cpu 的 scoreboard 也是如此，顺序单发射时能保证同时只有一条指令在读寄存器）。
* 没看懂这个 ctrlSig 中的 writemask 和 readmask 有什么用
* ~~simt complete 信号如何产生，为啥在该信号拉高时也要清除 scoreboard 的 beq 寄存器~~：这个信号的意思对于一条 simt 分支指令，如果优先调度的是 not taken 分支，就不需要产生 branch_ctrl 指示 warp scheduler 调整 pc 了，因此拉高 complete 信号来指示 scoreboard 清除 beq 寄存器
* 在 lsu 中为啥要用一个 shiftboard 来限制 in-flight 的 req 数目呢？（和 fence 指令有关系吗，因为我看它在 shiftboard 为空时告知了 scoreboard fence 指令完成了）
  * 为啥访问 dcache 和 sharemem 时要求 warp 中各个 thread 访存地址的 setIdx 相同？（当不相同时会拆分为多个请求）
  * 而在 sharemem 一端，read 操作中处理 bankconflict 时是不是也有些问题？（见`一些我感觉是 bug 的地方`中的详细描述）
* CSR_KNL 是干什么的？

## 一些我感觉是 bug 的地方

* warp_schedule 会在 pc_ibuffer_ready 的时候（即 queue 中还有位置）发送 cache 访问，但由于 cache hit 了也需要 2 个周期，这周期间隔会导致 buffer overflow？
* warp_schedule_exp 和 warp_schedule_belong 感觉源码中整混乱了
* `ventus/src/L1Cache/ShareMem/BankConflictArbiter.scala`该文件中下面代码，迭代上限是 NLanes 而不是 NBanks，另外，io 中 port `dataCrsbarSel1H` 声明第一维应该为 NrLane  

```scala
  (0 until NBanks).foreach{ i =>
    ActiveLaneWhenConflict1H(i) := Cat(perBankActiveLaneWhenConflict1H.map(_(i))).orR}

    val dataCrsbarSel1H = Output(Vec(NBanks, UInt(NBanks.W)))
```

* 接上一条，sharememory 里面如果是 write 要等第二个 cycle 才处理，而 read 在第一个 cycle 就处理了**，另外 read 没有在 conflict 的时候重复读，为啥？**
* VLW_V 与 VLW12_V 这些指令是否有些功能上的重复？是否是设计上有问题的地方
* NUMBER_RES_TABLE 和 RES_TABLE_ADDR_WIDTH，前者默认值为 1，使得后者默认值也为 1，但 `dis_controller` 中默认使用 RES_TABLE_ADDR_WIDTH，导致它认为 NUMBER_RES_TABLE 为 2，这是否会有问题，感觉 NUMBER_RES_TABLE，RES_TABLE_ADDR_WIDTH，NUMBER_CU，CU_ID_WIDTH 这几个参数的关系乱七八糟的，比如在`dis_controller` 中的这个代码 `cu_groups_allocating(alloc_waiting_cu_id(CU_ID_WIDTH - 1, CU_ID_WIDTH - RES_TABLE_ADDR_WIDTH)) := true.B` 的索引是咋搞的
* `resource_table` 中的下面代码在 alloc_res_en 和 dealloc_res_en 同时拉高时是否会出现问题，因为 `res_addr_cu_id` 被放到 `dealloc_cu_id` 上去了，但后面的代码在这种情况下又会进入 `alloc` 的状态

```scala
  when(io.alloc_res_en) {
    alloc_cu_id_i := io.alloc_cu_id
    alloc_wg_slot_id_i := io.alloc_wg_slot_id
    alloc_res_size_i := io.alloc_res_size
    alloc_res_start_i := io.alloc_res_start
    res_addr_cu_id := io.alloc_cu_id
  }

  dealloc_res_en_i := io.dealloc_res_en
  when(io.dealloc_res_en) {
    dealloc_cu_id_i := io.dealloc_cu_id
    dealloc_wg_slot_id_i := io.dealloc_wg_slot_id
    res_addr_cu_id := io.dealloc_cu_id
  }
```

* `resource_table` 中规定了 `RES_TABLE_HEAD_POINTER_U`  和 `RES_TABLE_END_TABLE_U` 来标识链表的首位（即如果一个节点的 prev 值为 `RES_TABLE_HEAD_POINTER_U`，那么该节点是首节点。判定尾节点的方法同理），但实际上这两个值会作为 addr 使用？
* `NUMBER_LDS_SLOTS` 的值有问题。当 num_thread = 32 的时候才能和 sharemem size 对得上（所以我猜是忘改了）
* `dis_controller` 中 alloc 状态机 从 IDLE 状态跳走时就应该表示接受了该 alloc 请求才对，怎么同时还可以接受另一个 dealloc 请求，这实在是混乱邪恶，就很奇怪，`cu_groups_allocating` 的表项索引是 res_table_number，但是在 `allocator_neo` 中没有 res_table_number 这个概念（或者说 res_table_number 值为 1）。在决定是否要拉高 `start_alloc` 时依赖于 `cu_groups_allocating`  是否有空位，但最终选择哪个 res table 又依赖于 `allocator_neo`，但后者压根就没有 res_table_number 的概念。
* 在 `allocator_neo` 中，仅有当 `encoded_cu_found_valid` 拉高时才会暂停 pipeline，当实际上在资源分配 reject 的时候，`inflight_wg_buffer` 也会用到 `allocator_wg_id_out`，不暂停 pipeline 的话能保证输出的 `allocator_wg_id_out ` 是合理的吗？（好吧，是可以保证的，是因为输入的 `inflight_wg_buffer_alloc_wg_id` 是稳定的，但我觉得这样还是不好）

```scala
    when(encoded_cu_found_valid && !pipeline_waiting){
        pipeline_waiting := true.B
    }
```



## 设计考虑

* 在 GPGPU architecture 的 two loop approximation 中谈到，scoreboard 中可以不是每个 register 一个 bit，而是有若干个 entry 记录将要被写的寄存器编号，以此来减少存储占用。将这个实现在 ventus gpgpu 中？
* **gpu 的 collector unit 和 rvvcore 的 operand queue 有何异同，能否用 collector unit 替换掉 operand queue**
* gpgpu architecture 中提到的 control code 和 read dependency barrier ？和之前在知乎上看到的那篇讨论 maxwell 下 control code 的东西比较一下
* 把 rvv 的变长思想加入到 gpu 的 warp 里面会怎样？

## 其它

* 关于 warp split 与 deadlock 问题，https://stackoverflow.com/questions/6666382/can-i-use-syncthreads-after-having-dropped-threads，这个帖子讨论了 __syncthreads() 能否在 conditional 条件下使用，另外看看他贴的那篇论文，挺有意思的 https://www.stuffedcow.net/files/gpuarch-ispass2010.pdf
* ~~理解 indenpendent thread scheduling~~
* 注释的要点
  * 整体的架构是怎样的？
  * 每个模块的功能是怎么样的？
  * 每个变量的含义是什么？
  * 不要残留没有用的代码，会给看代码的人造成混乱