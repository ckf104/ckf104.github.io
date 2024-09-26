## Sample in Disk and Sphere

为了在 disk 上均匀采样，pbrt4 中使用了论文 A Low Distortion Map Between Disk and Square 中的方法，相比于根据 inversion method 算出来的映射，这种方法 distortion 更少。pbrt4 中对应的函数为 `SampleUniformDiskConcentric`。论文中进一步讨论了如何将 uniform sampled disk 转换为 uniform sampled hemisphere

论文 [Fast Equal-Area Mapping of the (Hemi)Sphere using SIMD](https://fileadmin.cs.lth.se/graphics/research/papers/2008/simdmapping/clarberg_simdmapping08_preprint.pdf) 将这种方法推广到了 sphere 上去。想法就是在 [Octahedral Mapping](https://www.pbr-book.org/4ed/Geometry_and_Transformations/Spherical_Geometry#x3-OctahedralEncoding) 中，一个大正方形由两个小正方形拼出来，每个小正方形对应一个半球，而每个小正方形上可以均匀采样，得到半球上的均匀采样，汇总就得到了球上的均匀采样。代码中巧妙地使用绝对值避免分支挺有意思的。它对应 pbrt4 中的 `EqualAreaSquareToSphere` 函数

在 pbrt4 的 A.5.3 中谈到了 Cosine-Weighted Hemisphere Sampling，即采样概率与平面法线夹角成正比，这个对应的实现是 `SampleCosineHemisphere` 函数。它利用 _Malley’s method_ 取巧地实现了（即发现半球上的面积在平面圆上的投影面积大小正好与余弦值成正比）

因为很多需要求解的积分都是带法线夹角这一项的，直观上 Cosine-Weighted Hemisphere Sampling 的概率分布函数与需要采样的函数更吻合，根据 importance sampling，我们会得到一个更小的方差

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