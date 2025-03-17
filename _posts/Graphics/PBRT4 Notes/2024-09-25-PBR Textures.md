### diffuse texture 与 albedo texture 的区别
我的理解是 diffuse texture 是在非 PBR 渲染中使用的，用来获取漫反射项的系数，例如 bling-phong shading 中的漫反射项为
$$
L_d = k_d\frac{I}{r^2}max(0,n \cdot l)
$$
一般 $l,n,v$ 分别指代光源方向，法线方向，视线方向。这里 $k_d$ 就是从 diffuse texture 中获取的。而 albedo texture 通常用来指定 PBR 中 lambertian material 的反射系数。这么一看两者好像挺相似的，因为如果我们假设光源是点光源的话，根据渲染方程有
$$
L_d = \frac{k_{lam}}{\pi}\int \frac{I}{r^2}\delta(w)cos\theta dw = \frac{k_{lam}}{\pi}\frac{I}{r^2}max(0,n \cdot l)
$$
可以看到，在这种情况下，两者只差一个常系数 $\pi$，但在其它情况下两者就无法比较了，因为它们参与的着色方程完全不一样。另外一个比较重要的点是，diffuse texture 通常会包含一些裂痕，阴影来制造一些真实感，例如 [LearnOpenGL Light Maps](https://learnopengl-cn.github.io/02%20Lighting/04%20Lighting%20maps/) 一节中使用的 diffuse texture。而 albedo texture 中不会包含这些，因为这些是由 PBR 中其它贴图考虑的事情，例如 roughness texture 等等
### Metallic-Roughness Workflow and Specular-Glossiness Workflow
[Adobe The PBR Guide - Part 2](https://www.adobe.com/learn/substance-3d-designer/web/the-pbr-guide-part-2) 讨论了这两种基于 PBR 的 workflow。我的理解是这两种 workflow 都基于同样的 brdf
$$
f_s(p,w_i,w_o) = k_d\frac{c}{\pi} + k_s\frac{F(w_o\cdot w_m)D(w_m)G(w_i, w_o,w_m)}{4 cos\theta_o cos\theta_i}
$$
即一个漫反射项混合一个微表面模型，其中漫反射项模拟光线折射进入非金属内部后又被散射回来的贡献。Metallic-Roughness Workflow 主要包含以下几类的 texture
* Metallic texture：包含 0，1 二值用于指示该点是否是金属
* base color texture：对于金属而言，纹理包含的 RGB 值指示该点的 F0 菲涅尔反射率，对于非金属而言，指示该点漫反射系数
* roughness texture：表示微表面模型的 roughness 参数

Notes:
* 金属没有漫反射项
* 非金属的 F0 是一个用户可配置的常量（而不是在 3D 模型中处处都可能不一样）

Specular-Glossiness Workflow 主要包含这三类 texture
* albedo / diffuse texture：指示非金属的漫反射系数，如果该点为金属，则值为 0,0,0
* specular texture：指示金属和非金属的 F0 菲涅尔反射率
* glossiness texture：指示光滑程度，我觉得就是 1 - roughness 这种感觉

Notes：
* 相比于 Metallic-Roughness Workflow，Specular-Glossiness Workflow 可以指示非金属的 F0 菲涅尔反射率，但需要注意设置合理的值，避免能量不守恒了
* Specular-Glossiness Workflow 的总 texture 会占用更大的内存

注：菲涅尔项可以用 Schick 近似，反射率 R 为
$$
R = F_0 + (1-F_0)(1-cos\theta)^5
$$
F0 菲涅尔反射率就是入射角为 0 时的反射率，也称为基础反射率


TODO：brdf 中的 $k_d$ 和 $k_s$ 参数是如何设置的？
TODO：如果允许 metallic 取 0 - 1 之间的值，brdf 是什么样的
TODO: 看看 UE 里材质编辑器里的 Fresnel 节点是啥意思