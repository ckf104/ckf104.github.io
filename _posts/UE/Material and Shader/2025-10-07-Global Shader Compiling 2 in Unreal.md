---
title: Global Shader Compiling 2 in Unreal
date: 2025-10-07 19:45:12 +0800
categories:
  - UE5
comments: true
---
### shader parameter struct

TODO：解释 `SHADER_PARAMETER_SRV` 和 `SHADER_PARAMETER_RDG_TEXTURE` 的区别，是否被 render graph track 有什么区别（我看 RDG  这边 track 的 resource 分得很细，是不是 array，是不是 texel buffer 之类的，但是没被 track 的 resource 的分类就很糙，只有 texure，SRV，UAV 和 sampler 这几种，为什么）

#### shader parameter struct

TODO：`FShaderParametersMetadata` 的构造函数中传入的 `EUniformBufferBindingFlags` 有 Shader 和 Static 两种，这俩有啥区别，以及 shader pramameter metadata 有个 `StaticSlotName` 字段
TODO：解释声明 shader parameter struct 时结构体的 reference 是什么意思，`SHADER_PARAMETER_STRUCT_REF`

声明一个 shader parameter struct 的示例如下

```c++
//Shader Property Struct
BEGIN_SHADER_PARAMETER_STRUCT(FColourExtractParams,)
	//定义颜色、贴图参数
	SHADER_PARAMETER(FVector4f, TargetColor)
	SHADER_PARAMETER_RDG_TEXTURE(Texture2D, SceneColorTexture)
	SHADER_PARAMETER_STRUCT_INCLUDE(FSceneTextureShaderParameters, SceneTextures)

	//运行时绑定渲染目标
	RENDER_TARGET_BINDING_SLOTS()
END_SHADER_PARAMETER_STRUCT()
```

这样除了定义出原本的结构体外，会额外声明一个 `FShaderParametersMetadata` 类型的静态变量（类似于 `FTypeLayoutDesc`），然后它有一个最重要的 `Members 字段`，按照结构体中字段的声明顺序，每个 `FShaderParametersMetadata::FMember` 描述了一个结构体中的字段（类似于 `FFieldLayoutDesc`）

```c++
class FShaderParametersMetadata
{
	/** List of all members. */
	TArray<FMember> Members;
};
```

之前把孤立的字段声明的宏串出来一个链表是通过 `__COUNTER__` 宏+递归调用模板特化实现的，这里串出来 `FMember` 数组是通过函数重载加 typedef 技巧实现的，也非常巧妙

而在 `FMember` 中自然有一个指向 `FShaderParametersMetadata` 类的字段

```c++
class FMember
{
	uint32 Offset;  // 在结构体中的偏移
	EUniformBufferBaseType BaseType;
	EShaderPrecisionModifier::Type Precision;
	uint32 NumRows;  // 该字段的行数目，例如 mat4 的列数目为 4，行数目为 4
	uint32 NumColumns;  // 该字段的列数目，例如 vec4 的列数目为 4，行数目为 1
	uint32 NumElements;  // 如果是数组的话，表示数组的元素个数
	const FShaderParametersMetadata* Struct;
};
```

套娃的终点在哪呢？UE 定义了模板 `TShaderParameterTypeInfo`，`TShaderResourceParameterTypeInfo` 的针对基本类型的一系列特化，这些基本类型对应的 `FMember` 类的 `Struct` 字段为空

相比于 `LAYOUT_FIELD` 宏，通过 `SHADER_PARAMETER` 宏声明的字段会自动按照 GPU 那边的对齐方式进行对齐。例如声明相邻的 vec3 和 vec4 字段，那么 vec3 后边会自动 padding 4 个字节，而 `LAYOUT_FIELD` 宏没有这个效果

总结一下，相比于直接声明一个结构体，使用 `BEGIN_SHADER_PARAMETER_STRUCT` 等宏会额外提供了两个接口
* `StructName::FTypeInfo::GetStructMetadata` 接口，这函数调用时触发 `FShaderParametersMetadata` 的静态构造，返回的 `FShaderParametersMetadata` 作为描述该结构体的元类
* `StructName::CreateUniformBuffer` 接口，这个接口在 shader parameter struct 中会返回空，但 uniform buffer 中是有具体实现的

#### uniform buffer

**TODO：在 uniform buffer 中声明 texture 得到了 int 类型的 bindless_xxx，这是咋用的**

声明 uniform buffer 和声明 shader parameter struct 差不多，只是把 `BEGIN_SHADER_PARAMETER_STRUCT` 换成 `BEGIN_UNIFORM_BUFFER_STRUCT`，`END_SHADER_PARAMETER_STRUCT` 替换为 `END_UNIFORM_BUFFER_STRUCT`（我看到也有用 `BEGIN_GLOBAL_SHADER_PARAMETER_STRUCT` 这套宏的，但是看起来较新的定义都是用的 `BEGIN_UNIFORM_BUFFER_STRUCT`）

举一个例子

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
```

然后 UE 这边生成给预处理的代码是（见 `CreateHLSLUniformBufferDeclaration` 函数）

```hlsl
#pragma once
UB_CB_DEFINITION_START(ColourExtractParamsUniform)
	UB_FLOAT(4) UB_CB_MEMBER_NAME(ColourExtractParamsUniform, TintColor1);
	UB_FLOAT(4) UB_CB_MEMBER_NAME(ColourExtractParamsUniform, Color2_TintColor2);
	UB_FLOAT() UB_CB_MEMBER_NAME(ColourExtractParamsUniform, Color2_ScreenRayLength);
	UB_FLOAT() UB_CB_MEMBER_NAME(ColourExtractParamsUniform, Padding36);
	UB_FLOAT() UB_CB_MEMBER_NAME(ColourExtractParamsUniform, Padding40);
	UB_FLOAT() UB_CB_MEMBER_NAME(ColourExtractParamsUniform, Padding44);
	UB_UINT() UB_CB_PREFIXED_MEMBER_NAME(ColourExtractParamsUniform, BindlessSRV_, SceneColorTexture);
	UB_FLOAT() UB_CB_MEMBER_NAME(ColourExtractParamsUniform, Padding52);
	UB_FLOAT() UB_CB_MEMBER_NAME(ColourExtractParamsUniform, Padding56);
	UB_FLOAT() UB_CB_MEMBER_NAME(ColourExtractParamsUniform, Padding60);
	UB_FLOAT() UB_CB_MEMBER_NAME(ColourExtractParamsUniform, SMRTRayCount);
UB_CB_DEFINITION_END(ColourExtractParamsUniform)
UB_RESOURCE_MEMBER_SRV(Texture2D, ColourExtractParamsUniform, SceneColorTexture);
UniformBuffer ColourExtractParamsUniform
{
UB_DECL_PARAMETER(ColourExtractParamsUniform,TintColor1,TintColor1);
UB_DECL_PARAMETER(ColourExtractParamsUniform,Color2.TintColor2,Color2_TintColor2);
UB_DECL_PARAMETER(ColourExtractParamsUniform,Color2.ScreenRayLength,Color2_ScreenRayLength);
UB_DECL_PARAMETER(ColourExtractParamsUniform,SMRTRayCount,SMRTRayCount);
UB_DECL_RESOURCE(ColourExtractParamsUniform,SceneColorTexture,SceneColorTexture);
};
```

然后预处理完成后，传递给 DXC 的代码是（`Saved/ShaderDebugInfo` 文件夹下边，设置 `r.DumpShaderDebugInfo=2`）

```hlsl
struct FColourExtractParamsUniformConstants {
	 float4    TintColor1 ;
	 float4    Color2_TintColor2 ;
	 float    Color2_ScreenRayLength ;
	 float    Padding36 ;
	 float    Padding40 ;
	 float    Padding44 ;
	 uint    BindlessSRV_SceneColorTexture ;
	 float    Padding52 ;
	 float    Padding56 ;
	 float    Padding60 ;
	 float    SMRTRayCount ;
 };
ConstantBuffer<FColourExtractParamsUniformConstants> ColourExtractParamsUniform;
Texture2D  ColourExtractParamsUniform_SceneColorTexture;
```

这说明 `SHADER_PARAMETER_STRUCT` 和 `SHADER_PARAMETER_STRUCT_INCLUDE` 没啥区别，只是在 shader 侧字段的名字和用法变了一下
在 shader 中，`ColourExtractParamsUniform.Color2.TintColor2` 被替换为了 `ColourExtractParamsUniform.Color2_TintColor2`，然后 `ColourExtractParamsUniform.SceneColorTexture` 被替换为了 `ColourExtractParamsUniform_SceneColorTexture`

另外需要在 cpp 文件里实现

```c++
IMPLEMENT_UNIFORM_BUFFER_STRUCT(FColourExtractParamsUniform, "ColourExtractParamsUniform");
```

总的来说，与 shader parameter struct 比较，主要的区别是

* 静态定义的 `FShaderParametersMetadata` 的 `UseCase` 字段是 `UniformBuffer`，而 shader parameter struct 中是 `ShaderParameterStruct`。然后 `ShaderVariableName` 字段中包含了我们在 shader 中使用的 uniform buffer 变量的名称，这是在 `IMPLEMENT_UNIFORM_BUFFER_STRUCT` 宏的字符串参数指定的
* `StructName::CreateUniformBuffer` 接口有具体实现
* `IMPLEMENT_UNIFORM_BUFFER_STRUCT` 还会声明一个用于延迟注册的全局变量，引擎在 `PreInitPreStartupScreen` 中会调用 `FShaderParametersMetadataRegistration::CommitAll` 来触发 uniform buffer 这边的 `FShaderParametersMetadata` 的构造（shader parameter struct 这边的 `FShaderParametersMetadata` 的构造是随 shader type 触发的）

#### shader parameter metadata 构造函数

然后我们说一下 shader parameter metadata 构造函数干的事情。这里会把 uniform buffer 的 shader parameter metadata 都串到全局的单链表 `GUniformStructList` 上，并加入到全局的哈希表 `NameStructMap` 中，这是 hashed variable name 到 `FShaderParametersMetadata` 的映射

然后 shader parameter struct 的 shader parameter metadata 会直接调用 `FShaderParametersMetadata::InitializeLayout`，它会根据 shader parameter struct 的结构，创建出 `FRHIUniformBufferLayout`，存储在 shader parameter metadata 的 `Layout` 字段，这个类感觉就是记录一下 shader parameter struct 中包含哪些 resource 以及它们在结构体中的偏移

而  uniform buffer 的 `FShaderParametersMetadata::InitializeLayout` 和 `FShaderParametersMetadata::InitializeUniformBufferDeclaration`（生成前面提到的 uniform buffer 的 hlsl 声明）是在后续
`PreInitPreStartupScreen` 调用的 `FShaderParametersMetadata::InitializeAllUniformBufferStructs` 中调用的

#### Global Shader 使用 shader parameter

然后我们的 global shader 大概会这样写

```c++
class FLearnShaderPS : public FGlobalShader
{
public:
        //生成着色器类型并且序列化
	DECLARE_EXPORTED_SHADER_TYPE(FLearnShaderPS,Global,)
	using FParameters = FColourExtractParams;
	SHADER_USE_PARAMETER_STRUCT(FLearnShaderPS, FGlobalShader);

	// other code...
};
```

这里 `DECLARE_EXPORTED_SHADER_TYPE` 展开后由两部分组成。第一部分和之前的 `DECLARE_TYPE_LAYOUT` 相同，主要是生成 `FTypeLayoutDesc` 的接口，第二部分大概长这样，可以看到，主要是声明 shader 的接口，例如 `ShaderMetaType` 和 `ShaderMapType` 的实际类型，最重要的是这个 `GetStaticType` 接口，它是整合了 `FTypeLayoutDesc` 和 `FShaderParametersMetadata`（前者描述 shader 内声明的各个字段，后者描述 shader 要使用的 parameter 结构），描述整个 shader 结构的元类，其它的 `ConstructSerializedInstance` 等函数都是后边用来填充 `ShaderMetaType` 的

```c++
	using ShaderMetaType = FGlobalShaderType;
	using ShaderMapType = FGlobalShaderMap;
	static ShaderMetaType& GetStaticType();

private:
	static FShaderTypeRegistration ShaderTypeRegistration;

public:
	static FShader* ConstructSerializedInstance() { return new FLearnShaderPS(); }
	static FShader* ConstructCompiledInstance(const typename FShader ::CompiledShaderInitializerType& Initializer) { return new FLearnShaderPS(static_cast<const typename ShaderMetaType ::CompiledShaderInitializerType&>(Initializer)); }
	static bool		ShouldCompilePermutationImpl(const FShaderPermutationParameters& Parameters) { return FLearnShaderPS ::ShouldCompilePermutation(static_cast<const typename FLearnShaderPS ::FPermutationParameters&>(Parameters)); }
	static void		ModifyCompilationEnvironmentImpl(const FShaderPermutationParameters& Parameters, FShaderCompilerEnvironment& OutEnvironment)
	{
		const typename FLearnShaderPS ::FPermutationDomain PermutationVector(Parameters.PermutationId);
		PermutationVector.ModifyCompilationEnvironment(OutEnvironment);
		FLearnShaderPS ::ModifyCompilationEnvironment(static_cast<const typename FLearnShaderPS ::FPermutationParameters&>(Parameters), OutEnvironment);
	};
```

`ShaderTypeRegistration` 用于注册，引擎初始化函数 `PreInitPreStartupScreen` 中调用 `FShaderTypeRegistration::CommitAll` 时，调用 `GetStaticType` 函数，触发 `ShaderMetaType` 的构造，并进一步把这个静态的  `ShaderMetaType` 实例注册到全局中

另外的 `using FParameters` 和 `SHADER_USE_PARAMETER_STRUCT` 主要是为实现 `GetStaticType` 函数的一些胶水代码（[GlobalShader参数的三种写法](https://www.cnblogs.com/wakuwaku/articles/16706479.html)）

然后是在 cpp 文件里会有一行

```c++
IMPLEMENT_SHADER_TYPE(, FLearnShaderPS, TEXT("/LearnShader/Private/LShader.usf"), TEXT("MainPS"), SF_Pixel);
```

它就实际实现 `GetStaticType` 函数，以及前边声明的 `ShaderTypeRegistration`。**因此总的来说，通过这一系列的宏，我们定义的 global shader 它对外层的关键接口就是这个元类 `ShaderMetaType`，它描述了 shader 的所有信息**

#### FShaderType 的构造函数

`FShaderType` 的构造函数主要做了一些全局注册，它一方面调用 `FTypeLayoutDesc::Register` 将 `FTypeLayoutDesc` 注册到全局的哈希链表 `GTypeLayoutHashBuckets` 之外，它还将自己注册到三个全局数据结构中
* `GShaderTypeList`：一个单链表，串起来所有的 shader type
* `ShaderNameToTypeMap`：一个 shader 名称到 shader type 的哈希映射
* `SortedTypesArray`：每种 shader type 一个有序数组，数组中按名称大小有序存放 shader type