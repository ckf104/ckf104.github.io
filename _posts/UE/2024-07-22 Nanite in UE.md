[UE5渲染技术简介：Nanite篇](https://zhuanlan.zhihu.com/p/382687738) 中比较 High Level 地讨论了一下

> 另一个优化方向是减少CPU和GPU之间的数据通讯，以及更加精确的剔除对最终画面没有贡献的三角形。基于这个思路，诞生了**GPU Driven Pipeline**。关于GPU Driven Pipeline以及剔除的更多内容，可以读一读笔者的这篇文章[[4\]](https://zhuanlan.zhihu.com/p/382687738#ref_4)。得益于GPU Driven Pipeline在游戏中越来越广泛的应用，把模型的顶点数据进一步切分为更细粒度的**Cluster**（或者叫做**Meshlet**），让每个Cluster的粒度能够更好地适应Vertex Processing阶段的Cache大小，并以Cluster为单位进行各类剔除（**Frustum Culling，Occulsion Culling，Backface Culling**）已经逐渐成为了复杂场景优化的最佳实践，GPU厂商也逐渐认可了这一新的顶点处理流程。但传统的GPU Driven Pipeline依赖Compute Shader剔除，剔除后的数据需要存储在GPU Buffer内，经由Execute Indirect这类API，把剔除后的Vertex/Index Buffer重新喂给GPU的Graphics Pipeline，无形中增加了一读一写的开销；此外顶点数据也会被重复读取（Compute Shader在剔除前读取以及Graphics Pipeline在绘制时通过Vertex Attribute Fetch读取）。基于以上的原因，为了进一步提高顶点处理的灵活度，NVidia最先引入了Mesh Shader[[5\]](https://zhuanlan.zhihu.com/p/382687738#ref_5)的概念，希望能够逐步去掉传统顶点处理阶段的一些固定单元（VAF，PD一类的硬件单元），并把这些事交由开发者通过可编程管线（Task Shader/Mesh Shader）处理

GPU Driven Pipeline,  Frustum Culling / Occulsion Culling / Backface Culling, Cluster / Meshlet, Mesh Shader，indirect rendering 这篇文章的引用也很值得看看

## CustomDepth

在 ue5.3 的代码里，FRelevancePacket::ComputeRelevance 函数中，NaniteMesh 的 StaticMeshRelevance 的 LODIndex 为 -1，因此下面的检查会不通过

```c++
LODToRender.ContainsLOD(StaticMeshRelevance.LODIndex)
```

这使得 AddMeshBatch 回调函数不会被调用

但在 FRelevancePacket::ComputeRelevance 函数最后，将需要渲染 CustomDepth 的 Nanite 的信息作为一个 FPrimitiveInstanceRange 塞到 NaniteCustomDepthInstances 中，这个最后在 FRelevancePacket::Finalize 函数中塞到了 FViewInfo 的 NaniteCustomDepthInstances 中