### Overview
[Architecture of the Vulkan Loader Interfaces](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderInterfaceArchitecture.md) 和 [Application Interface to Loader](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderApplicationInterface.md) 包含关于 vulkan 总体设计的一些文档，一些关键的地方有：

除了少数的 global commands，其余的 commands 被称为 dispatchable commads，因为它们接收 VkInstance, VkPhysicalDevice, VkDevice, VkQueue, 或者 VkCommandBuffer 作为第一个参数，然后通过内部的 dispatch table，将其转发给对应的 driver 函数（因为 vulkan loader 支持多个 driver 同时存在，应用也可以同时控制多个 driver）

大部分应用都只会和特定的一个 device 交互，因此为了保证性能，vulkan 的最佳实践是
* 一开始加载 vulkan 的动态库，使用 platform-specific 的方式获取 `vkGetInstanceProcAddr` 指针，然后用该函数指针获取其它 VkInstance 级别的函数地址
* 然后用 `vkGetDeviceProcAddr` 获取其它级别的的函数地址（即仅与一个 logic device 交互的 dispatchable commads）。通过这种方式调用 vulkan 函数就能够跳过 dispatch table，节省一些开销

但这种做法的缺点是只能和一个特定的 device 交互。当然一个简单的解决办法是自己维护一个类似于 dispatch table 的东西，调用多次 `vkGetDeviceProcAddr`，获取针对每个 device 的 vulkan 函数。[volk](https://github.com/zeux/volk) 就是一个用来帮助加载 vulkan 动态库以及获取 vulkan 函数指针的库

除了 [volk](https://github.com/zeux/volk) 之外，[imgui](https://github.com/ocornut/imgui) 是一个轻量级的 GUI 库，可以用来创建 GUI 界面，并使用 vulkan 作为后端的渲染 API。[VulkanMemoryAllocator](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator) 是一个管理 GPU 内存分配的，vulkan 本来的 API 是创建 buffer，image 与分配设备内存分离，vma 就把这两者的 API 封装到一起了，并且自动地帮用户选择合适的 memory type（貌似它还有个 GPU 内存管理器，就会申请一大块 GPU 内存，然后再自己给 buffer 和 image 进行分配）

关于在项目中集成 [volk](https://github.com/zeux/volk)，[imgui](https://github.com/ocornut/imgui)，以及 [VulkanMemoryAllocator](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator) 的注意事项，参考 [Vulkan集成Volk踩坑记录](https://zhuanlan.zhihu.com/p/634912614) 以及 [nvpro_core2](https://github.com/nvpro-samples/nvpro_core2) 中的实现。[Vulkan版Dear ImGui的接入和使用教程](https://zhuanlan.zhihu.com/p/694585131) 讨论了如何使用 imgui 的 vulkan 后端

TODO：解释画面怎么渲染到一个指定的 viewport，和其它 UI 控件分离开
### Extension
vulkan 的 extension 有两种方式提供拓展接口，最简单的是直接提供新的函数，另外，vulkan 的结构体基本都具有下面的形式
```c++
typedef struct VkXXXCreateInfo {
    VkStructureType    sType;
    const void*        pNext;
	// other fields
} VkXXXCreateInfo;
```
其中 sType 指定结构体的类型，而 pNext 则提供额外的信息。通常这个 pNext 又指向一个新的结构体，但对于同一个函数，不同的拓展可能又有不一样的结构体类型要求，但 vulkan 可以根据 pNext 指向的这个结构体的 sType 字段搞清楚用户到底是希望使用哪个拓展。见 [Vulkan: What is the point of sType in vkCreateInfo structs?](https://stackoverflow.com/questions/36347236/vulkan-what-is-the-point-of-stype-in-vkcreateinfo-structs)
### 基本的 Rendering Flow

### Chapter 1
创建 vkInstance -> 枚举 Physical Device

每个 Physical Device 有自己支持的 feature，例如 geometry shader，multidraw indirect 等
每个 Physical Device 有自己的 memory，每个 memory 有自己的 flag，例如 coherent，local 等，memory 由 heaps 组成，heaps 是什么？
每个 Physical Device 有自己的 queue family，每个 queue family 有自己能执行的 command 类型，queue family 里可能有多个 queue，这些 queue 里的 cmd 可以并发执行，为什么是 queue family 内部的可以并发执行，而不是 queue family 之间可以并发？ 

然后从 Physical Device 中 Logic Device，创建时需要指明需要哪些 queue family，每个 family 中的 queue number，需要用到的 feature，那不同的 instance（甚至在不同的线程，进程中）用到同一个 queue 会如何？
### Chapter 2
在创建 buffer 时，storage buffer 和 uniform buffer 有什么区别：感觉就是前者是可读写的，后者是只读的

TODO：解释 vulkan 里的各种 memory type
TODO：跳过了 sparse image / buffer 的部分
TODO：Access flags，image tiling, image layout，Image Aspect Flags 这几个概念的关系和区别是什么
TODO：第六章的 texel buffer 一节说 texel buffer 应该认为是 1D texture？没有 2D texture 吗
### Vulkan Memory
通过 `vkGetPhysicalDeviceMemoryProperties` API 获取 memory type 和 memory heap

`vkAllocateMemory` 分配 device memory 时需要指定使用哪种 memory type

`vkGetBufferMemoryRequirements` 以及 `vkGetImageMemoryRequirements` 获取指定的 buffer 和 image 需要哪种 memory type

为什么区分 memory type 和 memory heap，参考
* https://stackoverflow.com/questions/51624650/vulkan-memoryheaps-and-their-memorytypes
* https://stackoverflow.com/questions/48242445/why-does-vkgetphysicaldevicememoryproperties-return-multiple-identical-memory-ty#48243730
* https://stackoverflow.com/questions/36436493/could-someone-help-me-understand-vkphysicaldevicememoryproperties/36437023#36437023

`VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT`
`VK_MEMORY_PROPERTY_HOST_COHERENT_BIT`
### Descriptor Set and Its Layout
vulkan 中 resource 主要是 buffer 和 image，我们需要解释 C 语言侧如何描述这些 resource，shader 侧如何描述这些 resource，然后两者如何关联起来
#### Uniform Buffer and Sampled Images
glsl 侧对 resource 的描述可以参考 [GL_KHR_vulkan_glsl.txt](https://github.com/KhronosGroup/GLSL/blob/main/extensions/khr/GL_KHR_vulkan_glsl.txt)，大部分和 OpenGL 的 glsl 是一致的。每个 resource 通过 set，bing 和 element 这三个值标定。例如
```glsl
layout (set=M, binding=N) uniform sampler2D variableNameArray[I];
```
element 表示它在数组中的下标。注意它是一个类型为 sampler2D 的数组，而不是 sampler2D array（两者在 C 侧的 binding 会有些区别）。另外 vulkan 中可以分开声明 sampler 和 texture
```glsl
layout(set = 1, binding = 0) uniform sampler s;
layout(set = 1, binding = 1) uniform texture2D t;
```
它们在 C 侧绑定时对应的类型分别为 `VK_DESCRIPTOR_TYPE_SAMPLER` 和 `VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE`。而将 sampler2D 这种合并 sampler 和 texture 的声明方式对应的类型为 `VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER`

Uniform Buffers 是类似的，例如
```glsl
layout (set=m, binding=n) uniform myUniformBuffer
{
    vec4 myElement[32];
};
```
它在 C 侧绑定时对应的类型为 `VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER`

在 C 侧创建 descriptor set layout 时每个 `VkDescriptorSetLayoutBinding` 结构体描述了 layout 的一个 binding
```c++
typedef struct VkDescriptorSetLayoutBinding {
	uint32_t binding;
	VkDescriptorType descriptorType;
	uint32_t descriptorCount;
	VkShaderStageFlags stageFlags;
	const VkSampler* pImmutableSamplers;
} VkDescriptorSetLayoutBinding;
```
其中 `binding` 字段指定 binding 的编号，`descriptorCount` 则描述了数组元素的个数。`VkDescriptorType` 指明了 resource 的类型（**注意，并不包括维度，大小等信息**），如果使用的 sampler 是固定的，可以在 `pImmutableSamplers` 中直接指定 sampler，这样后续不需要用 cmd 来绑定 sampler 了
#### Other Descriptor Types
**TODO：参考 [GL_KHR_vulkan_glsl.txt](https://github.com/KhronosGroup/GLSL/blob/main/extensions/khr/GL_KHR_vulkan_glsl.txt)，解释 Storage Buffers， Storage Texel Buffers，Uniform Texel Buffers，Storage Images**
#### Descriptor Set
TODO：解释 descriptor set 以及如何将实际的 buffer 和 image 绑定到 descriptor set 上
#### Pineline Layout and Push Constants
在创建好了各个 descriptor set layout 后，我们将其组合成 pipeline layout，这些 descriptor set layout 在 pipeline set layout 中的顺序就是它们的 set 标号

在创建 pipeline layout 时，可以指定多段 push constant range，每段 push constant range 有自己的大小和偏移以及在哪些 shader stage 中被使用。在 shader 侧，我们声明为
```glsl
layout(push_constant) uniform BlockName {
    int member1;
    float member2;
    ...
} InstanceName; // optional instance name
```
可以通过 `layout(offset)` 指定偏移，使用多段 push constant range 的例子见 [Using different push-constants in different shader stages](https://stackoverflow.com/questions/37056159/using-different-push-constants-in-different-shader-stages)

后续使用 `vkCmdPushConstants` 实际设置管线的 push constants 的值

### 管线概念关系
* descriptor set layout，pipeline layout
* descriptor set pool，descriptor set，descriptor
	* sampler
	* image
	* uniform block / storage block / texel buffer
	* push constant
* render pass，subpass

**整个 `vkCreateGraphicsPipelines` 函数接收的输入**
第一部分是 shader 代码 --> 由 `VkPipelineShaderStageCreateInfo` 描述
第二部分是各个 stage 的参数
* input vertex format --> 由 `VkPipelineVertexInputStateCreateInfo` 描述
	* 其中 `VkVertexInputBindingDescription` 描述了每个 input vertex buffer，每个 buffer 中结构体数据的步长
	* `VkVertexInputAttributeDescription` 描述了每个 input vertex attribute，包括它的 location（对应 shader 中的 location），它所在的 vertex buffer，它在结构体数据中的 offset，它的类型（**我感觉这里的 binding 字段只是用来索引后续的 vertex buffer 的，和 shader 代码没有关系，也不意味着不同 binding 的 attribute 可以使用相同的 location**）
* input assembly：由 `VkPipelineInputAssemblyStateCreateInfo` 描述，它表示渲染的 primitive 是什么，输入的 vertex 如何组装成 primitive
* Tessellation State：TODO
* Viewport State：描述 viewport 的大小，用于 viewport transform，TODO：解释 scissor test 和 multiple viewport
* Rasterization State：描述背面剔除模式，深度变换方式（例如投影矩阵的 inverse z），线宽等等
* Multisample State：TODO
* Depth and Stencil State：描述做深度测试和模板测速时的各种参数
* Color Blend State：描述如何做 blending
第三部分是 dynamic state：描述各个 stage 的参数的哪些部分允许后续动态修改
第四部分是 pipeline layout：TODO，解释
第五部分是 render pass 和 subpass，TODO，解释
### Synchronization
TODO：解释 fence 和 event 等（但感觉它们的功能可以直接用 timeline semaphore 替代了
#### Binary and Timeline Semaphores
binary semaphore 只有 reset 和 signal 两种状态。刚创建出来是 reset 状态，然后一些函数会产生 semaphore signal operation，将其设置为 signal 状态，通过 wait semaphore 可以将 signal 状态的 semaphore 又设置为 reset 状态（然后又可以复用该 semaphore），一个相关的讨论见 [Can I check if a semaphore has signaled already?](https://community.khronos.org/t/can-i-check-if-a-semaphore-has-signaled-already/108055)

但 binary semaphore 有许多局限，例如在 [vkQueueSubmit](https://registry.khronos.org/vulkan/specs/latest/man/html/vkQueueSubmit.html) 中要求
> All elements of the `pWaitSemaphores` member of all elements of `pSubmits` created with a [VkSemaphoreType](https://registry.khronos.org/vulkan/specs/latest/man/html/VkSemaphoreType.html) of `VK_SEMAPHORE_TYPE_BINARY` **must** reference a semaphore signal operation that has been submitted for execution and any [semaphore signal operations](https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html#synchronization-semaphores-signaling) on which it depends **must** have also been submitted for execution

即需要先 submit signal command 再 submit wait command，也不是很理解为啥会有这样的顺序要求

另一方面，vulkan 1.2 引入了 Timeline Semaphores 则是用 64 bits 数来表示状态，要求其状态单调递增。wait 时指定一个数值，当 semaphore 的数值大于等于 wait 的值时 wait 结束，并且允许 wait before signal 操作

**但同时 [Vulkan Timeline Semaphores](https://www.khronos.org/blog/vulkan-timeline-semaphores) 中谈到 WSI API 尚不支持 timeline semaphore**
### Memory Barrier
**TODO**

TODO：解释 synchronization scope，通常的 StageMask（例如在 VkSemaphoreSubmitInfo 中）我感觉是指定在哪个 pipeline stage 进行同步，但是如果 command buffer 里很多会经过该 pipeline stage 的 cmd，那这个 StageMask 应该对应哪个 cmd 呢。并且在 solid color 这个例子中，某个 command buffer 中的 barrier 感觉更需要与在它之前的 command buffer 中的 cmd 同步？
### Vulkan 实践
在 [vk_mini_samples](https://github.com/nvpro-samples/vk_mini_samples) 中看到的一些使用方法，下面简称 samples
#### Swap Chain 的使用和同步
使用 swap chain 创建了 k 个用于 presentation 的 image。并且
* 为每个 presentation image 创建了单独的 command pool，command buffer
* 创建了 2k 个 binary semaphore
* 创建了一个 timeline semaphore

它的目标是可以同时有 k 帧的 GPU 指令 in-flight。具体的同步方法是
* 使用 timeline semaphore 同步，保证渲染当前的第 n 帧时，第 n - k 帧已经渲染完成了（当第 n - k 帧渲染完成了我们才能放心地复用第 n - k 帧的 binary semaphore）
* 当前帧还要使用两个 binary semaphore 做同步，一个是用于 `vkAcquireNextImageKHR` API 和 submit command buffer 之间的同步，保证 draw call 执行时从 swap chain 中获取到的 image 确实可用于渲染了。另一个是用于 submit command buffer 与 `vkQueuePresentKHR` 间的同步，保证渲染到屏幕上前 draw call 已经执行完毕了

因为 WSI API 尚不支持 timeline semaphore，这导致这里使用了额外的一个 binary semaphore 来做 submit command buffer 与 `vkQueuePresentKHR` 之间的同步（否则直接用 timeline semaphore 就行了）