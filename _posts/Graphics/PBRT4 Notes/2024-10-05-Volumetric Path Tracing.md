---
title: Volumetric Path Tracing
date: 2022-10-05 20:17:00 +0800
math: true
categories:
  - Graphics
comments: true
---

系统的复杂度主要来源于两点
* heterogeneous  --> $\sigma_a$ 等参数依赖于位置
* chromatic --> $\sigma_a$ 等参数依赖于波长
## Ray Marching

[An Introduction to Volume Rendering](https://www.scratchapixel.com/lessons/3d-basic-rendering/volume-rendering-for-developers/intro-volume-rendering.html) 对 ray marching 的介绍挺好的，并给出了渲染方程怎么从微分形式到积分形式的详细推导。它的基本想法就是，将渲染方程中的积分转换为黎曼和（ray marching 就是求这个黎曼和的形象化表述）。对于 in scattering 的贡献，它就做了简化，只考虑一次 scattering 的路径，不考虑多次 scattering 的路径对结果的贡献

这样的话，我们要计算从 w 方向，到达 A 点的 radiance，就从 A 点出发，沿着 -w 方向行进光线，每前进 dt 长度，我们要
* 计算一次黎曼和（这个对应 $L_e$，也就是自发光项的贡献）
* 在当前位置采样一个 in scattering 方向，如果这个方向能击中光源，沿着这个采样的方向又做 ray marching（求黎曼和），然后计算这条 in scattering 光路对结果的贡献（这里要求能击中光源也是出于只有一次 scattering 的简化，如果考虑各个方向反射过来的环境光的话，追踪一条光线就分裂出了追踪多条光线，path tracing 就没法做了）
直到前进 dt 长度光线离开了这个 participating media，那就正常往前继续做路径追踪即可（细想一下这里我觉得稍微有些别扭，如果使用路径追踪的话，这里光源 in-scattering 的贡献属于什么路径呢？）
## Ratio Tracking, Null Scattering, and Delta Tracking

TODO：解释公式 (11.13) 的推导
## General Solution of Rendering Equation with Participating Media

这里我想直观地解释一下 14.1.4 节中渲染方程解的形式。13.1.4 节中的给出的渲染方程解没有考虑到渲染方程解，但这个解没有考虑 participating media。14.1.4，14.1.5 节做的事情就是把这个结果泛化到存在 participating media 的情况。我们先回顾一下原本三点式的，只考虑表面反射，折射的渲染方程
$$
\begin{equation} \tag{1}
L\left(\mathrm{p}^{\prime} \rightarrow \mathrm{p}\right)=L_{\mathrm{e}}\left(\mathrm{p}^{\prime} \rightarrow \mathrm{p}\right)+\int_A f\left(\mathrm{p}^{\prime \prime} \rightarrow \mathrm{p}^{\prime} \rightarrow \mathrm{p}\right) L\left(\mathrm{p}^{\prime \prime} \rightarrow \mathrm{p}^{\prime}\right) G\left(\mathrm{p}^{\prime \prime} \leftrightarrow \mathrm{p}^{\prime}\right) \mathrm{d} A\left(\mathrm{p}^{\prime \prime}\right)
\end{equation}
$$
在 13.1.4 节中，我们反复迭代上式，拿到了这个渲染方程的解。现在除了上面的渲染方程，还额外加入了体渲染方程，它的微分形式是
$$
\displaylines{
L_s(x,w) = \int_{S^2} p(w,w^{\prime})L(x,w^{\prime})dw^{\prime}
\\
\frac{dL(x,w)}{dt} = -\sigma_mL(x,w)+\sigma_n(x)L(x,w)+\sigma_s(x)L_s(x,w)+\sigma_a(x)L_e(x,w)
}
$$
其中 $\sigma_s(x)L_s(x,w)$ 是 in-scattering 项，$\sigma_n(x)L(x,w)$ 是 null-scattering 项，$\sigma_aL_e(x,w)$ 是自发光项，$-\sigma_mL(x,w)$ 是衰减项。相比微分形式，该方程的积分形式在我们迭代求解渲染方程时更好用（推导见 [From the Radiative Transfer Equation to the Volume Rendering Equation](https://www.scratchapixel.com/lessons/3d-basic-rendering/volume-rendering-for-developers/volume-rendering-summary-equations.html)，这里形式和它有些不一样的原因在于我们使用了 null scattering 技巧）
$$
\tag{2} L(x,w) = \int_0^d e^{-\sigma_mt}(\sigma_n(x-tw)L(x-tw,w)+\sigma_s(x-tw)L_s(x-tw,w)+\sigma_a(x-tw)L_e(x-tw,w))dt+e^{-\sigma_m d}L(x-dw,w)
$$
通常我们会设置 $x-dw$ 为 participating media 的边界。这个积分形式的直观上很好理解，由 in-scattering 项， null-scattering 项，自发光项组成每个 $x-tw$ 位置的 radiance 贡献，然后它们到达 $x$ 处还会经历一个由微分形式的衰减项造成的指数衰减。整个积分求和就拿到了整个路径的 radiance 贡献，最后还再加上从边界射入的外部贡献

现在我们综合 $(1) (2)$ 两式，它们是相互叠加的一个关系。在第 13 章我们只存在 $(1)$ 式时，$(1)$ 式右边的 $L\left(\mathrm{p}^{\prime \prime} \rightarrow \mathrm{p}^{\prime}\right)$ 的值由两项叠加贡献而来
* $p^{\prime \prime}$ 是一个物体的表面，$L\left(\mathrm{p}^{\prime \prime} \rightarrow \mathrm{p}^{\prime}\right)$ 表示该物体表面从 $p^{\prime \prime}$ 到 $p^{\prime}$ 的反射光线
* $p^{\prime \prime}$ 是一个发光物体的表面，$L\left(\mathrm{p}^{\prime \prime} \rightarrow \mathrm{p}^{\prime}\right)$ 表示该光源从 $p^{\prime \prime}$ 到 $p^{\prime}$ 的出射光线。同时光路终止
现在由于 $(2)$ 式的存在，我们还需要考虑 $p^{\prime \prime}$ 位于 participating media 的内部的情况，这产生另外三项 radiance 贡献
* $L\left(\mathrm{p}^{\prime \prime} \rightarrow \mathrm{p}^{\prime}\right)$ 表示在 $p^{\prime \prime}$ 处 participating media 沿着方向 $\mathrm{p}^{\prime \prime} \rightarrow \mathrm{p}^{\prime}$ 的自发光。同时光路终止
* $L\left(\mathrm{p}^{\prime \prime} \rightarrow \mathrm{p}^{\prime}\right)$ 表示在 $p^{\prime \prime}$ 处 participating media 沿着方向 $\mathrm{p}^{\prime \prime} \rightarrow \mathrm{p}^{\prime}$ 的 in-scattering 项贡献
* $L\left(\mathrm{p}^{\prime \prime} \rightarrow \mathrm{p}^{\prime}\right)$ 表示在 $p^{\prime \prime}$ 处 participating media 沿着方向 $\mathrm{p}^{\prime \prime} \rightarrow \mathrm{p}^{\prime}$ 的 null-scattering 项贡献
额外需要注意的是，由于 $(2)$ 式是沿着 $w$ 方向积分，因此当 $p^{\prime \prime}$ 位于 participating media 中时，迭代时出来一个 $dwdt$ 项，根据球坐标系的微分代换式，我们有 $$
dwdt = \frac{dV}{|\mathrm{p}^{\prime \prime} \rightarrow \mathrm{p}^{\prime}|^2}
$$而在 $p^{\prime \prime}$ 位于物体表面时，对应的微分代换式为
$$
dw = \frac{cos\theta dA}{|\mathrm{p}^{\prime \prime} \rightarrow \mathrm{p}^{\prime}|^2}
$$
其中 $\theta$ 是 $p^{\prime \prime}$ 处表面法线和 $\mathrm{p}^{\prime \prime} \rightarrow \mathrm{p}^{\prime}$ 方向的夹角。因此这里形式上会差一个余弦项。另外，如果 $p^{\prime}$ 位于 participating media 中，相比于表面散射方程，这个体散射方程 $L_s(x,w) = \int_{S^2} p(w,w^{\prime})L(x,w^{\prime})dw^{\prime}$ 也会差一个余弦项。这样就解释了书中 (14.13) 式这个 _geometric term_ 的来历

现在我们能够直观地想象出对最终解 $L(x,w)$ 有贡献的路径组成了。在 13 章中没有 participating media 时，每个路径的起始点为 $x$，路径上每个点都是一个表面散射点，然后最后一个点是发光物体表面。除了路径上前两个点外，路径上每个点使得结果表达式多一个二重积分。现在有了 participating media，路径上最后一个点除了可能是发光物体表面，还可能是 participating media 中的自发光点。而路径的中间点除开是表面散射点外，还可能是体散射点以及 null scattering 点，并且体散射点以及 null scattering 点会使结果表达式多一个三重积分（null scattering 可以理解为镜面散射，因为它只有一个确定散射方向）
## Simple Volumetric Integrator

## Improved Volumetric Integrator

相比于一些 Simple Volumetric Integrator 的一些提升
* 支持 surface scattering
* 使用 MIS 面向光源采样
* 处理 $\sigma_a, \sigma_s$ 随波长变化的情况

整个算法的复杂度来源于好几个地方，一个是对于 heterogeneous media，它的 $\sigma_a,\sigma_s$ 等参数的值依赖于空间位置。另一个是对于 chromatic media，它的  $\sigma_a,\sigma_s$ 等参数的值还依赖于波长，这会对采样产生影响。再者就是使用 MIS 技术进行面向光源采样
### heterogeneous media
我们首先讨论 heterogeneous media 的处理。pbrt4 中使用 null scattering 的技术，额外引入了 $\sigma_n \ge 0$，使得 $\sigma_t + \sigma_n = \sigma_{maj}$ 不再依赖于空间位置（但可以依赖于波长）。但显然 $\sigma_{maj}$ 越小，对应采样到 null scattering 的概率越小，采样效率越高。因此在 11.4 节的 `GridMedium` 实现中会把 participating media 划分为若干小立方体，在每个小立方体内计算一个更紧的 $\sigma_{maj}$ 估计。现在 $\sigma_{maj}$ 变为了一个分段常量，我们如何使用 delta tracking 进行采样呢？

需要明确的是，我们要做的只是按照某种概率分布采样路径，使用不同的概率分布采样路径只会影响方差大小，而不会影响无偏性。当 $\sigma_{maj}$ 是常量时，我们采样用的概率分布是 $p(t) = \sigma_{maj}e^{-\sigma_{maj}t}$，这是预期这个指数概率分布刚好抵消掉体渲染方程中的指数衰减项，使得最后的方差较小。而现在 $\sigma_{maj}$ 变为了一个分段常量。一个很自然的想法采样想法就是，我先用当前所在的小立方体的 $\sigma_{maj}$ 作指数概率分布的采样，如果采样出来的 $t$ 值仍在小立方体内，我们就将其作为得到的采样点。如果采样得到的 $t$ 值超过了小立方体的边界，那么我们将光线原点移动到这个边界处，然后按照下一个小立方体的 $\sigma_{maj}$ 重新作指数分布采样。直到采样出来的 $t$ 值在当前的小立方体内，或者越过了整个 participating media，进入新的 participating media，继续上面的整个循环，或者打中物体表面，物体表面的交点作为最终的采样点。其实这个想法的本质上就是将 $\sigma_{maj}$ 不同的小立方体视为不同的 participating media。[equation 14.8](https://pbr-book.org/4ed/Light_Transport_II_Volume_Rendering/The_Equation_of_Transfer#eq:tmaj-over-segments) 其实就是对这一想法的数学化描述，而 `SampleT_maj` 函数对应其代码实现
### chromatic media
在此基础上我们进一步考虑 chromatic media，它带来的问题是 $\sigma_{maj}$ 依赖于波长。一种方法是，我们取的 $\sigma_n$ 将 $\sigma_t + \sigma_n$ 补齐到不依赖波长的统一的 $\sigma_{maj}$，但其实指标不治本。因为我们在确定下一个路径点后，还需要随机采样，确定在这个路径点发生的事件是 scattering, null scattering 还是 absorption，它们的概率依然是依赖于波长的。另外一种方法是，我就粗暴地按照采样的第一个波长对应的 $\sigma_{maj},\sigma_n$ 等进行采样，这当然也不影响无偏性，但是其它波长算出的 radiance 结果的方差会比较大

pbrt4 中解决这个问题的方法是 one sample model 的 MIS。假设我们采样了 $m$ 个波长，那么我们可以从中随机选择一个波长 $\lambda_j$，按照它的 $\sigma_{maj},\sigma_n$ 等进行采样。使用 balance heuristic，对应的估计表达式为
$$
F = \frac{P(\boldsymbol{p}|\lambda_j)}{\sum_{i=1}^m P(\boldsymbol{p}|\lambda_i)} \sum_{i=1}^m\frac{f(\lambda_i,\boldsymbol{p})}{P(\lambda_i)P(\boldsymbol{p}|\lambda_j)}
$$
其中 $\boldsymbol{p}$ 是采样的路径，$f(\lambda,\boldsymbol{p})$ 是被积函数，$P(\boldsymbol{p}|\lambda)$ 是按照波长 $\lambda$ 对应的 $\sigma_{maj},\sigma_n$ 等进行路径采样的概率函数。很容易看出来这个估计是无偏的。但 pbrt4 中稍微做了一个简化。因为这 $m$ 个波长地位等同，那我没必要随机选择波长 $\lambda_j$ 了，直接取 $\lambda_1$ 即可。此时的估计表达式变为$$
F = \frac{P(\boldsymbol{p}|\lambda_1)}{\sum_{i=1}^m P(\boldsymbol{p}|\lambda_i)} \sum_{i=1}^m\frac{f(\lambda_i,\boldsymbol{p})}{P(\lambda_i)P(\boldsymbol{p}|\lambda_1)} = \frac{1}{\sum_{i=1}^m P(\boldsymbol{p}|\lambda_i)} \sum_{i=1}^m\frac{f(\lambda_i,\boldsymbol{p})}{P(\lambda_i)}
$$$F$ 依然是无偏的，原因在于 $F$ 是一个关于 $\lambda_i$ 的轮换对称式，因此
$$
\begin{aligned}
E[F] & =\int F(\prod_{i=1}^{m} P(\lambda_i)) P(\boldsymbol{p}|\lambda_1)d\boldsymbol{p}\prod_{i=1}^{m}d\lambda_i
\\
& =\int F(\prod_{i=1}^{m} P(\lambda_i)) P(\boldsymbol{p}|\lambda_2)d\boldsymbol{p}\prod_{i=1}^{m}d\lambda_i
\\
& = \frac{1}{m}\sum_{j=1}^m \int F(\prod_{i=1}^{m} P(\lambda_i)) P(\boldsymbol{p}|\lambda_j)d\boldsymbol{p}\prod_{i=1}^{m}d\lambda_i
\end{aligned}
$$
这就化归到之前的 one sample model 的期望表达式了

利用 one sample model 对 chromatic media 的处理也适用于 bsdf，在微表面模型中，菲涅尔反射中使用的折射系数 $\eta$ 可以依赖于光线的波长。这意味着 bsdf 使用的采样函数也会依赖于波长。pbrt4 中处理得比较简单，如果此时 $\eta$ 依赖于波长，那么就只追踪单一波长了。但使用这里的  one sample model MIS，我们其实还是可以继续追踪多个波长。唯一不能处理的是镜面折射模型，因为各个波长的光路就直接不一样了
### 面向光源采样
在上一节我们用 one sample model 的 MIS 技术综合了不同的 $\lambda_j$ 对应的路径采样的概率 $P(\boldsymbol{p}|\lambda_j)$。类似于 Path Tracing，我们在体渲染中仍然有面向光源采样，这使得我们将 $P(\boldsymbol{p}|\lambda_j)$ 细分为 $P_u(\boldsymbol{p}|\lambda_j)$ 以及 $P_l(\boldsymbol{p}|\lambda_j)$，其中 $P_u(\boldsymbol{p}|\lambda_j)$ 表示按照 bsdf 采样出路径 $\boldsymbol{p}$ 的概率，而 $P_l(\boldsymbol{p}|\lambda_j)$ 表示面向光源采样采样出路径 $\boldsymbol{p}$ 的概率

这里用到的是 multi sample model 的 MIS 技术。结合前面 one sample model 的表达式，新的估计式可以表示为
$$
F = \frac{P_u(\boldsymbol{p}|\lambda_1)}{\sum_{i=1}^m P_u(\boldsymbol{p}|\lambda_i)+\sum_{i=1}^m P_l(\boldsymbol{p}|\lambda_i)} \sum_{i=1}^m\frac{f(\lambda_i,\boldsymbol{p})}{P(\lambda_i)P_u(\boldsymbol{p}|\lambda_1)}+\frac{P_l(\boldsymbol{p}|\lambda_1)}{\sum_{i=1}^m P_u(\boldsymbol{p}|\lambda_i)+\sum_{i=1}^m P_l(\boldsymbol{p}|\lambda_i)} \sum_{i=1}^m\frac{f(\lambda_i,\boldsymbol{p})}{P(\lambda_i)P_l(\boldsymbol{p}|\lambda_1)}
$$
现在我们还需要回答两个问题：在哪些地方可以面向光源采样，以及如何选择面向光源采样的概率函数如何选择

先讨论第一个问题。在第 13 章的 path tracing 中，我们在每个非镜面反射的路径点都可以面向光源进行采样。现在考虑体渲染时，我们依然可以在这个位置面向光源采样。但除此之外，如果在 participating media 中采样到了 scattering 路径点，那么我们也可以在这个位置进行面向光源采样（但 null scattering 显然不行，因为它不会改变光线方向）

现在说第二个问题。在 13 章中，我们使用了 `lightSampler` 这一封装，它帮助我们采样光源上某个点，并给出采样概率，由此我们也可以确定光线的散射方向。最后判断散射点与光源上的采样点之间是否存在遮挡，如果没有，我们就得到了合法的路径，这条路径的概率为
$$
P(\boldsymbol{p}) = P(\boldsymbol{p^{\prime}})*P_l
$$
其中 $\boldsymbol{p^{\prime}}$ 表示从相机出发点到最终的散射点的路径，而 $\boldsymbol{p}$ 是 $\boldsymbol{p^{\prime}}$ 额外加上光源上的采样点的路径，$P_l$ 表示 `lightSampler` 返回的概率。将这个采样方法直接照搬到体渲染中不是太合适。原因在于存在 participating media 后，散射点到光源采样点的路径上可能发生其它的 scattering 事件。也就是说，这种面向光源采样的方式，相比于 bsdf 采样，能覆盖到的路径太少了（当然它肯定是正确的，它没覆盖到的路径，bsdf 采样一定会覆盖到，$P_u(\boldsymbol{p}|\lambda)$ 和 $P_l(\boldsymbol{p}|\lambda)$ 不会同时为 0）

我们注意到 null scattering 不会改变光线的行进方向，因此我们可以允许从散射点到光源采样点的路径上发生 null scattering，这样能覆盖到路径就增加了一些。和 bsdf 采样时的 delta tracking 一样，我们从散射到沿着光源采样点前进，每次前进的距离由概率分布 $p(t) = \sigma_{maj}e^{-\sigma_{maj}t}$ 的采样结果决定。但与之前不同的是，我们取 null scattering 发生的概率为 1，来保证只发生 null scattering，因此光线不会散射到其它地方（ratio tracking）。这就是 [equation 14.23](https://www.pbr-book.org/4ed/Light_Transport_II_Volume_Rendering/Volume_Scattering_Integrators#eq:volpath-light-path-probability) 的来历，它给出了 $P_l(\boldsymbol{p}|\lambda)$ 的计算方式

对于 homogeneous media，由于没有 null scattering，就退化为原来的面向光源采样方法。这也是一个潜在的优化点。即在 `SampleLd` 函数中，对 homogeneous media 进行特判，对于 homogeneous media 我们不使用 ratio tracking，而直接用 $P(\boldsymbol{p}) = P(\boldsymbol{p^{\prime}})*P_l$ 作为概率即可。目前的 `SampleLd` 函数对于 homogeneous media 仍然使用 ratio tracking，这导致的问题在于如果采样点落在 participating media 内，由于 $\sigma_n$ 为 0，因此这样的光路对结果是 0 贡献的。这就好像在说，我本来可以直接计算 $e^{-\sigma d}$ 的值，但非要根据 $p(t) = \sigma e^{-\sigma t}$ 进行采样，如果采样结果 $t \gt d$，那么取估计值 1，如果 $t \le d$，那么取估计值 0。由此来保证估计的期望为 $e^{-\sigma d}$。这样做白白地增大了方差
### Other Tricks
第一个是有关自发光项的采样。我们并不需要在发生 absorption 的位置才计算自发光项，每产生一个新的位于 participating media 中的采样点，都可以视为一条完整的路径，计算这条光源来自 participating media 的自发光的路径的 radiance 贡献。另外，这个路径不参与面向光源采样的 MIS 的计算，因为面向光源采样的 `lightsampler` 采样时只考虑光源，没有考虑 participating media 的自发光

由此马上想到的事情是，那我何必还有个 $\frac{\sigma_a}{\sigma_{maj}}$ 的离散概率去采样 absorption 呢？确实是这样，我们可以只以一定的离散概率采样 scattering 和 null scattering 即可。不过由于采样到 absorption 后，整个路径的采样就终止了，因此我们可以将其等效为一个 russian roulette

第二个是 _rescaled path probabilities_，直接记录 $P_u(\boldsymbol{p}|\lambda),P_l(\boldsymbol{p}|\lambda)$ 的话很容易就上溢出或者下溢出了。因此在代码中 `r_u,r_l` 变量实际上记录的是 $$
r_u = \frac{P_u(\boldsymbol{p}|\lambda)}{P_{path}(\boldsymbol{p}|\lambda_1)},r_l=\frac{P_l(\boldsymbol{p}|\lambda)}{P_{path}(\boldsymbol{p}|\lambda_1)}$$这里 $P_{path}(\boldsymbol{p}|\lambda_1)$ 的含义稍微有些微妙，它表示按照 $\lambda_1$ 对应的 $\sigma_{maj},\sigma_n$ 等采样出路径 $\boldsymbol{p}$ 的概率。也就是说，如果这条路径本身是按照正常的 bsdf 采样得到的，则 $P_{path}(\boldsymbol{p}|\lambda_1)=P_u(\boldsymbol{p}|\lambda_1)$，而如果是面向光源采样得到的，那么 $P_{path}(\boldsymbol{p}|\lambda_1)=P_l(\boldsymbol{p}|\lambda_1)$

其它已经在 13 章使用过的 tricks，例如 allowIncompeletePDF(MIS Compensation)，path regularization 等，在这里仍然适用
## 对 Sampler 的讨论

pbrt4 中在 8.3 节以及 13.4 节这两章强调过不能把 sampler 的采样放到条件语句中。主要是为了保证一个固定的积分维度使用固定的 sampler 采样的维度，充分利用好 sampler 返回的均匀采样点的良好性质。但在 `VolPathIntegrator::Li` 中，`SampleLd` 函数中使用了三维的 sampler 的返回值来采样光源，但这个函数却被放在下面的条件语句中
```c++
if (IsNonSpecular(bsdf.Flags())) {
    L += SampleLd(isect, &bsdf, lambda, sampler, beta, r_u);
    DCHECK(IsInf(L.y(lambda)) == false);
}
```
这挺奇怪的，这就使得路径中每个点使用的 sampler 维度除了依赖它是第几个路径点外，还依赖于它前面的路径点有多少个镜面反射。在体渲染中还涉及到 null scattering 的话我们不需要调用 sampler 获取一个二维的采样来确定下一个散射的方向等

一种可能的解释是，我们可以将路径拆分为若干类型，除了按路径长度分类外，还可以进一步划分为路径中有多少个镜面反射，有多少个 null scattering 等（pbrt4中的类似讨论见 [13.1.6 Partitioning the Integrand](https://www.pbr-book.org/4ed/Light_Transport_I_Surface_Reflection/The_Light_Transport_Equation#PartitioningtheIntegrand)）

但仔细想想还有些问题，我们考虑使用蒙特卡洛方法估计下面的积分 $$
\int f(x)dx+\int g(x)dx
$$一种方法是，我们使用 sampler 拿到一个二维的采样结果 $(u,v)$。我们首先根据 $u$ 的值决定本次是估计 $f$ 还是 $g$，然后用 $v$ 来得到一个实际的估计值，$\frac{f(v)}{p(v)}$ 或者是 $\frac{g(v)}{p(v)}$
另外一种方法是使用 sampler 先拿到一个一维的采样结果 $u$，根据 $u$ 的值决定向 sampler 获取第二维的采样结果 $v_1$ 还是第三维的采样结果 $v_2$，对应的估计为 $\frac{f(v_1)}{p(v_1)}$ 还是 $\frac{g(v_2)}{p(v_2)}$
这两种方法的区别在于，第一种方法它的 sampler 返回值会被偷掉一部分（在 $f$ 看来一部分属于它的第二维的采样拿去估计 $g$ 了），这对 holton 等采样器会产生什么样的影响呢？

TODO：理解这一问题
TODO：理解处理 bssrdf 采样的代码
## Layered Bxdf

TODO：解释为什么采样 `exitInterface` 的 wi 方向过来的入射光线的折射方向时 `TransportMode` 要取反
TODO：解释 two sided 参数，什么是双面材质？
TODO：解释 14.31 公式，现在 beta 项会有个额外的 $1/cos\theta$
TODO：我感觉这个方法可以进一步用来刻画 bssrdf
TODO：为什么 sample_f 函数最后返回的 f 值没有乘以 $cos\theta$，可能需要看下 [Position-Free Monte Carlo Simulation for Arbitrary Layered BSDFs](https://shuangz.com/projects/layered-sa18/) 论文的推导才行
TODO：解释公式 14.36，为什么会单独使用 brdf 和 btdf 呢，概率我觉得还是应该用 bsdf 才对呀

参考资料
* [Production Volume Rendering](https://graphics.pixar.com/library/ProductionVolumeRendering/paper.pdf)
* [Monte Carlo methods for physically based volume rendering](https://cs.dartmouth.edu/~wjarosz/publications/novak18monte-sig.html) 这个 18 年的 siggraph course 据说讲得很好，还罗列了最近的一些与这个话题有关的论文
* 据 [hw2: Volumetric Path Tracing](https://cseweb.ucsd.edu/~tzli/cse272/wi2024/homework2.pdf) 中说 [Integral formulations of volumetric transmittance](https://dl.acm.org/doi/pdf/10.1145/3355089.3356559) 讨论了为什么解一个常微分方程来得到 volumetric rendering equation，而不是直接两边同时积分（虽然正常感觉，对两边同时积分得到的形式进行采样的话方差会很大吧）
* [Position-Free Monte Carlo Simulation for Arbitrary Layered BSDFs](https://shuangz.com/projects/layered-sa18/)：讨论 layered material 的论文