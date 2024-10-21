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


这里 MIS 有两处，一个是面向光源采样，一个是根据不同的波长采样，这两处结合起来的方程形式需要考虑一下，另外，allowIncompeletePDF 在这里的使用
解释 SampleT_maj
解释 specularBounce，解释 r_l rescaling
在每个位置采样 $L_e$
这个方法可以拓展到 non-specular microfacet

TODO：
* 这个采样的路径长度是否要考虑 null scattering，我感觉面向光源采样的时候得到的路径上可能有多个 null scatter，路径长度不太对？
* 经历了若干次 null scattering 和 0 次 null scattering 的光照计算有什么区别？
* ~~这个 integrator 里为什么每到一个新的点都要采样一个 Le，这意味着，如果反复发生 null scattering，它会采样很多的~~ 这个不是问题，它不参与 MIS
* MIS 还是面向实体光源在做，但是我没看懂 面向光源采样的路径的概率和正常采样的路径的概率是怎么算的？
* homogeneous media 下的面向光源采样还需要做 ratio tracking 吗？这时候就退化为更简单的情况了，因为没有 null scattering 了，直接计算 transmittance 就行了（这就更像没有 media 时 path tracing 做的面向光源采样，采样的路径只会多一个光源点，中间不会再有其它点了）
* 据 [hw2: Volumetric Path Tracing](https://cseweb.ucsd.edu/~tzli/cse272/wi2024/homework2.pdf) 中说 [Integral formulations of volumetric transmittance](https://dl.acm.org/doi/pdf/10.1145/3355089.3356559) 讨论了为什么解一个常微分方程来得到 volumetric rendering equation，而不是直接两边同时积分（虽然正常感觉，对两边同时积分得到的形式进行采样的话方差会很大吧）
* 对 chromatic media 的重要性采样还没有看懂，它这里总是按照 $\sigma_{m,\lambda_0}$ 采样是否合适，如果不合适应该怎么改？

一些关键的观察
* 由 null scattering 的各种组合的叠加等效为没有使用 null scattering 的路径估计
* 不同波长的光线选取的是同一条采样路径，这在求解形式上的积分所选取的采样点带来了一些相关性，但并不影响无偏性

## 对 Sampler 的讨论


参考资料
* [Production Volume Rendering](https://graphics.pixar.com/library/ProductionVolumeRendering/paper.pdf)
* [Monte Carlo methods for physically based volume rendering](https://cs.dartmouth.edu/~wjarosz/publications/novak18monte-sig.html) 这个 18 年的 siggraph course 据说讲得很好，还罗列了最近的一些与这个话题有关的论文