Simple Path Tracer
_next event estimation_ 面向光源采样，解决点光源采样的问题
在 Monte Carlo 一节增加 MIS 的动机：解决 f(x)g(x) 的采样

Path Tracer
MIS, Russian Roulette, path regularization

delta light 和 specular bounce 没有用 MIS 加权？ MIS 带来了一些耦合性，因为两条分别的采样路径的前 i-1 个点是完全相同的，但这和 Simple Path Tracer 那的耦合性完全一致，用条件概率分布去理解这一点就好了

面向光源采样怎么还提前退出了？没有吃到 Russian Roulette 的倍增所以没啥问题？
[Fix handling of interface materials in Path and SimplePath integrators](https://github.com/mmp/pbrt-v4/commit/cdccb71cb1e153b63e538f624efcc13ab0f9bda2)  ，这样修改的原因在于 shadow ray 测试的时候没有考虑 participating media 的情况，因此为了一致性，就直接把 participating media 的边界认为是一个镜面层了

没看懂为什么 allowIncompletePDF 在 Uniform Infinite Lights 中的用处以及它与 MIS 的关系
SampleLd 的调用也有个 if 包着的，咋没见将这个 SampleLd 中的采样提到这个 if 之前呢？以及 Russian Roulette 里也有个包在 if 里的 Sample1D

