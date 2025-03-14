---
title: Microfacet Theory and Torrance–Sparrow BRDF
math: true
date: 2024-08-24 15:47:39 +0800
comments: true
categories:
  - Graphics
---

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
由于 $w_i,w_m,w_o$ 满足关系式 $\frac {w_i + w_o}{\|w_i + w_o\|} = w_m$，由于 $w_o$ 是给定的，可得微分关系式 $dw_m = \frac{dw_i}{4(w_o\cdot w_m)}$ 
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
w_m = -\frac{\eta_i w_i + \eta_o w_o}{\|\eta_i w_i + \eta_o w_o\|}
$$
类似使用球坐标系中 dw 的微分形式，并固定 $w_o$，我们有
$$
dw_m = \frac{\eta_i^2|w_i\cdot w_m|}{(\eta_i (w_i \cdot w_m) + \eta_o (w_o \cdot w_m))^2}dw_i
$$
论文 Microfacet Models for Refraction through Rough Surfaces 中通过几何方法得到了这个微分关系式，这也挺有意思的

由此可类似得到 btdf 的表达式（并注意在折射时需要乘以 $\frac{\eta_o^2}{\eta_i^2}$）
$$
f_t(p,w_i,w_o) = \frac{D(w_m)(1-F(w_o \cdot w_m))G(w_i,w_o,w_m)}{(\eta_i (w_i \cdot w_m) + \eta_o (w_o \cdot w_m))^2}\frac{\eta_o^2|w_i\cdot w_m\|w_o\cdot w_m|}{|cos\theta_i cos\theta_o|}
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
## Trowbridge-Reitz Distribution / GGX 分布
本节讨论 GGX 分布和它的重要性采样的推导，作为 PBRT4 9.6 节的补充。主要参考了
* [GGX重要性采样](https://zhuanlan.zhihu.com/p/104422026)
* [The Ellipsoid Normal Distribution Function](https://www.cs.cornell.edu/projects/metalappearance/SupplementalEllipsoidNDF.pdf)

一些其它的相关的，但我目前没时间看的材料包括
* [Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs](https://jcgt.org/published/0003/02/03/paper.pdf)，Eric Heitz 的这篇论文全面的阐述了自遮挡函数
* [Importance Sampling Microfacet-Based BSDFs using the Distribution of Visible Normals](https://inria.hal.science/hal-00996995v1/document)，使用代数方法推导了 GGX 的重要性采样
* [Sampling the GGX Distribution of Visible Normals](https://jcgt.org/published/0007/04/01/paper.pdf)，使用几何方法推导了 GGX 的重要性采样

### GGX 分布推导
GGX 分布来自于椭球表面的法线分布。我们设椭球的曲面方程为 $\mathbf{p}^TA^T A\mathbf{p} - C_e^2 = 0$，其中 $A$ 是 3x3 的矩阵，由缩放矩阵 $S$ 和旋转矩阵 $R$ 相乘得到，其中
$$
S = \left[
\begin{array}{ccc} \alpha_x & 0 & 0
\\ 0 & \alpha_y & 0
\\ 0 & 0 & 1
\end{array} 
\right]
$$
$\alpha_x$ 和 $\alpha_y$ 就是 GGX 分布的粗糙度参数。并且我们通常使用的 GGX 分布会取 R 为单位矩阵

我们首先推导椭球在给定方向 $\mathbf{u}$ 上的投影面积 $A_e^\perp(\mathbf{u})$ 。它可以表示为
$$
A_{e}^{\perp}(\mathbf{u})=\int_{\mathcal{S}} \chi_{+}(\mathbf{u} \cdot \mathbf{m}) (\mathbf{u} \cdot \mathbf{m}) dS
$$
其中 $\mathbf{m}$ 表示该点处的法线方向。我们通过几何方法来推导它的结果。首先考虑恰好不贡献有效面积的点，即 $\mathbf{u} \cdot \mathbf{m} = 0$ 的点的轨迹，对椭球上任意一点 $\mathbf{p}$，求梯度可得它的法线方向 $\mathbf{m}$ 为
$$
\mathbf{m} = \frac{A^T A \mathbf{p}}{\|A^T A \mathbf{p}\|}
$$
因此有
$$
(A^T A\mathbf{u})\cdot \mathbf{p} = \mathbf{u}A^T A\mathbf{p} = \|A^T A \mathbf{p}\| \, u^T\mathbf{m} = 0
$$
这表明满足 $\mathbf{u} \cdot \mathbf{m} = 0$ 的 $\mathbf{p}$ 都在法线为 $A^T A\mathbf{u}$ 的过原点的平面上，这个平面将椭球切分成两部分，上半部分会为 $\mathbf{u}$ 方向的投影贡献面积，而这部分的投影面积也等于法线为 $A^T A\mathbf{u}$ 的平面与椭球相交截出的椭圆沿着 $\mathbf{u}$ 方向的投影面积

做线性变换 $\mathbf{p}\prime = A\mathbf{p}$，将椭球变换为球体。根据代数恒等式（这个式子我们已经在推导法线修正矩阵中看到过了）
$$
(M\mathbf{a}) \times (M\mathbf{b}) = |M| M^{-T} (\mathbf{a} \times \mathbf{b})
$$
我们知道原来是法线为 $\mathbf{u}$ 的平面，在变换后法线为 $A^{-T}\mathbf{u}$，因此新的需要计算的面积是半径为 $C_e$ 的球沿着 $A\mathbf{u}$ 方向投影到法线为 $A^{-T}\mathbf{u}$ 平面上的面积，这也等价于半径为 $C_e$，平面法线为 $A\mathbf{u}$ 的圆投影到法线为 $A^{-T}\mathbf{u}$ 平面上的面积。反过来说就是待求的面积 $S_{new}$ 沿着 $A\mathbf{u}$ 方向的投影是半径为 $C_e$ 的圆，因此我们有
$$
S_{new} = \frac{\pi C_e^2 \|A^{-T}\mathbf{u}\|\,\|A\mathbf{u}\|}{A^{-T}\mathbf{u}\cdot A\mathbf{u}} = \frac{\pi C_e^2 \|A^{-T}\mathbf{u}\|\,\|A\mathbf{u}\|}{\mathbf{u}A^{-1} A\mathbf{u}} = \frac{\pi C_e^2 \|A^{-T}\mathbf{u}\|\,\|A\mathbf{u}\|}{\|\mathbf{u}\|^2} = \pi C_e^2 \|A^{-T}\mathbf{u}\|\,\|A\mathbf{u}\|
$$
由于叉乘后的向量的长度表示原来两个向量构成的三角形的面积，因此根据上面的代数恒等式我们知道做线性变换 $\mathbf{p}\prime = A\mathbf{p}$ 后新旧面积之比为 $|A|\,\|A^{-T}\mathbf{u}\|$，因此有
$$
A_e^\perp(\mathbf{u}) = \frac{S_{new}}{|A|\,\|A^{-T}\mathbf{u}\|} =\frac{\pi C_e^2 \|A\mathbf{u}\|}{|A|}
$$
我们记宏表面法线为 $\mathbf{n}$，根据定义，我们知道法线分布函数 $D(\mathbf{m})$ 为
$$
D(\mathbf{m}) = \frac{1}{A_{e}^{\perp}(\mathbf{n})} \cdot \frac{dA}{d\mathbf{m}}
$$
而 $\frac{dA}{d\mathbf{m}}$ 被称为高斯曲率 $K_{g}(\mathbf{m})$，它的推导我就没看了，最终的结果是
$$
K_{g} = \frac{|A|^{2} \left\| A^{-T}\mathbf{m} \right\|^{4}}{C_{e}^{2}}
$$
因此最终有
$$
D(\mathbf{m})=\frac{\chi_{+}(\mathbf{m} \cdot \mathbf{n})}{\pi|\mathbf{A}|\|\mathbf{A} \mathbf{n}\|\left\|\mathbf{A}^{-\top} \mathbf{m}\right\|^4}
$$
额外的 $\chi_{+}(\mathbf{m} \cdot \mathbf{n})$ 在点积结果大于等于 0 的时候结果为 1，否则为 0，用于过滤掉在平面下面的半个不可见的椭球。带入
$$
A = \left[
\begin{array}{ccc} \alpha_x & 0 & 0
\\ 0 & \alpha_y & 0
\\ 0 & 0 & 1
\end{array} 
\right], \, \mathbf{n} = \left[
\begin{array}{ccc} 0
\\ 0
\\ 1
\end{array} 
\right]
$$
可见 $D(\mathbf{m})$ 与标准的 GGX 分布一致
### 自遮挡项 G1 推导
在推导 G1 项之前，我们先计算 $A^{\perp}_{\ell}(\mathbf{u},\mathbf{v})$，它表示椭圆在 $\mathbf{v}$ 方向中可见的部分，向 $\mathbf{u}$ 投影的面积
$$
A_{\ell}^{\perp}(\mathbf{u}, \mathbf{v})=\int_{\mathcal{S}} \chi_{+}(\mathbf{u} \cdot \mathbf{m}) \chi_{+}(\mathbf{v} \cdot \mathbf{m})(\mathbf{u} \cdot \mathbf{m}) dS
$$
同上地做一个线性变换，计算 $A_e^\perp(\mathbf{u})$ 时有效的投影曲面是一个半球面（进而可以简化为一个圆），但在计算 $A_e^\perp(\mathbf{u})$ 时有效的投影曲面不再是一个法线为 $A\mathbf{u}$ 方向的平面截出的半球面了，有效的投影曲面是法线为 $A\mathbf{u}$ 方向的平面截出的半球面与法线为 $A\mathbf{v}$ 方向的平面截出的半球面的交集。我们需要计算的是，这个交出的曲面沿着 $A\mathbf{u}$ 方向的投影面积，在法线为 $A^{-T}\mathbf{u}$ 的平面上的投影面积

与之前一样，我们先计算出它在 $A\mathbf{u}$ 方向的平面上的投影面积，然后除以 $A\mathbf{u}$ 方向的平面与 $A^{-T}\mathbf{u}$ 方向平面夹角余弦值即可。现在，我们的问题化归为夹角为 $\theta$ 的两个平面交出的球面在其中一个平面上的投影面积

大概可以在脑海里想象这个画面，不妨设一个平面就是 xy 平面，然后假设 $\theta$ 大于 90 度，那么一部分投影就是一个半圆，另外一部分投影是什么呢，是一个椭圆，它可以看作是由另一个平面和球交出的圆的上半部分投影得到的，因此整体的投影面积就是
$$
S_{proj} = \pi C_e^2 \frac{1 + cos(\pi - \theta)}{2}
$$
这里用 $\pi - \theta$ 是因为它是用平面法向量点积来计算夹角时得到的角度。因此最终 $A_{\ell}^{\perp}(\mathbf{u}, \mathbf{v})$ 可以表示为
$$
A_{\ell}^{\perp}(\mathbf{u}, \mathbf{v}) = \pi C_e^2 \frac{1 + \frac{A\mathbf{u}\cdot A\mathbf{v}}{\|A\mathbf{u}\|\|A\mathbf{v}\|}}{2} |A| \|A\mathbf{u}\| = \frac{\pi C_{\mathrm{e}}^2(\|\mathbf{A u}\|\|\mathbf{A} \mathbf{v}\|+\mathbf{A u} \cdot \mathbf{A v})}{2 |\mathbf{A}|\|\mathbf{A} \mathbf{v}\|}
$$
现在我们来考虑 $G_1(\mathbf{u}, \mathbf{m})$，它表示法线为 $\mathbf{m}$ 的微表面在 $\mathbf{u}$ 方向上的可见面积比例。我们通常假设 $G_1$ 的值与法线方向无关，由此可以得到
$$
G_1(\mathbf{u}, \mathbf{m}) = \frac{\mathbf{u}\cdot \mathbf{n}}{\int_{H^2(\mathbf{n})}D(\mathbf{\mathbf{w}^\prime})max(0, \mathbf{u}\cdot \mathbf{w}^\prime)\,d\mathbf{w}^\prime}
$$
此即 PBRT4 9.6 节的 9.18 式。观察上面的表达式，如果我们分子分母同时乘以 $A_e^\perp(\mathbf{n})$，分母这个积分的含义就是 $A_{\ell}^{\perp}(\mathbf{u}, \mathbf{n})$。因此我们有
$$
G_1(\mathbf{u}, \mathbf{m}) = \frac{A_e^\perp(\mathbf{n})(\mathbf{u}\cdot \mathbf{n})}{A_{\ell}^{\perp}(\mathbf{u}, \mathbf{n})}
$$
带入我们已经求解出的 $A_e^\perp(\mathbf{n})$ 和 $A_{\ell}^{\perp}(\mathbf{u}, \mathbf{n})$，可知 $G_1(\mathbf{u}, \mathbf{m})$ 的表达式与 PBRT4 9.6 节的 9.19 式一致
### GGX 重要性采样
最后我们讨论 GGX 的重要性采样。基本的想法是说我们采样的概率函数 $p(\mathbf{m})$ 尽量与 $D(\mathbf{m})$ 成比例。由于
$$
\int_{H^2(\mathbf{n})} D(\mathbf{m})(\mathbf{m}\cdot \mathbf{n})d\mathbf{m} = 1
$$
因此我们可以取 $p(\mathbf{m}) = D(\mathbf{m})(\mathbf{m}\cdot \mathbf{n})$ 作为我们的概率密度函数，那如何采样它呢，注意到
$$
p(\mathbf{m})d\mathbf{m} = D(\mathbf{m})(\mathbf{m}\cdot \mathbf{n})d\mathbf{m} = \frac{dA^{\perp}}{A_e^\perp(\mathbf{n})}
$$
也就是说，我们只需要在椭圆上均匀采样，然后从该采样点沿着宏表面法线 $\mathbf{n}$ 发出射线与椭圆求交，椭圆交点处的法线就是我们采样得到的微表面法线

但这种采样方法没有将已经给定的出射方向 $\mathbf{u}$ 考虑进来，显然会采样到很多没有贡献的微表面法线（即 $\mathbf{u}\cdot \mathbf{m} \le 0$）。因此更好的方法是让 $p(\mathbf{m})$ 与 $D(\mathbf{m})(\mathbf{m}\cdot \mathbf{\mathbf{u}})$ 成比例，我们知道
$$
\int_{H^2(\mathbf{n})} D(\mathbf{m})(\mathbf{m}\cdot \mathbf{\mathbf{u}})\chi(\mathbf{m}\cdot \mathbf{\mathbf{u}}) d\mathbf{m} = \frac{A_{\ell}^{\perp}(\mathbf{u}, \mathbf{n})}{A_e^\perp(\mathbf{n})}
$$
因此取 $p(\mathbf{m}) = \frac{A_e^\perp(\mathbf{n})}{A_{\ell}^{\perp}(\mathbf{u}, \mathbf{n})}D(\mathbf{m})(\mathbf{m}\cdot \mathbf{\mathbf{u}})\chi(\mathbf{m}\cdot \mathbf{\mathbf{u}})$ ，并且
$$
p(\mathbf{m})d\mathbf{m} = \frac{A_e^\perp(\mathbf{n})}{A_{\ell}^{\perp}(\mathbf{u}, \mathbf{n})}D(\mathbf{m})(\mathbf{m}\cdot \mathbf{\mathbf{u}})\chi(\mathbf{m}\cdot \mathbf{\mathbf{u}}) d\mathbf{m} = \frac{dA_{\ell}^{\perp}(\mathbf{u}, \mathbf{n})}{A_{\ell}^{\perp}(\mathbf{u}, \mathbf{n})}
$$
这表明我们只需要均匀采样 $A_{\ell}^{\perp}(\mathbf{u}, \mathbf{n})$ 即可

为了采样 $A_{\ell}^{\perp}(\mathbf{u}, \mathbf{n})$，我们还是做一个线性变换 $\mathbf{p}\prime = A\mathbf{p}$（容易知道，对线性变换后的面积均匀采样，就相当于对线性变换前的面积均匀采样），然后均匀采样变换后的球体上的有效面积沿着 $A\mathbf{u}$ 方向投影到法线为 $A^{-T}\mathbf{u}$ 平面上的面积。而平面的投影显然也不改变均匀采样的性质，因此我们又只需要均匀采样变换后的球体上的有效面积沿着 $A\mathbf{u}$ 方向的投影面积。而由前面的讨论我们知道，这个投影面积由一个半圆和一个椭圆组成，我们可以通过一个仿射变换将其变回一个圆。最终问题就划归为在圆上的均匀采样了

这个采样和变换的步骤就是 PBRT4 的 9.6 节中采样 visible normal 的方法。有一点需要注意的是，PBRT4 中为了使仿射变换的表达式简单，采样时选取的坐标轴是以 $A\mathbf{u}$ 作为 z 轴，两平面的交线作为 x 轴，y 轴由 z 和 x 轴叉乘得到，这样使得仿射变换就是对 y 坐标分量进行压缩

TODO：解释折射情况下如何做重要性采样
TODO：解释 G2 项，即 PBRT4 9.6 节式子 9.22 的来历

TODO：irradiance map 以及 IBL 的实现，然后还有论文 [An Efficient Representation for Irradiance Environment Maps](https://zhuanlan.zhihu.com/p/363600898)！



TODO:
$$
f_s(p,w_i,w_o) = k_d\frac{c}{\pi} + k_s\frac{F(w_o\cdot w_m)D(w_m)G(w_i, w_o,w_m)}{4 cos\theta_o cos\theta_i}
$$
LearnOpenGL 上使用的微表面是这个，$k_d,k_s$ 是哪来的