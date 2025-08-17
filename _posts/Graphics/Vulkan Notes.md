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
