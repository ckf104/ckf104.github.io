---
title: Radiance, Luminance and Color Space
date: 2024-10-09 18:14:25 +0800
comments: true
math: true
categories:
  - Graphics
---

## Solid Angle

总结一下立体角，主要参考 [立体角とガウスの発散定理](https://hooktail.sub.jp/vectoranalysis/GaussSolidAngle/)

从一维的角度推到二维上去：在平面上我们观察任意一条曲线张成的范围大小用角度来衡量，三维空间中任意一条曲线也可以类似处理，考虑任意一个定向曲面张成的范围大小：**曲面的立体角定义为曲面投影在单位球面上的面积**。那我们可以得到曲面立体角的计算公式
$$
\Omega=\iint_S\frac{\vec{r}\cdot d\vec{S}}{r^3}
$$
其中 $r$ 表示观察点到曲面微元的距离。这意味着，依据三维曲面的朝向，它的立体角可正可负。特别地，对于闭合曲面，根据高斯定理可知，如果当观察点在闭合曲面外时，立体角为 0，而当观察点在曲面内时，立体角大小为 $4\pi$

**立体角的积分**：我们可以定义函数 $f(\omega)$，这表示 $f$ 的取值仅依赖于 $w$ 的方向，然后我们可以取任意的立体角范围来考虑积分 $\iint_\Omega f(\omega)d\omega$，这里 $d\omega$ 是一个立体角微元，我们认为在一个微元大小里 $f(w)$ 近似保持不变，然后对整个大的立体角 $\Omega$ 积分

## PBR

在 pbrt4 的 [4.1 Radiometry](https://www.pbr-book.org/4ed/Radiometry,_Spectra,_and_Color/Radiometry) 中阐述了 PBR 中做出的一些假设：

* 光的属性只通过波长刻画，不考虑偏振光（pbrt4 的 4.1 节）
* 不同波长的光相互独立，不考虑 fluorescence（荧光） 或者 phosphorescence（磷光）这些现象中入射波长 A，但反射波长 B 的情况

> if radiance is given, then all the other values can be computed in terms of integrals of radiance over areas and directions. **Another nice property of radiance is that it remains constant along rays through empty space. It is thus a natural quantity to compute with ray tracing.**

上面的出自 4.1 节，标粗的地方让我有些困惑，[Why does radiance remain constant along rays of light through empty space?](https://physics.stackexchange.com/questions/177775/why-does-radiance-remain-constant-along-rays-of-light-through-empty-space) 也讨论了这个问题。困惑的点在于，考虑一个向外辐射的点光源，在与点光源距离 r 的球面上的点考虑 radiance 值，按照高赞回答的说法，固定单位面积不变，辐射通量和立体角都是以 $1 / r^2$​ 衰减的，因此 radiance 不变。但换种方法，如果固定单位立体角，随着距离增大，发现辐射通量不变，但面积却变大了，这说明 radiance 变小了

为什么会得出不同的结论？我目前的解释是，这样固定立体角去算有问题：对于空间中的一块面积，有两条路径可以去获得 radiance

* 一种是计算每个面积微元对辐射通量的贡献，然后再考虑这个面积微元的各个立体角微元对面积微元的辐射通量的贡献
* 另外一种是先考虑一个立体角微元对整块面积的辐射通量的贡献，然后再考虑这个立体角微元下单个微元面积对辐射通量的贡献

**前面的固定立体角计算 radiance 实际上是在采用第二种方法，但是除以面积时，各个面积微元对应的立体角微元方向其实是不一样的，所以这样算得到了错误的结果**

在 Radiometry 一节中定义的 flux，intensity，irradiance，radiance，包括材质 $f(p,w_i,w_o)$​，这些其实都隐含了一个波长项 ，为了得到实际的在一定波长范围的结果，还应当对波长进行积分，例如
$$
L(p,w) = \int_{\lambda_1}^{\lambda_2}L(p,w,\lambda)d\lambda
$$
## 色彩空间

从 [color matching function](https://zhajiman.github.io/post/color_matching_function/) 最大的 takeaway 是区分 color matching function 和 light emission function，前者积分的结果决定发出的光线中后者的份数。在 light emission function 确定后，通过实验测量能够获得它对应的 color matching function。我觉得 pbrt4 中没有很好地区分两者，(4.24) 的推导是有些问题的，虽然后面的 RGB color space 的部分没啥问题。我觉得 (4.24) 更正确的写法应该是
$$
\displaylines{
x = \int X(\lambda)S(\lambda)d\lambda \approx \int X(\lambda)(rR_e(\lambda)+gG_e(\lambda)+bB_e(\lambda))d\lambda
\\
=r\int X(\lambda)R_e(\lambda)d\lambda+g\int X(\lambda)G_e(\lambda)d\lambda+b\int X(\lambda)B_e(\lambda)d\lambda
}
$$由此我们得到
$$
\left[\begin{array}{l}x \\ y \\ z\end{array}\right]=\left(\begin{array}{lll}\int R_e(\lambda) X(\lambda) \mathrm{d} \lambda & \int G_e(\lambda) X(\lambda) \mathrm{d} \lambda & \int B_e(\lambda) X(\lambda) \mathrm{d} \lambda \\ \int R_e(\lambda) Y(\lambda) \mathrm{d} \lambda & \int G_e(\lambda) Y(\lambda) \mathrm{d} \lambda & \int B_e(\lambda) Y(\lambda) \mathrm{d} \lambda \\ \int R_e(\lambda) Z(\lambda) \mathrm{d} \lambda & \int G_e(\lambda) Z(\lambda) \mathrm{d} \lambda & \int B_e(\lambda) Z(\lambda) \mathrm{d} \lambda\end{array}\right)\left[\begin{array}{l}r \\ g \\ b\end{array}\right]
$$
这里的 $R_e,G_e,B_e$ 是这个 RGB 色彩空间的 light emission function
## 从辐射度量到人眼亮度
我们可以把颜色拆分成两部分，一部分是色相，表示颜色本身，另一部分是亮度，表示颜色的明亮程度。人们通过实验得到了[亮度函数](https://en.wikipedia.org/wiki/Luminous_efficiency_function)，下面的公式建立了辐射通量到光通量的桥梁$$
\Phi_{\mathrm{v}}=683.002(\operatorname{lm} / \mathrm{W}) \cdot \int_0^{\infty} \bar{y}(\lambda) \Phi_{\mathrm{e}, \lambda}(\lambda) \mathrm{d} \lambda
$$其中 $\bar{y}(\lambda)$ 就是亮度函数。它的函数最大值被归一化到 1。在 CIE 1931（XYZ color space）中作为匹配函数 $Y(\lambda)$。因此对于颜色我们通常有两种表示方式，一种是 xyz 形式，表示该颜色在 XYZ 色彩空间的坐标。另一种是 xyY 形式，这里的 xy 对应原来的 xyz 坐标归一化到 $x+y+z=1$ 的平面后的 xy 坐标，对应色相，而这里的 Y 表示原来的 y 坐标，对应亮度
## 白平衡

TODO：pixel sensor 中的白平衡，对于 xyz 色彩空间的白平衡，根据 [LMS color space](https://en.wikipedia.org/wiki/LMS_color_space) 中说的，Bradford，CAT02, CAT16 等转换就是将颜色从 xyz 空间转到 lms 空间。pbrt4 中用的是 Bradford 转换矩阵。pbrt4 中在进行 von Kries transform 之前先对 xyz 坐标的 Y 值进行了归一化处理，来保证 lightness 不参与

我不太理解的地方有两点：
* 为啥 target 是 output color space 的白色而不是 LMS color space 的白色（但这我觉得几乎没有差别吧，毕竟白色的定义基本都差不多，例如许多色彩空间都用 D65 来定义白色）
* 为什么会有不同的从 xyz 到 lms 的转换矩阵，按道理来说应该是固定的一个色彩空间转换矩阵？

color chart 与 white balance adjustment，三个核心问题
* 有了 color chart 后，算法具体如何工作？pbrt 中采取的方式是找到一个矩阵，使得它将当下场景中白平衡光源照射 color chart 得到的颜色映射为标准白光照射 color chart 得到的颜色
* 为什么在 xyz 空间的构造函数不使用这个方法，而是使用 von Kries transform？
* 为什么 sensor 到 xyz 的色彩空间转换不采用矩阵的方式，而是定义了一个优化目标？

[Standard illuminant](https://en.wikipedia.org/wiki/Standard_illuminant) 解释了 pbrt4 中 `Spectra::D` 函数从哪来的

TODO：有必要看看 UE 后处理中白平衡的实现
## 显示器相关

现在我们应用对色彩空间的理解看看显示器的各项参数

首先是显示器能显示的颜色范围：例如通常说的 99% sRGB，我认为就是显示器能显示的颜色覆盖到色品图上的 99% 的 sRGB 范围。而 8bit, 10bit 的颜色比特数主要与覆盖面积中的点的密度相关

然后上面这些只是色调（对应色品图上 x+y+z=1 这个平面），显示器参数中的亮度和对比度就表征了它能表示多亮和多暗的颜色。我猜测亮度中的 250cd/m^2 之类的应该是最大亮度吧。对比度的话有动态对比度（dynamic contrast ratio）和静态对比度（static contrast ratio）。根据 [Dynamic Contrast Ratio vs Static Contrast Ratio](https://www.reddit.com/r/AskReddit/comments/trqr7/dynamic_contrast_ratio_vs_static_contrast_ratio/)，静态对比度是指在同一帧中，最亮和最暗的像素的比值。而动态对比度是不限制在同一帧

>Dynamic contrasting works by lowering the power of the backlight on the TV making the whole image darker but simultaneously amplifying the few pixels which should be coloured/bright. This means it can adjust based on how dark the overall image is allowing you to see dark scenes better. But, the limit on how well you can see those scenes is the static contrast ratio; the system obviously can't do any better than this.

这种提升动态对比度的技术是全局调光，例如一些显示器会有开启/关闭动态对比度的选项。另外一种能提升静态对比度是局部调光（Local Dimming）
#### Gamma Correction
然后我们来讨论一下 gamma 校正，[What and Why is Gamma Correction in Photo Images?](https://www.scantips.com/lights/gamma2.html) 挺有意思，作者反复强调了 gamma 校正和与人眼对暗处的变化更敏感这件事是无关的，虽然我觉得还是有些关系就是了

总的来说，现在还要做 gamma 校正主要是因为历史原因，因为 CRT 的非线性，所以数据先乘以 1/2.2 的幂次后再传给显像设备。虽然细想稍微有一些奇怪，因为为啥这一层不在 CRT 设备里面做呢，这样就把非线性的事情给对外屏蔽掉了，可能的解释是早期的设备做这种事比较费吧，还是让计算机提前做了比较好。但现在的显示设备已经是线性的了，所以现在的显示器会将收到的非线性的 sRGB 值又转回线性的 sRGB 值再进行显示（例如许多显示器可以设置进行 gamma 校正的指数大小）

另外一个理由是人眼对亮度的敏感度的非线性。虽然作者反复强调和这个没有关系，但他假设的前提是传输的 bit depth 和显示的 bit depth 相同。例如我们假设传输和显示的 bit depth 都是 8 bits，那来回 gamma 校正确实没啥用。但如果传输的是 8 bits，而显示的是 10 bits，就不一样了，因为乘以 2.2 次方颜色普遍变小了，因此更多的颜色落在了暗处的位置，我们更好地利用了暗处位置的编码空间。一个相似的逻辑是在 OpenGL 中使用 sRGB 纹理，因为采样的结果会转为 32 bits 的浮点参与 shader 的计算，因此我们的 8bits 编码为偏暗的颜色保留了更高的精度

OpenGL 中与 sRGB 相关的有两处，一个是刚刚提到的 sRGB 纹理，在这种情况下对纹理采样时首先会将储存的非线性空间值转到线性空间再传递给 shader。另外是 framebuffer 的 color attachment，如果我们使用 `glEnable(GL_FRAMEBUFFER_SRGB)`，那么 OpenGL 会假设 shader 写入的结果是线性的，它会做 gamma 校正转到非线性然后再存到 render target 中。默认情况下这个是不开启的，意味着需要我们自己在 shader 中手动做 gamma 校正

类似地，在 pbrt4 中，如果生成图片的格式是 png 的话，它也需要将 integrator 计算出的线性颜色进行 gamma 校正，因为 png 文件中存储的是非线性的 sRGB 值。gamma 校正的实现见 `src/pbrt/util/color.h` 中的 `LinearToSRGB` 函数
#### HDR
然后是 HDR 相关的概念，参考了一下
* [reddit: Whats the difference between HDR10, HDR10+ HDR400, HDR600?](https://www.reddit.com/r/Monitors/comments/hwdwtf/whats_the_difference_between_hdr10_hdr10_hdr400/)
* [不严谨的HDR科普：十分钟弄懂HDR显示和HDR调色](https://zhuanlan.zhihu.com/p/348100007)
* [HDR学习笔记（一）：动态范围与传递函数](https://zhuanlan.zhihu.com/p/624292553)
总的来说，HDR10 以及 HDR10+ 是针对 HDR 内容的通信协议，而 DisplayHDR400，DisplayHDR600 等是 VESA 制定了显示器性能的认证，包含了静态对比度，最大亮度，色域等的要求。具体的各项要求可以查看 [Summary of DisplayHDR Specs under CTS 1.2](https://displayhdr.org/performance-criteria/)

[不严谨的HDR科普：十分钟弄懂HDR显示和HDR调色](https://zhuanlan.zhihu.com/p/348100007) 中描述 color bits depth 和动态范围（dynamic range）的关系时做的比喻非常巧妙。我们想象一把尺子，动态范围就对应尺子的长度，而 color bits depth 就对应尺子的刻度。color bits 越多，尺子上的刻度就越密集，颜色的过渡就更平滑。color bits depth 不变时动态范围越大，尺子上各个刻度的间隔就越大。自然界场景的亮度分布非常广泛，但显示器没办法表示这么宽泛的亮度范围，将自然界的亮度范围调制到显示器的亮度范围的过程就是所谓的 tone mapping

在 OpenGL 渲染中，所谓的 HDR 工作流通常是使用一个 float16 精度的 framebuffer，这使得 shader 的输出颜色能够超过 1，然后再利用 tone mapping 将颜色又压缩回 1，最后做一个 gamma 校正，再把结果传递给显示器。这里的 tone mapping 通常会有一个曝光参数（感觉是从摄影里来的一个概念），一个低的曝光参数意味着它对明亮区域更加友好，输出的结果能较好地显示明亮区域的细节。而高曝光参数则更好地显示黑暗区域的细节

TODO：上面的表述还是有些模糊，主要我也不理解细节。要进一步理解需要回答下面两个问题：

第一个问题是显示器是如何看待收到的 8/10bits 三元 RGB 组，这个又如何转化为屏幕亮度呢？首先，每个显示器的色调，饱和度，亮度，对比度，色温等可以设置。那大概的流程应该要做一个 gamma 校正的逆变换，然后再根据此时显示器的设置将每个 sRGB 值映射到一个亮度上（这可以看作是 tone mapping 的逆变换）。在 SDR 流程中，在渲染阶段的 tone mapping 和显示器内部做的 tone mapping 的逆变换并没有一个约定。但在 HDR 流程中，显然是需要一个约定才能发挥 HDR 的效果的。根据 [HDR学习笔记（一）：动态范围与传递函数](https://zhuanlan.zhihu.com/p/624292553) 中的解释，这里有一个光电转换函数，电光转换函数的概念，前者将线性的光照编码到 0 到 1 的非线性的空间，而后者是逆变换，将其还原为原始的线性光照。对于 SDR，我们可以认为 gamma 校正的函数就是光电转换函数。而在 HDR10 协议中，使用 [PQ](https://en.wikipedia.org/wiki/Perceptual_quantizer) 函数作为光电转换函数，从 PQ 函数的定义我们也可以理解为什么说 HDR10 最高支持 10000 nit 的亮度

这也可以解释为什么 DisplayHDR600 的静态对比度要求是 8000。套用之前的比喻，如果尺子上的刻度间隔是线性的话，10 bits 的 color bits depth 最多只能表现出 1024 的静态对比度，但光电转换函数是一个非线性的函数，因此尺子上的刻度随着值的增大是越来越稀疏的

第二个问题是 HDR 内容是什么，HDR10 协议规定了些什么，GPU 和显示器通信除了传递 8/10bits 的三元 RGB 之外还需要传递其它什么东西吗。有关 HDR10 协议的细节有必要参考一下 [High-dynamic-range television](https://en.m.wikipedia.org/wiki/High-dynamic-range_television)

#### Dithering
 最后我们讨论 dithering 这个概念，[GL_DITHER 抖动算法](https://blog.csdn.net/GrimRaider/article/details/7449278) 讲得很好，可以将 dithering 理解为是一个将 color bits 更多的图像转化为 color bits 更少的图像的算法比较好。它的核心想法就是人眼会自动地对颜色进行融合，例如颜色 1 和 3 在远处看就融合成 2 了。这就能解释常见的 6 抖 8，8 抖 10 的概念了。例如 6 抖 8 我认为就是显卡发送的是 8 bits 数据，然后显示器这边只能做 6 bits 显示，就通过 dithering 算法，将 8 bits 的颜色抖为 6 bits 颜色（不太确定 dithering 应该发生在显卡侧还是 显示器侧）