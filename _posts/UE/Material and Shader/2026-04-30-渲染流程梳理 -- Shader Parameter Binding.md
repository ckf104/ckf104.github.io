---
title: 渲染流程梳理 -- Shader Parameter Binding
date: 2026-04-30 21:41:57 +0800
categories:
  - Vulkan
  - UE5
  - Graphics
comments: true
---

本文以 vulkan RHI 为例，讨论 C++ 侧绑定的 shader 参数是如何最终传递给 shader 的

## 0. 上层接口

UE 中现代 shader 参数最常见的写法是 shader parameter struct，它的设计有几个重要的特点：

* 混合参数声明： scalar，texture，sampler 等不同类型的参数，一个 shader parameter struct 就将 shader 中所有用到的参数都包括进来
* 统一的 shader 参数设置方法：声明时 shader parameter struct 的同时会生成描述 C++ 侧 parameter 布局的 metadata，这套基于宏的反射使得有统一的设置 shader 参数的方法，而不需要用户手动设置每个 shader 参数
* 名称匹配检查：通过 metadata，结合 shader 的编译结果，可以预先检查 shader 侧使用的参数与 C++ 侧声明的参数是否一致，而不是推迟到 shader 执行前进行校验

C++ 侧的参数声明的例子：

```c++
class FLearnShaderPS : public FGlobalShader
{
	DECLARE_GLOBAL_SHADER(FLearnShaderPS);
	SHADER_USE_PARAMETER_STRUCT(FLearnShaderPS, FGlobalShader);

	BEGIN_SHADER_PARAMETER_STRUCT(FParameters, )
		SHADER_PARAMETER(FVector4f, ColorMask)
		SHADER_PARAMETER_TEXTURE(Texture2D, InputTexture)
		SHADER_PARAMETER_SAMPLER(SamplerState, InputSampler)
		SHADER_PARAMETER_STRUCT_REF(FViewUniformShaderParameters, View)
		RENDER_TARGET_BINDING_SLOTS()
	END_SHADER_PARAMETER_STRUCT()
};
```

在 shader 侧声明为

```hlsl
#include "/Engine/Public/Platform.ush"
#include "/Engine/Generated/GeneratedUniformBuffers.ush" // 需要这一行，UE 会替换为实际的 uniform buffer 声明

float4 ColorMask;
Texture2D InputTexture;
SamplerState InputSampler;

float4 MainPS(float4 SV_Position : SV_POSITION) : SV_Target
{
	float2 UV = SV_Position.xy * View.BufferSizeAndInvSize.zw;
	float4 InputColor = InputTexture.Sample(InputSampler, UV);

	return InputColor * ColorMask;
}
```

 shader 侧不需要声明 uniform buffer，只需要加上 `#include "/Engine/Generated/GeneratedUniformBuffers.ush"` 这一行

从 graphics API 的角度看

- `ColorMask` 是 loose parameter，它最终会被放进一个自动生成的 packed uniform buffer
- `InputTexture`、`InputSampler` 是 shader 会访问的 resource
- `View` 是一个 uniform buffer
- `RENDER_TARGET_BINDING_SLOTS` 是 RDG pass 的 render target 参数，承接 color output

C++ 侧初始化 shader parameter，在设置好 PSO 后，调用 `SetShaderParameters` 这个统一传参的接口完成参数传递，然后就可以调用 draw call 了

```c++
		FGraphicsPipelineStateInitializer GraphicsPSOInit;
		// ... init PSO
		
		SetGraphicsPipelineState(RHICmdList, GraphicsPSOInit, StencilRef);
		SetShaderParameters(RHICmdList, PixelShader, PixelShader.GetPixelShader(), Parameters);
		DrawFullscreenTriangle(RHICmdList);
```

C++ 侧 uniform buffer 的声明和 shader parameter struct 是类似的，只是把 `BEGIN/END_SHADER_PARAMETER_STRUCT` 宏换为 `BEGIN/END_UNIFORM_BUFFER_STRUCT`，ue 的 uniform buffer 与 vulkan 的 uniform buffer 不同，它除了 scalar 外，还可以混合 resource。为了区分，接下来将它们分别称为 ue uniform buffer 和 gfx uniform buffer

接下来我们讨论一下上述这些接口的实现

## 1. SHADER_PARAMETER 宏

shader parameter struct 的字段由 `ShaderParameterMacros.h` 中的一组宏声明。它实现的反射机制与 shader parameter metadata 见 [[2025-10-07 Global Shader Compiling 2 in Unreal|Global Shader Compiling 2]]，这里我主要再对这些宏进行一个分类

从后续绑定角度看，这些宏大致可以分成几类

第一类是最终会写入 uniform / constant buffer 的普通数值参数，例如 `float`、`FVector4f`、`FMatrix44f` 等字段

- `SHADER_PARAMETER`
- `SHADER_PARAMETER_ARRAY`
- `SHADER_PARAMETER_EX`

第二类是 shader resource

- `SHADER_PARAMETER_TEXTURE`
- `SHADER_PARAMETER_SAMPLER`
- `SHADER_PARAMETER_SRV`
- `SHADER_PARAMETER_UAV`
- `SHADER_PARAMETER_RDG_TEXTURE`
- `SHADER_PARAMETER_RDG_BUFFER`
- `SHADER_PARAMETER_RDG_TEXTURE_SRV`
- `SHADER_PARAMETER_RDG_BUFFER_SRV`
- `SHADER_PARAMETER_RDG_TEXTURE_UAV`
- `SHADER_PARAMETER_RDG_BUFFER_UAV`

这类参数不会写入 constant buffer 的字节区，而是作为 resource 由 `FShaderParameterBindings` 记录 C++ struct offset，再在运行时提取出 RHI resource

第三类是 uniform buffer reference

- `SHADER_PARAMETER_STRUCT_REF`
- `SHADER_PARAMETER_RDG_UNIFORM_BUFFER`

`SHADER_PARAMETER_STRUCT_REF` 的含义是引用一个 uniform buffer

如果只是想把另一个非 uniform buffer 的 parameter struct 展开到当前 struct 中，应使用 `SHADER_PARAMETER_STRUCT` 或 `SHADER_PARAMETER_STRUCT_INCLUDE`

- `SHADER_PARAMETER_STRUCT`
- `SHADER_PARAMETER_STRUCT_INCLUDE`

这类宏会把另一个 parameter struct 的字段并入当前 layout

第五类是 render target binding

- `RENDER_TARGET_BINDING_SLOTS`
- `SHADER_PARAMETER_RDG_TEXTURE_RENDER_TARGET`
- `SHADER_PARAMETER_RDG_TEXTURE_RENDER_TARGET_ARRAY`

这类参数主要服务 RDG pass 的 render target / depth stencil 绑定，不是普通 shader resource 参数

其中有 RDG 和无 RDG 的宏的唯一区别在于是否由 RDG 管理资源，在 shader 参数绑定的讨论中无关仅要

## 2. shader 编译

[[2025-10-07 Global Shader Compiling 3 in Unreal|Global Shader Compiling 3]] 涉及了一部分的 shader 编译流程，那篇文章讨论了以下的内容

* global shader 的编译流程
* uniform buffer 在编译时的处理
* 存储编译结果的 shader map

这一节我们着重于讨论 shader 编译与 shader parameter 绑定的关系。总的来说，为了正确绑定 shader 和它的参数，我们会预期 shader 的编译结果包含两部分的内容

* 编译得到的 spirv 代码
* 描述 shader 使用了哪些 resource，每个 resource 的 descriptor set / binding 编号的元数据

实际上 UE 就是这样做的，[[2025-10-07 Global Shader Compiling 3 in Unreal|Global Shader Compiling 3]] 中谈到，shader 的编译结果存放在 `FShaderMapResourceCode` 中

```c++
class FShaderMapResourceCode : public FThreadSafeRefCountedObject
{
public:
	struct FShaderEntry
	{
		TArray<uint8> Code;
		int32 UncompressedSize;
		EShaderFrequency Frequency;
		
		// ...
	};
	TArray<FShaderEntry> ShaderEntries;
```

这里 `TArray<uint8> Code` 就是单个 shader 的编译结果，而针对 vulkan RHI，它由 header, resource table, spirv code 这三部分构成

```c++
template <typename ShaderType> 
ShaderType* FVulkanShaderFactory::CreateShader(TArrayView<const uint8> Code, FVulkanDevice* Device)
{
	FMemoryReaderView Ar(Code, true);
	FVulkanShaderHeader CodeHeader;
	Ar << CodeHeader;
	FShaderResourceTable SerializedSRT;
	Ar << SerializedSRT;
	FVulkanShader::FSpirvContainer SpirvContainer;
	Ar << SpirvContainer;

	// ...
}
```

这里 `FVulkanShaderHeader` 实际上就存储了该 shader 用到的所有 resource 以及它的 binding 编号。`FShaderResourceTable` 用于 ue uniform buffer

```c++
// Vulkan ParameterMap:
// Buffer Index = EBufferIndex
// Base Offset = Index into the subtype
// Size = Ignored for non-globals
struct FVulkanShaderHeader
{
	TArray<FUniformBufferInfo>	UniformBuffers; // shader 中引用的 ue uniform buffer
	TArray<FGlobalInfo>			Globals;  // shader 中引用的各种 resource
	// ...
};
```

因此 shader 参数绑定在 shader 编译一侧干的事情就是，编译 shader 获得 spirv code，通过 spirv reflect，我们就知道该 shader 使用了哪些 resource，以及它们目前的 binding 编号（这个是编译器自动分配的），据此生成 `FVulkanShaderHeader`，它与 spirv 代码封装为无类型的 bytes 数据，作为编译结果传递给上层的 RenderCore 模块

```c++
struct FShaderCompilerOutput
{
	FShaderParameterMap ParameterMap;
	FShaderCode ShaderCode;
	// ...
}
```

这里的调用链路大概是

```text
CompileVulkanShader
  -> CompileWithShaderConductor
    -> shader compiling ...
    -> BuildShaderOutputFromSpirv
      -> BuildShaderOutput
        -> BuildResourceTableMapping
        -> ConvertToHeader  // 这里实际地构建 FVulkanShaderHeader
        -> BuildSRTFromHeader  // 这里实际地构建 FShaderResourceTable
```

虽然我们已经在 Vulkan RHI 一层已经知道 shader 使用了哪些 resource，以及 spirv 中的分配的 binding 编号，但仍需要把这些信息传递给 RenderCore 一层，这样 RenderCore 这边就可以校验 C++ 侧声明的 shader parameter struct 是否与 shader 侧的参数一致

另一方面，在 Vulkan RHI 一层则对 shader parameter struct 无感知（因为 Vulkan RHI 只需要关心 shader 侧的参数），它需要向 RenderCore 传递参数标识符，这样 RenderCore 这边调用 Vulkan RHI 传参时才知道这是在设置 shader 的哪个参数，这就是 shader compiler output 的 `ParameterMap` 的作用

```c++
struct FParameterAllocation
{
	uint16 BufferIndex = 0;
	uint16 BaseIndex = 0;
	uint16 Size = 0;
	EShaderParameterType Type{ EShaderParameterType::Num };
}
```

`ParameterMap` 是一个 TMap，将参数名称映射到一个 `FParameterAllocation` 结构体，其中 BufferIndex 和 BaseIndex 用来对 `FVulkanShaderHeader` 进行索引。它作为参数的标识符，对于不同类型的参数，含义如下

```text
InputTexture:
  Type = SRV
  BufferIndex = FVulkanShaderHeader::Global
  BaseIndex = Globals[] 里的 index

InputSampler:
  Type = Sampler
  BufferIndex = FVulkanShaderHeader::Global
  BaseIndex = Globals[] 里的 index

ColorMask:
  Type = LooseData
  BufferIndex = FVulkanGraphicsPipelineDescriptorState::PackedGlobals[] 里的 index
  BaseIndex = byte offset
  Size = 16

View:
  Type = UniformBuffer
  BufferIndex = UniformBuffers[] 里的 index
  BaseIndex = FVulkanShaderHeader::UniformBuffer
```

RenderCore 模块根据编译结果，初始化 `FShader`，`FShader` 的构造函数根据传入的 parameter map，对比校验 C++ 侧的 shader parameter struct，生成 `Bindings`，它是 shader 参数索引到 C++ shader parameter struct 之间的映射

```c++
	LAYOUT_FIELD(FShaderParameterBindings, Bindings);
	LAYOUT_FIELD(FShaderParameterMapInfo, ParameterMapInfo); // 用于 mesh draw command 链路，会忽略 UAV resource
```

`FShader` 构造时还会根据 shader 中使用到的 ue uniform buffer 初始化 `UniformBufferParameterStructs` 和 `UniformBufferParameters`，这两个字段服务于 `GetUniformBufferParameter<T>() / SetUniformBufferParameter(...)` 这一类 legacy uniform buffer binding 路径，使用 shader parameter struct 绑定参数时不会用到它们

### 2.1 UE Uniform Buffer 与 Resource Table

如果 shader 引用了 ue uniform buffer，那么实际编译后的参数处理会更麻烦一点。原因在于 spirv reflect 得到的 parameter map 是 hlsl 一层看到的 parameter，因此看到的不是 ue uniform buffer，而是 gfx uniform buffer 和 resource

```text
CompileVulkanShader
  -> CompileWithShaderConductor
    -> shader compiling ...
    -> BuildShaderOutputFromSpirv
      -> BuildShaderOutput
        -> BuildResourceTableMapping  // gfx uniform buffer + resource -> ue uniform buffer 
        -> ConvertToHeader  // 这里实际地构建 FVulkanShaderHeader
        -> BuildSRTFromHeader  // 这里实际地构建 FShaderResourceTable
```

因此 vulkan RHI 拿到原始的 parameter map 后，需要判定哪些用到的 resource 属于 ue uniform buffer，哪些又应该归属于 global resource。归属 ue uniform buffer 的 resource 由 shader parameter struct 中引用的 ue uniform buffer 中的相应字段进行绑定，归属 global resource 的 resource 由 shader parameter struct 中的相应字段进行绑定

那 vulkan RHI 是如何知道 shader 引用了哪些 ue uniform buffer 的呢，[[2025-10-07 Global Shader Compiling 3 in Unreal|Global Shader Compiling 3]] 中已经讨论过了，编辑器模式下会检索每个 `FShaderType` 的 shader 文件，匹配全局注册的 ue uniform buffer 的名称，确定每个 shader 可能引用哪些 ue uniform buffer

Note: 这里没有从 shader parameter struct 来分析 ue uniform buffer 的使用，我觉得是为了兼容以前的手动声明 shader parameter 的方式，该模式使用 `GetUniformBufferParameter<T>() / SetUniformBufferParameter(...)` 这套 API 来设置 ue uniform buffer 参数，shader 中不会显式声明它将使用哪些 ue uniform buffer

举一个例子，假设 shader 中引用了 view 这个 ue uniform buffer，只用到了它的 `BlueNoiseTexture` 和 `BlueNoiseSampler` 这两个 resource，那么原始的 parameter map 就只包含

```text
# 如果使用了 view 中的 scalar data，则 parameter map 中还会包含 View
View_BlueNoiseTexture,Type=SRV
View_BlueNoiseSampler,Type=Sampler
```

`BuildResourceTableMapping` 进行处理后，parameter map 就变为了

```text
View,Type=UniformBuffer
```

这也是 RenderCore 这一层看到的 parameter map，它只关心 shader 使用了哪些 ue uniform buffer，然后把 uniform buffer 提供给 Vulkan RHI，不关心 ue uniform buffer 具体哪些字段被使用了

shader 需要绑定 ue uniform buffer 的哪些 resource 是 Vulkan RHI 关心的事情，这个信息记录在我们前面提到的 `FShaderResourceTable` 中，它的结构如下

```c++
struct FShaderResourceTable
{
	/** Bits indicating which resource tables contain resources bound to this shader. */
	uint32 ResourceTableBits = 0;

	/** Mapping of bound SRVs to their location in resource tables. */
	TArray<uint32> ShaderResourceViewMap;

	/** Mapping of bound sampler states to their location in resource tables. */
	TArray<uint32> SamplerMap;

	/** Mapping of bound UAVs to their location in resource tables. */
	TArray<uint32> UnorderedAccessViewMap;

	/** Mapping of bound Textures to their location in resource tables. */
	TArray<uint32> TextureMap;
}
```

其中每个 resource 数组内部数据的组织方式是一样的，我们以 `TextureMap` 为例进行说明。假设这个 shader 总共引用了 5 个 ue uniform buffer，针对 texture 类型的 resource，shader 引用了第 2 个 uniform buffer 的第 7 和第 8 个 resource，第 5 个 ue uniform buffer 的第 1 个 resource，那么 `TextureMap` 应当包含以下三个表项

```text
Entry(UB=2, ResourceIndex=7, BindIndex=12)
Entry(UB=2, ResourceIndex=8, BindIndex=13)
Entry(UB=5, ResourceIndex=1, BindIndex=4)
```

而 `TextureMap` 实际长度为 10，里面的表项是按照如下方式存储的，每个 entry `UBIndex`，`ResourceIndex` 以及 `BindIndex` 压缩为一个 `uint32`

```text
Index: 0  1  2  3  4  5  6      7      8      9
Data:  0  0  6  0  0  8  Entry  Entry  Entry  End
             ^        ^
             |        |
          UB2 从 6 开始
                   UB5 从 8 开始
```

这里一个重要的观察是，ue 只会绑定 shader 实际用到的 resource，用户在 C++ 侧声明的 shader parameter struct、ue uniform buffer 可以包含更多的 resource，但参与绑定的只有 shader 实际用到的部分。因此不需要担心使用 View 这种包含巨多 resource 的 ue uniform buffer 带来性能负担

Note：唯一的例外是 ue uniform buffer 的 scalar 数据，它们会存放在一个 gfx uniform buffer 里。如果 shader 使用了 ue uniform buffer 中任何的 scalar data，则会绑定整个 gfx uniform buffer，而不是说将使用的 scalar data 将凑为一个新的 gfx uniform buffer 布局来绑定

## 3. 创建与设置 graphics pipeline

在讨论 `SetShaderParameters` 这个统一的参数绑定入口前，我们先讨论一下 Vulkan API 的 resource binding。在 Vulkan API 中，每个 resource 由 descriptor set, binding, element 唯一标识，其中 element 是 resource array 中的下标。但 ue 看起来不支持 shader 中使用 resource array（我不确定 bindless 是怎么做的），使用 `SHADER_PARAMETER_TEXTURE_ARRAY` 宏声明 C++ 侧的 resource array 都会被展平为 `resource_%d` 这种命名的单个 resource，并且在创建 descriptor set layout 时 descriptor count 固定为 1

```c++
	VkDescriptorSetLayoutBinding Binding;
	FMemory::Memzero(Binding);
	Binding.descriptorCount = 1;
```

因此我们将注意放在 descriptor set 和 binding 上。虽然在 shader 编译为 spirv 时已经自动为每个 resource 分配了 descriptor set 和 binding，但这只是针对单个 shader，实际的 pipeline / descriptor set layout 需要在管线创建时才能最终确定

我们接下来描述 pipeline layout 的创建与 pipeline / descriptor set layout 的确定规则。用户侧通常设置 graphics pipeline 的代码是

```c++
		FGraphicsPipelineStateInitializer GraphicsPSOInit;
		// ... init PSO
		SetGraphicsPipelineState(RHICmdList, GraphicsPSOInit, StencilRef);
```

自然，这里会做一些 pipeline cache 的事情，尝试复用已有的 PSO，如果找不到，尝试创建新的 PSO。我们首先分析创建 PSO 的路径，之后回来分析 `RHICmdList.SetGraphicsPipelineState`

```c++
void SetGraphicsPipelineState(FRHICommandList& RHICmdList, const FGraphicsPipelineStateInitializer& Initializer, uint32 StencilRef, EApplyRendertargetOption ApplyFlags, bool bApplyAdditionalState, EPSOPrecacheResult PSOPrecacheResult)
{
#if PLATFORM_USE_FALLBACK_PSO
	RHICmdList.SetGraphicsPipelineState(Initializer, StencilRef, bApplyAdditionalState);
#else
	FGraphicsPipelineState* PipelineState = PipelineStateCache::GetAndOrCreateGraphicsPipelineState(RHICmdList, Initializer, ApplyFlags, PSOPrecacheResult);

	if (PipelineState && !Initializer.bFromPSOFileCache)
	{
		PipelineState->Verify_IncUse();
		check(IsInRenderingThread() || IsInParallelRenderingThread());
		RHICmdList.SetGraphicsPipelineState(PipelineState, Initializer.BoundShaderState, StencilRef, bApplyAdditionalState);
	}
#endif
}
```

### 3.1 创建 graphics pipeline

`PipelineStateCache::GetAndOrCreateGraphicsPipelineState` 内如果找不到可复用的 PSO，会调用 Vulkan RHI 创建 PSO 的接口

```c++
	/**
	* Creates a graphics pipeline state object (PSO) that represents a complete gpu pipeline for rendering.
	* This function should be considered expensive to call at runtime and may cause hitches as pipelines are compiled.
	* @param Initializer - Descriptor object defining all the information needed to create the PSO, as well as behavior hints to the RHI.
	* @return FGraphicsPipelineStateRHIRef that can be bound for rendering; nullptr if the compilation fails.
	* CAUTION: On certain RHI implementations (eg, ones that do not support runtime compilation) a compilation failure is a Fatal error and this function will not return.
	* CAUTION: Even though this is marked as threadsafe, it is only valid to call from the render thread or the RHI thread. It need not be threadsafe unless the RHI support parallel translation.
	* CAUTION: Platforms that support RHIThread but don't actually have a threadsafe implementation must flush internally with FScopedRHIThreadStaller StallRHIThread(FRHICommandListExecutor::GetImmediateCommandList()); when the call is from the render thread
	*/
	// FlushType: Thread safe
	virtual FGraphicsPipelineStateRHIRef RHICreateGraphicsPipelineState(const FGraphicsPipelineStateInitializer& Initializer) = 0;
```

该函数的大致流程如下。可以看到，Vulkan RHI 中存在多个层级的复用，如果 PSO 无法复用，会根据 `FinalizeBindings` 确定的 layout 尝试 pipeline layout 的复用，如果没有可复用的 pipeline layout 则会尝试 descriptor set layout 的复用

```text
RHICreateGraphicsPipelineState(Initializer)
  │
  ├─► CreateGfxEntry(Initializer, &DescriptorSetLayoutInfo, &Desc)
  │     │
  │     ├─ 1. ProcessBindingsForStage() × N   // 第一遍：遍历各 Stage 的 ShaderHeader，
  │     │     收集 UniformBuffer / Global / PackedUB 信息，
  │     │     通过 LayoutHash 识别跨 Stage 共用的 UB
  │     │
  │     ├─ 2. FinalizeBindings<false>()        // 第二遍：真正分配 Descriptor Set / Binding
  │     │     决定每个资源落在哪个 Set 的哪个 Binding，
  │     │     产出 FDescriptorSetRemappingInfo
  │     │
  │     └─ 3. 填充 FGfxPipelineDesc             // 光栅化状态、混合状态、深度模板、
  │           顶点输入布局、ShaderKeys 等
  │
  ├─► FindOrAddLayout(DescriptorSetLayoutInfo, /*bGfxLayout=*/true)
  │     │
  │     ├─ LayoutMap.Find(DescriptorSetLayoutInfo)  // 按 Hash 查缓存
  │     │   └─ Hit → 直接返回已缓存的 FVulkanLayout（跨 PSO 复用）
  │     │
  │     └─ Miss → 新建 FVulkanGfxLayout
  │           ├─ DescriptorSetLayout.CopyFrom(DescriptorSetLayoutInfo)
  │           ├─ Compile(DSetLayoutMap)
  │           │   ├─ 对每个 Set: 创建 VkDescriptorSetLayout（缓存到 DSetLayoutMap）
  │           │   └─ vkCreatePipelineLayout()  // 组合所有 Set Layout
  │           └─ GfxPipelineDescriptorInfo.Initialize(RemappingInfo)  // 保存 RemappingInfo
  │
  └─► CreateGfxPipelineFromEntry(PSO, Shaders, bPrecompile)
        ├─ GetOrCreateShaderModules()   // SPIR-V Patch（修正 descriptor set offset）
        ├─ 填充 VkGraphicsPipelineCreateInfo
        └─ CreateVKPipeline() → vkCreateGraphicsPipelines()
```

`FinalizeBindings` 中分配 Descriptor Set / Binding 的算法很直接，就是每个 shader stage 一个 descriptor set，同一个 shader stage 内，每个 resource 递增一个 binding 号。文末举一个较为复杂的例子来进行说明

`FinalizeBindings` 分配的 Descriptor Set / Binding 用于后续的 pipeline layout 复用或者创建。最后创建 graphics pipeline 时，会根据分配的 Descriptor Set / Binding 修改每个 shader 的 spirv 文件（这里直接在 shader 原有的 spirv 文件上修改即可，因为创建 graphics pipeline 时会将 spirv 编译为最终 gpu 可识别的代码，不会依赖于原始 spirv 文件）

 `FVulkanGfxPipelineDescriptorInfo` 中保存了 remapping info，在参数绑定时，将 RenderCore 一层看到的 buffer index / base index 映射为 descriptor set / layout

### 3.2 设置 graphics pipeline

在 graphics pipepine 创建好后，我们来看看 `RHICmdList.SetGraphicsPipelineState`，这里涉及到如下的对象

```text
FVulkanCommandListContext                          (VulkanContext.h)
│
├─owns─► PendingGfxState: FVulkanPendingGfxState*   (VulkanPendingState.h)
│        │
│        ├─ref─► CurrentPipeline: FVulkanRHIGraphicsPipelineState*
│        │        (当前绑定的 Graphics PSO)
│        │
│        ├─ref─► CurrentState: FVulkanGraphicsPipelineDescriptorState*
│        │        (当前 PSO 对应的 Descriptor 状态)
│        │
│        └─owns─► PipelineStates: TMap< FVulkanRHIGraphicsPipelineState*,
│                                       FVulkanGraphicsPipelineDescriptorState* >
│                  │
│                  └── 1:1 映射 ── Key=PSO, Value=该PSO的描述符状态(lazy create, map持有所有权)
│
└─owns─► PendingComputeState: FVulkanPendingComputeState*  (同 compute 管线)
```

`FVulkanRHIGraphicsPipelineState` 是 vulkan graphics pipeline 的 C++ 封装，而 `FVulkanGraphicsPipelineDescriptorState` 则记录了它对应的 graphics pipepine 的 resource 绑定情况

`RHICmdList.SetGraphicsPipelineState` 由 `FVulkanCommandListContext::RHISetGraphicsPipelineState` 实现，它干的事情根据传入的 graphics pipeline，设置好 `CurrentPipeline` 与 `CurrentState`，然后将 graphics pipeline 绑定到 vulkan command buffer 上

```text
RHICmdList.SetGraphicsPipelineState(PSO, StencilRef)
  └─► FVulkanCommandListContext::RHISetGraphicsPipelineState()
        ├─► FVulkanPendingGfxState::SetGfxPipeline(InGfxPipeline, bForceReset)
        │     ├─ 从 PipelineStates Map 查找或新建 FVulkanGraphicsPipelineDescriptorState
        │     └─ 设置 CurrentPipeline / CurrentState
        └─► 绑定 PSO 到 CommandBuffer
```

## 4. 绑定 Shader 参数

在 graphics pipeline 创建和绑定完成后，就可以调用 `SetShaderParameters` 实际地绑定 shader 参数了

```c++
template<typename TRHICmdList, typename TShaderClass, typename TShaderRHI>
inline void SetShaderParameters(TRHICmdList& RHICmdList, const TShaderRef<TShaderClass>& Shader, TShaderRHI* ShaderRHI, const typename TShaderClass::FParameters& Parameters);
```

它的大致流程是（核心思想很简单，因为此前通过 `Bindings` 已经建立了 shader 参数到 shader parameter struct 偏移的映射，这里就根据 Bindings 把 shader 需要的参数从 shader parameter struct 中提出来就好了）

```text
SetShaderParameters(RHICmdList, Shader, ShaderRHI, Parameters)
  │
  ├─► TShaderClass::FParameters::FTypeInfo::GetStructMetadata()
  │     取得 C++ shader parameter struct 的 metadata
  │
  ├─► SetShaderParameters(RHICmdList, ShaderRHI,
  │                       Shader->Bindings,
  │                       ParametersMetadata,
  │                       &Parameters)
  │
  └─► SetShaderParametersInternal(...)
        │
        ├─► ExtractShaderParameters()
        │     利用 Bindings，从 Parameters 中提取 loose scalar data
        │     生成 FRHIShaderParameter[]
        │
        ├─► ExtractShaderParameterResources()
        │     利用 Bindings，从 Parameters 中提取 Texture / SRV / UAV / Sampler / UniformBuffer
        │     生成 FRHIShaderParameterResource[]
        │
        └─► RHICmdList.SetShaderParameters(...)
              │
              ├─ 如果 RHI command list bypass
              │   └─► FVulkanCommandListContext::RHISetShaderParameters()
              │
              └─ 否则
                  └─► 记录 FRHICommandSetShaderParameters
                       后续在 RHI thread 执行时进入
                       FVulkanCommandListContext::RHISetShaderParameters()
```

我们前面提到过，声明 shader parameter 时，RDG 和无 RDG 的宏的唯一区别在于是否由 RDG 管理资源，在 shader 参数绑定的讨论中无关仅要。以下从 shader parameter struct 中提取 resource 的代码，针对是否为 RDG 的 texture，只是提取 RHI Resource 的方法稍微有些不一样，但是传递到 Vulkan RHI 一层就统一变为了 RHI Resource，它对是否为 RDG 管理是无感知的

```c++
template<typename BindingParameterType>
FRHIShaderParameterResource ExtractShaderParameterResource(FShaderParameterReader Reader, const BindingParameterType& Parameter)
{
	const EUniformBufferBaseType BaseType = static_cast<EUniformBufferBaseType>(Parameter.BaseType);

	switch (BaseType)
	{
	case UBMT_TEXTURE:
	{
		FRHITexture* Texture = Reader.Read<FRHITexture*>(Parameter);
		checkSlow(Texture);
		return FRHIShaderParameterResource(Texture, GetParameterIndex(Parameter));
	}
	case UBMT_RDG_TEXTURE:
	{
		FRDGTexture* RDGTexture = Reader.Read<FRDGTexture*>(Parameter);
		checkSlow(RDGTexture);
		RDGTexture->MarkResourceAsUsed();
		return FRHIShaderParameterResource(RDGTexture->GetRHI(), GetParameterIndex(Parameter));
	}
	// ...
}
```

`RHISetShaderParameters` 简单调用 `RHISetShaderParametersShared`，内部根据参数类型进一步转发

```text
RHISetShaderParametersShared
  │
  ├─► 遍历 FRHIShaderParameter[]
  │     └─► Context.RHISetShaderParameter(...)
  │
  ├─► 遍历 BindlessParameters[]
  │     └─► 写 bindless handle 到 shader parameter
  │
  └─► 遍历 FRHIShaderParameterResource[]
        │
        ├─ Texture       -> RHISetShaderTexture
        ├─ SRV           -> RHISetShaderResourceViewParameter
        ├─ UAV           -> RHISetUAVParameter
        ├─ Sampler       -> RHISetShaderSampler
        └─ UniformBuffer -> RHISetShaderUniformBuffer
```

最终来讲，此时不会触发 `vkCmd...` 的调用，这些参数值暂存到 `FVulkanGraphicsPipelineDescriptorState` 中，对于 scalar / loose data

```text
FVulkanGraphicsPipelineDescriptorState
  ├─ PackedUniformBuffers[Stage]
  └─ PackedUniformBuffersDirty[Stage]
```

Texture / SRV / UAV / Sampler / gfx Uniform Buffer（表示 ue uniform buffer 中存储 scalar data 的部分）

```text
FVulkanGraphicsPipelineDescriptorState
  ├─ DSWriter[DescriptorSet]
  ├─ DSWriteContainer.DescriptorWrites
  ├─ DSWriteContainer.DescriptorImageInfo
  ├─ DSWriteContainer.DescriptorBufferInfo
  ├─ DynamicOffsets
  └─ bIsResourcesDirty
```

注意这些 resource 不会区分 shader stage 了，通过 remapping info，它们根据实际分配的 descriptor set / binding 存储

ue uniform buffer 还会存储在 `FVulkanCommandListContext` 中

```text
FVulkanCommandListContext
  ├─ BoundUniformBuffers[Frequency][BufferIndex]
  └─ DirtyUniformBuffers[Frequency]
```

以 `RHIDrawPrimitive` 为例，在调用 draw call 时，会首先通过 `CommitGraphicsResourceTables` 函数，将 shader resource table 中记录的 shader 引用的 uniform buffer 的 resource 加入到 `FVulkanGraphicsPipelineDescriptorState` 中。然后由 `PrepareForDraw` 更新和绑定 descriptor set 到 graphics pipeline 上，最后调用 draw call

```text
FVulkanCommandListContext::RHIDrawPrimitive
  │
  ├─► CommitGraphicsResourceTables
  │     │
  │     └─► SetResourcesFromTables(Shader)
  │           │
  │           ├─ Enumerate ResourceTable.TextureMap
  │		      │		  └─ Get RHIResource From BoundUniformBuffers[Frequency][BufferIndex]
  │           ├─ Enumerate ResourceTable.ShaderResourceViewMap
  │           │       └─ Get RHIResource From BoundUniformBuffers[Frequency][BufferIndex]
  │           ├─ Enumerate ResourceTable.SamplerMap
  │           │       └─ Get RHIResource From BoundUniformBuffers[Frequency][BufferIndex]
  │           ├─ Enumerate ResourceTable.UnorderedAccessViewMap
  │           │       └─ Get RHIResource From BoundUniformBuffers[Frequency][BufferIndex]
  │           │
  │           └─ Update Resource Binding
  │                 │
  │                 ├─ GlobalRemappingInfo[Stage][BindIndex]
  │                 │     -> DescriptorSet + BindingIndex
  │                 │
  │                 └─ PendingGfxState->SetXForUBResource
  │                       -> CurrentState->DSWriter[Set].Write...
  │
  ├─► PendingGfxState->PrepareForDraw
  │     │
  │     ├─► CurrentState->UpdateDescriptorSets
  │     │     │
  │     │     ├─► UpdatePackedUniformBuffers
  │     │     │     ├─ Allocate uniform ring buffer memory
  │     │     │     ├─ memcpy PackedUniformBuffers[Stage]
  │     │     │     └─ DSWriter[Set].WriteUniformBuffer / WriteDynamicUniformBuffer
  │     │     │
  │     │     ├─► Allocate / fetch VkDescriptorSet
  │     │     ├─► DSWriter[Set].SetDescriptorSet
  │     │     ├─► vkUpdateDescriptorSets
  │     │     └─► bIsResourcesDirty = false
  │     │
  │     ├─► UpdateDynamicStates
  │     │     -> viewport / scissor / stencil
  │     │
  │     └─► CurrentState->BindDescriptorSets
  │           └─► vkCmdBindDescriptorSets
  │
  └─► vkCmdDraw
```

Note1：loose parameter 会被打包到一个 uniform buffer 中，在 `UpdatePackedUniformBuffers` 中才正式创建、更新该 uniform buffer。该 uniform buffer 使用 host visible 和 host coherent 类型的 memory，加上 command submit 时会自动使得 cpu 侧的写变得可见，因此不需要额外的同步

Note2：如果不使用 descriptor set cache（即检查是否已经有相同填充的 descriptor set 了），除非 resource binding 完全不变，否则每个 draw call 都需要重新分配 descriptor set（这由 vulkan 的语义决定，等 command buffer 执行完成，CPU 侧收到同步信号时才能回收这些 descriptor set），从代码上看，只有一些低端的设备才会启用 descriptor set cache，我猜想可能的原因是高端设置走 bindless 路径就好了

Note3：一旦某一个 descriptor set 的 resource binding 发生改变，都会为整个 pipeline layout 申请和更新 descriptor set，即使可能其它的 descriptor set 并未发生改变

Note4：uniform buffer 在分配 gpu memory 大小时，是按整个 C++ 结构体的大小来算，这意味着在非 bindless 情况下，这些 resource 占用的字节被浪费了

## 5. 总结

关键要点

* ue 通过 shader parameter struct 和 ue uniform buffer 绑定 shader 参数，虽然它们可以混合 scalar data 和 resource，但最终底层实现仍然是将它们拆分成 gfx uniform buffer + resource
* 绑定时只会绑定 shader 实际使用的参数，因此 shader parameter struct 和 ue uniform buffer 声明比 shader 实际使用的更多的参数不会带来额外的性能负担
* 当前的实现（这里没有考虑 bindless 路径是怎么做的）里 shader 侧不能使用 resource array，C++ 侧声明的 resource array 会展平为 `resource_%d`
* 在 pipeline 创建时才会最终决定 pipeline layout，并修改 spirv 文件中的绑定情况。RenderCore 一层看到的 Buffer Index / Base Index 只是 Vulkan RHI 提供的索引，与 descriptor set / binding 没有关系
* 决定 pipeline layout 时，Vulkan RHI 默认为每个 shader stage 分配 descriptor set，stage 内每个 resource 一个 binding 号。不会考虑跨 stage 复用 resource 的情况，
* Vulkan RHI 中存在 PSO 的复用，pipeline layout 的复用以及 descriptor set layout 的复用
* 切换 pipeline 时，不会根据 pipeline layout compatibility 来减少 resource binding，只要有一个 resource binding 发生改变，就会申请并更新所有的 descriptor set，然后重新 binding

TODO：出于完整性，是不是应该解释一下创建各个 resource（包括 texture 和 ue uniform buffer 等）的 Vulkan RHI，后续应该单开一个讨论 Vulkan RHI 内 resource 的创建和管理的 blog 

TODO：后续看看 bindless texture 路径

## 附录

考虑一个较为复杂的 Shader 例子来理解整个确定布局的流程。Vertex Shader 使用以下资源：

```hlsl
// loose parameter，编译后进入 PackedUB
float4 VSColorScale;

// 普通 uniform buffer
cbuffer View
{
	float4x4 ViewProjectionMatrix;
};

// uniform buffer，内部既有 constant data 又有 resource
cbuffer SkinUniform
{
	float4 SkinParams;
	Texture2D BoneTexture;
	SamplerState BoneSampler;
};

// global resource
StructuredBuffer<float4> PositionBuffer;
SamplerState VSSampler;
```

Pixel Shader 使用以下资源：

```hlsl
// loose parameter，编译后进入 PackedUB
float4 PSTint;

// 普通 uniform buffer，和 VS 使用同一个 View layout
cbuffer View
{
	float4 CameraVector;
};

// 只包含 resource 的 uniform buffer
cbuffer MaterialUniform
{
	Texture2D BaseColorTexture;
	SamplerState BaseColorSampler;
};

// global resource
Texture2D SceneColorTexture;
SamplerState SceneColorSampler;
Texture2D NormalTexture;
SamplerState NormalSampler;
StructuredBuffer<float4> LightBuffer;
RWTexture2D<float4> DebugOutput;
```

编译完成后，VS 的 `FVulkanShaderHeader` 可以抽象成：

```
VSHeader.PackedUBs
  [0] VS loose parameter packed UB

VSHeader.UniformBuffers
  [0] View，has constant data
  [1] SkinUniform，has constant data + resource entries

VSHeader.Globals
  [0] BoneTexture，来自 SkinUniform 内部 resource
  [1] BoneSampler，来自 SkinUniform 内部 resource
  [2] PositionBuffer，global SRV
  [3] VSSampler，global sampler
```

PS 的 `FVulkanShaderHeader` 可以抽象成：

```
PSHeader.PackedUBs
  [0] PS loose parameter packed UB

PSHeader.UniformBuffers
  [0] View，has constant data
  [1] MaterialUniform，resource only，没有 constant data

PSHeader.Globals
  [0] BaseColorTexture，来自 MaterialUniform 内部 resource
  [1] BaseColorSampler，来自 MaterialUniform 内部 resource
  [2] SceneColorTexture，global texture
  [3] SceneColorSampler，global sampler
  [4] NormalTexture，global texture
  [5] NormalSampler，global sampler
  [6] LightBuffer，global SRV
  [7] DebugOutput，global UAV
```

注意，**uniform buffer 内部的 resource 也会进入 `CodeHeader.Globals`**，但它们不是 C++ shader parameter struct 上直接声明的 global resource，而是后续通过 `FShaderResourceTable` 从 uniform buffer 自己的 resource table 中展开绑定

在 `DescriptorSetLayoutMode = 0` 下，`FindOrAddDescriptorSet(Stage)` 会为每个 stage 创建一个专属 set

因此：

```
Vertex Stage -> Descriptor Set 0
Pixel Stage  -> Descriptor Set 1
```

VS 的处理顺序是 `PackedUBs -> UniformBuffers -> Globals`

| VS resource                  | CodeHeader 分类       | Vulkan set | Vulkan binding | descriptor type                             |
| ---------------------------- | ------------------- | ---------: | -------------: | ------------------------------------------- |
| VS loose parameter packed UB | `PackedUBs[0]`      |          0 |              0 | `UNIFORM_BUFFER` 或 `UNIFORM_BUFFER_DYNAMIC` |
| `View` constant data         | `UniformBuffers[0]` |          0 |              1 | `UNIFORM_BUFFER` 或 `UNIFORM_BUFFER_DYNAMIC` |
| `SkinUniform` constant data  | `UniformBuffers[1]` |          0 |              2 | `UNIFORM_BUFFER` 或 `UNIFORM_BUFFER_DYNAMIC` |
| `BoneTexture`                | `Globals[0]`        |          0 |              3 | `SAMPLED_IMAGE`                             |
| `BoneSampler`                | `Globals[1]`        |          0 |              4 | `SAMPLER`                                   |
| `PositionBuffer`             | `Globals[2]`        |          0 |              5 | `STORAGE_BUFFER`                            |
| `VSSampler`                  | `Globals[3]`        |          0 |              6 | `SAMPLER`                                   |

PS 同样按 `PackedUBs -> UniformBuffers -> Globals` 处理。注意 `MaterialUniform` 是 resource only uniform buffer，没有 constant data，因此它会进入 `StageInfos[Pixel].UniformBuffers[1]`，但不会创建自己的 uniform buffer descriptor binding。它内部的 texture / sampler 会作为 `Globals` 获得 binding

| PS resource                     | CodeHeader 分类       | Vulkan set | Vulkan binding | descriptor type                               |
| ------------------------------- | ------------------- | ---------: | -------------: | --------------------------------------------- |
| PS loose parameter packed UB    | `PackedUBs[0]`      |          1 |              0 | `UNIFORM_BUFFER` 或 `UNIFORM_BUFFER_DYNAMIC`   |
| `View` constant data            | `UniformBuffers[0]` |          1 |              1 | `UNIFORM_BUFFER` 或 `UNIFORM_BUFFER_DYNAMIC`   |
| `MaterialUniform` constant data | `UniformBuffers[1]` |          无 |              无 | resource only，不创建 UB descriptor               |
| `BaseColorTexture`              | `Globals[0]`        |          1 |              2 | `SAMPLED_IMAGE`                               |
| `BaseColorSampler`              | `Globals[1]`        |          1 |              3 | `SAMPLER`                                     |
| `SceneColorTexture`             | `Globals[2]`        |          1 |              4 | `SAMPLED_IMAGE`                               |
| `SceneColorSampler`             | `Globals[3]`        |          1 |              5 | `SAMPLER`                                     |
| `NormalTexture`                 | `Globals[4]`        |          1 |              6 | `SAMPLED_IMAGE`                               |
| `NormalSampler`                 | `Globals[5]`        |          1 |              7 | `SAMPLER`                                     |
| `LightBuffer`                   | `Globals[6]`        |          1 |              8 | `STORAGE_BUFFER`                              |
| `DebugOutput`                   | `Globals[7]`        |          1 |              9 | `STORAGE_IMAGE` 或 `STORAGE_BUFFER`，取决于 UAV 类型 |

对应的 `FDescriptorSetRemappingInfo` 可以抽象成：

```
StageInfos[Vertex].PackedUBDescriptorSet = 0
StageInfos[Vertex].PackedUBBindingIndices[0] = 0

StageInfos[Vertex].UniformBuffers[0] = { set 0, binding 1 }
StageInfos[Vertex].UniformBuffers[1] = { set 0, binding 2 }

StageInfos[Vertex].Globals[0] = { set 0, binding 3 }
StageInfos[Vertex].Globals[1] = { set 0, binding 4 }
StageInfos[Vertex].Globals[2] = { set 0, binding 5 }
StageInfos[Vertex].Globals[3] = { set 0, binding 6 }

StageInfos[Pixel].PackedUBDescriptorSet = 1
StageInfos[Pixel].PackedUBBindingIndices[0] = 0

StageInfos[Pixel].UniformBuffers[0] = { set 1, binding 1 }
StageInfos[Pixel].UniformBuffers[1] = resource only，没有 binding

StageInfos[Pixel].Globals[0] = { set 1, binding 2 }
StageInfos[Pixel].Globals[1] = { set 1, binding 3 }
StageInfos[Pixel].Globals[2] = { set 1, binding 4 }
...
```

在 `VulkanCommon.h` 中对 `CombinedImageSampler` 的注释明确标记为 `*not used*`，所以上述的 binding 中没有考虑 combined image sampler