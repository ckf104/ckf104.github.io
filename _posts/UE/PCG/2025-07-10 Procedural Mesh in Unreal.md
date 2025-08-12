~~TODO：procedural mesh 的 CreateMeshSection 函数中的 triangle index 是以什么规则生成三角形的？strip 还是就是每 3 个 index 对应一个三角形之类的~~
看起来就是每 3 个 index 生成一个三角形

tangent 是哪个方向？看起来应该是 uv 坐标中的 u 轴的方向
**TODO：看看 `UKismetProceduralMeshLibrary::CalculateTangentsForMesh` 的实现**


perlin noise，unreal 中已经实现好了，FMath::PerlinNoiseXD，当输入的浮点数小数部分相同，并且整数部分相差是 256 的倍数时，输出的随机数相同。[一篇文章搞懂柏林噪声算法，附代码讲解](https://www.cnblogs.com/leoin2012/p/7218033.html) 中讨论了综合不同振幅和频率的 perlin noise 的技巧，事实上，[Unreal Engine 5 - Runtime Terrain Generation #2 - Heightmap Improvements](https://www.youtube.com/watch?v=u4oBSj5r_ck) 中也是这么做的

打开 mesh 视图，看看 landscape 的 mesh 情况

[UE5 Open World #3 - Procedural Landscape Material Layers](https://www.youtube.com/watch?v=jH8s_NRucWA) 这篇做 landscape 的材质看看


有个 stat unitgraph 以图的形式查看实时性能


World 的 `OriginLocation` 是做什么的，它和 world partition 有关系吗，在 world partition 存在时，是否需要注意动态调整 actor relative location
```c++
/** Current location of this world origin */
FIntVector OriginLocation;
```