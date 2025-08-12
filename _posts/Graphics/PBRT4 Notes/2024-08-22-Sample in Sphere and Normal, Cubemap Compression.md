---
title: Sample in Sphere and Normal, Cubemap Comporession
math: true
date: 2024-08-22 16:13:27 +0800
comments: true
categories:
  - Graphics
---

## Sample in Disk and Sphere

为了在 disk 上均匀采样，pbrt4 中使用了论文 A Low Distortion Map Between Disk and Square 中的方法，该论文认为 inversion method 算出来的映射有较大的 distortion，而它的 concentric map 则更好地保持了原来的形状。这样的好处是，例如我们通过低差异序列来生成随机数，那么这些随机数之间会隔得尽可能地远，如果这个变换的 distortion 比较小，那么我们会认为变换后的随机数仍然会相互之间隔得比较远，保留了低差异序列的优良性质

说回具体的映射，它将正方形按照直线 $x = y$ 和 $x = -y$ 划分为四块，我们以角度在 $-\frac{\pi}{4}$ 到 $\frac{\pi}{4}$ 的正方形举例，它的映射为
$$
r = x, \phi = \frac{\pi}{4}\frac{y}{x}
$$
这样就把角度在 $-\frac{\pi}{4}$ 到 $\frac{\pi}{4}$ 的正方形映射为了角度在 $-\frac{\pi}{4}$ 到 $\frac{\pi}{4}$ 的圆盘。对于其它三块也可类似地定义映射。计算雅可比行列式验证可知，这个映射对于各处的面积缩放相同，对正方形的均匀采样就等价于在圆上均匀采样了。可以看到，在这个映射中，$x = a$ 的一条正方形边会被映射为角度在 $-\frac{\pi}{4}$ 到 $\frac{\pi}{4}$ 的圆弧，进而把一圈一圈同心的正方形轮廓映射为同心的圆，因此称为 concentric map，pbrt4 中对应的采样函数为 `SampleUniformDiskConcentric`

在圆盘上能够均匀采样后，取采样点沿着平面与半球的交点，就实现了 Cosine-Weighted Hemisphere Sampling，即采样半球上的点，并且采样概率与该点的天顶角的余弦值成正比。这是因为半球上的面积在平面圆上的投影面积大小正好与余弦值成正比。pbrt4 中对应的采样函数是 `SampleCosineHemisphere`

该论文还进一步讨论了如何将 uniform sampled disk 转换为 uniform sampled hemisphere。设圆盘上的采样点为 $(u,v)$，那么映射到半球上的采样点为
$$
\displaylines{
x = u \frac{\sqrt{1-z^2}}{r}\\
y = v \frac{\sqrt{1-z^2}}{r} \\
z = 1 - r^2
}
$$
其中 $r$ 是 $(u,v)$ 到原点的距离。这是半球上的均匀采样，因为对于半球上任意一个点，它的面积微元为 $dS$ 为
$$
dS = sin\theta d\theta d\phi = -dcos\theta d\phi = -dz d\phi = 2rdrd\phi = 2dudv
$$
因此这个映射的面积比固定为 2，能够将圆盘上的均匀采样映射到半球上的均匀采样。请注意这也是一个 low distortion 的变换，新的坐标 $(x,y,z)$ 在球坐标系中的方位角和原来圆盘上的坐标 $(u,v)$ 的方位角相同。因此这个映射将四分之一的圆盘映射到四分之一的半球面，这一映射关系在 [Fast Equal-Area Mapping of the (Hemi)Sphere using SIMD](https://fileadmin.cs.lth.se/graphics/research/papers/2008/simdmapping/clarberg_simdmapping08_preprint.pdf) 的 Figure 1 中展示得非常清楚

论文 [Fast Equal-Area Mapping of the (Hemi)Sphere using SIMD](https://fileadmin.cs.lth.se/graphics/research/papers/2008/simdmapping/clarberg_simdmapping08_preprint.pdf) 将这种方法推广到了 sphere 上去。想法就是在 [Octahedral Mapping](https://www.pbr-book.org/4ed/Geometry_and_Transformations/Spherical_Geometry#x3-OctahedralEncoding) 中，一个大正方形由两个小正方形拼出来，而我们已经有正方形均匀采样映射到半球的均匀采样了，现在两个小正方形各对应一个半球，汇总就得到了球上的均匀采样。代码中巧妙地使用绝对值避免分支挺有意思的。它对应 pbrt4 中的 `EqualAreaSquareToSphere` 函数

另外需要额外注意的是，对 w 进行采样和对 $\theta,\phi$ 进行采样得到的概率分布函数是不一样的。对于在球面上均匀采样的情况，
$$
\begin{aligned}
p(w) = \frac{1}{4\pi}
\\
p(\theta,\phi) = \frac{sin\theta}{4\pi}
\end{aligned}
$$
但这不会影响蒙特卡洛积分的结果。考虑 _hemispherical-directional reflectance_ 的计算
$$
\rho_{hd} = \int_{H^2(\boldsymbol{n})}f_r(p,w_o,w_i)|cos\theta_i|dw_i
$$
如果我们是对立体角 w 进行采样，那么一次采样的结果是 $\frac{f_r(p,w_o,w_i)|cos\theta_i|}{p(w)}$，而如果是对 $\theta,\phi$ 进行采样，则首先需要把 $dw_i$ 的微分换为 $d\theta,d\phi$, 这会多出一个 $sin\theta$，恰好与概率分布函数中多出的 $sin\theta$ 相抵消了
## Normal and Cubemap Compression
将正方形的均匀采样映射为球面的均匀采样的方法可以用来做 cubemap 的压缩。这样我们只需要一张贴图，而不是六张贴图来存储环境光。同时 cubemap 一直被诟病的非均匀映射的问题也得到了解决

然后是法线的压缩。由于法线模长为 1，使用三个浮点来存有些浪费了。很容易想到两种压缩方法
* 只存储 x, y 的值，可能需要额外的 1 bit 来存储 z 的符号
* 存储法线在球坐标系下的天顶角和方位角

方法 1 这需要额外的 1 bit 有些尴尬，并且两种方法的表示精度都有些不均匀，两种方法都是，极点附近的点有着最高的表示精度，而赤道附近的点表示精度最低

2010 年的论文 [On Floating-Point Normal Vectors](https://onlinelibrary.wiley.com/doi/epdf/10.1111/j.1467-8659.2010.01737.x) 最早地提出了 Octahedral Mapping 来做法线存储的压缩。在 [A Survey of Efficient Representations for Independent Unit Vectors](https://jcgt.org/published/0003/02/01/paper.pdf) 中 Octahedral Mapping 被认为是最佳的压缩方法。用 Octahedral Mapping 来做法线压缩的话，使用的映射方法和之前的均匀采样映射稍微有些不一样。我们首先使用 L1 范数归一化，找到球面上的点在八面体上的投影点，然后再将其投影到 xy 平面上，然后视该球面点的 z 坐标正负决定是否要再最后翻转一下 xy 坐标。具体的实现可参考 PBRT4 的 [OctahedralVector](https://www.pbr-book.org/4ed/Geometry_and_Transformations/Spherical_Geometry#x3-OctahedralEncoding)

虽然这个映射也不是均匀的，但是相比于前面两种方法 distortion 更少，并且编解码简单，不会像均匀映射那样涉及到三角运算
