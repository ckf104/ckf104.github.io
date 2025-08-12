## Global Shader

* global shader 的反射是怎么搞的， layout_field 宏相关

* 声明 shader 变量时，fshaderparameter.bind 干了啥？fshaderparameter 中的字段都是啥意思

* RDG 中的 passParameter 结构体中的 RenderTargets 字段来设置 renderTarget

* FRenderResource 到底是个啥，和 FRHIResource 的区别是什么

* uniform buffer 是全局的shader 参数是啥意思，`BEGIN_UNIFORM_BUFFER_STRUCT` 和 `BEGIN_GLOBAL_SHADER_PARAMETER_STRUCT` 有啥区别呢

* https://zhuanlan.zhihu.com/p/344573382 这篇文章谈到了 `FRHIVertexDeclaration`，它其实就是用来说明顶点属性的排布（在 opengl 里面有对应的函数，比如我现在有一个顶点数据 buffer，然后我就用这个 vertex declaration 说明buffer 中哪些数据是对应 shader 中 layout 0 的数据，哪些对应 layout 1 中的数据）。下面是一个典型

  ```c++
  class FMediaVertexDeclaration : public FRenderResource;
  
  struct FMediaElementVertex
  {
  	FVector4f Position;
  	FVector2f TextureCoordinate;
  
  	FMediaElementVertex() { }
  
  	FMediaElementVertex(const FVector4f& InPosition, const FVector2f& InTextureCoordinate)
  		: Position(InPosition)
  		, TextureCoordinate(InTextureCoordinate)
  	{ }
  };
  
  void FMediaVertexDeclaration::InitRHI(FRHICommandListBase& RHICmdList)
  {
  	FVertexDeclarationElementList Elements;
  	uint16 Stride = sizeof(FMediaElementVertex);
      // `FVertexElement` equals to `glVertexAttribPointer` function in opengl
  	Elements.Add(FVertexElement(0, STRUCT_OFFSET(FMediaElementVertex, Position), VET_Float4, 0, Stride));
  	Elements.Add(FVertexElement(0, STRUCT_OFFSET(FMediaElementVertex, TextureCoordinate), VET_Float2, 1, Stride));
  	VertexDeclarationRHI = PipelineStateCache::GetOrCreateVertexDeclaration(Elements);
  }
  ```

  

* https://logins.github.io/graphics/2021/03/31/UE4ShadersIntroduction.html 这篇文章写得很好

* `FRHIRenderPassInfo` 这个包装了许多渲染时需要用到的资源，我能看懂的是这个 renderTarget 和 depthStencilTarget，前者这个结构体中还有 `ERenderTargetActions` 这个枚举变量，我猜测这个结构体的意思是设置 renderTarget 在渲染前后是否需要做什么（例如 ELoad 表示要在渲染前保留 renderTarget 之前的值，而 EStore 表示渲染后要把结果传回 CPU）

* 那 `GraphicsPSOInit.DepthStencilState` 设置的这个 DepthStencilState 是个啥，和 depthStencilTarget 有啥区别（为啥两个都要设置）

* 切换渲染对象时调用的是 `RHICmdList.Transition`，但我疑惑的是，ue 是怎么知道传入的 `FRHITransitionInfo` 中的纹理是干什么的？（噢，我猜测这是那个枚举变量 `ERHIAccess` 的作用，例如 ERHIAccess::RTV 就是指 render target？）

  * https://blog.csdn.net/a359877454/article/details/78305046 中讲了 D3D11 中的 resource，我感觉 ue 中的 `ERHIAcess` 中的含义就是指的这个相关的
    * Render Target：RenderTargetView（RTV）
    * Depth Stencil：DepthStencilView（DSV）
    * Shader Resource：ShaderResourceView（SRV）
    * Unordered Access：UnorderedAccessView（UAV）

* RHICmdList 中的 BeginRenderPass cmd 和 EndRenderPass cmd 是干什么的

* `OneColorShader.h` 中的例子非常重要

  * multiple render target 中的 TShaderPermutationDomain？

* vetex shader 中的投影矩阵该上哪去找呢

* FRHIResource，FRenderResource，FRDGResource？它们之间的区别和联系？

  * 我觉得 FRHIResource 对应底层的渲染资源相关的，而 FRenderResource 是它的一个封装

现在重点看 CustomDepth 这个 Pass 是怎么实现的！

### Custom Depth Pass

meshProcessor 的 addMeshBatch 函数的调用来自于两种

* 一种是可缓存的 staticMesh，对于新加入场景的 staticMesh，`FPrimitiveSceneInfo::CacheMeshDrawCommands` 中会调用 `addMeshBatch` 函数
* 另一种是动态生成的 mesh，在 `GenerateDynamicMeshDrawCommands` 函数中调用。而在 `DispatchPassSetup` 函数中通过 taskgraph 机制异步调用 `GenerateDynamicMeshDrawCommands` 这个函数
* 还没有梳理得特别清楚 `ComputeRelevance` 函数和 addMeshBatch 的关系，直观上看，如果 ComputeRelevance 中的测试不通过，那么这个 mesh 就不会被调用 addMeshBatch

### ComputeRelevance

该函数中考虑各种 mesh 与 meshpass 的相关性（该 meshpass 是否需要处理该 mesh）

* PrimitiveSceneProxy 的 GetViewRelevance 函数（子类重载）负责从 PrimitiveSceneProxy 中获取需要计算 relevance 相关的属性

### Culling

cpu culling来减少向gpu传输的数据？之前在 learning opengl 中都没做过这种事？



要不要使用 meshmetrial shader，如果用，如何向它传入参数。输出的 renderTarget 插件中如何用上

RDG？

### 问题定位

没有调用 customDepth 是因为需要画的三角形数量为 0

* 没有调用 customDepth 是因为 `FParallelMeshDrawCommandPass::DispatchPassSetup` 中显示需要画的三角形数目为 0

* 从 render 主函数中一路 call 下来的这个 `FVisibilityTaskData::ProcessRenderThreadTasks` 函数中调用了 ComputeRelevance（代码 `Context->Finalize()`） 和 SetupMeshPasses 函数（这个函数最终调用了 DispatchPassSetup 函数）
* 没看明白 FVisibilityViewPacket 中 Relevance 字段是怎么初始化的，明天debug 看看
* FVisivilityTaskData.DynamicMeshElements.ViewCommandsPerView 字段是最终的 viewCommand 输出
* FVisibilityTaskData 的 ViewPackets 字段的类型为 FVisibilityViewPacket，它的 Relevance.Context 字段（类型为 FComputeAndMarkRelevance）和 Relevance.Context.Packets（类型为 FRelevancePacket）都引用的上面那个 viewCommand

### OCam 相机的实现

* 场景中新建了一个 FSceneRenderer，然后注册了，这有什么影响呢

### 实现思路

* shader 中输出的 coloar 必须是 0 到 1 吗
* ~~类比 `CustomDepthStencilValue`，给 primitive component 添加一个新的 property `CustomStencilValue`~~
* ~~类比 `CustomDepthStencilValue`，给 PrimitiveSceneProxy 类添加一个新的成员 `CustomStencilValue`~~
* 添加新的处理 CustomStencil 的 meshProcessor
  * 添加新的枚举变量 EMeshPass::CustomStencil
  * 在 SceneVisibility.cpp 的 ComputeRelevance 函数中处理相关性（即 CustomStencil 是否需要处理这个 meshbatch，这里照着 CustomStencil 写就好了）
  * 类比 FCustomDepthPassMeshProcessor，实现新的 FCustomStencilMeshProcessor
* 在 struct FSceneTextures 中增加一个纹理来作为 custom stencil 的输出，在 FSceneTextures::InitializeViewFamily 中增加 custom stencil 输出纹理的初始化（这个函数也是在大的 Render 函数中被调用）
* **Others**

### Others

我们来看下原来的 CustomStencilValue 都在哪些地方用了

* FViewInfo 的 CustomDepthStencilValues 字段记录了所有 primitive component 的 stencil value 值，不过没看到它用。FSceneRenderer 类负责渲染工作，它的 Views 字段是一个 FViewInfo 的数组（我想应该是每个摄像机视角都对应一个 FViewInfo）

* FPrimitiveUniformShaderParameters 是一个全局的 Uniform Buffer（它在 shader 里面对应 FPrimitiveSceneData 这个结构体，查看 SceneData.h），感觉这个结构体描述了 shader 需要的所有 primitive component 的信息，最后一个参数数组 CustomPrimitiveData，这个可以自定义，我决定用这个作为 stencil value，然后在材质编辑器里面读出来。并且 bHasCustomData 这个 bool 值存放在 primitive shader parameter data 的 flags 中

* 在 primitiveComponent 中设置 CustomPrimitiveData 后，会调用 FScene 的 UpdateCustomPrimitiveData 函数，将更新的 PrimitiveSceneProxy 和 它的 CustomPrimitiveData 作为一对 pair 传递到 UpdatedCustomPrimitiveParams 这个 map 中。然后看下面这个函数调用栈

  FDeferredShadingSceneRenderer::Render

  ​    ->  FSceneRenderer::UpdateScene 

  ​        ->  FScene::UpdateAllPrimitiveSceneInfos

  在这个函数中遍历上面说到的这个 map 中的 pair，实际地将 新的 CustomPrimitiveData 设置在了 SceneProxy 的 CustomPrimitiveData 字段

  最终在函数 FPrimitiveSceneProxy::BuildUniformShaderParameters 函数中，将这个 CustomPrimitiveData 的值暴露给了 

  PrimitiveUniformShaderParametersBuilder 的 FPrimitiveUniformShaderParameters，这个参数将用来构建我们需要的 uniform buffer

  由于 FPrimitiveUniformShaderParameters 的 CustomPrimitiveData 字段是 TStaticArray 类型，后者默认会将数组初始化为 0，因此不用担心 shader 收到的 CustomPrimitiveData 会是未定义的

* FPrimitiveSceneShaderData 存储了 PRIMITIVE_SCENE_DATA_STRIDE（41） 个浮点，以一种更紧凑的方式保存了整个 primitive parameter 的 uniform buffer？具体的 layout 见 FPrimitiveSceneShaderData::Setup 函数。我感觉这个结构体的引入和 GPUScene 之类的有些关系，见 SceneData.ush 中两种 GetPrimitiveData 的定义方式

* GetMaterialPixelParameter 函数的实现，看起来像是每个顶点工厂对应的 usf 文件有这个函数的定义

* 影响 primitiveId 是否为恒为 0 的关键在于 VF_SUPPORTS_PRIMITIVE_SCENE_DATA 宏是否被定义了

* PrimitiveId 的值来源于 vertexShaderInput 的 InstanceIdOffset 和 DrawInstanceId 属性，见 SceneData.ush 的 GetSceneDataIntermediates 函数，不过仅在宏 VF_SUPPORTS_PRIMITIVE_SCENE_DATA 值为 1 时有效



### 问题

**如何传递参数给 meterial shader**

**CustomDepthPass 的 shader 都有一个 GetShaderBindings 函数，这个函数会在 BuildMeshDrawCommand 函数中被调用，在这个时候我们设置 shader 参数**

PrimitiveComponent 的CustomDepthStencilValue 是怎么传递给 PrimitiveSceneProxy 的？（在直接设置 CustomDepthStencilValue 时）我猜是不是因为每一帧都会建一个新的 PrimitiveSceneProxy 之类的？

UE 是如何获得回传的 GPU 数据同时不卡的呢，在 RDG 中调用 rhicmdlist.readsurfacedata 函数会极大地影响帧率，看看 URenderTarget 相关的代码？是如何回传的，以及对应的 EStoreAction 干了什么