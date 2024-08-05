* 数字图像处理的图像检索部分课程回放，傅里叶变换推导，重新理解采样，像素，图像缩放（对于处理有形变的缩放如何理解，非均匀的采样吗）等等

  * $X(w)=\int_{-\infty}^\infty x(t)e^{-jwt}dt$
  * 逆变换 $x(t)=\frac{1}{2\pi}\int_{-\infty}^\infty X(w)e^{jwt}dw$
  * 离散形式 $x(t)=a_n\sum_{-\infty}^{\infty}e^{jnw_0t}$，$w_0$ 是信号 $x(t)$ 的角频率。其中 $a_n=\frac{1}{T_0}\int_{T_0}e^{-jnw_0t}$

  * 任意信号乘以周期的冲击函数（采样）的傅里叶变换是原函数傅里叶变换的周期平移（**注意，简单乘以一个平移的冲击函数得不到一个傅里叶变换的平移**）---> 采样定理
  * 对于图像复原，傅里叶频谱乘以二维的低通滤波，对应到空域上的卷积，由于冲击函数的存在，积分变成求和，所以原始的卷积是整个图像的值进行线性组合，但如果我们采用一个小的卷积图像（例如这个卷积图像只在3x3的面积内值非0，相信这个卷积核是一个低通滤波器），那么就得到通常我们看到的那种卷积形式了。
  * 傅里叶变换得到的信号的幅值和功率是什么关系
  * 什么是振铃现象？

* 高体论文，boom

* comopy
  
  * TODO：看 generate IR 相关的代码
  
  * debug 的支持？`line_trace` 不够，debug 代码最好能翻译到 verilog 中，并且有一些条件编译的选项可以关闭，进一步说，验证相关的支持？
  * 如何做联合仿真
  * 参数化？if else ?
  * pymtl 中这样的代码 `s.reg_incrs = [ RegIncr() for _ in range(nstages) ]` 能处理吗（右值不是 HDLObject）

### Current

* ATaggerInstance 是一个 actor，而 UTagger 是一个 component，它们是什么关系？
* UTaggedComponent 也是一个 component，它又是干嘛的

### Current

* 关注 cva6.py 的 cov 参数，它是如何做覆盖测试的？



**GatewayPorts yes 后才能做端口转发（不然服务器端口只会监听本地端口127.0.0.1）**

**使用 nc 做简单的 tcp 连接测试**

**GitLens 可视化比较分支**

**GitLens Blame，gitlens toggle file / line blame**

**git clone 时使用 ssh 协议比 http 协议更稳定，不容易中断**

TODO：scene view extension

* https://itscai.us/blog/post/ue-view-extensions/
* https://blog.csdn.net/u010281174/article/details/123806725

### Current

~~TODO：在 gameInstance 的构造函数中获取 cuda module 会导致打包失败，显示 cuda module 尚且未加载，为什么？~~

在打包时会创建 CDO 对象的，这会调用 gameInstance 的构造函数！**在 unreal 中将一些设置写在 C++ 的构造函数中是极其危险的事情**

### Current

cuImportExternalMemory，在设备 A 上调用这个函数 import  设备 B 上的 meory 报错 CUDA_ERROR_INVALID_DEVICE，为啥？

### Current

custom stencil 的事情在 鱼眼相机，CustomMeshComponent 上蹦了，为什么，以及鱼眼相机是怎么实现的

### Current

为啥我没找到 View 的大小在哪设置的？准确来说，为什么强制设置为 1024x1024 的纹理之后，viewPort 的设置仍然是对的？

### Current

如何在 ue shader 中转换屏幕坐标和世界坐标？看看 https://forums.unrealengine.com/t/how-to-convert-world-position-to-screen-uv-coordinate/458907。View.ScreenToTranslatedWorld 到底怎么用的？

[Unity 光照探针](https://docs.unity3d.com/cn/2021.1/Manual/LightProbes-TechnicalInformation.html)，ue 里面也有类似的，球谐函数的运用

### Current

试试 zsh？感觉比 bash 酷炫多了

### Current

ue 中是如何对半透明物体排序的？

### Current

ResX 和 ResY 为什么对 3Dgs 渲染的质量产生了影响？目前的解释是 niagara 渲染时有bug，读的是主相机的 resX 和 resY（默认取的 32，导致 niagara 渲染时取的很低的分辨率）

### Current

三维 LUT 图像迁移

### Current

View.PreViewTranslation 感觉是将相机平移到原点，但是我为什么没有在 view 这个 uniform 参数里找到这个成员呢

### Current

**我还没搞明白 UE 是怎么把 scale, rot, translation 揉到一个 Transfrom 矩阵里的**

### Current

使用高阶球谐系数导致粒子数目被截断，发现只需要减少 particle attribute 的数目就可以了（不是提前采样纹理得到每个粒子的球谐系数，而是在每个 update 阶段用到了再采样）。**目前猜测这样做解决了问题是因为 particle attribute 是通过 buffer 实现的，可能 buffer 的大小有限制？**

另外，据说排序精度 low 和 high 都是使用的 float16 排序的？

