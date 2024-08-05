## Asset Manager Module

FAssetToolsModule 负责管理 Asset

LoaderUtils.cpp 中展示了 UE 中如何创建新的 asset：创建一个 UTexture2D，它的 owner 设置为一个 UPackage，这就得到了一个 2D 纹理的 asset

LoadUtils.cpp 的第 51 行，Mipmap 的类型需要加引用，Mipmap 中的 bulkData 和 TextureResource 中的 UE::Serialization::FEditorBulkData BulkData 有啥区别

## Material

四种材质：



## 预处理

[PLY Polygon File Format](https://web.archive.org/web/20161221115231/http://www.cs.virginia.edu/~gfx/Courses/2001/Advanced.spring.01/plylib/Ply.txt)，目前生成的 ply 文件内容中的 f\_dc\_* 表示 RGB 的 一阶球谐函数系数。f\_rest_\* 表示更高阶的球谐函数系数，前15 个是 R，中间 15 个是 G，后 15 个是 B 

从 ply 文件中得到 LumaRenderSDK::Gaussians 结构体，包含了全部高斯点的信息，动态库中的 LUMA_load_splat_ply 函数负责将 ply 文件转换为 LumaRenderSDK::Gaussians

动态库中的 LUMA_UE_chunk_gaussians 函数负责从 LumaRenderSDK::Gaussians 得到 LumaRenderSDK::GaussianChunks，每个chunk 代表一部分的高斯点，indice 字段用来是 Gaussians 中 data 数组的索引

LumaSplatLoader.cpp 中，InitializeF16GaussianTextureDataPerTexel 函数，为什么要 copy 第二遍数据。以及在 CreateGaussianChunkLuma 中为啥要对高斯点的坐标做一个旋转（我猜是训练的时候用的坐标轴和 ue 的坐标轴不一样把）

## 数学推导

[多元高斯分布的协方差矩阵](https://www.cnblogs.com/harold-lu/p/16686272.html) 证明了正定的协方差矩阵可以分解为 Scale + rotation 矩阵（Scale 矩阵是一个对角矩阵，它对角线上的值是协方差矩阵的本征值开根号的-1次方，这相当于椭圆的半轴值取倒数）

[3D Gaussian Splatting中的数学推导](https://zhuanlan.zhihu.com/p/666465701) 给出高斯分布的许多性质，高斯分布在卷积后，线性变换后新的协方差矩阵形式等。**以及给出了 reconstruction kernel 的形象定义**



## 区别

**HLSL 中矩阵初始化 float3x3 使用的是行主序（即前三个数对应第一行），而 cuda 中用的 glm 使用的列主序（即前三个数对应第一列）**

3Dgs 的投影矩阵定义在 graphics_utils.py 文件中的 getProjectionMatrix 函数中，从 [深入理解透视矩阵](https://www.zhyingkun.com/perspective/perspective/) 的讨论中，我认为 3Dgs 用的是左手系，与 UE 中的投影矩阵完全一致（将 z 值映射到 0 到 1 这个范围）。**3Dgs 使用这个投影矩阵来算高斯点在 image plane 上的位置，但是在投影 3D 高斯分布到 2D 时却采用的是相机的内参矩阵，为什么？**

3Dgs 在计算投影矩阵的雅克比矩阵 J 时，做了一个截断（这个截断大概的意思就是将在视锥外面的椭球压到里面来，不太确定这个事情有没有必要），但在 ue 渲染中没有类似的处理

```c
	const float limx = 1.3f * tan_fovx;
	const float limy = 1.3f * tan_fovy;
	const float txtz = t.x / t.z;
	const float tytz = t.y / t.z;
	t.x = min(limx, max(-limx, txtz)) * t.z;
	t.y = min(limy, max(-limy, tytz)) * t.z;
```

对于投影在屏幕外的点，只要它的半径够大覆盖到一个 rect，3Dgs 仍然会把它加入渲染中，但 ue 的粒子系统会如何处理我还不太清楚。另外，3Dgs 中会直接去除掉距离相机过近的点（z 值小于 0.2，见 in_frustom 函数）

UE 中使用的坐标系与 3Dgs 训练时的坐标系不同？

~~UE 里面算 alpha 的值是使用的高斯分布没有用到 cov2D？~~ 通过设置粒子旋转和缩放就达到了相同的效果，但我认为粒子的大小设置非常关键？

TODO：**粒子的大小设置得合不合适？粒子的旋转方向设置得对不对？niagara 的 sprite rotation 是顺时针旋转的角度**

3dgs cuda 的 depth 分量是椭圆中心 view 坐标系中的 z 分量，ue 里面排序半透明物体使用的 depth 分量是哪个？如果是使用 view 坐标系中的 z 分量，或者是投影矩阵变换后的 z 分量，结果应该都是相同的

3dgs cuda 中计算颜色时使用的二维高斯分布为 $e^{-\frac{1}{2}(x-p)^T\sum^{-1}(x-p)}$，注意没有乘常量因子

3dgs cuda 中椭球颜色是通过球谐函数得到的，而 ue 中则是每个椭球一个固定的 rgb

3dgs cuda 中 computeCov3D 函数计算 world space 的协方差矩阵 $\sum=R^TS^TSR$，但 ue 中是 $\sum=RSS^TR^T$

* 上面的论述错误，两者都是用的 $\sum=RSS^TR^T$，只是 glm 是列主序，所以看起来和 ue 中有点不一样

查看 3dgs cuda 源码时，里面也存在 scale modifier 之类的，在 ue 中则是固定为 100，在训练时计算梯度是否有对齐？

TODO：看下 3dgs cuda 中 depth 分量是怎么算的，看下具体的渲染过程，我主要关心最后的颜色是怎么算出来的，**给协方差+0.3的 trick 做低通滤波，这个在反向传播时是否有考虑到？**

~~TODO：看下源码中是如何运用 shs 的~~

TODO：看下源码中是如何处理分 chunk 操作的

TODO：训练是如何选择相机视角的，我猜想是给一个3D场景的多个视角图，然后每次从这几个视角中随机选择一个，那整个重建过程我应该理解为有一个神秘的网络，它根据一张或多张输入视角图生成高斯点云，然后数据就是很多的3D场景以及它们的视角图？推理过程就是进行泛化？还是说没有办法泛化，对于每个场景都需要根据视角图单独训练？我猜想大概率是后者？**如何根据视角图设置 fov, n, f 等摄像机参数呢**

## 目前的修改

~~将输入的 color 拆分为 shs index + opacity~~

输入的 color 就是 base color + opacity，其中 base color = SH_C0 * shs0 + 0.5f

**需要对输入的 scale 做 sigmoid 操作吗**，在场景中又对 component 进行了 scale，这和对粒子进行 scale 有区别吗？