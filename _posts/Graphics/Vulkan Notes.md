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


