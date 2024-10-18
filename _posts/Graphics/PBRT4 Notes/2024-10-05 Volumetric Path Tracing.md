系统的复杂度主要来源于两点
* heterogeneous  --> $\sigma_a$ 等参数依赖于位置
* chromatic --> $\sigma_a$ 等参数依赖于波长
## Ray Marching

[An Introduction to Volume Rendering](https://www.scratchapixel.com/lessons/3d-basic-rendering/volume-rendering-for-developers/intro-volume-rendering.html) 对 ray marching 的介绍挺好的，并给出了渲染方程怎么从微分形式到积分形式的详细推导。它的基本想法就是，将渲染方程中的积分转换为黎曼和（ray marching 就是求这个黎曼和的形象化表述）。对于 in scattering 的贡献，它就做了简化，只考虑一次 scattering 的路径，不考虑多次 scattering 的路径对结果的贡献

这样的话，我们要计算从 w 方向，到达 A 点的 radiance，就从 A 点出发，沿着 -w 方向行进光线，每前进 dt 长度，我们要
* 计算一次黎曼和（这个对应 $L_e$，也就是自发光项的贡献）
* 在当前位置采样一个 in scattering 方向，如果这个方向能击中光源，沿着这个采样的方向又做 ray marching（求黎曼和），然后计算这条 in scattering 光路对结果的贡献（这里要求能击中光源也是出于只有一次 scattering 的简化，如果考虑各个方向反射过来的环境光的话，追踪一条光线就分裂出了追踪多条光线，path tracing 就没法做了）
直到前进 dt 长度光线离开了这个 participating media，那就正常往前继续做路径追踪即可（细想一下这里我觉得稍微有些别扭，如果使用路径追踪的话，这里光源 in-scattering 的贡献属于什么路径呢？）
## Ratio Tracking and Null Scattering

TODO：解释公式 (11.13) 的推导
## General Solution of Rendering Equation with Participating Media

这里我想直观地解释一下 14.1.4 节中渲染方程解的形式。13.1.4 节中的给出的渲染方程解没有考虑到渲染方程解，但这个解没有考虑 participating media。14.1.4，14.1.5 节做的事情就是把这个结果泛化到存在 participating media 的情况。我们先回顾一下原本的渲染方程，

TODO：解释 14.1.4，14.1.5 中渲染方程解的含义
## Simple Volumetric Integrator

## Improved Volumetric Integrator

相比于一些 Simple Volumetric Integrator 的一些提升
* 支持 surface scattering
* 使用 MIS 面向光源采样
* 处理 $\sigma_a, \sigma_s$ 随波长变化的情况


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


参考资料
* [Monte Carlo methods for physically based volume rendering](https://cs.dartmouth.edu/~wjarosz/publications/novak18monte-sig.html) 这个 18 年的 siggraph course 据说讲得很好，还罗列了最近的一些与这个话题有关的论文