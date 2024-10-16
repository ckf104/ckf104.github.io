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
## 从辐射度量到人眼亮度

TODO：增加 $V(\lambda)$ 的描述，它是连接辐射度和亮度的桥梁，在 CIE 1931（XYZ color space）中，它是匹配函数 $Y(\lambda)$。虽然 pbrt4 4.6.1 节中讲到 $V(\lambda)=638Y(\lambda)$，但在 wiki 上谈到的 $V(\lambda)$ 是最大值归一化后的函数了，所以我这里说的是 $V(\lambda)=Y(\lambda)$

candela（cd）是发光强度的单位，luminous flux （cd sr）表示光通量，luminance（cd / m^2） 表示**单位投影面积**的发光强度

TODO：解释三个二维的归一化后的xy坐标+一个白光的xyz坐标能够确定一个色彩空间

从 [color matching function](https://zhajiman.github.io/post/color_matching_function/) 最大的 takeaway 是区分 color matching function 和 light emission function，前者积分的结果决定发出的光线中后者的份数，我觉得 pbrt4 中没有很好地区分两者，(4.24) 的推导是有些问题的，虽然后面的 RGB color space 的部分没啥问题

TODO：pixel sensor 中的白平衡，对于 xyz 色彩空间的白平衡，根据 [LMS color space](https://en.wikipedia.org/wiki/LMS_color_space) 中说的，Bradford，CAT02, CAT16 等转换就是将颜色从 xyz 空间转到 lms 空间。pbrt4 中用的是 Bradford 转换矩阵。pbrt4 中在进行 von Kries transform 之前先对 xyz 坐标的 Y 值进行了归一化处理，来保证 lightness 不参与

我不太理解的地方有两点：
* 为啥 target 是 output color space 的白色而不是 LMS color space 的白色（但这我觉得几乎没有差别吧，毕竟白色的定义基本都差不多，例如许多色彩空间都用 D65 来定义白色）
* 为什么会有不同的从 xyz 到 lms 的转换矩阵，按道理来说应该是固定的一个色彩空间转换矩阵？

[Standard illuminant](https://en.wikipedia.org/wiki/Standard_illuminant) 解释了 pbrt4 中 `Spectra::D` 函数从哪来的

[色彩空间基础](https://zhuanlan.zhihu.com/p/24214731)






然后我们来讨论 pbrt4 的输出文件与显示器参数
首先是显示器能显示的颜色范围：例如通常说的 99% sRGB，我认为就是显示器能显示的颜色覆盖到色品图上的 99% 的 sRGB 范围。而 8bit, 10bit 的颜色比特数主要与覆盖面积中的点的密度相关

然后上面这些只是色调（对应色品图上 x+y+z=1 这个平面），显示器参数中的亮度和对比度就表征了它能表示多亮和多暗的颜色。我猜测亮度中的 250cd/m^2 之类的应该是最大亮度吧。对比度的话有动态对比度（dynamic contrast ratio）和静态对比度（static contrast ratio）。根据 [Dynamic Contrast Ratio vs Static Contrast Ratio](https://www.reddit.com/r/AskReddit/comments/trqr7/dynamic_contrast_ratio_vs_static_contrast_ratio/)，静态对比度是指在同一帧中，最亮和最暗的像素的比值。而动态对比度是不限制在同一帧

>Dynamic contrasting works by lowering the power of the backlight on the TV making the whole image darker but simultaneously amplifying the few pixels which should be coloured/bright. This means it can adjust based on how dark the overall image is allowing you to see dark scenes better. But, the limit on how well you can see those scenes is the static contrast ratio; the system obviously can't do any better than this.

例如一些显示器会有开启/关闭动态对比度的选项，就是干这个事情的

下一个是 HDR，
TODO：如何用 OpenGL 渲染 HDR 图像，我看网上的做法基本都是使用 float framebuffer + tone mapping，感觉这里完全没用到显示器 HDR 的功能呢
TODO：png vs openExr，显示器参数中的亮度和对比度与色彩空间的关系是什么，它与 hdr, sdr 的关系是什么？静态对比度和动态对比度有什么区别
显示器的 gamma 值应该如何设置，它和 gamma 矫正的关系是什么

显示器设置中的色调，饱和度，亮度，对比度，色温等我觉得就理解为后处理的操作就行了