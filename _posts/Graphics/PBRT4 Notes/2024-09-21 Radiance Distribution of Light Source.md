记录各种光源的 radiance distribution
## Point Light

指定 intensity 的 频率分布，radiance 随 intensity 以距离的平方衰减并额外乘以一个立体角的 δ 函数（这个结论对任意点光源都成立，不局限于各向同性的点光源），这个 δ 函数的积分变元是以观测点为中心的立体角（用于面向光源采样，见 [pbrt4 13.3 节的 Simple Path Tracer](https://www.pbr-book.org/4ed/Light_Transport_I_Surface_Reflection/A_Simple_Path_Tracer)）
## Directional Light

指定 irradiance 的频率分布，radiance 为 irradiance 乘以一个立体角的 δ 函数，这个 δ 函数的积分变元是以观测点为中心的立体角（用于面向光源采样，见 [pbrt4 13.3 节的 Simple Path Tracer](https://www.pbr-book.org/4ed/Light_Transport_I_Surface_Reflection/A_Simple_Path_Tracer)）
## Area Light

pbrt4 中只有一个 DiffuseAreaLight 类，它由一个几何体指定形状，通过一张纹理指定几何体上每个点的 radiance 的频率分布，也即该点朝各个方向发射的 radiance
## Infinite Area Light

对应环境光，每个点的环境光分布相同，即 radiance 只与方向相关