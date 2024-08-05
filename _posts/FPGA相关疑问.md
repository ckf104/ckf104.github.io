## CLOCKING

* mixed-mode clock manager (MMCM) vs phase-locked loop (PLL)，它们是干什么的？
* RTL设计对应到物理实现的资源开销有多大？功耗？时延？如何估计？
* ~~异步的 reset 是如何避免亚稳态的？~~（参考*Asynchronous & Synchronous Reset Design Techniques*，这篇详细解释了同步复位和异步复位的实现，具体异步复位中第二个触发器如何避免亚稳态的，分析上可以参考[马里奥理论](https://zhuanlan.zhihu.com/p/67511756)，要义在于，不管是触发器的保持时间，建立时间，还是复位时的恢复时间，去除时间（removal time），都是要避免两个蹲着的马里奥同时站起来（亚稳态），而第二个触发器的输入为低电平时，没有保持好 recovery/removal time 也不会陷入亚稳态（两个蹲子同时想站起来）。上面那篇英文的论文有点冗长，中文简洁版是[Reset深入理解](https://zhuanlan.zhihu.com/p/110866597)），另外两篇 [xilinx support blogs](https://support.xilinx.com/s/question/0D52E00006hpiy3SAA/demystifying-resets-synchronous-asynchronous-and-other-design-considerations-part-2?language=en_US) 也讲得挺好，主要很有启发的一点是 reset 打拍与 retiming 的结合，不需要细致地用 verilog 写出 reset tree，只需要给 reset 多打几拍，然后让工具自己做 retiming 就行了。
* retiming 介绍？
* ~~什么是 FPGA Global Set/Reset（GSR)~~，在每次 fpga configuration 时，GSR 信号 assert，在最后的 startup 阶段 deassert。这会将 fpga 上的存储单元复位为 initial state，值得注意的是，这并不一定是和自定义的 reset 信号的复位结果相同。控制 initial state 的是在声明信号是对其所赋的初值，因此可以选择该初值和 reset 信号复位的值不一样。例如 7 series 中 FDPE, FDRE 等 primitives 都有 INIT attribute 设置其初值。在声明信号时不赋初值，那么初值和 reset 的值一样，见 ug470，ug474，ug953。
* ~~为什么需要 clock buffer 以及其它乱七八糟的 buffer，buffer 是如何实现的？~~，首先要搞清楚 buffer 在电路中的作用，这个 buffer 完整地应称为 voltage buffer，用来将 high input impedance 的外部输入电路转化为 low input impedance 的输入提供给负载。通常用于驱动后面连接的大电容的负载（drive strength: 给电容充电速度越快，drive strength 就越强，通常的做法是使用更大的晶体管来减小 input impedance，或者使用更高的电压）。clock buffer 和其它的普通 buffer 最显著的区别在于 clock buffer 得保证 fall time 和 rise time 尽可能地相等，来满足 flip-flop 的 minimum pulse width 的要求。一种简单的实现是用反相器，但是反相器中的 PMOS 的大小是 NMOS 的两倍多？**因为 相同大小的 PMOS 和 NMOS，PMOS 的电阻更大，导致 rise time 会大于 fall time？**

## Analog Circuits

### 第一讲：PN结

* 掺杂donor P时，P元素中的电子所在的最高的能级与 Si 的导带很接近，因此 P 元素的电子很容易电离到 Si 的导带中形成自由电子，从而导电（留下带正电的质子）。掺杂acceptor B时，B元素中所在的最高的能级与 Si 的价带很接近，Si 的电子很容易电离到 B 的最高能带中去，形成带负电的 B 原子，而在 Si 原来的能级形成空穴，使得电子有位置能够移动，从而导电。
* PN 结单向导电性：电流 P 到 N 是正向电流，多数载流子导电（电源像水泵一样，多数载流子通过扩散到达对面时能够被及时抽走），电流 N 到 P 是反向电流，少数载流子导电（电子从负极到达P区时与空穴结合，而N区的自由电子被电源抽走，导致形成更大的耗尽层）。 相比于多数载流子，少数载流子对温度更敏感（影响电离程度） --> PN结的反向饱和电流对温度敏感。

### 第二讲：PN结与二极管特性

* 齐纳击穿（发生在掺杂浓度高时，内建电场较强，温度越高，价电子的能量越高，需要的击穿电压更低），雪崩击穿（温度越高，少子浓度高，漂移运动影响电场建立，导致需要更高的击穿电压） ，导致温度升高，烧毁器件

### 第七讲：BJT相关

* 关于饱和区的理解：饱和区表示 $I_b$ 过大，乘以共射放大系数后的对应的电流 $I_c$ 超过了电源 $U_c$ 能输出的最大电流（因为有限流电阻的存在）。但我不是很懂这里发射结和集电结都正向偏置后为啥电流 $I_c$ 还是正的，这在集电结处不是电流从低电势流向高电势了？（但由于整体考虑，集电结+发射结还是高电势流向低电势，所以没问题？）

## 编译

* partial redundancy elimination: **为啥适用于循环不变量外提（是巧合？）**
* SSA相关术语
  * CSSA, TSSA: 见论文 Translating Out of Static Single Assignment Form
  * minimal/pruned/semi-pruned ssa: 见论文 Practical Improvements to the Construction and Destruction of Static Single Assignment Form
  * ESSA: extended ssa form?
* **关于公共子表达式消除 TODO**
  * Global Value Number
  * SSAPRE
  * GVN-PRE



## GEM5

* params参数机制如何实现的，如何把python参数传递给C++类，最奇怪的是，配置的python文件有些时候会定义新的attr，例如system类本来是没有cpu这个属性的，这种新的自定义属性是如何处理的？然后，proxy parameters是怎么一回事，parent.any咋弄的
* 在Sconscript中的simobject,source类接口是啥意思
* 在python 类的定义中，cxx_header, cxx_class, type 这几个 field 是干嘛的
* port的bind函数是什么时候被调用的，vector port 是怎么弄的
* ~~为什么simobject的子类的构造函数的params参数一会是常引用，一会又是指针~~（虽然网页上的教程用的指针，但代码中还是用的常引用）
* Request 和 Packet 这两个类？为啥需要两个类
* 目前出现了两种event，EventFunctionWrapper和AccessEvent。



关于 port 中需要实现的接口：

```c++
# 现在只考虑TimingProtocol，且不考虑snoop相关的
# 在TimingProtocol中，TimingRequestProtocol实现了sendReq函数，它做的事情就是调用
# TimingResponseProtocol的recvTimingReq函数，如果该函数返回false，表明包发送失败
# 因此在继承TimingRequestProtocol需要实现recvReqRetry函数，指明第一次req失败后，之后
# 收到ReqRetry时的行为，以及需要实现recvTimingResp函数，表明收到返回的packet时的行为
# 另外TimingRequestProtocol实现了sendRetryResp函数，即返回的packet被requester拒绝之后
# requester调用这个函数来请求responder重新发送返回的packet，这个函数内部就是简单调用responder的
# recvRespRetry函数

# TimingResponseProtocol则恰好相反，它已经实现了sendResp和sendRetryReq，需要实现
# recvTimingReq函数和recvRespRetry函数
class TimingRequestProtocol:
	bool sendReq(TimingResponseProtocol *peer, PacketPtr pkt); // 已实现
	void sendRetryResp(TimingResponseProtocol *peer);         // 已实现
	virtual bool recvTimingResp(PacketPtr pkt) = 0;           // 没实现
	virtual void recvReqRetry() = 0;                         // 没实现

class TimingResponseProtocol:
	bool sendResp(TimingRequestProtocol *peer, PacketPtr pkt);  // 已实现
	void sendRetryReq(TimingRequestProtocol *peer);           // 已实现
	virtual bool recvTimingReq(PacketPtr pkt) = 0;            // 没实现
	virtual void recvRespRetry() = 0;                         // 没实现

# 可以看到，继承了RequestPort的子类仍然需要实现recvTimingResp和recvReqRetry函数
class RequestPort: public Port, public TimingRequestProtocol
    bool sendTimingReq();   // 对sendReq的简单封装
    void sendRetryResp();   // 对sendRetryResp的简单封装

# 可以看到，继承了ResponsePort的子类仍然需要实现recvTimingReq和recvRespRetry函数
# 此外，ResponsePort还需要实现一个额外的getAddrRanges函数，用来告诉ReqPort自己的地址范围
class ResponsePort : public Port, public TimingResponseProtocol
    bool sendTimingResp();  // 对sendResp的简单封装
	void sendRetryReq()     // 对sendRetryReq的简单封装
    virtual AddrRangeList getAddrRanges() const = 0;
```

关于 SimObject 的一些接口

```c++
class SimObject:
	// SimObject的getPort实现是直接引发异常，因此对于有port的子类，必须实现该函数
	virtual Port &getPort(const std::string &if_name,
                          PortID idx=InvalidPortID);
	// 该函数在模拟开始前被会调用，在SimObject中的实现为空函数
	virtual void startup();
```



