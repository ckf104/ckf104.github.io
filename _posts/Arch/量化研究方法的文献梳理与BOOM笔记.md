## 量化第三章：指令级并行
ILP 的两种实现方法
* 依靠硬件来动态发现并实现并行
* 依靠软件技术在编译时静态发现并行

流水线CPI = 理想流水线CPI +结构化停顿+数据冒险停顿+控制停顿。一些优化技术会对这个式子的一项或几项产生影响
![[Pasted image 20250315123231.png]]

3.2 节讨论了编译技术来静态地发现 ILP，通过指令调度来尽可能地隔离开有数据依赖的指令，并且循环展开可以扩大指令调度的范围，更好地利用 ILP
### 分支预测
branch 的分类
* 条件跳转，需要预测是否跳转，预测跳转地址（相对固定）
* 无条件跳转，预测跳转地址

分支预测的分类：
* 静态分支预测，动态分支预测？
* 预测是否跳转，预测跳转地址？
* 只依赖 pc 的预测，依赖指令编码的预测？
#### 1981 A STUDY OF BRANCH PREDICTION STRATEGIES
对当前的分支预测技术做了一个 servey，并提出了一些 refinement，只预测跳转或者不跳转，不预测跳转地址

静态分支预测方法
* 总是跳转或不跳转
* Refinement: 基于分支指令的 opcode 决定跳转或不跳转  --> 需要拿到指令之后再做判断
* 向后跳转的指令预测跳转，向前跳转的指令预测不跳转  --> 需要计算或者比较 pc，导致长延迟？

动态分支预测方法
* 维护一个定长的 table 里面保存了最近执行了且没有跳转的分支指令，当遇到一条新分支指令时，如果在 table 中预测不跳转，否则预测跳转。使用 LRU 策略替换 table 中的表项
* 为 ICache 中每条指令维护一个额外的 bit，表示该指令上次是否发生跳转。如果该指令新进入 cache，默认为跳转
* Refinement: 对 pc 地址进行哈希，哈希结果作为地址去访问 RAM，RAM 中每个表项保存了上一次是否发生跳转。预测是否跳转的结果和上一次相同（**Branch History Table**）
* Refinement：RAM 中使用 n bits 而不是 1 bits 来记录分支指令的历史（ n bits 饱和计数器），这样的好处是，例如大部分都是跳转的指令，偶尔会来一次不跳转。对于这种情况，2 bits 的饱和计数器只会有一次预测错误，但是 1 bits 的饱和计数器有两次预测错误
* Refinement：饱和计数器中的数值可以作为 confidence level。如果我们认为清理 issued mispredicted instruction 会有更大的 penalty 的话。可以允许 confidence 大的分支指令后面的指令 issue，但是不允许 confidence 小的指令 issue，这样能取得更好的性能

文章的评测使用 ADVAN，GIBSON，SCI2，SINCOS，SORTST，TBLLNK 这六个程序评估分支预测的准确率
#### 1991 Two-Level Adaptive Training Branch Prediction
每个分支有自己的 Branch History Register，表示该分支最近 k 次的分支结果，这些 Branch History Register 构成一个 History Register Table。然后有一个长度为 2 的 k 次方的 Branch History Pattern Table，每个表项是一个 n bits 的饱和计数器之类的分支预测器

要做分支预测时，首先用当前 pc 对 History Register Table 进行寻址，拿到该分支的前 k 次历史，再用这个对 Branch History Pattern Table 进行寻址，拿到一个饱和计数器，然后用它来预测分支结果。分支 resolve 后，更新相应的 Branch History Register 和 Branch History Pattern Table 表项

原论文还讨论了两次访问 RAM 对分支预测延迟的影响，提出了一种优化：在分支 resolve 后更新 Branch History Register 时，可以直接访问 Branch History Pattern Table 来获取预测结果。为每个 Branch History Register 增加一个 bit 保存该预测结果。这样在预测时只需要一次访问 RAM 就可以了

有意思的点在于它预测结果时是针对分支历史进行预测，但不区分这个历史来自哪个分支

文章的评测使用 SPEC 来评估分支预测的准确率
#### 1992 Improving the accuracy of dynamic branch prediction using branch correlation
重要的观察在于一个分支的结果不仅与自己的历史有关系，还可能和前面的分支的结果有关系。有可能一个分支的历史结果看起来是随机的，但是如果按照它前面的分支的结果的不同，将自己的分支历史划分为若干 subpath，每个 subpath 内部的历史可能就看起来有规律了

使用 M bits 记录 global branch history，然后 N bits 的饱和计数器，这称为 (M，N) schema。具体实现上，给定 branch history table 的大小，例如 1KB，以及给定 schema，例如 (8, 2)，我们就可以计算出使用的 pc 地址是多少位。在这个例子中就是 4 位的 pc 地址，然后寻址时使用 8 bits 的 global branch history 以及 4 bits 的 pc 地址，共 12 位寻址 branch history table 获取饱和计数器的值，然后进行分支预测

这个实现相比于 Two-Level Adaptive Training Branch Prediction，不需要做两次的 RAM 访问

文章的评测使用 SPEC 来评估分支预测的准确率
#### 1993 Combining Branch Predictors
主要是两个贡献，一个是提出了 gshare 预测器。它的重要观察在于不仅仅是 pc 地址，global history 也能够提供定位该 branch 指令在哪的信息，因此 Improving the accuracy of dynamic branch prediction using branch correlation 中将 global history bits 和 pc bits 拼接起来的做法有些信息上的冗余。在 gshare 预测器中，它将 global history bits 和 pc bits 的异或结果用来寻址，缩减了 RAM 的大小

第二个是提出了 combining branch predictor（又称为 tournament predictor），同时跑两个分支预测器（通常一个是 local predictor，根据本 branch 的历史结果进行预测，另一个是 global predictor，根据前面若干个分支的结果进行预测），然后每个 branch 有一个额外的饱和计数器，用来记录哪个分支预测器的准确率更高，最终的预测结果使用针对该 branch 准确率更高的分支预测器的预测

文章中发现使用 Two-Level Adaptive Training Branch Prediction 论文中的预测器作为 local predictor，gshare predictor 作为 global predictor，取得了最高的准确率

文章的评测使用 SPEC 来评估分支预测的准确率

Alpha 21264 中也使用了 tournament predictor。它的 local predictor  使用 Two-Level Adaptive Training Branch Prediction 中的分支预测器，1024 个分支表项，每个表项是 10 位的 local history，然后这个 10 位的 local history 用来索引 3 bits 的饱和计数器。然后有一个 12 bits 的 global history register。global predictor 用这 12 bits 的 global history 索引 2 bits 的饱和计时器（而不是 Combining Branch Predictors 中使用 gshare 作为 global predictor）。然后 predictor selector 也是使用 12 bits 的 global history 索引 2 bits 的饱和计时器（而不是 Combining Branch Predictors 中使用 branch pc 进行索引）
#### 2006 A case for (partially) tagged geometric history length branch prediction
这篇文章提出了 TAGE 预测器。它大概可以理解为级联多个不同历史长度的，并且有 tag 的 gshare 预测器进行预测

具体来讲，TAGE 预测器由一个不带 tag 的 default predictor 和 M 个依赖的历史长度成几何级数的带 tag 的 gshare predictor 组成。default predictor 只使用该 branch 的局部历史进行预测，并且没有 tag，因此提供一个基础的预测结果。如果假设 M 的值 为 8，且几何级数的公比是 2

#### 1984 Branch Prediction Strategies and Branch Target Buffer Design
提出了 Branch Target Buffer，使用 pc 地址来寻址 Branch Target Buffer，获取 branch 的目标地址

文章的评测使用 IBM 370 和 CDC 6400 等机器的 workloads 的 trace 来评估分支预测的准确率
#### 1991 Branch history table prediction of moving target branches due to subroutine returns
Branch Target Buffer 的不足是无法处理同一个分支跳转地址变化的情况。一个常见的情形是，函数 return 时，每次 return 到的地址可能是完全不一样的。该论文提出 Return Address Stack，在 call 指令时将返回地址压入 stack 中，return 时再取出栈顶的返回地址，使用该返回地址作为预测结果

TODO：如何将识别 call 和 return 指令识别出来呢？看看 BOOM 中是怎么做的
TODO：论文中使用了两个 stack，分别保存 return address 和 call target，使用 return address 做预测的前提是 call target 与 branch target buffer 中保存的 call target 与 stack 中的 call target 相同，有必要这样做吗？

文章的评测使用 SPEC 来评估分支预测的准确率

TODO：如何判断当前 pc 是否需要做分支预测，一种是 BTB 表项中有一个 tag，用来比对 pc 是否是分支指令。另一种是在 cache 中做初步的 decode，BOOM 中是怎么做的
TODO：BTB 在指令修改时的处理，如果指令发生了自修改会如何，以及上下文切换时如何 flush BTB
TODO：一个分支还没有 resolve，就需要预测下一个分支时，BOOM 是如何处理的，以及，是否会 speculatively 更新 branch history table 然后在 mispredict 的时候回退？