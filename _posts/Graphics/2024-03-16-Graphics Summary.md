---
title: Graphics Summary
date: 2024-03-16 4:42:36 +0800
math: true
categories: [Graphics]
---

## Transformation

* local  space：以待渲染的物体为中心的坐标系
* world space：将所有待渲染的物体都容纳进来的坐标系
* view space：以摄像机为原点的坐标系（这里应当先把摄像机平移到原点，再按照摄像机的朝向旋转），**其中 up 方向指定了世界坐标系中哪个方向作为屏幕空间中向上的 y 轴**
* clip space：经过投影变换后，坐标范围缩到 -1, 1 的坐标系
* model matrix 将物体从 local space 变换到 woxrld space，view matrix 将物体从 world space 变换到 view space，projection matrix 将物体从 view space 变换到 clip space
* 关于为什么会有 local space，因为在建模的时候，通常是一个物体一个物体建模，因此得到的物体坐标总是以物体为中心的。另外，如果我们希望画大量重复物体，那么只用一组坐标，然后通过变换得到若干相同的物体是更可取的。local space 到 world space 施加变换的顺序通常是 scaling，rotation，translation。在 local space 进行 scaling，使得 scaling 的结果不依赖于 rotation 的选择

注意投影矩阵对 z 值的变换表达式，它是关于 z 的反比例函数，意味着它对近平面的 z 值变化比远平面更加敏感，远平面的物体更容易出现 z fighting 的现象。这也意味着，更多的 z 值会集中远平面，即在 1 附近，而浮点数的表示方法使得 0 附近的表示精度比 1 附近大得多，这就是 [Reverse Z](https://tomhultonharrop.com/mathematics/graphics/2023/08/06/reverse-z.html) 要解决的问题。Reverse Z 的映射是反过来的，将远平面上的数映射到 0 附近，而近平面上的数映射到 1 附近（Z 的取值范围为 0 到 1）。此时应该 Z 值大的通过深度测试（**默认深度测试的比较函数是 GL_LESS，深度值小的才会通过测试**）

为了在 OpenGL 中实现 Reverse Z，除了使用新的投影矩阵外，还需要做如下的事情

* glDepthFunc 使用 GL_GREATER
* glClipControl 中 depth 变换使用 GL_ZERO_TO_ONE（因为 OpenGL 默认会认为在 vertex shader 中输出的 z 值范围是 -1 到 1，然后它会利用 glDepthRange 给出了 n 和 f 值将 depth 变换到 0 到 1，这个函数就是告诉 OpenGL 我们输出的 depth 值已经在 0 到 1 了）

* 我们可以将远平面拉伸到无限远处，f -> 无穷大，得到极限情况下的透视矩阵（我觉得这个透视矩阵才符合现实）
### 手系对变换矩阵的影响
从 glm 的源码中可以看出，左手系和右手系，以及其它一些因素都会对最终的变换矩阵产生影响
* model 变换不受影响
* view 变换会受影响。左手系中通常摄像机看向 z 的正半轴，而右手系中摄像机看向 z 的负半轴。通常的 lookAt 函数要求 eye pos 和 focal point 参数，因此左右手系会决定到底 z 轴是朝哪边的，进一步影响 view 变换的结果
* 投影变换会受影响。虽然从 [深入理解透视矩阵](https://www.zhyingkun.com/perspective/perspective/) 的推导可以看出，当透视投影矩阵的 $n$ 和 $f$ 是带符号的坐标值时，投影变换的形式是不依赖于手系的，但在实际的实现中，有两个方面的因素导致它会受到手系的影响
	* 一个是这些数学库提供的接口都假定用户传入的 $n,f$ 是不带符号的绝对值，这使得库内部的实现需要分辨用户使用的是左手系还是右手系
	* 另一个是习惯上，右手系的透视投影矩阵会整体乘以 -1（由齐次性，这不会改变矩阵的变换），使得右手系下 $m[3][2]$ 的值为 -1 而不是 1，便于用户分辨
* 除了手系外，深度映射的范围（0 到 1 还是 -1 到 1，是否需要 reverse Z）也会影响投影变换的形式
* OpenGL 等图形学 API 本身是没有手系这个概念的，但约定了屏幕坐标系中原点在屏幕左下方
* 右手系摄像机看向 z 轴负方向，而左手系摄像机看向 z 轴正方向。这个约定我觉得是为了匹配屏幕坐标系中原点在屏幕左下方这个约定。如果不这样做，例如右手系下摄像机看向 z 轴正方向，就会感觉渲染出来的结果和三维空间想象的结果左右或者上下翻折了
### Quaternions
[四元数与三维旋转](https://krasjet.github.io/quaternion/quaternion.pdf) 已经讲得足够好了，我这里做一些额外的补充

一个是 slerp 插值，现在有四元数 $q_1$，$q_2$。[四元数与三维旋转](https://krasjet.github.io/quaternion/quaternion.pdf)  提到朴素的插值方法是
$$
q(t) = (q_2q_1^{-1})^t q_1
$$
显然这个插值方法是恒定角速度的（设想一个刚体原本是 $q_1$ 朝向，希望旋转到 $q_2$ 朝向，那么 $q_2 q_1^{-1}$ 实际上给出了刚体的旋转轴 $\mathbf{u}$ 和旋转角度 $\theta$，$(q_2q_1^{-1})^t$ 就是将刚体绕着轴 $\mathbf{u}$ 旋转 $t\theta$

文中使用 [Geometric slerp](https://en.wikipedia.org/wiki/Slerp) 作为四元数的 slerp 插值。推导出的结果为
$$
q(t) = \frac{sin[(1-t)\theta]}{sin\theta}q_1 + \frac{sin[t\theta]}{sin\theta}q_2
$$
从推导过程可以看出，插值过程中 $q(t)$ 与 $q_2$ 的夹角减小速度保持恒定，但是不太能明显看出插值过程中的旋转轴保持恒定。现在我们说明这个朴素的插值方法就是 slerp 方法，因此 slerp 方法确实保持插值过程中角速度恒定

记 $q_2q_1^{-1} = [cos\theta, \mathbf{u}sin\theta]$，我们有
$$
\displaylines{
\begin{align*}
q(t) &= \frac{sin[(1-t)\theta]}{sin\theta}q_1 + \frac{sin[t\theta]}{sin\theta}q_2 \\
&= (\frac{sin[(1-t)\theta]}{sin\theta} + \frac{sin[t\theta]}{sin\theta}[cos\theta, \mathbf{u}sin\theta])q_1 \\
&= [cos[t\theta], \mathbf{u}sin[t\theta]]q_1 \\
&= (q_2q_1^{-1})^t q_1
\end{align*}
}
$$
因此这两个插值方法是一致的

另外一个是四元数的指数表示，记 $q = [cos\theta, \mathbf{u}sin\theta]$，[Quaternions, Interpolation and Animation](https://web.mit.edu/2.998/www/QuaternionReport1.pdf) 中定义了 $log\,q=[0,\mathbf{u}\theta]$  $e^{log\,q} = q$，但这并不意味着说指数表示也满足乘法（除非旋转轴相同），即 $e^{\mathbf{u_1}\theta_1 + \mathbf{u_2}\theta_2} \neq q_1*q_2$，要说明这一点也很简单，因为指数乘法是满足交换律的，但四元数的乘法是不可交换的

在 [Quaternions, Interpolation and Animation](https://web.mit.edu/2.998/www/QuaternionReport1.pdf) 的 proposition 29 证明了 slerp 总是沿着较短的圆弧插值过去的（即旋转夹角小于等于 180 度），对应的三维空间旋转角度小于等于 360 度。但由于 -q 和 q 表示相同的旋转，因此我们总是可以使得需要插值的两个四元数的夹角小于等于 90 度，这样得到的三维空间的旋转角度小于等于 180 度

TODO：解释四元数的导数和角速度定义
TODO：解释 squad 插值
### Pinhole Camera Model

真实的 pinhole camera model，内参矩阵：fx, fy, cx, cy，见 [Why does the focal length in the camera intrinsics matrix have two dimensions?](https://stackoverflow.com/questions/16329867/why-does-the-focal-length-in-the-camera-intrinsics-matrix-have-two-dimensions) 的讨论，高赞回答引用的 learn opencv 一书中的描述解释得很到位
$$
f_x = F * s_x,\quad f_y = F * s_y
$$
其中 $F$ 正常的 focal length，即 camera 到 image plane 的距离，而 $s_x$ 表示 1 物理世界的单位长度对应 x 方向上多少个像素，类似 $s_y$ 是对应 y 方向上多少个像素（这里是考虑了像素可能不是一个正方形的情况）。因此 $f_x$ 和 $f_y$ 表示了以 x 或者 y 方向的像素长度为单位，$F$ 的长度是多少



### Lens Camera

TODO

### Fisheye Camera

TODO

## Rasterization

* 光栅化的想法是在屏幕上一个一个画物体，然后根据 z-buffer 来判定遮挡。在 cpu 程序中，传入一组顶点，表示物体由这些顶点组成的若干三角形构成。在 vertex shader 中，通过变换算出顶点的 `gl_position`，该坐标用于计算插值要用到的重心坐标。三角形光栅化后每个像素点会调用 fragment shader，在 fragment shader 中实际计算出该像素点的颜色。

* 基本的 bling-phong 着色模型由环境光，漫反射光，高光三部分组成。为了在 fragment shader 中确定像素具体的颜色，我们需要该像素点的坐标，以及光源的坐标，再加上摄像机的坐标（在 LearningOpenGl 的教程中，计算是在 word space 下完成的，如果在 view space 下进行，摄像机的坐标就是原点了），以及该点的法线方向。这些都在 vertex shader 中输出，插值后传递给 fragment shader。**这里就有一些奇怪的地方，例如每个像素点的法线方向是由顶点的法线方向插值得到的，但实际上作为一个三角形，它的法线显然是固定的？为什么不直接使用这个三角形的法线呢**

* games101 中提到了三种着色方式：flat, vertex, pixel，flat 表示三角形作为着色基本元，每个三角形一种颜色。vertex 表示顶点作为着色基本元，每个顶点一个颜色，像素颜色根据顶点插值得到。而像素着色则是每个像素分别计算颜色。直觉上 vertex, pixel 这两种着色方式比较容易实现（前者只需要对顶点应用 bling-phong 着色模型即可）。不知道 flat 的 shader 要咋写

* 整个光栅化程序要求的输入：每个三角形的顶点坐标，顶点纹理坐标以及对应的纹理图，顶点法线。纹理用于增加模型的细节，例如每个像素点的材质，每个像素点的法线方向等等

* 关于透视矫正：这和写 shader 关系不大，但 opengl 需要意识到这一点。因为在光栅化时，我们只知道每个像素点在屏幕上的坐标，能用像素点在屏幕上三角形的位置来插值吗，不行的，因为透视映射会改变像素点在三角形内的重心坐标。透视矫正的含义就是说，根据像素点在屏幕上的重心坐标，来推出正确的属性插值（因为属性插值是 vertex shader 和 fragment shader 之间做的，与写 shader 没有直接关系）。具体的公式我很久以前已经写在[games101代码](https://gitee.com/ckf104/games101---job-code)中了。再大概补充一下推导原理。因为通常的平移，正交旋转不会改变重心坐标，我们只需考虑透视投影前后重心坐标的变化即可。但这里没有必要用投影矩阵去思考，因为透视投影后的三角形再将其投影到透视投影用的平面上时，这个三角形与原三角形的各点连线应该聚焦到投影点上（透视本身的含义）

* 关于 normal mapping 与 bump mapping 与的 TBN 矩阵

  * 首先解释 u，v 坐标轴的含义。根据重心坐标进行插值的纹理映射是可逆的，通常我们是求出来某点在世界坐标中的重心坐标，然后得到其纹理坐标，我们当然也可以反过来考虑由此 $$
    x = f_x(u,v), \quad y = f_y(u,v), \quad z = f_z(u,v)
    $$
    可以得到 T，B 轴。N 轴由叉乘得到 $$
  \vec{T} = (\frac{\partial{x}}{\partial{u}},\frac{\partial{y}}{\partial{u}},\frac{\partial{z}}{\partial{u}}) \quad \vec{B} = (\frac{\partial{x}}{\partial{v}},\frac{\partial{y}}{\partial{v}},\frac{\partial{z}}{\partial{v}}) \quad \vec{N} = \vec{T} \times \vec{B}
  $$
  * 一种直观理解 $\vec{T}$ 和 $\vec{B}$ 的方式是，当世界坐标中的三角形中的某个像素点沿着 $\vec{T}$ 方向移动时，它对应的 $(u,v)$ 坐标中仅有 $u$ 会移动，而 $v$ 保持不变（对于一般的可逆映射来说，只能对无穷小量成立，但这里的映射显然是线性的，因此它总是成立的）。$\vec{B}$ 也是同样的道理。这就是 u, v 轴的来历，即 $\vec{T}$ 和 $\vec{B}$ 代表了纹理坐标的变化方向

  * 那 $\vec{T}$ 和 $\vec{B}$ 是不是应该垂直呢？毕竟 u，v 轴本身是垂直的。是应该这样，只要这个映射没有发生形变。就是说，如果纹理图上的三角形与世界坐标中的三角形是相似的，那么 $\vec{T}$ 和 $\vec{B}$ 是垂直的。为了看出这一点，我们需要将上面的映射写为矩阵形式$$
    \vec{x} = A\vec{u} +\vec{b}
    $$
    这里我们将 $(u,v)$ 拓展为 $(u,v,0)$，因此 $A$ 是一个 3x3 的矩阵。可以知道 $\vec{T}$ 对应矩阵的第一列，而 $\vec{B}$ 对应矩阵的第二列。第三列由于没有实际作用，我们暂时不管。由于对世界坐标中的三角形平移常量不改变偏导数的值，因此我们可以不妨设 $\vec{b}$ 为 0，另外，由于两个三角形相似，我们可以对矩阵 A 乘以常量缩放因子 k，使得两个三角形全等（这并不改变 $\vec{T}$ 和 $\vec{B}$ 的方向），现在可以看出矩阵 $kA$ 实际上是一个保距变换，因此是一个正交矩阵，从而可知 $\vec{T}$ 和 $\vec{B}$ 垂直

  * 接下来我们说明上面的公式和下面实际应用中的公式其实是一致的。这里 $\vec{E_1}$ 和 $\vec{E_2}$ 是世界坐标中三角形的两条边，$\Delta{U_1}$ 和 $\Delta{U_2}$ 是在 这两条边对应到 u, v 坐标系中的边的 u 轴差值。$\Delta{V_1}$ 和 $\Delta{V_2}$ 是类似的，$\vec{N}$ 是顶点法线 $$
    \displaylines{
    \vec{E_1} = \Delta{U_1}\vec{t}+\Delta{V_1}\vec{b} \\
    \vec{E_2} = \Delta{U_2}\vec{t}+\Delta{V_2}\vec{b} \\
    \vec{T} = normalized(\vec{t} - (\vec{t}\cdot\vec{N})\vec{N}) \\
    \vec{B} = normalized(\vec{b} - (\vec{b}\cdot\vec{N})\vec{N} - (\vec{b}\cdot\vec{T})\vec{T})
    }
    $$
    因为在实际应用中，通常会告知顶点法线，因此 $\vec{N}$ 是已知的。然后容易看出，这里的 $\vec{t}$ 和 $\vec{b}$ 其实和理论公式中的 $\vec{T}$ 和 $\vec{B}$ 是一致的。如果顶点法线与三角形平面的法线一致，那么自然有 $\vec{t}$ 和 $\vec{N}$ 垂直，因此 $\vec{T} = \vec{t},\vec{B}=\vec{b}$
    
  * 在实际的实现上，我们会在 CPU 代码中计算每个顶点的 $\vec{T},\vec{B}$ 向量，然后作为顶点属性传入，由此可以插值得到每个像素点的 TBN 矩阵。但是  $\vec{T},\vec{B}$ 向量是逐三角形的，我们怎么得到单个顶点的 $\vec{T},\vec{B}$ 向量呢？最直接的做法是说不要使用 `GL_TRIANGLE_STRIP` 之类的模式复用顶点，这样每个顶点的 $\vec{T},\vec{B}$ 向量就是这个顶点对应的三角形的 $\vec{T},\vec{B}$ 向量。如果希望复用顶点，那么可以取顶点所在的所有三角形的 $\vec{T},\vec{B}$ 向量的平均作为自己的 $\vec{T},\vec{B}$ 向量（例如 [tutorial-13-normal-mapping](https://www.opengl-tutorial.org/intermediate-tutorials/tutorial-13-normal-mapping/)），当然这种做法引入了一些误差。也许也可以让建模软件导出模型时带上顶点的 $\vec{T},\vec{B}$ 向量，这样就不需要我们手动算了（顶点的 $\vec{T},\vec{B}$ 向量相关的这些考虑实际上和顶点的法线向量是非常类似的）
  * 比起插值得到每个像素点的 TBN 矩阵，但更常用的方法是将光源向量和视线向量都转到 TBN 空间中（因为 TBN 矩阵是正交矩阵，因此我们只需要取一个转置即可），这样不用在 fragment shader 中乘 TBN 矩阵转换法线到世界坐标系，会更快一些。当然，fragment shader 中看到的光源向量和视线向量都是 vertex shader 输出的值的插值。例如，在 PBRT4 中计算 radiance 都是在 TBN 空间进行计算的

  * bump mapping 中的高度位移是 normal mapping 的更原始形式。即当我希望制造一些凹凸感时，在 3D 软件中创造 bump mapping 更加直观，然后我们用 bump mapping 中的高度偏移，计算出实际法线方向，存储在 normal mapping 中

  * displacement mapping 相比于 bump mapping，会实际移动像素点在世界坐标中的位置

  * [cg tutorial](https://developer.download.nvidia.cn/CgTutorial/cg_tutorial_chapter08.html) 是上面这部分内容的重要参考

* 

* TODO：法线修正矩阵？（因为在做模型变换的时候，如果进行不等比的缩放会导致法线变换后不再垂直于平面）

* mipmap 的解释
  * 由于透视映射的关系，远离摄像机的三角形经过变换后面积会缩小。这意味着，本来在 3D 视图中，两个同样大小的三角形，对应在纹理图上也是同样大小（包含了同样多的细节）。但最终的 2D 屏幕上，离摄像机近的三角形会占据更多的像素点。那这里就有两个问题，一个是被放大的三角形可能会用过多的像素点表达没有那么多细节的纹理。另一个是被缩小的三角形需要用很少的像素点来表达丰富的纹理
  * 第一个问题很好解决，我们在像素点采样时进行插值即可（本质上是利用插值方法将纹理进行放大）
  * 第二个问题就比较麻烦了，仅仅是简单的插值是不行的。为什么？因为我们可以用微分的方法简单计算一个像素在纹理中占据面积，考虑 x 轴相邻的两个点的距离，再考虑这两个点映射到纹理图上的距离（类似也可以考虑 y 轴），就能大概知道这块区域中一个像素面积对应到纹理图上是多少面积。由于通常的插值仅考虑一个像素点映射到纹理图上时周边的四个纹素，但如果一个像素面积对应为纹理图上的许多面积，那实际上需要考虑周边许多的纹素
  * mipmap 就是用来解决这个问题的，它预先对纹理图按每次长宽除 2 进行缩放，得到许多级的纹理图。在实际做查询时，首先根据这个点对应的像素面积与纹理图面积的比值，来选择合适的一级纹理图，再正常插值得到最终的纹素。此时虽然仅考虑了周边四个纹素，但由于缩放的缘故，对应到原图可能就是一大片的面积了
  * 本质地讲，mipmap 实际上提供了一种范围查询的机制。在纹理图没有被缩放时，只能查询一个纹理面积对应的纹素。缩放后，我们可以查询 1x1, 2x2, 4x4 ... 这些大小的正方形范围对应的纹素（其它面积的正方形查询通过插值得到）。一些对 mipmp 的改进，例如 Anisotropic Filtering，则是提供了更多种的纹理图压缩，使得允许一般矩形的查询（虽然我看 opengl spec 中的描述感觉 Anisotropic Filtering 的实现就是在 mipmap 上采样多次）。以及 Summed Area Table，生成一张新的纹理，这张纹理的每个纹素值是一个它与原点围成的矩形包含的所有纹素在原纹理中的值的和，这样实际上就允许通过四次采样查询任何一个边与坐标轴对齐的矩形了

## Ray Tracing

基本的想法是：光栅化是一个一个画物体然后根据深度测试来判定物体的前后关系，光线追踪从每个像素点发出光线，然后依次判断每个像素点的颜色

### Whitted-Style Ray Tracing

我感觉这个不同的地方算法也有些不一样，在作业5中的算法是，从每个像素点发出光线后，判断与物体的交点。这里考虑了三种材质，一种是全反射，就是光线全部从表面反射出去（此时物体的材质类似于镜子）。然后是光线一部分反射，一部分折射（此时该物体的材质类似于玻璃球），最后是漫反射材质，这是递归的终止点，利用任意的着色模型进行着色（例如 bling-phong），这里注意判定光源是否被遮挡

然后也有地方的说法是在每个交点都要用着色模型进行着色，然后也许弹射若干次后终止？我想这两种说法都有些道理，具体哪种取决于材质吧

### Acceleration Structure

主要的目的是加速光线追踪中和物体的交点判断问题，如果依次和每个三角形进行判断太慢了。想法就是对空间进行划分，把三角形框在方形的包围盒。在判断相交时，首先对包围盒求交，这样减少了很多求交的判断。主要介绍了两种划分方法，KD-tree 和 BVH（Bounding Volume Hierarchy），两者都是二叉树的结构。KD-tree 是对空间进行不重复地划分，但可能导致有些三角形在多个包围盒中。BVH 是对三角形进行不重复的划分，但包围盒之间可能有空间上的重叠。比较来讲，BVH 更好用一点

### Radiometry

这是涉及基于物理的渲染，我们用物理学上的定义来刻画光源。主要引入了如下概念

* radiant energy：辐射能量 $Q$

* radiant flux：辐射通量 $\Phi=\frac{dQ}{dt}$，单位时间的辐射能量，对应功率

* radiant intensity：辐射强度 $I(w)=\frac{d\Phi}{dw}$，单位立体角上的辐射功率，这里等式左边的参数 $w$ 表示立体角的方位（转换到极坐标系中，需要用 $\theta$ 和 $\phi$ 两个参数刻画）

* irradiance：这玩意不知道咋翻译了，$E(p)=\frac{d\Phi}{dA}$，单位面积上的辐射功率，这里等式左边的参数 $p$ 是一个三维坐标

* radiance：也不知道咋翻译，$L(p,w) = \frac{d^2\Phi}{dwdAcos\theta}$，单位面积，单位立体角上的辐射功率，**这里的 $\theta$ 的值显然是依赖于 $w$ 的方向选取，多一个 $cos\theta$ 是因为 $dA$ 需要投影到垂直 $w$ 的方向**。可以看到这些物理量有些直观的关系，$L(p,w)$ 对半球立体角（注意，由于我们不考虑反方向的射过来的光，因此对立体角进行积分时只考虑一个半球面）进行积分，就可以得到 $E(p)$，表示单位面积的辐射通量。如果对一块面积进行积分，就可以得到  $I(w)$，表示这块面积上单位立体角的辐射通量

* 所谓物体的材质，刻画的属性是当有 irradiance $dE$ 从方向 $w_i$ 发射过来时，从各个方向 $w_r$ 散射出去的 radiance $dL$ 是如何分布的，即
  $$
  f(p,w_i,w_r) = \frac{dL_r(p,w_r)}{dE_i(p)} = \frac{dL(p,w_r)}{L_i(p,w_i)cos\theta_idw_i}
  $$
  我们可以将上面的式子写做积分式，并考虑物体自身发出的光，便可以得到著名的渲染方程，这里 $p$ 表示空间坐标，$w_i$ 和 $w_o$ 表示入射立体角和出射立体角，$n$ 表示 $p$ 点处法线方向，$L_e(p,w_0)$ 是对物体自身发光的刻画
  $$
  L_o(p,w_o) = L_e(p,w_o)+\int_{H^2}L_i(p,w_i)f(p,w_i,w_o)(n\cdot w_i)dw_i
  $$
  渲染方程中我比较困惑的一点是对输入的刻画是一个垂直于平面的能量项  $L_i(p,w_i)(n\cdot w_i)$，但是输出却是一个任意方向的 radiance，当然这可能不是本质的，因为也可以把 $n\cdot w_i$ 吸收到 $f(p,w_i,w_o)$ 中。不过最奇怪的还是能量守恒项的描述
  $$
  \int_{w_o} f(p,w_i,w_o) cos\theta_o dw_o \le 1
  $$
  它的推导是认为输出的能量大小是 $L_o(p,w_o)*cos\theta_o$，那与平面平行的那部分 radiance 从哪来的，从输入的与平面平行的 radiance 中来的吗，那为什么没有体现出这部分约束呢？
#### 各向同性 brdf
对于各项同性的 brdf，它的表达式可写为 $f(w_i,w_o) = f(\theta_i,\theta_o,\phi_i - \phi_o)$，其中 $\theta$ 是天顶角，$\phi$ 是方位角。对各项同性的 brdf 的直观理解是，如果用某一光源照射有着各项同性的 brdf 的小纸片，然后从某一固定视角接收到反射的光线。现在沿着法线方向将小纸片旋转任意角度，视角方向接收到的光照不变。另外一种理解是，如果给予各项同性的光照 $L_i(\theta_i)$，那么反射的光线 $L_o(\theta_o) = \int f(\theta_i,\theta_o,\phi_i - \phi_o)sin\theta_i d\theta_i d\phi_i$ 也是各项同性的（显然 $\phi_o$ 的取值不影响结果）

一个典型的例子是 GGX microfacet brdf，如果我们使用各向同性的 GGX 分布，那么法线分布 $D(h)$ 和自遮挡项 $G(h,l,v)$ 可以分别写为 $D(h \cdot n)$ 和 $G(l \cdot h, v \cdot h)$，这里 $h$ 是 视线方向 $v$ 和光照方向 $l$ 的半程向量。可以看出，当我们绕着法线方向对 $l$ 和 $v$ 同时旋转任意角度，$h \cdot n, l \cdot h, v \cdot h$ 的值都是不会改变的，因此 $D$ 和 $G$ 的值不变，进而可以推出 brdf 的值不变。因此各向同性的 GGX 分布会对应各向同性的 brdf
### Path Tracing

为了求解渲染方程，首先是用蒙特卡洛方法估计积分，取一个分布在 $[a,b] 上的$随机变量 $X$ 和它的概率密度函数 $pdf(X)$，那么我们为求 $\int_a^b{f(x)}$ ，我们有
$$
E(\frac{f(X)}{pdf(X)}) = \int_a^b\frac{f(x)}{pdf(x)} pdf(x)dx = \int_a^b{f(x)} \\
=>\int_a^b{f(x)} \approx \frac{1}{N}\sum_{i=1}^{N}\frac{f(x_i)}{pdf(x_i)}
$$
另一方面，渲染方程是递归的，我们通过递推的方式来求解

具体来说，对于每一根从像素点发出的光线，当它命中某个物体时，如果该物体不发光，那么根据蒙特卡洛估计有
$$
L_o(p,w_o) \approx \frac{1}{N}\sum_{i=1}^{N}\frac{L_i(p,w_i)f(p,w_i,w_o)(n\cdot w_i)}{pdf(w_i)}
$$
此时 $p$ 和 $w_o$ 都是已知量，我们需要在半球上对 $w_i$ 进行采样，同时递归地调用求解函数来得到 $L_i(p,w_i)$ 的值。这样的递归显然会导致指数爆炸，因此实际的情况是取 $N=1$，同时为了避免过大的噪声，每个像素点发出许多根光线（SPP，Samples per pixel）来平均

TODO：补充俄罗斯轮盘赌

TODO：在计算直接光照时，实际选择的 pdf 是面向光源采样的

TODO：实际得到的计算结果不是颜色，而是 radiance，如何转换为颜色？-> color space and gamma correction
## Shadow Mapping

参见 learn opengl 中的介绍

shadow acne 描述的现象是 self occlusion，就是一个本来不在阴影中的点，算出来的实际深度值比在 shadow map 中采样得到的深度值大，导致被误判为在阴影中

关于 shadow acne 的成因（参考 [关于ShadowMap中Shadow acne现象的解释](https://blog.csdn.net/n5/article/details/115617598) 和 [What causes shadow acne?](https://stackoverflow.com/questions/36908835/what-causes-shadow-acne)），主要来源于以下两个因素

* shadow map 的有限分辨率：在 shadow map 采样时会进行 linear filtering，当采样得到的值比实际的深度值小时，就会发生 shadow acne（当光线方向与平面垂直时，不存在这个问题，当光线与平面接近平行时，这个问题最严重）
* 浮点运算精度：不太确定这个是否会有影响（或者是一个更次要的影响），因为两次算实际深度值（一次在计算 shadow map 时，一次在使用 shadow map 渲染时）时的计算过程完全一样，按道理来说即使浮点运算产生误差，两次计算的误差也应该是完全相同的

简单的解决方法是在深度比较时加一个小的 bias，当采用的深度值比实际的深度值大 bias 时才认为该点在阴影中。另外，相邻点深度值的变化速度（深度值的变化速度决定了 shadow map 中采用时的误差）和光线方向有关，当顶点法线和光线平行时，相邻点的深度值完全相同，因此纹理采样不会有误差。而当法线和光线接近垂直时，深度值变化最快。因此最好 bias 的添加与光线和法线的夹角有一些关系

```c++
float bias = max(0.05 * (1.0 - dot(normal, lightDir)), 0.005); 
```

当添加的 bias 过大时，有可能造成 peter panning，即本来在阴影中的点被误认为不在阴影中（看起来像是物体悬空了一样）。一个缓和的方法是，在计算 shadow map 时，对于有完整表面的物体，可以采用 front face culling，这样使得在 shadow map 中存储的是在阴影中的 back face 的深度值，这样在第二遍的实际渲染中，front face 的实际深度值天然就比纹理中采样得到的值大（**但这显然导致的一个问题是，如果在第二遍的实际渲染中，本来在 shadow mapping 计算时的 back face 现在成了 front face，那么很有可能会错误地将阴影渲染为非阴影，在这种情况下 bias 我认为应该取一个负值来平衡一下**，另外，在 Games202 中讲到 Second-depth shadow mapping，深度纹理中的实际值是 front face 和 back face 的中间深度值）

另外还有的问题是由于 shadow map 的有限大小，如果在第二遍的实际渲染中的像素点在计算 shadow map 时的视锥之外，会导致采样时纹理坐标不在 0 - 1 之间，或者 z 值大于 1。这种情况下我们默认该点不在阴影中

最后的最后，上面的方法只能制造硬阴影，阴影与非阴影之间的边界非常清楚。为了模糊这个边界，制造软阴影，一种做法是 PCF（percentage-closer filtering），在采样点周围采样多次，根据阴影点占据的比例来着色

TODO：**Point Shadows（这里看看几何 shader）**，Cascaded shadow maps

## Order Independent Transparency

https://learnopengl.com/Guest-Articles/2020/OIT/Introduction，值得一读

## Volume Rendering

在 EWA Volume Splatting 论文中，将 Volume Rendering 大致分为两类

* backward mapping：类似光线追踪的方法
* forward mapping：类似光栅化的方法

TODO：论文中的 volume rendering equation 怎么来的
