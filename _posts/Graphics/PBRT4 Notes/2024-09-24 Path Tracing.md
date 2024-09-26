我们讨论 PBRT4 的第 13 章 Simple Path Tracer 和 Path Tracer 的实现
## Overview

Path Tracing 是一种求解渲染方程的算法。为了引出 Path，我们首先将立体角积分改为面积积分，定义
$$
\begin{equation} \tag{1}
G\left(\mathrm{p} \leftrightarrow \mathrm{p}^{\prime}\right)=V\left(\mathrm{p} \leftrightarrow \mathrm{p}^{\prime}\right) \frac{|\cos \theta|\left|\cos \theta^{\prime}\right|}{\left\|\mathrm{p}-\mathrm{p}^{\prime}\right\|^2}
\end{equation}
$$ 其中 $V\left(\mathrm{p} \leftrightarrow \mathrm{p}^{\prime}\right)$ 取值为 0 或 1，取 1 时表示两点间未被遮挡，因此渲染方程可重写为 _three-point form_$$
\begin{equation} \tag{2}
L\left(\mathrm{p}^{\prime} \rightarrow \mathrm{p}\right)=L_{\mathrm{e}}\left(\mathrm{p}^{\prime} \rightarrow \mathrm{p}\right)+\int_A f\left(\mathrm{p}^{\prime \prime} \rightarrow \mathrm{p}^{\prime} \rightarrow \mathrm{p}\right) L\left(\mathrm{p}^{\prime \prime} \rightarrow \mathrm{p}^{\prime}\right) G\left(\mathrm{p}^{\prime \prime} \leftrightarrow \mathrm{p}^{\prime}\right) \mathrm{d} A\left(\mathrm{p}^{\prime \prime}\right)
\end{equation}
$$ 其中 $\mathrm{p}^{\prime \prime} \rightarrow \mathrm{p}^{\prime}, \mathrm{p}^{\prime} \rightarrow \mathrm{p}$ 分别表示入射光线和出射光线。然后我们将上式反复迭代，即反复地将右边式子中 $L$ 替换为右式，得到
$$
\begin{equation} \tag{3}
\begin{aligned}
L\left(\mathrm{p}_1 \rightarrow \mathrm{p}_0\right)= & L_{\mathrm{e}}\left(\mathrm{p}_1 \rightarrow \mathrm{p}_0\right) \\
& +\int_A L_{\mathrm{e}}\left(\mathrm{p}_2 \rightarrow \mathrm{p}_1\right) f\left(\mathrm{p}_2 \rightarrow \mathrm{p}_1 \rightarrow \mathrm{p}_0\right) G\left(\mathrm{p}_2 \leftrightarrow \mathrm{p}_1\right) \mathrm{d} A\left(\mathrm{p}_2\right) \\
& +\int_A \int_A L_{\mathrm{e}}\left(\mathrm{p}_3 \rightarrow \mathrm{p}_2\right) f\left(\mathrm{p}_3 \rightarrow \mathrm{p}_2 \rightarrow \mathrm{p}_1\right) G\left(\mathrm{p}_3 \leftrightarrow \mathrm{p}_2\right) \\
& \quad \times f\left(\mathrm{p}_2 \rightarrow \mathrm{p}_1 \rightarrow \mathrm{p}_0\right) G\left(\mathrm{p}_2 \leftrightarrow \mathrm{p}_1\right) \mathrm{d} A\left(\mathrm{p}_3\right) \mathrm{d} A\left(\mathrm{p}_2\right)+\cdots
\end{aligned}
\end{equation}
$$
这个式子揭示了渲染方程解的形式。如果我们取 $\mathrm{p}_0$ 为摄像机屏幕上的点，$\mathrm{p}_1$ 为从 $\mathrm{p}_0$ 发出的光线与空间中物体的交点，那么上式表明待求的 radiance 等于所有长度的路径贡献的 radiance，右边式子的第 k 项就是所有长为 k 的路径贡献的 radiance。这就是 Path 的来历

求解积分自然会用到 Monte Carlo 方法，我们就需要对路径进行采样。最直接的做法是，为了估计长度为 k 的路径的 radiance 贡献，我们就在场景表面任取 k-1 个点，来构造一条长度为 k 的路径。但这样采样的效率很低，主要原因在于很有可能这样采样的路径有两个相邻的点互相不可见，即 $V\left(\mathrm{p} \leftrightarrow \mathrm{p}^{\prime}\right)=0$，因此这个路径对 radiance 没有贡献。一个更加高效的采样方法是，我们递推地构造路径，在取定点 n 后，对点 n 处的立体角进行采样，根据立体角方向投射出的光线与场景的交点确定路径中的下一个点。这样采样生成路径会更加高效（可以理解为一种重要性采样），最终生成的路径的概率函数可以用条件概率进行表示
$$
P\left(\mathrm{p}_k \rightarrow \cdots\rightarrow \mathrm{p}_1 \rightarrow \mathrm{p}_0\right) = P_w(\mathrm{p}_2|\mathrm{p}_0,\mathrm{p}_1)P_w(\mathrm{p}_3|\mathrm{p}_0,\mathrm{p}_1,\mathrm{p}_2)\cdots P_w(\mathrm{p}_k|\mathrm{p}_0,\mathrm{p}_1,\cdots,\mathrm{p}_{k-1})
$$
接下来考虑的问题是如何选择合适的 $P_w(\mathrm{p}_n|\mathrm{p}_0,\mathrm{p}_1,\cdots,\mathrm{p}_{n-1})$。根本上来讲，由于$$
L\left(\mathrm{p}_{n-1} \rightarrow \mathrm{p}_{n-2}\right)=L_{\mathrm{e}}\left(\mathrm{p}^{\prime} \rightarrow \mathrm{p}\right)+\int_A f_{\mathrm{p}_{n-1}}\left(\mathrm{p}_n \rightarrow \mathrm{p}_{n-1} \rightarrow \mathrm{p}_{n-2}\right) L\left(\mathrm{p}_n \rightarrow \mathrm{p}_{n-1}\right) G\left(\mathrm{p}_n \leftrightarrow \mathrm{p}_{n-1}\right) \mathrm{d} A\left(\mathrm{p}_n\right)
$$那么最佳的采样应该是根据 $fLG$ 值越大的方向，采样的概率越大，但 $L$ 是未知的，计算 $G$ 的值又需要计算交点。因此一个启发式的做法是根据 $f_{\mathrm{p}_{n-1}}\left(\mathrm{p}_n \rightarrow \mathrm{p}_{n-1} \rightarrow \mathrm{p}_{n-2} \right)$ 的值进行重要性采样，在大部分的场景中，这种采样方法能帮助我们找到 radiance 贡献更大的路径

额外需要注意的是，从 $(3)$ 式可以看出，路径中最后一个点需要打在光源上，否则该路径同样不会有 radiance 贡献，因此我们在采样路径最后一个点 $p_k$ 时，需要面向光源进行采样。如果不这样做，不仅会降低采样效率，而且也没办法处理方向光和点光源

此时我们采样 k-1 个点只能得到一条路径，实际上我们做得更好，在每产生路径上新的点后就面向光源进行一次采样，产生一条路径，这样我们每采样两个点就能得到一条路径。具体来说，当产生交点 $\mathrm{p}_1$ 时，我们面向光源采样，得到一条长为 2 的路径。然后产生交点 $\mathrm{p}_2$ 时，再面向光源采样，得到一条长为 3 的路径，以此类推。虽然这样会导致产生的不同长度的路径之间存在依赖性，但这个估计依然是无偏的。我们可以举个例子说明这一点，考虑下面的积分 $$
F = \int f(x)dx + \iint g(x,y)dxdy
$$
我们以分布 $p(x,y)$ 进行采样来估计 $F$ 的值，记 $p(x,y)$ 关于 $x$ 的边缘分布为 $p_m(x)$，那么我们先根据 $p_m(x)$ 采样一个 $x_0$，然后根据 $p(y|x)$ 采样一个 $y_0$，现在考虑 $F$ 的一种估计式 $$
F_1 = \frac{f(x_0)}{p_m(x_0)} + \frac{g(x_0,y_0)}{p(x_0,y_0)}
$$这个估计式是无偏的，因为 $$
\begin{aligned}
E(F_1) & = \iint (\frac{f(x)}{p_m(x)} + \frac{g(x,y)}{p(x,y)})p_m(x)p(y|x)dxdy
\\
& = \iint f(x)p(y|x)dxdy + \iint g(x,y)dxdy
\\
& = \int f(x)dx + \iint g(x,y)dxdy
\end{aligned}
$$ 即使 $f$ 和 $g$ 的采样点存在耦合。将这个思路应用到更高维的积分，更多项的求和上，就能说明我们的路径采样优化依然是一个无偏估计。在路径上每个点都面向光源进行一次采样的方法被称为 _next event estimation_，PBRT4 上的描述相对比较简略，[Rendering: Next Event Estimation](https://www.cg.tuwien.ac.at/sites/default/files/course/4411/attachments/08_next%20event%20estimation.pdf) 中讲得很好
## Simple Path Tracer

现在我们讨论 PBRT4 13.3 节中实现的 Simple Path Tracer。它的实现基本就是按照前面讨论的采样方法采样，然后把各个长度路径计算出的 radiance 求和汇总，作为最后的计算结果。但还有一些细节需要注意

首先是为了避免无穷求和，它设置了路径的最大深度。其次是在应用 _next event estimation_ 时，即使 BSDF 的重要性采样生成的路径击中了光源，也不能将这里的 radiance 贡献算进去，因为此时上一个点在面向光源采样时已经计算过该长度的路径的 radiance 贡献了，除非上一个点的 BSDF 是 specular 的，因为对于 specular BSDF，反射方向已经确定了，就没办法面向光源采样了（或者理解为，我们此时选择的面向光源采样的概率函数与 BSDF 重要性采样的概率函数相同）

另外就是当光线与场景没有交点时，需要采样环境光
## Path Tracer
Path Tracer 额外增加了以下的特性
* Multi Importance Sampling
* MIS Compensation and Incomplete PDF
* Russian Roulette
* Path Regularization

Path Tracer
MIS, Russian Roulette, path regularization
_next event estimation_ 是面向直接光源的重要性采样，而 BSDF 是面向间接光源的重要性采样，用 MIS 将它们结合起来
delta light 和 specular bounce 没有用 MIS 加权？ MIS 带来了一些耦合性，因为两条分别的采样路径的前 i-1 个点是完全相同的，但这和 Simple Path Tracer 那的耦合性完全一致，用条件概率分布去理解这一点就好了

面向光源采样怎么还提前退出了？没有吃到 Russian Roulette 的倍增所以没啥问题？
[Fix handling of interface materials in Path and SimplePath integrators](https://github.com/mmp/pbrt-v4/commit/cdccb71cb1e153b63e538f624efcc13ab0f9bda2)  ，这样修改的原因在于 shadow ray 测试的时候没有考虑 participating media 的情况，因此为了一致性，就直接把 participating media 的边界认为是一个镜面层了

没看懂为什么 allowIncompletePDF 在 Uniform Infinite Lights 中的用处以及它与 MIS 的关系
SampleLd 的调用也有个 if 包着的，咋没见将这个 SampleLd 中的采样提到这个 if 之前呢？以及 Russian Roulette 里也有个包在 if 里的 Sample1D