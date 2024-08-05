传统延迟渲染被诟病的缺点

* 带宽
* 不支持 MSAA
* 不支持多种材质

## Light Volumes

[Deferred Shading - Part 2](https://ogldev.org/www/tutorial36/tutorial36.html)

渲染一个实际的球体使得实际的渲染只处理光源周围的物体

[Deferred Shading - Part 3](https://ogldev.org/www/tutorial37/tutorial37.html)

使用精妙的模板测试处理：

* 对于前向面，当深度测试失败时，模板值减一
* 对于背向面，当深度测试失败时，模板值加一

由此会发现仅在有效的渲染点上，模板值为 1（不论摄像机在球体里还是球体外）。但这需要逐光源地做模板测试，渲染。然后下一个光源 clear 模板值。评论区有人认为这样逐光源搞太慢了，直接所有的光源一起做模板测试，然后再渲染模板值不为 0 的点。这样速度会快一些，但会产生 overdraw（例如一个物体被光源 A 覆盖，并且在光源 B 外，但如果屏幕空间中物体在光源 B 代表的球体中，那么渲染光源 B 代表的球体时，就会渲染该物体）

## Light-Pre Pass

[Deferred lighting approaches](https://www.realtimerendering.com/blog/deferred-lighting-approaches/) 讲得不错，最后混合的时候逐 mesh 进行使得可以一定程度支持多种材质

结果：减小 G-Buffer，一定程度上支持多种材质，支持 MSAA

## Tile-Based Deferred Rendering

[延迟渲染的前生今世](https://zhuanlan.zhihu.com/p/28489928) 讲得不错，[Directx11进阶教程之Tiled Based Deffered Shading](https://blog.csdn.net/qq_29523119/article/details/115837278) 包含一些代码。这个方法主要是解决做 light culling 的

结果：减少每个光源的着色次数

对于传统的 deferred rendering，我们可以在 pixel shader 里求每个光源是否能渲染到当前的像素，如果能那么就计算着色

**这样性能会比预先分 tile，计算每个 tile 会被哪些光源影响的 TBDR 方法差吗？唯一只是前者是为每个像素算一次与光源求交，而分 tile 的方法是 tile 整体与光源求交，后者可能计算量更小一点吗？**

## Forward+

然后是 [Forward+ Shading](https://zhuanlan.zhihu.com/p/85615283)，[Forward-Plus-Renderer](https://github.com/bcrusco/Forward-Plus-Renderer) 是一个可以参考的实现，但我还不是很确定最后的 shading 是怎么做的，目前的猜想是最后的 shading 需要重新提交一遍场景中所有的物体（但由于有 z-prepass 提供的深度图，所以也不会 overdraw？）

这里有一篇[forward和tiled-based-deferred性能比较](http://www.klayge.org/2013/04/25/forward%E5%92%8Ctiled-based-deferred%E6%80%A7%E8%83%BD%E6%AF%94%E8%BE%83/)

结果：减小 G-Buffer，减少光源着色次数，支持多种材质，支持 MSAA，不过速度肯定比不上 TBDR



TODO：这样改进的方法对 MSAA 的支持如何？

TODO：另外的关于 TBDR 的含义：区别于 PC 端通常的 ***Immediate Mode Renderers***，移动端更多地采用了 ***Tile-Based (Deferred) Rendering*** 的渲染模式

* [移动设备GPU架构知识汇总](https://zhuanlan.zhihu.com/p/112120206)，这篇大概讨论了 TBR 和 TBDR 的区别
* [A look at the PowerVR graphics architecture: Deferred rendering](https://blog.imaginationtech.com/the-dr-in-tbdr-deferred-rendering-in-rogue/) 和 [A look at the PowerVR graphics architecture: Tile-based rendering](https://blog.imaginationtech.com/a-look-at-the-powervr-graphics-architecture-tile-based-rendering/) 讨论了 PowerVR 上的 TBDR

TODO: 延迟渲染如何处理不同的材质？

TODO: [Stencil Shadow Volume](https://ogldev.org/www/tutorial40/tutorial40.html)

## Visibility Buffer and Deferred Material

 Bindless Texture