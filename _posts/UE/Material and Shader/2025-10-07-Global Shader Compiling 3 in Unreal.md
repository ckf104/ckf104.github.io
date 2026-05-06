---
title: 渲染流程梳理 -- Shader Parameter Binding
date: 2025-10-07 20:45:12 +0800
categories:
  - Graphics
  - UE5
comments: true
---

[The Shader Permutation Problem - Part 2: How Do We Fix It?](https://therealmjp.github.io/posts/shader-permutations-part2/) 特别有意思，讨论了各种减少 shader permutation 的方法，以及它引用的一个讨论 PSO 的 [The Missing Guide to Modern Graphics APIs – 2. PSOs](https://blog.mecheye.net/2021/06/the-missing-guide-to-modern-graphics-apis-2-psos/)
### Global Shader Compiling Flow

TODO：增加对 shader pipeline 的描述
TODO：每个 job 有对应的 id，结合 material shader 的编译再看看

```c++
/** Used to identify the global shader map in compile queues. */
const int32 GlobalShaderMapId = 0;
```

TODO：我看 global shader 编译时是没有 vertex factory type 的，看看 vertex factory type 什么时候才会出现
TODO：编译结果得到 `TMap<FString, FParameterAllocation>` 表示 shader 中用到的 resource，这个 `BufferIndex` 和 `BaseIndex` 分别表示什么意思，后边是怎么用的，编译器是如何合理地设置 `BufferIndex` 和 `BaseIndex` 的呢？这个后续 copy 到了 `FShader` 的 `ParameterMapInfo` 字段，但 copy 时忽略了 `EShaderParameterType::UAV` 的类型是为什么？
TODO：如下的 shader parameter struct

```c++
BEGIN_SHADER_PARAMETER_STRUCT(Color2Setting,)
	SHADER_PARAMETER(FVector4f, TintColor2)
	SHADER_PARAMETER(float, ScreenRayLength)
END_SHADER_PARAMETER_STRUCT()

BEGIN_SHADER_PARAMETER_STRUCT(Tmp,)
	SHADER_PARAMETER(float, SMRTRayCount)
END_SHADER_PARAMETER_STRUCT()

//Shader Property Struct
BEGIN_UNIFORM_BUFFER_STRUCT(FColourExtractParamsUniform,)
	//定义颜色、贴图参数
	SHADER_PARAMETER(FVector4f, TintColor1)
	SHADER_PARAMETER_STRUCT(Color2Setting, Color2)
	SHADER_PARAMETER_RDG_TEXTURE(Texture2D, SceneColorTexture)
	SHADER_PARAMETER_STRUCT_INCLUDE(Tmp, TTmp)
	// SHADER_PARAMETER_STRUCT_INCLUDE(FSceneTextureShaderParameters, SceneTextures)
END_UNIFORM_BUFFER_STRUCT()

// End Test

//Shader Property Struct
BEGIN_SHADER_PARAMETER_STRUCT(FColourExtractParams,)
	//定义颜色、贴图参数
	SHADER_PARAMETER(FVector4f, TargetColor)
	SHADER_PARAMETER(float, TargetColor2)
	SHADER_PARAMETER_RDG_UNIFORM_BUFFER(FColourExtractParamsUniform, ColourExtractParamsUniform)
	SHADER_PARAMETER_RDG_TEXTURE(Texture2D, SceneColorTexture)
	// SHADER_PARAMETER_STRUCT_INCLUDE(FSceneTextureShaderParameters, SceneTextures)

	//运行时绑定渲染目标
	RENDER_TARGET_BINDING_SLOTS()
END_SHADER_PARAMETER_STRUCT()
```

查看生成的 d3d 汇编，可知 d3d 这边输出的 resource binding

```hlsl
; Resource Bindings:
;
; Name                                 Type  Format         Dim      ID      HLSL Bind  Count
; ------------------------------ ---------- ------- ----------- ------- -------------- ------
; _RootShaderParameters             cbuffer      NA          NA     CB0            cb0     1
; ColourExtractParamsUniform        cbuffer      NA          NA     CB1            cb1     1
; ColourExtractParamsUniform_SceneColorTexture   texture     f32          2d      T0             t0     1
; SceneColorTexture                 texture     f32          2d      T1             t1     1
```

然后编译出的 parameter allocation 长这样

![D3D resource binding overview](/assets/img/posts/ue/global-shader-compiling-3/d3d-resource-binding-overview.png)

我尝试把 graphics api 切换为了 vulkan，查看输出的 spirv 代码

```c++
               OpDecorate %ColourExtractParamsUniform DescriptorSet 1
               OpDecorate %ColourExtractParamsUniform Binding 1
               OpDecorate %ColourExtractParamsUniform_SceneColorTexture DescriptorSet 1
               OpDecorate %ColourExtractParamsUniform_SceneColorTexture Binding 2
               OpDecorate %_Globals DescriptorSet 1
               OpDecorate %_Globals Binding 0
               OpDecorate %SceneColorTexture DescriptorSet 1
               OpDecorate %SceneColorTexture Binding 3
```

然后编译出的 parameter allocation 长这样

![Vulkan resource binding overview](/assets/img/posts/ue/global-shader-compiling-3/vulkan-resource-binding-overview.png)

TODO：另外就是 `TMap<FString, FParameterAllocation>` 中的 shader resource type 只有 `EShaderParameterType` 中规定的，是不是少了一点，相比于 C++ 侧的 shader resource type 的 `EUniformBufferBaseType` 中规定的，两者是怎么转换的

在 `FShaderTypeRegistration::CommitAll` 调用之后（这时候就有 shader type 了），`PreInitPreStartupScreen` 中会调用

```c++
void CompileGlobalShaderMap(bool bRefreshShaderMap);
```

来触发 global shader 的编译

首先是调用 `TryLoadCookedGlobalShaderMap`，这个函数会去找有没有指定的 bin 文件，所有编译好的 bin 文件都会放在里面。编辑器下调试是找不到这个（我猜可能打包后的版本才有这玩意）

然后在编辑器模式下会去 DDC 缓存里找。它会把所有的 global shader type 按照依赖的 shader 文件进行分类（因为可能多个 global shader 是写在一个 usf 文件里的），依赖同一个 shader 文件的所有 global shader type 混合生成一个查找 DDC 缓存的 key，如果缓存命中，就反序列化得到一个 `FGlobalShaderMapSection` 加入到 `FGlobalShaderMap` 中

再之后调用 `VerifyGlobalShaders`，验证是否每个 global shader type + permutation id 的对子都能在 `FGlobalShaderMap` 中找到 global shader，如果找不到，则调用 `FGlobalShaderTypeCompiler::BeginCompileShader` 生成一个 shader compiling job

```c++
class FShaderCompileJob : public FShaderCommonCompileJob
{
public:
	static const EShaderCompileJobType Type = EShaderCompileJobType::Single;

	FShaderCompileJobKey Key;

	/** 
	 * Additional parameters that can be supplied to the compile job such 
	 * that it is available from the compilation begins to when the FShader is created.
	 */
	TSharedPtr<const FShaderType::FParameters, ESPMode::ThreadSafe> ShaderParameters;

	/** Input for the shader compile */
	FShaderCompilerInput Input;
	FShaderPreprocessOutput PreprocessOutput;
	TUniquePtr<FShaderPreprocessOutput> SecondaryPreprocessOutput{};
	FShaderCompilerOutput Output;
	TUniquePtr<FShaderCompilerOutput> SecondaryOutput{};
}
```

我们重点关注 `Input` 字段，所有传递给编译器参数都存放在这里

```c++
struct FShaderCompilerInput
{
	FShaderTarget Target; // shader 的类型（例如是 vertex 还是 fragment shader）
	
	FString VirtualSourceFilePath;  // shader file 路径
	FString EntryPointName;   // shader 的入口点名称
	
	FShaderCompilerEnvironment Environment;  // 编译器的命令行参数和宏定义等
	
	// other fields....
};
```

`FGlobalShaderTypeCompiler::BeginCompileShader` 中会填充 `Input` 字段，也会调用我们的 `ModifyCompilationEnvironment` 函数，这个函数传入的 `FShaderCompilerEnvironment` 就是 `Input` 的 `Environment` 字段

然后 `VerifyGlobalShaders` 中会调用 `FShaderCompilingManager::SubmitJobs` 把这些 compiling job 先做一遍 preprocess（主要是处理宏），然后提交上去。依据配置，这些编译任务可能多线程执行，也可能另起新的进程执行，还可能是分布式编译。默认情况下是另起新的进程执行，可以在配置文件中加上

```c++
r.ShaderCompiler.ParallelInProcess=1
r.Shaders.AllowCompilingThroughWorkers=0
```

这样这些编译任务就会在多线程执行了，方便 debug

具体的编译步骤可以大概分为三步
* 第一步是预处理（见 `PreprocessShaderInternal` 函数），它与平台无关，主要是将 include 的头文件包含进来（这时候就把生成的 uniform buffer 的定义给包括进来了），然后做一下宏替换
* 第二步是 shader parameter 的预处理，它就与平台相关了，在 D3D 平台中，它会把我们在 shader 中全局声明的数据类型的 shader parameter（例如 float4）都塞到一个 uniform buffer 中（`FShaderParameterParser::MoveShaderParametersToRootConstantBuffer`），名称固定为 `_RootShaderParameters`
* 第三步就是最终的编译，在 D3D 平台中，它会调用 windows 提供的 DXC 编译器将 shader 代码编译为 d3d 汇编。除了 d3d 汇编外，还会得到一些反射信息，例如 shader 中使用的 resource 的名称，它的 binding 编号等（也许是编译器直接输出的，也可能是解析编译器输出得到的，例如 SPIRV-Reflect 这样的库）。这些输出都存放在 `FShaderCompileJob` 的 `Output` 字段

Note0：第三步中拿到了 shader 代码的反射信息，这会拿来检查这些 resource 名称是否在 c++ 侧的 shader parameter struct 有对应的匹配字段。注意 uniform buffer 是不需要检查这个的，因为它在 shader 侧的代码是自动生成的，shader 代码编译过了就说明匹配上了

Note1: `FShaderCompilingManager::SubmitJobs` 会用 preprocess 得到的代码，以及编译参数等做一个 hash，然后查找 DDC 和缓存的编译结果，如果命中了则跳过该 job 的编译。这样做避免了改动 shader 导致所有的 shader permutation 都要重新编译

Note2: `MoveShaderParametersToRootConstantBuffer` 在将全局声明的数据类型的 shader parameter 都塞到一个 uniform buffer 时，会保持 parameter 在 uniform buffer 中的偏移和 parameter 在 C++ shader parameter struct 中的偏移一致（这样的好处是在用用户提供的 struct 更新这个 uniform buffer 时很方便，一个 memcpy 就行了），这也意味着我们在声明 shader parameter struct 时应该把所有的数据类型的 parameter 都放在开头，例如

```c++
BEGIN_SHADER_PARAMETER_STRUCT(FColourExtractParams,)
	//定义颜色、贴图参数
	SHADER_PARAMETER(FVector4f, TargetColor)
	SHADER_PARAMETER(float, TargetColor2)
	SHADER_PARAMETER_RDG_UNIFORM_BUFFER(FColourExtractParamsUniform, ColourExtractParamsUniform)
	RENDER_TARGET_BINDING_SLOTS()
END_SHADER_PARAMETER_STRUCT()
```

`MoveShaderParametersToRootConstantBuffer` 生成的全局 cbuffer 是紧凑排列的

```hlsl
cbuffer _RootShaderParameters
{
float4 TargetColor : packoffset(c0);
float TargetColor2 : packoffset(c1);
}
```

但如果我如果把 shader 参数写成这样，把 `TargetColor` 和 `TargetColor2` 分开

```c++
BEGIN_SHADER_PARAMETER_STRUCT(FColourExtractParams,)
	SHADER_PARAMETER(FVector4f, TargetColor)
	SHADER_PARAMETER_RDG_UNIFORM_BUFFER(FColourExtractParamsUniform, ColourExtractParamsUniform)
	SHADER_PARAMETER(float, TargetColor2)
	RENDER_TARGET_BINDING_SLOTS()
END_SHADER_PARAMETER_STRUCT()
```

`MoveShaderParametersToRootConstantBuffer` 生成的 cbuffer 就会在中间增加 16 bytes 的 padding

```hlsl
cbuffer _RootShaderParameters
{
float4 TargetColor : packoffset(c0);
float TargetColor2 : packoffset(c2);
}
```

另一方面，我把 RHI 切换为 vulkan SM6，发现 vulkan 没有受这个布局影响，因为 vulkan 的预处理中没有把这些全局变量塞到一个 cbuffer 里

后续 game 线程在适当时机调用 `FShaderCompilingManager::FinishAllCompilation` 或者 `FShaderCompilingManager::FinishCompilation` 阻塞等待 shader 编译完成。编译完成后，会 new 出新的 `FGlobalShader`，把它和编译得到的 shader 代码加入到 global shader map 中，并将每个 `FGlobalShaderMapSection` 序列化到 DDC 中

#### uniform buffer including

这里讨论一下 uniform buffer 的 shader 代码是怎么 include 进来的。接口上，UE 要求我们在使用 uniform buffer 时需要 include `/Engine/Generated/GeneratedUniformBuffers.ush` 头文件。然后 `FShaderCompilerEnvironment` 中包含如下两个字段

```c++
struct FShaderCompilerEnvironment
{
	// Map of the virtual file path -> content.
	// The virtual file paths are the ones that USF files query through the #include "<The Virtual Path of the file>"
	TMap<FString,FString> IncludeVirtualPathToContentsMap;

	TMap<FString, FThreadSafeSharedAnsiStringPtr> IncludeVirtualPathToSharedContentsMap;
	
	// other code...
};
```

`IncludeVirtualPathToContentsMap` 和 `IncludeVirtualPathToSharedContentsMap` 中直接保存了文件名到文件内容的映射。在编译的第一步预处理中，如果 shader 中 include 的文件在这俩 map 中，那就不会在磁盘上去找文件，而是直接将这俩 map 保存的文件内容替换进来了。`FGlobalShaderTypeCompiler::BeginCompileShader` 中会调用 `FShaderType::AddUniformBufferIncludesToEnvironment` 和 `FVertexFactoryType::AddUniformBufferIncludesToEnvironment`，它们干的事情都是一样的，针对每个自己引用的 uniform buffer，生成两条映射（其中 %s 替换为 uniform buffer 的实际名字）加入到 map 中

```
/Engine/Generated/GeneratedUniformBuffers.ush  -> #include "/Engine/Generated/UniformBuffers/%s.ush"
/Engine/Generated/UniformBuffers/%s.ush ->  uniform buffer declaration
```

其中 %s 替换为 uniform buffer 的实际名字，uniform buffer declaration 替换为 ``FShaderParametersMetadata::InitializeUniformBufferDeclaration`` 中生成的 uniform buffer 定义

这样在预处理完成后 shader 中就包含实际的 uniform buffer 定义了。那 shader type 和 vertex factory type 是怎么知道自己引用了哪些 uniform buffer 呢

引擎在 `FEngineLoop::PreInitPreStartupScreen` 会调用 `InitializeShaderTypes`，该函数会 load 所有的 shader type 和 vertex factory type 使用的 shader 文件，搜索文件中是否包含用户在 C++ 侧定义的 uniform buffer 变量名称，匹配上的 uniform 变量名称都存储在 shader type 和 vertex factory type 的 `ReferencedUniformBufferNames` 字段中

这感觉有点过于粗暴了，为啥不从 C++ 侧的 shader parameter struct 引用的 uniform buffer 入手呢？

#### global shader 的构造过程

我们详细说下 `FGlobalShader` 的构造函数。编译完成后 new 出新的 `FGlobalShader` 时调用的构造函数是（`SHADER_USE_PARAMETER_STRUCT` 宏的展开）

```c++
	FLearnShaderPS(const ShaderMetaType ::CompiledShaderInitializerType& Initializer)
		: FGlobalShader(Initializer) { BindForLegacyShaderParameters<FParameters>(this, Initializer.PermutationId, Initializer.ParameterMap, true); }
```

它就是用 shader 的编译结果填充 `FShader` 中的字段，下面几个字段是和 shader 参数绑定相关的
其中 `FShader` 的构造函数初始化 `ParameterMapInfo`, `UniformBufferParameters`

```c++
	LAYOUT_FIELD(FShaderParameterBindings, Bindings);
	LAYOUT_FIELD(FShaderParameterMapInfo, ParameterMapInfo); 

	LAYOUT_FIELD(TMemoryImageArray<FHashedName>, UniformBufferParameterStructs);
	LAYOUT_FIELD(TMemoryImageArray<FShaderUniformBufferParameter>, UniformBufferParameters);
```

其中 `FShader` 的构造函数初始化 `ParameterMapInfo`，`UniformBufferParameterStructs`，`UniformBufferParameters`。这几个主要是保存 shader 侧的 binding index，而 `BindForLegacyShaderParameters` 初始化 `Bindings` 字段，它保存了每个 resource 在 c++ 侧的 shader parameter struct 中的偏移
### Global Shader Map

现在我们来看看 `FGlobalShaderMap` 的结构，这个 map 的 key 是 shader usf 文件的哈希，因为一个 shader usf 文件中可能包含多个 global shader（因为每个 shader permutation 都对应一个 shader，而且不同的 shader 也可能放在一个 usf 文件里），因此把它们整合为了 `FGlobalShaderMapSection` 类

```c++
class FGlobalShaderMap
{
private:
	TMap<FHashedName, FGlobalShaderMapSection*> SectionMap;
	EShaderPlatform Platform;
};
```

然后是 `FGlobalShaderMapSection` 的定义

```c++
class FGlobalShaderMapSection : public TShaderMap<FGlobalShaderMapContent, FShaderMapPointerTable>;

template<typename ContentType, typename PointerTableType = FShaderMapPointerTable>
class TShaderMap : public FShaderMapBase;

class FShaderMapBase
{
	TRefCountPtr<FShaderMapResource> Resource;
	TRefCountPtr<FShaderMapResourceCode> Code;
	FShaderMapPointerTable* PointerTable;
	TMemoryImageObject<FShaderMapContent> Content;
	uint32 NumFrozenShaders;
	EShaderPermutationFlags PermutationFlags;
};
```

因为它是会被序列化到磁盘的，因此有一个专门的 pointer table 来处理指针的序列化，相关机制我们已经在 Global Shader Compiling 1 in Unreal 中介绍过了

#### shader map content

我们先看看 `Content` 字段有些什么，它的指针指向的实际类型为 `FGlobalShaderMapContent`

```c++
class FGlobalShaderMapContent : public FShaderMapContent
{
	LAYOUT_FIELD(FHashedName, HashedSourceFilename);  // 包含这组 global shader 的哈希文件
};

class FShaderMapContent
{
	LAYOUT_FIELD(FMemoryImageHashTable, ShaderHash);
	LAYOUT_FIELD(TMemoryImageArray<FHashedName>, ShaderTypes);
	LAYOUT_FIELD(TMemoryImageArray<int32>, ShaderPermutations);
	LAYOUT_FIELD(TMemoryImageArray<TMemoryImagePtr<FShader>>, Shaders);
	LAYOUT_FIELD(TMemoryImageArray<TMemoryImagePtr<FShaderPipeline>>, ShaderPipelines);
	/** The ShaderPlatform Name this shader map was compiled with */
	LAYOUT_FIELD(FMemoryImageName, ShaderPlatformName);
};
```

整个其实就是一个哈希表组织，只不过哈希表中存的是指针。`ShaderHash` 就是一个拉链式的哈希表，由 shader name + shader permutation 产生一个哈希值。哈希表的 value 是一个数组下标索引（指针），索引 `ShaderTypes`，`ShaderPermutations` 和 `Shaders` 这三个数组。我们通常使用下面的代码获取 global shader

```c++
TShaderMapRef<FLearnShaderPS> PixelShader(GlobalShaderMap, PermutationVector);
```

它的工作逻辑就是根据我们提供的 shader 类型拿到 global shader type，这样就从 `GlobalShaderMap` 中拿到对应的 `FGlobalShaderMapSection`，然后再计算哈希值，从 `FShaderMapContent` 的 `Shaders` 数组中找到我们要的 shader（虽然我觉得 `ShaderTypes` 这个字段有些多余，因为我可以直接从 `FShader` 中拿到 shader type，然后拿到 hashed name）

`FShaderMapContent::Finalize` 会将 `FShaderMapContent` 中的数组按照 `ShaderTypes` 的大小进行排序，这样保证序列化的结果是唯一的
#### shader map resource code

另一块是 `FShaderMapResourceCode`，它包含所有 global shader code。其中数组是按照 shader code hash 的大小有序排列的，使得序列化的结果是唯一的

```c++
class FShaderMapResourceCode : public FThreadSafeRefCountedObject
{
	struct FShaderEntry
	{
		TArray<uint8> Code;
		int32 UncompressedSize;
		EShaderFrequency Frequency;
	};
	/** A hash describing the total contents of *this. Constructed from the contents of ShaderHashes during Finalize. */
	FSHAHash ResourceHash;
	TArray<FSHAHash> ShaderHashes;
	TArray<FShaderEntry> ShaderEntries;
};
```

#### shader map resource

```c++
class FShaderMapResource_InlineCode : public FShaderMapResource
{
	TRefCountPtr<FShaderMapResourceCode> Code;
};
class FShaderMapResource : public FRenderResource, public FDeferredCleanupInterface
{
	/** An array of shader pointers (refcount is managed manually). */
	TUniquePtr<std::atomic<FRHIShader*>[]> RHIShaders;

	/** Since the shaders are no longer a TArray, this is their count (the size of the RHIShaders array). */
	int32 NumRHIShaders;
	
	// other code...
}
```

如果是 `FShaderMapResource_InlineCode`，则 shader map resource 这边不参与序列化，它主要创建和保存 RHI Shader

TODO：另外还有一种 `FShaderMapResource_SharedCode`，不知道它是用来解决什么问题的
