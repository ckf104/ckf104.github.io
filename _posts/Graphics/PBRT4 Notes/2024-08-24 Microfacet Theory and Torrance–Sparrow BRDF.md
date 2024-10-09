## Basic Idea

使用镜面反射，但是每个点不是单一的法线了，而是一个微表面，这个微表面存在一个法线分布，这个法线分布是一个围绕 macro surface 的法线的扰动。扰动的大小由 roughness 这个参数决定，roughness 越大，这个分布离标准的 macro surface 法线分布 $\delta(w-n)$ 偏差越大

定义 Normal Distribution Function 为: 单位面积，单位立体角下的以该立体角方向为法线的面积大小，记为 $D(w_m)$。即 $D(w_m)dw_mdA$ 表示微元面积 dA 中法线为 $w_m$ 的微表面的面积大小。

考虑法线为 $n$ 的微元面积 dA(n)，以及 $w_i$ 方向的 radiance $L(w_i)$，由通量守恒，我们有
$$
\int_{H^2(n)} D(w_m)dw_mdA(n)dw_i (w_m\cdot w_i)L(w_i) = d\phi = dw_idA(n)(w_i\cdot n)L(w_i)
$$
由此得到
$$
\displaylines{
\int_{H^2(n)} D(w_m)(w_m\cdot w_i)dw_m = w_i\cdot n = cos\theta_i
}
$$
如果我们定义 $D_{w_i}(w_m) = \frac {D(w_m)(w_m\cdot w_i)}{cos\theta_i}$，则
$$
\int_{H^2(n)}D_{w_i}(w_m)dw_m = 1
$$
因此 $D_{w_i}(w_m)$ 提供了半球面上法线分布的概率描述，但对于入射方向 $w_i$，如果我们直接按照这个分布去采样（pbrt 中称为 full microfacet distribution sampling），会包含许多不可用的法线。

主要原因在于微表面间存在遮挡关系，例如 $w_m\cdot w_i < 0$ 的法线 $w_m$ 对应的平面一定是被遮挡住的。pbrt4 9.6 节讨论了三种微表面间的作用，Masking, Shadowing, Interreflection。这里的 $w_m\cdot w_i < 0$ 就是 Masking 的一种

因为 Interreflection 不好建模，我们忽略这部分情况（这会导致结果偏暗？）

为了刻画微表面间的遮挡关系，我们引入 $0 \leq G(w_i, w_m) \leq 1$，它表征了法线为 $w_m$ 的微表面在入射方向 $w_i$ 下的有效面积，因此
$$ \tag{1}
\int_{H^2(n)} D(w_m)G(w_i,w_m)max(0, w_m\cdot w_i)dw_m = w_i\cdot n = cos\theta_i
$$
现在我们对分布函数
$$
D_{w_i}(w_m) = \frac{D(w_m)G(w_i,w_m)max(0,w_m\cdot w_i)}{cos\theta_i}
$$
进行采样（Visible normal sampling），就能够得到有效的法线了
##### Note
这里的 $G(w_i, w_m)$ 以及后面引入的 $G(\mathbf{i}, \mathbf{o}, \mathbf{m})$ 都表示可见面积的比例，它小于 1 的原因除了因为自遮挡之外，还可能是因为 macro face 的投影。例如我们考虑宏表面和微表面构成的这样一个三角形 $\Delta$，取 $w_i,w_m$ 都为左侧斜坡的法线，根据 $(1)$ 式，此时应有 $G(w_i, w_m)$ 的值为底边在左侧斜边上的投影比上左侧斜边长。此时 $G(w_i, w_m) < 1$ 的原因在于，从宏表面上看，光线打在左侧斜边偏上的部分，根本就不会落到宏表面上
## Torrance–Sparrow BRDF

有了微表面的法线分布之后，并结合镜面反射的假设。我们可以反推出材质的 brdf

给定出射方向 $w_o$，我们考虑如何用法线分布计算 radiance $L(w_o)$。首先根据 $D_{w_o}(w_m)$ 对法线 $w_m$ 进行采样，并记镜面反射得到的入射方向为 $w_i$，对应的入射 radiance 为 $L(w_i)$，那么我们知道这个采样的立体角 $w_m$ 对 $L(w_o)$ 的贡献为
$$
dL(w_o) = F(w_i\cdot w_m)D_{w_o}(w_m)L(w_i)dw_m = F(w_o\cdot w_m)D_{w_o}(w_m)L(w_i)dw_m
$$
虽然 $D_{w_o}(w_m)$ 已经考虑了 Masking 的作用，但不能保证反射的 $w_i$ 不会被其它的微表面 Shadowing。如果我们假设 Masking 和 Shadowing 作用相互独立，那么这里被其它微表面 Shadowing 的面积恰好是沿着 $w_i$ 方向会被 Masking 的面积。因此有
$$
dL(w_o) = F(w_o\cdot w_m)G(w_i,w_m)D_{w_o}(w_m)L(w_i)dw_m
$$
另一方面，根据渲染方程，$w_i$ 方向的 radiance 对 $L(w_o)$ 的贡献可以表示为
$$
dL(w_o) = f_r(p, w_i,w_o)L(w_i)cos\theta_idw_i
$$
由于 $w_i,w_m,w_o$ 满足关系式 $\frac {w_i + w_o}{||w_i + w_o||} = w_m$，由于 $w_o$ 是给定的，可得微分关系式 $dw_m = \frac{dw_i}{4(w_o\cdot w_m)}$ 
由此可解出
$$
f_r(p,w_i,w_o) = \frac{F(w_o\cdot w_m)G(w_i,w_m)D_{w_o}(w_m)}{4(w_o\cdot w_m)cos\theta_i} = \frac{F(w_o\cdot w_m)D(w_m)G(w_i,w_m)G(w_o,w_m)}{4 cos\theta_o cos\theta_i}
$$
$G(w_i,w_m)G(w_o,w_m)$ 表达了同时考虑 Masking 和 Shadowing 效果时的有效面积比例，我们记为 $G(w_i,w_o,w_m)$，最终得到
$$
f_r(p,w_i,w_o) = \frac{F(w_o\cdot w_m)D(w_m)G(w_i, w_o,w_m)}{4 cos\theta_o cos\theta_i}
$$
## BTDF

相比于计算 brdf 时是简单的反射关系，对于折射的情况我们有
$$
w_m = -\frac{\eta_i w_i + \eta_o w_o}{||\eta_i w_i + \eta_o w_o||}
$$
类似使用球坐标系中 dw 的微分形式，并固定 $w_o$，我们有
$$
dw_m = \frac{\eta_i^2|w_i\cdot w_m|}{(\eta_i (w_i \cdot w_m) + \eta_o (w_o \cdot w_m))^2}dw_i
$$
论文 Microfacet Models for Refraction through Rough Surfaces 中通过几何方法得到了这个微分关系式，这也挺有意思的

由此可类似得到 btdf 的表达式（并注意在折射时需要乘以 $\frac{\eta_o^2}{\eta_i^2}$）
$$
f_t(p,w_i,w_o) = \frac{D(w_m)(1-F(w_o \cdot w_m))G(w_i,w_o,w_m)}{(\eta_i (w_i \cdot w_m) + \eta_o (w_o \cdot w_m))^2}\frac{\eta_o^2|w_i\cdot w_m||w_o\cdot w_m|}{|cos\theta_i cos\theta_o|}
$$
这个结果与论文 [Microfacet Models for Refraction through Rough Surfaces](https://www.graphics.cornell.edu/~bjw/microfacetbsdf.pdf) 中一致，但 pbrt4 中的表达式没有乘以 $\frac{\eta_o^2}{\eta_i^2}$ 这个 scaling factor，因为它在代码中把这个 scaling factor 单独拿出来考虑的，根据 transport mode 是 importance 还是 radiance 来决定要不要乘以 scaling factor。因此推导结果都是一致的
## Microfacet Models for Refraction through Rough Surfaces

这篇论文也对 Torrance–Sparrow BRDF 和 BTDF 进行了推导，而且它的推导手法很漂亮，并且更具有一般性。因此我额外记录一下论文中是怎么推的。首先论文中的 equation 8 建立了 microface bsdf 和 macroface bsdf 的联系
$$
f_s(\mathbf{i}, \mathbf{o}, \mathbf{n})=\int\left|\frac{\mathbf{i} \cdot \mathbf{m}}{\mathbf{i} \cdot \mathbf{n}}\right| f_s^m(\mathbf{i}, \mathbf{o}, \mathbf{m})\left|\frac{\mathbf{o} \cdot \mathbf{m}}{\mathbf{o} \cdot \mathbf{n}}\right| G(\mathbf{i}, \mathbf{o}, \mathbf{m}) D(\mathbf{m}) d \omega_m
$$
$G(\mathbf{i}, \mathbf{o}, \mathbf{m})$ 表示给定入射和出射方向 $\mathbf{i}, \mathbf{o}$ 时，法线为 $\mathbf{m}$ 的微表面的可见面积比例，当我们假定不同方向的可见面积相互独立时，有
$$
G(\mathbf{i}, \mathbf{o}, \mathbf{m}) = G_1(\mathbf{i}, \mathbf{m})G_1(\mathbf{o}, \mathbf{m})
$$
$G_1(\mathbf{i}, \mathbf{m})$ 表示对于方向 $\mathbf{i}$，法线为 $\mathbf{m}$ 的微表面的可见面积比例。这个式子的大概推导是，对于入射的 $L(\mathbf{i})$，法线为 $\mathbf{m}$ 的微表面贡献的出射通量
$$
\displaylines{
dL_o = L(\mathbf{i})f_s^m(\mathbf{i}, \mathbf{o}, \mathbf{m}) |\mathbf{i} \cdot \mathbf{m}| dw_i
\\
dS_m = G(\mathbf{i}, \mathbf{o}, \mathbf{m})D(\mathbf{m})dSdw_m
\\
d\Phi_m = dL_odw_o|\mathbf{o} \cdot \mathbf{m}|dS_m
}
$$
对 $w_m$ 进行积分，我们得到了整个微表面的出射通量
$$
d\Phi = L(\mathbf{i})dSdw_idw_o\int\left|\mathbf{i} \cdot \mathbf{m}\right| f_s^m(\mathbf{i}, \mathbf{o}, \mathbf{m})\left|\mathbf{o} \cdot \mathbf{m}\right| G(\mathbf{i}, \mathbf{o}, \mathbf{m}) D(\mathbf{m}) d \omega_m
$$
另一方面我们有
$$
d\Phi = L(\mathbf{i})f_s(\mathbf{i}, \mathbf{o}, \mathbf{n})|\mathbf{i} \cdot \mathbf{n}|dw_i |\mathbf{o} \cdot \mathbf{n}|dw_o dS
$$
由此可导出 equation 8。该公式更具一般性，它不依赖于微表面 bsdf 是镜面这一假设。然后 equation 9 推出了 specular bsdf 的公式
$$
f_s^m(\mathbf{i}, \mathbf{o}, \mathbf{m})=\rho \frac{\delta_{\omega_o}(\mathbf{s}, \mathbf{o})}{|\mathbf{o} \cdot \mathbf{m}|}
$$
其中 $\mathbf{s}$ 是给定 $\mathbf{i}, \mathbf{m}$ 后的镜面反射或折射的方向，$\delta_{\omega_o}(\mathbf{s}, \mathbf{o})$ 表示当出射方向 $\mathbf{o}$ 和 $\mathbf{s}$ 相等时取到无穷大，其余情况为 0，$w_o$ 的下标表示该 $\delta$ 函数是对 $w_o$ 进行积分，$\rho$ 表示反射或折射的比例。根据镜面假设，我们可以不妨设 
$$
f_s^m(\mathbf{i}, \mathbf{o}, \mathbf{m})=T\delta_{\omega_i}(\mathbf{s}, \mathbf{i})
$$
其中 $\mathbf{s}$ 表示给定 $\mathbf{o}, \mathbf{m}$ 后的入射方向。由此可得到
$$
L_o = T|\mathbf{i} \cdot \mathbf{m}|L_i
$$
根据通量守恒，我们有
$$
\displaylines{
d\Phi_o = \rho* d\Phi_i
\\
=> L_o = \rho L_i\left|\frac{\mathbf{i} \cdot \mathbf{m}}{\mathbf{o} \cdot \mathbf{m}}\right|\frac{dw_i}{dw_o}
}
$$
由此可解出
$$
f_s^m(\mathbf{i}, \mathbf{o}, \mathbf{m})=\rho \left|\frac{1}{\mathbf{o} \cdot \mathbf{m}}\right|\frac{dw_i}{dw_o} \delta_{\omega_i}(\mathbf{s}, \mathbf{i}) = \rho \frac{\delta_{\omega_o}(\mathbf{s}, \mathbf{o})}{|\mathbf{o} \cdot \mathbf{m}|}
$$
这导出了 equation 9。最后，由于 equation 8 需要的是 $\delta_{w_m}$，因此我们再做一个换元，得到
$$
f_s^m(\mathbf{i}, \mathbf{o}, \mathbf{m}) = \rho \frac{\delta_{\omega_m}(\mathbf{s}, \mathbf{o})}{|\mathbf{o} \cdot \mathbf{m}|}\frac{dw_m}{dw_o}
$$
而反射和折射的 $\frac{dw_m}{dw_i}$ 已经在之前推导过了，$\frac{dw_m}{dw_o}$ 的推导完全类似 
## Trowbridge-Reitz Distribution

TODO：这个 D，G 函数的来历和推导还没弄懂，然后能否按照书上说的那样，投影到一个纵向压扁的圆上采样呢。因为椭圆是凸的，又哪来的 Shadowing 效果呢

TODO:
$$
f_s(p,w_i,w_o) = k_d\frac{c}{\pi} + k_s\frac{F(w_o\cdot w_m)D(w_m)G(w_i, w_o,w_m)}{4 cos\theta_o cos\theta_i}
$$
LearnOpenGL 上使用的微表面是这个，$k_d,k_s$ 是哪来的

TODO：解释为什么金属没有漫反射项