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

TODO：菲涅尔反射项的贴图跑哪去了？
TODO：记录 PBR 中其它的贴图