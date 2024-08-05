TODO：[Unreal Engine 4 Rendering Part 1: Introduction](https://medium.com/@lordned/unreal-engine-4-rendering-overview-part-1-c47f2da65346)

TODO：https://github.com/chriscummings100/signeddistancefields，这个系列对 sdf 的讲解不错，可惜 shader 是用 unity 写的

TODO：https://blog.csdn.net/Game_jqd/article/details/121708448，这篇讲 sdf 怎么做字体渲染

TODO：理解 High Dynamic Range，我尤其关心 UE 里面是怎么弄这个的（看起来材质编辑器里的 emissive color 是可以输入大于 1 的颜色来实现 HDR，但是 base color 可能没啥用）

TODO：[Large World Coordinate](https://dev.epicgames.com/documentation/en-us/unreal-engine/large-world-coordinates-rendering-in-unreal-engine-5)，在 shader 中满天飞的 FLWCVector3 看起来和这个有关系

TODO：https://medium.com/@shinsoj/lighting-features-cheat-sheet-5b81b63b3ab7，feature cheating sheet

## Shadow

TODO：Mesh Distance Fields  vs Global Distance Fields

TODO：SSAO  -> Distance Field Ambient Occlusion，这里有一个 DFAO 在 unity 中的实现，https://zephyrl.github.io/SDF-Unity/   ，虽然我没看明白咋做的

## Reflection

## Blending

区分几种 Blending 下可能的深度测试方式

* 关闭深度测试：这种我感觉不太可能，因为如果 translucent 被一个 opaque 遮挡的话，关闭深度测试会导致 opaque 也被画出来
* 正常深度测试：这种会导致的问题是，如果物体 A 排序在物体 B 后边，但同时 A 有一小部分在物体 B 前边，由于会先画物体 A，导致最终物体 B 在物体 A 后面的一小部分被物体 A 完全遮挡了（LearnOpenGL 的 Blending 一节采取的这种方式）
* 正常深度测试，但关闭深度写入：我感觉这种是最合理的，UE 对外表现的行为也是这种（虽然没看到源码，但是设置 Translucency Sort Priority 使得深度值更小的物体先画，但这个物体并没有将后面的物体遮挡住）

关于 Niagara 以及 Component 级别中 UE 排序的处理：[Niagara 5.3 Sorting Mini Tutorial](https://realtimevfx.com/t/niagara-5-3-sorting-mini-tutorial/24380) 讲得特别好
