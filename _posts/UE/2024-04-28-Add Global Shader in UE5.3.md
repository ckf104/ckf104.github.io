主要参考了这两篇文章

* [Adding Global Shaders to Unreal Engine](https://dev.epicgames.com/documentation/en-us/unreal-engine/adding-global-shaders-to-unreal-engine?application_version=5.3)，这个比较老了，用的很多 API 都没了
* [UE4.25添加GlobalShader踩坑](https://zhuanlan.zhihu.com/p/364559948)，这个是上一个的更新版，不过用的一部分 API 也都被弃用了

我主要在 UE 代码中做了如下添加

这是第一个新建文件 `Engine/Source/Runtime/Engine/Public/FMyTestVS.h`

```c++
#include "GlobalShader.h"
#include "Math/Color.h"
#include "RHIDefinitions.h"

// This can go on a header or cpp file
class FMyTestVS : public FGlobalShader {
    // DECLARE_EXPORTED_SHADER_TYPE(FMyTestVS, Global, /*MYMODULE_API*/);
    // DECLARE_GLOBAL_SHADER(FMyTestVS);
    DECLARE_EXPORTED_GLOBAL_SHADER(FMyTestVS, RENDERCORE_API);
    // DECLARE_EXPORTED_SHADER_TYPE(FMyTestVS, Global, RENDERCORE_API);

    FMyTestVS() {}
    FMyTestVS(const ShaderMetaType::CompiledShaderInitializerType &Initializer)
        : FGlobalShader(Initializer) {}

    static bool ShouldCache(EShaderPlatform Platform) { return true; }
};

class FMyTestPS : public FGlobalShader {
    // DECLARE_EXPORTED_SHADER_TYPE(FMyTestPS, Global, /*MYMODULE_API*/);
    DECLARE_EXPORTED_GLOBAL_SHADER(FMyTestPS, RENDERCORE_API);
    // DECLARE_EXPORTED_SHADER_TYPE(FMyTestPS, Global, RENDERCORE_API);

    LAYOUT_FIELD(FShaderParameter, MyColorParameter);

    FMyTestPS() {}
    FMyTestPS(const ShaderMetaType::CompiledShaderInitializerType &Initializer)
        : FGlobalShader(Initializer) {
        MyColorParameter.Bind(Initializer.ParameterMap, TEXT("MyColor"),
                              SPF_Mandatory);
    }

    static void ModifyCompilationEnvironment(
        const FGlobalShaderPermutationParameters &Parameters,
        FShaderCompilerEnvironment &OutEnvironment) {
        FGlobalShader::ModifyCompilationEnvironment(Parameters, OutEnvironment);
        // Add your own defines for the shader code
        OutEnvironment.SetDefine(TEXT("MY_DEFINE"), 1);
    }

    static bool ShouldCache(EShaderPlatform Platform) {
        // Could skip compiling for Platform == SP_METAL for example
        return true;
    }

    // FShader interface.
    /*virtual bool Serialize(FArchive &Ar) override {
      bool bShaderHasOutdatedParameters = FGlobalShader::Serialize(Ar);
      Ar << MyColorParameter;
      return bShaderHasOutdatedParameters;
    }*/
    void SetParameters(FRHIBatchedShaderParameters &BatchedParameters,
                  const FLinearColor &Color) {
        SetShaderValue(BatchedParameters, MyColorParameter, Color);
    }
  
};
```

这是第二个新建文件 `Engine/Source/Runtime/Engine/Private/FMyTestVS.cpp`

```c++
#include "FMyTestVS.h"

// IMPLEMENT_GLOBAL_SHADER(FClusteredShadingVS,
// "/Engine/Private/ClusteredDeferredShadingVertexShader.usf",
// "ClusteredShadingVertexShader", SF_Vertex);

// This needs to go on a cpp file
IMPLEMENT_GLOBAL_SHADER(FMyTestVS, "/Engine/Private/MyTest.usf", "MainVS",
                        SF_Vertex);

// Same source file as before, different entry point
// IMPLEMENT_SHADER_TYPE(, FMyTestPS, TEXT("MyTest"), TEXT("MainPS"), SF_Pixel);
IMPLEMENT_GLOBAL_SHADER(FMyTestPS, "/Engine/Private/MyTest.usf", "MainPS",
                        SF_Pixel);
```

这是第三个新建文件 `Engine/Shaders/Private/MyTest.usf`

```hlsl
// Simple pass-through vertex shader
#include "/Engine/Public/Platform.ush"

void MainVS(in float4 InPosition
            : ATTRIBUTE0, out float4 Output
            : SV_POSITION) {
  Output = InPosition;
}

// Simple solid color pixel shader
float4 MyColor;
float4 MainPS() : SV_Target0 { return MyColor; }
```

然后第四个文件 `Engine/Source/Runtime/Renderer/Private/DeferredShadingRenderer.cpp` 我添加了如下修改

```c++
// My adding code starts

static TAutoConsoleVariable CVarMyTest(
		TEXT("r.MyTest"),
		1,
		TEXT("Test My Global Shader, set it to 0 to disable, or to 1, 2 or 3 for fun!"),
		ECVF_RenderThreadSafe
);

void RenderMyTest(FRHICommandList& RHICmdList, ERHIFeatureLevel::Type FeatureLevel, const FLinearColor& Color)
{
	// Get the collection of Global Shaders
	auto ShaderMap = GetGlobalShaderMap(FeatureLevel);

	// Get the actual shader instances off the ShaderMap
	TShaderMapRef<FMyTestVS> MyVS(ShaderMap);
	TShaderMapRef<FMyTestPS> MyPS(ShaderMap);

	FGraphicsPipelineStateInitializer GraphicsPSOInit;
	RHICmdList.ApplyCachedRenderTargets(GraphicsPSOInit);
	GraphicsPSOInit.RasterizerState =  TStaticRasterizerState<>::GetRHI();
	GraphicsPSOInit.BlendState = TStaticBlendState<>::GetRHI();
	GraphicsPSOInit.DepthStencilState=TStaticDepthStencilState<false, CF_Always>::GetRHI();
	GraphicsPSOInit.BoundShaderState.VertexDeclarationRHI = GetVertexDeclarationFVector4();
	GraphicsPSOInit.BoundShaderState.VertexShaderRHI = MyVS.GetVertexShader();
	GraphicsPSOInit.BoundShaderState.PixelShaderRHI = MyPS.GetPixelShader();
	GraphicsPSOInit.PrimitiveType = PT_TriangleStrip;

	SetGraphicsPipelineState(RHICmdList, GraphicsPSOInit, 0); // Call our function to set up parameters
	// Call our function to set up parameters
	SetShaderParametersLegacyVS(RHICmdList, MyPS, Color);

	// create a static vertex buffer
	FRHIResourceCreateInfo CreateInfo(TEXT("FClearVertexBuffer"));
	FBufferRHIRef VertexBufferRHI = RHICmdList.CreateVertexBuffer(sizeof(FVector4f) * 4, BUF_Static, CreateInfo);
	void* VoidPtr = RHICmdList.LockBuffer(VertexBufferRHI, 0, sizeof(FVector4f) * 4, RLM_WriteOnly);
	// Generate the vertices used
	FVector4f* Vertices = reinterpret_cast<FVector4f*>(VoidPtr);
	Vertices[0] = FVector4f(-1.0f, 1.0f, 0.0f, 1.0f);
	Vertices[1] = FVector4f(1.0f, 1.0f, 0.0f, 1.0f);
	Vertices[2] = FVector4f(-1.0f, -1.0f, 0.0f, 1.0f);
	Vertices[3] = FVector4f(1.0f, -1.0f, 0.0f, 1.0f);
	RHICmdList.UnlockBuffer(VertexBufferRHI);
	RHICmdList.SetStreamSource(0,VertexBufferRHI, 0);
	RHICmdList.DrawPrimitive(0,2,1);
}

// My adding code ends

void FDeferredShadingSceneRenderer::Render(FRDGBuilder& GraphBuilder){
 	// ...
    
    SCOPE_CYCLE_COUNTER(STAT_FDeferredShadingSceneRenderer_RenderFinish);
	RDG_GPU_STAT_SCOPE(GraphBuilder, FrameRenderFinish);
	GraphBuilder.SetCommandListStat(GET_STATID(STAT_CLM_RenderFinish));
    
    // My adding code starts
    
    int32 MyTestValue = CVarMyTest.GetValueOnAnyThread();
	if (MyTestValue != 0)
	{
		FLinearColor Color(MyTestValue == 1, MyTestValue == 2, MyTestValue == 3, 1);
		RenderMyTest(GraphBuilder.RHICmdList, FeatureLevel, Color);
	}
    
    // My adding code ends
    
    RenderFinish(GraphBuilder, ViewFamilyTexture);
	GraphBuilder.SetCommandListStat(GET_STATID(STAT_CLM_AfterFrame));
	GraphBuilder.AddDispatchHint();
	GraphBuilder.FlushSetupQueue();
}
```

### TODO

输出的颜色和我预想的不一样，实际情况是变量值为1时输出蓝色，变量值为2时输出绿色？（但我预期变量值为1时应该输出红色？）



## Global Shader

这里对目前从 global shader 中看到的东西进行总结。在 `FMyTestVS.h` 中看到了 vertex shader 和 pixel shader，针对它们的写法，我们可以提出下面的问题

* global shader 的实例如何创建，又是如何注册到 ue 中的
* CompiledShaderInitializerType 是什么，FShaderParameter 又是什么东西，它是如何关联到实际的 pixel shader 中的 mycolor 参数的？
* IMPLEMENT_GLOBAL_SHADER 宏干了什么
* paramter.bind 函数在干嘛

### 反射的类型信息

global shader 中会定义两个重要的类型，`ShaderMetaType` 和 `ShaderMapType`，它们通常是通过下面这些宏定义的

```c++
#define DECLARE_GLOBAL_SHADER(ShaderClass)
#define DECLARE_EXPORTED_GLOBAL_SHADER(ShaderClass, RequiredAPI)
#define DECLARE_EXPORTED_SHADER_TYPE(ShaderClass,ShaderMetaTypeShortcut,RequiredAPI, ...)

#define INTERNAL_DECLARE_SHADER_TYPE_COMMON(ShaderClass,ShaderMetaTypeShortcut,RequiredAPI) \
	public: \
	using ShaderMetaType = F##ShaderMetaTypeShortcut##ShaderType; \
	using ShaderMapType = F##ShaderMetaTypeShortcut##ShaderMap; \
	\
	static RequiredAPI ShaderMetaType& GetStaticType(); \
	private: \
	static FShaderTypeRegistration ShaderTypeRegistration; \
	public: \
	\
	SHADER_DECLARE_VTABLE(ShaderClass)
```

`Runtime/Core/Public/Serialization/MemoryLayout.h` 文件中定义的下面两个结构体描述了类型信息

```c++
struct FFieldLayoutDesc{
    const TCHAR* Name;
	const struct FTypeLayoutDesc* Type;
	const FFieldLayoutDesc* Next;
    uint32 Offset;
    // Other fields are ignored
}
struct FTypeLayoutDesc{
    const TCHAR* Name;
	const FFieldLayoutDesc* Fields;
    uint32 Size; // 整个类型的大小，例如 sizeof(MyTestPS)
    uint32 SizeFromFields; // 绑定的纹理参数的总大小，考虑了对齐，padding 等等因素
    uint8 NumBases;  // 描述这个类型有多少个基类，TODO：我没看懂这个字段是怎么合理实现的，主要感觉哪个
    // InternalInitializeBases函数扫描不到真正的 base，导致的结果是通常这个NumBases为1，对应的 Fields描述了这个 type 自己，相比之下，通过 DECLARE_SHADER_TYPE_EXPLICIT_BASES 这样的宏显式地指出基类的实现就合理得多了
    
    // 下面这俩字段用于将 FTypeLayoutDesc 注册到一个全局的链式 hash 表中，见 `反射信息注册` 一节
    const FTypeLayoutDesc* HashNext;
    uint64 NameHash;
    
    // Other fields are ignored
}
```

可以看到两件事，一个是这两个类型中都有指向对方的指针，另一个是 `FFieldLayoutDesc` 是一个单链表结构

通常我们在 Shader 中若干个 `Layout_Field` 进行声明时，每个 `Layout_Field` 宏除了帮助我们生成相应类型的变量声明，还会生成一个静态的 FFieldLayoutDesc 结构体。同一个类若干 `Layout_Field`  生成的 FFieldLayoutDesc 会被串为一个单链表（这里实际的实现其实非常有技巧性，利用 \_\_counter\_\_ 宏以及模板的偏特化），这就是 FFieldLayoutDesc 结构体中 Next 字段的含义

而在 `IMPLEMENT_GLOBAL_SHADER` 这个宏中，会实现在 `DECLARE_GLOBAL_SHADER` 等宏中声明的两个重要的接口函数 `StaticGetTypeLayout` 和 `GetStaticType`。在 `StaticGetTypeLayout` 函数中声明和初始化静态的  FTypeLayoutDesc 的结构体，它的 Fields 字段就指向了 FFieldLayoutDesc 单链表的头部。而 FTypeLayoutDesc 的 Type 字段则指向了这个 field 的类型对应的 FTypeLayoutDesc 结构体。例如我们看 FShaderParameter 的声明和定义

```c++
/** A shader parameter's register binding. e.g. float1/2/3/4, can be an array, UAV */
class FShaderParameter
{
	DECLARE_EXPORTED_TYPE_LAYOUT(FShaderParameter, RENDERCORE_API, NonVirtual);

private:
	LAYOUT_FIELD(uint16, BufferIndex);
	LAYOUT_FIELD(uint16, BaseIndex);
	// 0 if the parameter wasn't bound
	LAYOUT_FIELD(uint16, NumBytes);
};

IMPLEMENT_TYPE_LAYOUT(FShaderParameter);
```

类似地，在 `DECLARE_EXPORTED_TYPE_LAYOUT` 宏中声明了 `StaticGetTypeLayout` 函数，这个函数的实现在 `IMPLEMENT_TYPE_LAYOUT` 中。因此，FShaderParameter 也有一个对应的 FTypeLayoutDesc，类型为 FShaderParameter 的字段对应的 FFieldLayoutDesc 结构体的 Type 字段就指向 FShaderParameter 的 FTypeLayoutDesc 结构体

最后还有一个问题是基本类型的 FTypeLayoutDesc 结构体从哪来的，ue 实际上是手动定义的，在 MemoryLayout.h 文件中

```c++
DECLARE_INTRINSIC_TYPE_LAYOUT(char);
DECLARE_INTRINSIC_TYPE_LAYOUT(short);
DECLARE_INTRINSIC_TYPE_LAYOUT(int);
DECLARE_INTRINSIC_TYPE_LAYOUT(int8);
DECLARE_INTRINSIC_TYPE_LAYOUT(long);

// TArray's FTypeLayoutDesc
DECLARE_TEMPLATE_INTRINSIC_TYPE_LAYOUT((template <typename T, typename AllocatorType>), (TArray<T, AllocatorType>));

// Other definitions...
```

高层次地讲，FTypeLayoutDesc 和 FFieldLayoutDesc 其实就是定义了反射的元类。UE 中使用了两种典型的反射实现方式，一种是基于编译的方式（使用自己实现的 UHT 预处理收集类型信息），一种是基于宏定义的方式（就是用这些 LAYOUT_FIELD，DECLARE_EXPORTED_TYPE_LAYOUT 宏来收集类型信息）。它们的区别仅在于收集类型信息的方式。可以看到，FTypeLayoutDesc 其实类似于 UClass，而 FFieldLayoutDesc 类似于 FProperty。DECLARE_GLOBAL_SHADER 等宏就类似于 UClass 标记，而 LAYOUT_FIELD 宏就类似于 UProperty 标记。这些通过宏生成的静态的 FTypeLayoutDesc 结构体就类似于 UHT 中生成的 xxx.generated.h 和 xxx.gen.cpp 文件，包含我们需要的类型信息

我认为 ue 在这里不使用 UHT 那一套，而是利用宏重新实现一套反射系统主要原因在于 UHT 那一套功能太多了，因为这里我们只需要一个更轻量级的反射系统，例如我们只需要标记字段，而不需要 UFuntion 等等

### 反射信息注册

有了静态的类型信息，我们还需要将

* GShaderTypeRegistrationInstances 是一个全局的数组，它的元素类型为 FShaderTypeRegistration，这个类型包含一个返回静态的 shader 类型信息的函数
* FShaderType 中调用 FTypeLayoutDesc::Register 函数，将 FTypeLayoutDesc 根据名称 hash，注册到了一个全局的链式 hash 表 GTypeLayoutHashBuckets 中（[Linux内核hash链表的理解与使用](https://blog.csdn.net/to_be_better_wen/article/details/127790516)）
* 在 FShaderType 的构造函数中，FShaderType 自己会加入到一个全局的 hash 链表 GShaderTypeList 中，还会加入到一个全局静态的 map 中，key 为 name，value 为 FShaderType 指针。还会加入到一个全局静态的，根据 shader 的类型分成的 array 中
* 对于一般的 parameterType，IMPLEMENT_TYPE_LAYOUT 宏会定义一个静态的结构体 FDelayedAutoRegisterHelper，它将这个 parameterType 对应的 FTypeLayoutDesc::Register 函数加入到一个全局静态的多播中（DECLARE_MULTICAST_DELEGATE 宏），ue 会在适当的时机调用这个多播的 broadcast 函数，从而将这个 parameterType 的 FTypeLayoutDesc 注册到全局的链式 hash 表中
* FShaderParametersMetadata 是干嘛的？
* FShaderPipeline 是什么？
* TODO：每个 shader parameter 的 BufferIndex，BaseIndex 分别指啥（而 RHI shader resource 好像只有一个 Index）
  * 参见 `struct FRHIBatchedShaderParameters` 中包含的 parameter 信息
* **TODO：反射信息注册后是怎么调用的**

### 反射信息的使用

注意 FShader 的构造函数 `FShader(const CompiledShaderInitializerType& Initializer)`，我感觉这个构造函数是 shaderUsf 编译完成后再调用，这个参数包含了编译  shaderUsf 时收集的参数信息，构造函数中利用这个，调用 `BuildParameterMapInfo` 函数，初始化了 FShader 的 ParameterMapInfo 字段，该字段就包含了该 shader 对应的 shaderUsf 中用到的所有参数。参数传递要做的事情就是将 shader 中声明的参数与 ParameterMapInfo 中包含的 shaderUsf 参数对应起来

例如最简单的 FshaderParameter，它能够绑定简单的标量数据（float，float3 等等），例如在 OneColorShader.h 中

```c++
	TOneColorVS(const ShaderMetaType::CompiledShaderInitializerType& Initializer)
		: FGlobalShader(Initializer)
	{
		DepthParameter.Bind(Initializer.ParameterMap, TEXT("InputDepth"), SPF_Mandatory);
	}
    LAYOUT_FIELD(FShaderParameter, DepthParameter);
```

这里 Bind 函数中第二个参数就是要绑定的 shaderUsf 变量的名称。这里绑定的作用就是让 FShaderParameter 知道自己对应变量的大小，位置信息（BufferIndex，BaseIndex）。然后 ue 提供了一个辅助函数

```c++
template<class ParameterType>
void SetShaderValue(
	FRHIBatchedShaderParameters& BatchedParameters
	, const FShaderParameter& Parameter
	, const ParameterType& Value
	, uint32 ElementIndex = 0
)
```

调用这个辅助函数，就会把 FShaderParameter 中保存的位置信息，以及 Value 表示的实际参数值，一起存放到 BatchedParameters 中，然后可以调用 `RHICmdList.SetBatchedShaderParameters` 来产生一个实际传递参数值给 gpu 的 RHICmd（这个 BatchedParameter 的作用仅仅是减少 RHICmd 的数目）

### Shader Parameters Struct

下面是声明 shader parameter 的一些例子，它会以宏的第一个参数为名称，定义一个新的 class，每个 SHADER_PARAMTER 宏为这个 class 贡献一个字段，SHADER_PARAMETER_STRUCT_INCLUDE 宏在 class 中定义一个嵌套的 class 成员，SHADER_PARAMETER_STRUCT_REF 的含义我还不太清除，它的使用涉及到 UNIFORM BUFFER

```c++
BEGIN_SHADER_PARAMETER_STRUCT(FScreenPassTextureViewportParameters, )
	SHADER_PARAMETER(FVector2f, Extent)
	SHADER_PARAMETER(FIntPoint, ViewportMin)
END_SHADER_PARAMETER_STRUCT()
    
BEGIN_SHADER_PARAMETER_STRUCT(FTESTPAAR, )
    SHADER_PARAMETER_RDG_TEXTURE(Texture2D, Extent)
    SHADER_PARAMETER_STRUCT_INCLUDE(FScreenPassTextureViewportParameters, View)
    RENDER_TARGET_BINDING_SLOTS()
END_SHADER_PARAMETER_STRUCT()
```

前面谈到了在 shader 中使用 LAYOUT_FIELD 来绑定 shader 参数。这里是另外一种写法（[GlobalShader参数的三种写法](https://www.cnblogs.com/wakuwaku/articles/16706479.html)），如果参数类型声明在外面，就在 shader 内部加一句 `using FParameter = MyShaderType`，因为默认 FParameter 作为 parameter 类型

```c++
class FRasterizeToRectsVS : public FGlobalShader
{
	DECLARE_EXPORTED_SHADER_TYPE(FRasterizeToRectsVS, Global, RENDERCORE_API);
	SHADER_USE_PARAMETER_STRUCT(FRasterizeToRectsVS, FGlobalShader);

	BEGIN_SHADER_PARAMETER_STRUCT(FParameters, )
		SHADER_PARAMETER_RDG_BUFFER_SRV(Buffer<uint4>, RectCoordBuffer)
		SHADER_PARAMETER_RDG_BUFFER_SRV(Buffer<float4>, RectUVBuffer)
		SHADER_PARAMETER(FVector2f, InvViewSize)
		SHADER_PARAMETER(FVector2f, InvTextureSize)
		SHADER_PARAMETER(float, DownsampleFactor)
		SHADER_PARAMETER(uint32, NumRects)
	END_SHADER_PARAMETER_STRUCT()

	class FRectUV : SHADER_PERMUTATION_BOOL("RECT_UV");
	using FPermutationDomain = TShaderPermutationDomain<FRectUV>;

	static bool ShouldCompilePermutation(const FGlobalShaderPermutationParameters& Parameters);
};

IMPLEMENT_GLOBAL_SHADER(FRasterizeToRectsVS, shader.usf", "Main", SF_Vertex);
```

新定义出的 shader parameter 类中内嵌了一个 FTypeInfo 子类，它包含一些与这个 shader parameter 相关的常量，以及最重要的 `FTypeInfo::GetStructMetadata`，这个静态函数会返回一个 FShaderParametersMetadata 类，这个类包含这个 shader paramter 类的元信息，它的 Members 字段是元素为 FMember 的结构体，每个 FMember 类描述了用 SHADER_PARAMETER 声明的结构体字段的元信息

```c++
struct FShaderParametersMetadata::FMember{
    // TODO：大部分都不清楚是干嘛的
    const TCHAR* Name;
	const TCHAR* ShaderType;
	int32 FileLine;
	uint32 Offset;
	EUniformBufferBaseType BaseType;
	EShaderPrecisionModifier::Type Precision;
	uint32 NumRows;
	uint32 NumColumns;
	uint32 NumElements;
	const FShaderParametersMetadata* Struct;
}
```

而 `SHADER_USE_PARAMETER_STRUCT` 的展开其实就是下面的东西，它帮助我们声明了构造函数，并额外定义了一个获取 shader parameter 类元类型的静态函数（可以看到，这里写死了类型别名为 FParameters），而在之前使用 LAYOUT_FIELD 那一套时，这两个构造函数是需要手写的。BindForLegacyShaderParameters 内部会利用 shader parameter metadata 这个反射信息，将位置信息绑定在 FShader 的 Bindings 字段（而之前这些信息是存在一个个单独的我们声明的 FShaderParameter 中）

```c++
ShaderClassName(
            const ShaderMetaType ::CompiledShaderInitializerType &Initializer)
            : FGlobalShader(Initializer) {
            BindForLegacyShaderParameters<FParameters>(
                this, Initializer.PermutationId, Initializer.ParameterMap,
                true);
        }
ShaderClassName() {}
        static inline const FShaderParametersMetadata *
        GetRootParametersMetadata() {
            return FParameters ::FTypeInfo ::GetStructMetadata();
        };
```

在实际传递参数值时，ue 提供了 SetShaderParameters 函数（见 ClearQuad.cpp 中的例子）。我们只需要声明相应的 FParameter 结构体，填充相应的参数字段，然后调用 SetShaderParameters 函数，即可完成结构体中每个 shader 参数的值的绑定。原因在于位置信息已经绑定在了 FShader 的 Bindings 字段中，知道每个元素（对应一个 FMember）在结构体中的偏移，SetShaderParameters 函数内部就是利用这个偏移来获取每个 shader 参数的值（**这个偏移原始来于 shader parameter metadata 中保存的偏移，但是这个偏移没有考虑嵌套结构体等情况，在 Bingdings 字段中的偏移则是一个总体的偏移，这部转换在 FShaderParameterStructBindingContext::Bind 中**）

**另外，由于 BindForLegacyShaderParameters 函数内部默认结构体字段名称就是我们要绑定的 shaderUsf 中的变量，因此这要求我们声明结构体字段名称时与 shaderUsf 中的变量名称保持一致。总的来讲，ParameterMapInfo 以及 UniformBufferParameters 它们保存的参数信息是从 shaderUsf 一侧看到的变量信息。而 Bindings 字段则提供了 c++ 侧参数到 shaderUsf 的映射关系**

值得注意的是，在使用 shader parameter 类时，仍然需要 DECLARE_EXPORTED_SHADER_TYPE 和 IMPLEMENT_GLOBAL_SHADER 这两个宏，意味着这个 shader 类仍然有它的 FTypeLayoutDesc 结构体（当然也会注册到全局的一些结构中），只是 Fields 字段现在为空指针了，但此时构建 ShaderMetaType 时，InRootParametersMetadata 参数不再为空，传入的是 shader parameter 类对应的 FShaderParametersMetadata 结构体，即 FParameter::TypeInfo::GetStructMetadata 函数的返回值

### Uniform Buffer

Uniform Buffer 与 shader parameter struct 一样，也会有一个对应的 FShaderParametersMetadata 保存它的元信息，不过这个原信息会被注册到一些全局结构中（注册发生在 FShaderParametersMetadata 的构造函数调用时，在 FShaderParametersMetadataRegistration::CommitAll 函数调用时触发）。这些全局结构包括

* 全局的哈希链表 GUniformStructList，每个 uniform buffer 类型的 FShaderParametersMetadata 会被串到上面
* 全局的 map，通过名称索引到这个 metadata

在创建 RHIUniformBuffer 时会用到 layout，这个结构体在 FShaderParametersMetadata::InitializeLayout 中初始化。layout 本质上描述的是uniform buffer 在 cpp 侧的内存布局（不包含 bufferIndex 之类的东西）。**我直观觉得这个事情是有必要的，因为 uniform buffer 的定义本来在 shaderUsf 侧是没有的，需要 c++ 侧来定义 layout，但我还不明白为啥这个 uniform buffer 里面没有 looseData 相关的记录**

我觉得 shader parameter struct 不需要这个 layout，因为它的位置信息都储存在 FShader 的 Bindings 字段中。但 Uniform Buffer 区别于 shader parameter struct 的点在于它是一个全局的变量，它的 layout 不可能和一个单独的 Shader 绑定。我想这就是 shader parameter metadata 中有一个 layout 字段的原因

然后说一下 Uniform Buffer 的赋值，创建 RHIUniformBuffer 的函数最后都会调用 RHICreateUniformBuffer 函数，这个函数接收一个 Uniform Buffer 结构体以及它的 layout，返回一个 RHIUniformBuffer 指针。因此我们只需要声明一个 Uniform Buffer 结构体，然后赋值，调用 RHICreateUniformBuffer 就行了。而其它使用 SHADER_PARAMETER_STRUCT_REF 宏引用了这个 Uniform Buffer 结构体的 shader parameter struct，就用这个 RHIUniformBuffer 指针填充结构体的对应字段就好了

### Summary

现在我们可以来看下声明 shader parameter member 相关的宏以及这些宏声明出来的类型和 EUniformBufferBaseType 枚举，一些注意：

* **UBMT_NESTED_STRUCT 和 UBMT_INCLUDED_STRUCT 的唯一区别在于 shaderUsf 侧的变量名称，查看 FShaderParameterStructBindingContext::Bind 函数是怎么 bind 这些字段的和定义这些宏位置的注释就知道了**

```c++
#define SHADER_PARAMETER_TEXTURE(ShaderType,MemberName) 
--> UBMT_TEXTURE, FRHITexture *
#define SHADER_PARAMETER_SRV(ShaderType,MemberName)
--> UBMT_SRV, FRHIShaderResourceView *
#define SHADER_PARAMETER_UAV(ShaderType,MemberName)
--> UBMT_UAV, FRHIUnorderedAccessView *
#define SHADER_PARAMETER_SAMPLER(ShaderType,MemberName)
--> UBMT_SAMPLER, FRHISamplerState *
#define SHADER_PARAMETER_STRUCT(StructType,MemberName)
--> UBMT_NESTED_STRUCT, StructType
#define SHADER_PARAMETER_STRUCT_INCLUDE(StructType,MemberName)
--> UBMT_INCLUDED_STRUCT, StructType
#define SHADER_PARAMETER_STRUCT_REF(StructType,MemberName)
--> UBMT_REFERENCED_STRUCT, TUniformBufferBinding<StructType>
# 这个 TUniformBufferBinding 除了包含 FRHIUniformBuffer* 外，还包含一个 BindFlags

# 下面是引入 RDG 后新加入的宏

#define SHADER_PARAMETER_RDG_TEXTURE(ShaderType,MemberName)
--> UBMT_RDG_TEXTURE, FRDGTexture *
#define SHADER_PARAMETER_RDG_TEXTURE_SRV(ShaderType,MemberName)
--> UBMT_RDG_TEXTURE_SRV, FRDGTextureSRV *
#define SHADER_PARAMETER_RDG_TEXTURE_UAV(ShaderType,MemberName)
--> UBMT_RDG_TEXTURE_UAV, FRDGTextureUAV *
#define SHADER_PARAMETER_RDG_BUFFER(ShaderType,MemberName)
被 RDG_BUFFER_ACCESS 宏替代
#define SHADER_PARAMETER_RDG_BUFFER_SRV(ShaderType,MemberName)
--> UBMT_RDG_BUFFER_SRV, FRDGBufferSRV *
#define SHADER_PARAMETER_RDG_BUFFER_UAV(ShaderType,MemberName)
--> UBMT_RDG_BUFFER_UAV, FRDGBufferUAV *
#define SHADER_PARAMETER_RDG_UNIFORM_BUFFER(StructType, MemberName)
--> UBMT_RDG_UNIFORM_BUFFER, TRDGUniformBufferBinding<StructType>
#define RDG_BUFFER_ACCESS(MemberName, Access)
--> UBMT_RDG_BUFFER_ACCESS, TRDGBufferAccess<Access>
#define RDG_TEXTURE_ACCESS(MemberName, Access)
--> UBMT_RDG_TEXTURE_ACCESS, TRDGTextureAccess<Access>
```

TODO：在 shader parameter member 中 RDG_BUFFER_ACCESS 和 RDG_TEXTURE_ACCESS 这一类宏是干嘛的

TODO：深入 RHI 下面，例如以 OpenGL 为例，看看 BufferIndex，BaseIndex 等等参数的含义

TODO：ShaderUsf 一侧是如何辨识 Uniform Buffer 的？（因为在 FShader 的构造函数中传入的 CompiledShaderInitializerType 参数已经包含 Uniform Buffer 的变量名和 BufferIndex 了）难道是未声明就使用的变量就认为是 Uniform Buffer 吗？**得看看 shader compiling 相关的代码才知道**

**再提一句 FShader 的 ParameterMapInfo。这个字段会在 Mesh Draw Pipeline 中被使用。在 BuildMeshDrawCommand 中会回调 GetShaderBindings 这个 shader 中定义好的函数，给 shader 绑定参数的时机**

**不过从根本上讲，所有的参数最后都是传递给 FRHIBatchedShaderParameters 结构体，所以我们只需要关注这个结构体中最终保存了参数的哪些信息就好了。参数可以分为两类，一类是离散的数据，每个包含了 BufferIndex，BaseIndex 和实际的数据值。另一类是 RHIResource，它包含了 RHIResource 指针（具体的基类可能是 FRHIUniformBuffer，FRHIShaderResourceView 等等）和一个 Index**

**TODO：目前缺少的重要拼图**

* **Render Dependency Graph**
* **Shader compiling**
* **Mesh Draw Pipeline**
* **Compute Shader**
* game线程 tick 和 render 线程同步，SceneCaptureComponent 是如何工作的
* **cook 逻辑**
* shader 中各种参数，例如 View，View 中的各种矩阵可参考 void FViewMatrices::Init(const FMinimalInitializer& Initializer);

命令行 -graphicsadapter= 可以指定 ue 使用哪张卡，或者使用 r.GraphicsAdapter 变量

uplugin 的 Installed 字段会影响 cook？chagpt 的意思是 insatlled uplugin 是属于引擎的一部分，总是会激活的。但我现在如果启动不带 editor 的版本仍然会报错 plugin 无法加载，不知道为啥

