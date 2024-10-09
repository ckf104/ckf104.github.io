系统的复杂度主要来源于两点
* heterogeneous  --> $\sigma_a$ 等参数依赖于位置
* chromatic --> $\sigma_a$ 等参数依赖于波长

[cse168 Volumetric Scattering](https://cseweb.ucsd.edu/classes/sp17/cse168-a/CSE168_14_Volumetric.pdf) 讲得很好，讨论了 Single/Multiple Scattering 的定义，Ray Marching 是一种考虑 Single Scattering 的方法

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