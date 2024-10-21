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
$$这个估计式是无偏的，即使 $f$ 和 $g$ 的采样点存在耦合。因为 $$
\begin{aligned}
E(F_1) & = \iint (\frac{f(x)}{p_m(x)} + \frac{g(x,y)}{p(x,y)})p_m(x)p(y|x)dxdy
\\
& = \iint f(x)p(y|x)dxdy + \iint g(x,y)dxdy
\\
& = \int f(x)dx + \iint g(x,y)dxdy
\end{aligned}
$$将这个思路应用到更高维的积分，更多项的求和上，就能说明我们的路径采样优化依然是一个无偏估计。在路径上每个点都面向光源进行一次采样的方法被称为 _next event estimation_，PBRT4 上的描述相对比较简略，[Rendering: Next Event Estimation](https://www.cg.tuwien.ac.at/sites/default/files/course/4411/attachments/08_next%20event%20estimation.pdf) 中讲得很好
## Simple Path Tracer

现在我们讨论 PBRT4 13.3 节中实现的 Simple Path Tracer。它的实现基本就是按照前面讨论的采样方法采样，然后把各个长度路径计算出的 radiance 求和汇总，作为最后的计算结果。但还有一些细节需要注意

首先是为了避免无穷求和，它设置了路径的最大深度。其次是在应用 _next event estimation_ 时，即使 BSDF 的重要性采样生成的路径击中了光源(或者与场景没有交点，我们可以认为这是击中了环境光），也不能将这里的 radiance 贡献算进去，因为此时上一个点在面向光源采样时已经计算过该长度的路径的 radiance 贡献了，除非以下两种情况
* 上一个点的 BSDF 是 specular 的，因为对于 specular BSDF，反射方向已经确定了，就没办法面向光源采样了（或者理解为，我们此时选择的面向光源采样的概率函数与 BSDF 重要性采样的概率函数相同）
* 这是光线的第一次弹射，即上一个点是摄像机平面，因为发出的光线的方向是确定的，我们不能在摄像机平面的位置进行面向光源采样（或者我们可以认为在摄像机平面发生了镜面反射，因此 Simple Path Tracer 的代码中将 `specularBounce` 的初始值设置为 `true`）

commit [Fix handling of interface materials in Path and SimplePath integrators](https://github.com/mmp/pbrt-v4/commit/cdccb71cb1e153b63e538f624efcc13ab0f9bda2) 新添了一点逻辑，它在光线穿过 participating media 后，会将 `specularBounce` 重新设置为 true
```c++
// Get BSDF and skip over medium boundaries
BSDF bsdf = isect.GetBSDF(ray, lambda, camera, scratchBuffer, sampler);
	if (!bsdf) {
        specularBounce = true;
        isect.SkipIntersection(&ray, si->tHit);
        continue;
    }
```
这其实是一个 hacking 的做法，原因在于面向光源采样时，判断光源上的采样点是否被遮挡的逻辑中并没有考虑 participating media 的影响，即如果只是跨越了 participating media 的边界，判断遮挡的逻辑也会简单认为光源被遮挡了。因此上面的代码就索性认为在跨越了 participating media 的边界时发生了镜面反射，来模拟面向光源采样失效的效果
## Path Tracer

Path Tracer 额外增加了以下的特性
* Multi Importance Sampling(MIS)
* MIS Compensation and Incomplete PDF
* Russian Roulette
* Path Regularization

我们首先从 MIS 说起，在 Simple Path Tracer 中，为了计算长度为 n 的路径的 radiance 贡献，我们在路径的最后一个节点面向光源进行采样，但因为 radiance 的值还依赖于 BRDF，面向光源采样没有考虑到 BRDF 的值对 radiance 的影响。而根据 BRDF 采样又忽略了光源在计算 radiance 中的作用。这就是 MIS 的用武之地了。在 Simple Path Tracer 中，如果 BSDF 产生的路径击中了光源，我们也不会将它的 radiance 贡献加进来。但现在我们会计算这个 radiance 贡献，并和在上一个点面向光源采样得到的 radiance 贡献进行加权平均。这实际上对应有两个概率密度函数，它们的采样数各为 1 的 multi sample model，PBRT4 中使用的权重函数为指数为 2 的 power heuristic

但在实际应用时有一些注意事项和 trick（在后面我们会讨论这些 trick 是否会对无偏性产生影响），为了叙述方便，我们称点光源和方向光源为 δ 光源
* 如果面向光源采样时采样到了 δ 光源，那么它们的加权值为 1。一种理解方式是，它们的概率分布是一个 δ 函数，从权重函数的表达式 $$w_{light} = \frac{p_{light}^2}{p_{brdf}^2+p_{light}^2}$$可以看出，当 $p_{light} \rightarrow +\infty$ 时，$w_{light} \rightarrow 1$
* 不对 uniform infinite light 使用 MIS，仅使用 BSDF 采样。即当面向光源采样时采样到 uniform infinite light 时，它的权重 $w_{light}$ 为 0，而在 BSDF 生成的路径上采样到 uniform infinite light 时，权重 $w_{bsdf}$ 记为 1。这样做的原因是，由于 uniform infinite light 是常量，在渲染方程中可以直接提到积分号外边，因此对它进行重要性采样没有意义，直接使用 BSDF 采样即可。PBRT4 中将这个 trick 称为 Incomplete PDF，因为它在光源采样中使用的概率函数恒为 0
* 和 Simple Path Tracer 一样，镜面反射时不能面向光源采样，因此 $w_{light}$ 为 0，而 $w_{bsdf}$ 为 1
* 路径长度为 1 的 radiance 贡献不会使用 MIS 加权平均，同 Simple Path Tracer 中的原因一样，我们认为在摄像机平面发生了镜面反射

在采样 Image Infinite Light 时，Path Tracer 中应用了 MIS Composation 技术，主要就是将原来的概率密度函数变得更尖锐了一些

在 Path Tracer 中还引入了 Russian Roulette，在光线发生弹射后，它通过概率决定继续追踪光线还是粗暴地将更长路径的 radiance 贡献直接记为 0。我们可以形式化它为 $M\left(\mathrm{p}_n \rightarrow \cdots\rightarrow \mathrm{p}_1 \rightarrow \mathrm{p}_0\right)$ ，表示在确定路径 $\mathrm{p}_n \rightarrow \cdots\rightarrow \mathrm{p}_1 \rightarrow \mathrm{p}_0$ 后，我们还继续产生路径下一个点的概率。这和在 Games101 中使用的 Russian Roulette 有一些区别，因为这里的概率 $M$ 不是常量，而可以依赖于我们选取的路径

直观上，如果当前路径的 β 值越小（即代码中的 beta 变量），继续追踪这条光线路径带来的收益就越小，我们放弃追踪的概率就越大，因此 $M$ 的值就越小。但每个采样的波长都有它的 β 值，因此 Path Tracer 中使用的采样波长中最大的 β 值作为 $M$ 的估计。另外一个实践上的 trick 是，计算 $M$ 时消除折射产生的 η 对 β 的贡献，因为在折射出物体后，又会回乘 1/η，就不要让 η 值对 $M$ 的估计产生干扰了

在讨论 Path Regularization 之前，我们先讨论它提出的背景。因为根据 BSDF 采样生成路径的概率不一定与间接光照的强度相匹配，有时候会导致大的方差，在屏幕上产生亮点。设想一个场景，光源是一个小圆盘，然后设想一条路径，它首先经过一个 lambertian material，因此在该处会在球面上按余弦值大小作为采样权重选取一个新方向。然后这个新方向撞上一个镜面反射材质，因此在这里没办法面向光源采样，然后镜面反射的方向恰好撞上这个小光源。由于此前的镜面反射，因此 MIS 的权重为 1，加上之前 lambertian material 近似均匀的采样，得到概率密度值很小，这导致我们最终估计出一个较大的 L，在屏幕上产生亮点

本质来讲，上面现象产生的原因还是根据 BSDF 采样时可能与间接光强度不匹配，lambertian material 材质是一种极端情况，它没有提供任何间接光强度的信息。我认为要从根本上解决问题需要 Path Guiding 之类的技术。相对来讲 Path Regularization 是一种简单的解决方案，它的观察在于，这个亮点产生的原因，还在于说路径中存在镜面反射，它导致了没有办法通过面向光源采样和 MIS 来降低 BSDF 上 radiance 的估计。因此 Path Regularization 就是在采样前将路径上的 BSDF 变得更粗糙一些

最后还有一件事。如果场景中有多个 infinite lights，代码中在面向光源采样时每次至多采样一个 infinite light，而根据 bsdf 采样时（即光线没有命中物体表面）会同时采样所有的 infinite lights，这样的不一致性是否会造成什么问题。我们可以等效地将场景中的 infinite lights 都合并为单个 infinite light，因此 bsdf 同时采样所有的 infinite lights 就等效为采样这合并后的 infinite light。而面向光源采样时采样单个 infinite light 就相当于对这若干个 infinite lights 求和的离散蒙特卡洛估计（见 [12.2 式](https://www.pbr-book.org/4ed/Light_Sources/Light_Sampling#eq:mc-sampled-sum)）。这也可以说是一个潜在的优化点，在初始化场景时，应该就把所有的 infinite light 合并，面向光源采样时也直接采样这个合并的 infinite light，这样方差会小一些
#### 无偏性分析

从前面的分析我们可以看到，如果 Simple Path Tracer 能够不限制路径的最大深度，无限求和直到收敛时，它是一个 radiance 的无偏估计。我们现在考虑 Path Tracer 中使用的 δ 光源对应的 δ 概率函数（虽然 Simple Path Tracer 也有 δ 概率函数，但它没有结合 MIS 使用），Incomplete PDF，镜面反射，Russian Roulette 这些技巧对无偏性是否会产生影响

最简单的是镜面反射，我们只需要在 power heuristic 给出的权重函数 $w_{light},w_{bsdf}$ 上略作修改，规定当 $\mathrm{p}_n$ 对应的 BSDF 为镜面反射时， $w_{light}(w|\mathrm{p}_n \rightarrow \cdots\rightarrow \mathrm{p}_1 \rightarrow \mathrm{p}_0)=0, w_{bsdf}(w|\mathrm{p}_n \rightarrow \cdots\rightarrow \mathrm{p}_1 \rightarrow \mathrm{p}_0)=1$ 即可，修改后的 $w_{light},w_{bsdf}$ 仍然满足权重函数和为 1 的约束

同样地对于 Incomplete PDF，我们规定如果当从 $\mathrm{p}_n$ 出发的 $w$ 方向击中的是 uniform infinite light，那么有 $w_{light}(w|\mathrm{p}_n \rightarrow \cdots\rightarrow \mathrm{p}_1 \rightarrow \mathrm{p}_0)=0, w_{bsdf}(w|\mathrm{p}_n \rightarrow \cdots\rightarrow \mathrm{p}_1 \rightarrow \mathrm{p}_0)=1$

接下来说明在 MIS 中使用 δ 函数也是无偏的。选定路径 $\mathrm{p}_{n-1} \rightarrow \cdots\rightarrow \mathrm{p}_1 \rightarrow \mathrm{p}_0$ 后，面向光源采样的部分的表达式的期望为 $$
\sum V(L_\delta,\mathrm{p}_{n-1})L_{\delta,e}(\mathrm{p}_{n-1})f(\mathrm{p}_{n-1},w_i,w_o)cos\theta+\int w_{light}(w_i)L_e(\mathrm{p}_{n-1},w_i)f(\mathrm{p}_{n-1},w_i,w_o)cos\theta dw_i
$$其中 $\sum V(L_\delta,\mathrm{p}_{n-1})L_{\delta,e}(\mathrm{p}_{n-1})f(\mathrm{p}_{n-1},w_i,w_o)cos\theta$ 项给出了点光源和方向光对 $\mathrm{p}_{n-1}$ 的 radiance 贡献，$V(L_\delta,\mathrm{p}_{n-1})$ 表示可见性约束，而 $L_e(\mathrm{p}_{n-1},w_i)$ 表示所有非 δ 光源的  radiance 分布。至于表达式的期望为什么是这样，我们可以将面向光源采样的步骤分为两步。我们首先以概率 $c$ 决定是否采样 δ 光源，如果是采样 δ 光源，那么这个采样给出了 δ 光源的期望估计，而如果是采样非 δ 光源，那么就给出了非 δ 光源的期望估计。加上 δ 光源的 $w_{light}=1$（如果同时有 BSDF 为镜面反射，应当取 $w_{light}=0$），我们就得到了上面的期望结果。而 BSDF 采样的 radiance 贡献的期望为 $$
\int w_{bsdf}(w_i)L_e(\mathrm{p}_{n-1},w_i)f(\mathrm{p}_{n-1},w_i,w_o)cos\theta dw_i
$$因为 BSDF 采样是不会采样到 δ 光源的，因此这里积分中的 $L_e(\mathrm{p}_{n-1},w_i)$ 同样是指所有非 δ 光源的  radiance 分布，这两个期望求和的结果正是我们需要求解的给定长为 n-1 的路径 $\mathrm{p}_{n-1} \rightarrow \cdots\rightarrow \mathrm{p}_1 \rightarrow \mathrm{p}_0$ 后的长为 n 的路径的 radiance 贡献。因此估计是无偏的

最后我们讨论 Russian Roulette 的无偏性。这个很容易看出来，因为在加入 Russian Roulette 之前，我们通过路径采样，得到长为 k 的路径的 radiance 的贡献期望为（我们记路径 $\mathrm{p}_k \rightarrow \mathrm{p}_{k-1} \rightarrow \cdots\rightarrow \mathrm{p}_1 \rightarrow \mathrm{p}_0$ 为 $PA_k$）
$$
\begin{aligned}
L_k &= \int w_{bsdf}(\mathrm{p}_k \rightarrow \mathrm{p}_{k-1}|PA_{k-1})P_{light}(PA_k)\cdot\frac{L\left(PA_k\right)}{P_{light}\left(PA_k\right)}d\left(PA_k\right)
\\
&+ \int w_{light}(\mathrm{p}_k \rightarrow \mathrm{p}_{k-1}|PA_{k-1})P_{bsdf}(PA_k)\cdot\frac{L\left(PA_k\right)}{P_{bsdf}\left(PA_k\right)}d\left(PA_k\right)
\\
&= \int L\left(PA_k\right)d\left(PA_k\right)
\end{aligned}
$$
其中 $L\left(PA_k\right)$ 的表达式已经由 $(3)$ 式给出。现在加入 Russian Roulette 后，此时 $L(PA_k)$  对应的采样概率为 $$
\displaylines{
P^{\prime}_{light}(PA_k) = P_{light}(PA_k){M(PA_1)}{M(PA_2)}\cdots{M(PA_{k-2})}
\\
P^{\prime}_{bsdf}(PA_k) = P_{bsdf}(PA_k){M(PA_1)}{M(PA_2)}\cdots{M(PA_{k-1})}
}
$$有 $$
\begin{aligned}
L^{\prime}_k &= \int w_{bsdf}(\mathrm{p}_k \rightarrow \mathrm{p}_{k-1}|PA_{k-1})P^{\prime}_{light}(PA_k)\cdot\frac{L\left(PA_k\right)}{P^{\prime}_{light}\left(PA_k\right)}d\left(PA_k\right)
\\
&+ \int w_{light}(\mathrm{p}_k \rightarrow \mathrm{p}_{k-1}|PA_{k-1})P^{\prime}_{bsdf}(PA_k)\cdot\frac{L\left(PA_k\right)}{P^{\prime}_{bsdf}\left(PA_k\right)}d\left(PA_k\right)
\\
&= \int L\left(PA_k\right)d\left(PA_k\right)
\end{aligned}
$$ 因此 Russian Roulette 不影响期望
#### 能量守恒分析

在我们渲染的场景中，光源时时不断地向场景中发出能量，另一方面，除开镜面反射等材质会完全反射掉入射能量外，大部分材质除反射外，都会吸收一部分能量，即$$
\int f_s(x,w_i,w_o)cos\theta dw < 1
$$光源的能量发射和材质的能量吸收使得场景中的能量保持动态平衡，这个动态平衡的 radiance 分布也就是渲染方程的解。那如果场景中所有问题，都有 $$
\int f_s(x,w_i,w_o)cos\theta dw \ge 1
$$在这种情况下应用 Path Tracing，得到的 radiance 解是什么样的呢？在光线每次弹射时，代码中更新 β 值$$ \beta_{new} = \beta\frac{f_s(x,w_i,w_o)cos\theta}{p(w)}$$在重要性采样中我们通常选取的 $p(w)$ 与 $f_s(x,w_i,w_o)cos\theta$ 有成比例的大小，由于 $\int f_s(x,w_i,w_o)cos\theta dw \ge 1$ 并且 $\int p(w)dw = 1$，因此大概率会有 $$
\frac{f_s(x,w_i,w_o)cos\theta}{p(w)} \ge 1
$$这意味着，随着光线的弹射，β 值不会收敛到 0，或者说路径对结果 radiance 的贡献不会随着路径长度的增加而减少，即 $(3)$ 式不能够收敛