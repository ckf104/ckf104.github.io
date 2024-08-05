## Cuda Related

cuda runtime 对应 libcudart.so，所有的函数都以 cuda 开头，例如 cudaMalloc

cuda driver api 是更底层的接口，对应 libcuda.so，所有函数都以 cu 开头，例如 cuCtxCreate

### Unified Virtual Address Space

这个感觉比较好理解，就是 gpu 地址和 cpu 地址统一到一起的，通过指针指向的地址就能知道这个是 gpu 还是 cpu 上的内存地址。此时该做的 copy 还是需要做，只是 cudaMemcpy 的 flags 可以设置为 cudaMemcpyDefault

与之伴随的是 **Zero Copy** 的概念，它的想法既然 gpu 和 cpu 内存地址统一了，那么就可以在 gpu kernel 中直接使用 cpu 地址指针，通过 PCIE 总线访问（根据网上对核显的说法，核显是直接使用 CPU 的内存的，那么使用 cpu 地址指针更加自然，都没必要走 PCIE 总线了）。zero copy 的一个问题是 gpu 这边不会 cache 数据，因此如果会多次访问同一地址的数据，效率不如先用 cudaMemcpy 将数据 copy 到显存中。[CUDA Zero Copy Mapped Memory](https://leimao.github.io/blog/CUDA-Zero-Copy-Mapped-Memory/) 中写了一个简单的 benchmark

传统的使用 zero copy 的方法是，先调用 cudaHostAlloc 在 host 上分配内存，flags 参数设置为 cudaHostAllocMapped 或者 cudaHostAllocPortable，然后调用 cudaHostGetDevicePointer 获取 gpu kernel 中使用的指针（通常情况下，这个指针的值和 cudaHostAlloc 返回的指针相同），不过 [cuda v12.4](https://docs.nvidia.com/cuda/cuda-runtime-api/group__CUDART__UNIFIED.html#group__CUDART__UNIFIED) 的文档说直接用 cudaHostAlloc 返回的指针就行了，也没必要加上 cudaHostAllocMapped 等 flags（在 [cuda c programing guide 的 3.2.10 节 Unified Virtual Address Space](https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html?highlight=ipc#unified-virtual-address-space) 中也有类似的论述）

**这么说来，我想 Zero Copy 本身不依赖于 Unified Virtual Address Space，而且 Zero Copy 应该提出得更早，这样才会有 cudaHostGetDevicePointer 这样的 API 被提出，然后在 Unified Virtual Address Space 出现后，就没必要使用 cudaHostGetDevicePointer 了**

**值得注意的是，zero copy 的本质是将 cpu 内存映射到 gpu 上，我目前没有看到将 gpu 显存映射到 cpu 上的说法**

### Pageable Memory，Pinned Memory，Portable Memory

Pageable Memory 就是最普通的 malloc 分配的内存，指 OS 可以将它换到 disk 中，或者修改页表，移动它在物理内存中的位置。而 Pinned Memory 指物理地址不可变的内存（OS 不可将它换出磁盘，不可移动它在物理内存中的位置）。用 cudaHostAlloc 分配的内存就是 Pinned Memory。Portable Memory 在 [cuda c programming guide](https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html?highlight=ipc#portable-memory) 中的论述如下

> A block of page-locked memory can be used in conjunction with any device in the system (see [Multi-Device System](https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html#multi-device-system) for more details on multi-device systems), but by default, the benefits of using page-locked memory described above are only available in conjunction with the device that was current when the block was allocated (and with all devices sharing the same unified address space, if any, as described in [Unified Virtual Address Space](https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html#unified-virtual-address-space)). To make these advantages available to all devices, the block needs to be allocated by passing the flag `cudaHostAllocPortable` to `cudaHostAlloc()` or page-locked by passing the flag `cudaHostRegisterPortable` to `cudaHostRegister()`.

我认为直观上的理解就是可以在多个 gpu device 中使用的 Pinned Memory。如果所有 gpu device 共享一个 address space，那么 cudaHostAlloc 分配的内存就是 Portable Memory

### Unified Memory

基本的想法就是对上屏蔽掉 device memory，host memory 的区别，程序员不需要区分 host 指针和 device 指针，具体的 copy 操作由 cuda 内部执行

device 对 unified memory 的支持程度分为两种。最强的支持是 Full CUDA Unified Memory，任意堆上，栈上的指针都可以直接传给 kernel。次一点的是 CUDA Managed Memory，对于 cudaMallocManaged 这套 API 分配的内存，可以不区分 host memory 和 device memory，host 端和 device 端都可以直接读写

### Task Schedule and Concurrent

在 Cuda by Example 一书的第 10 章介绍了如何使用 non-default stream 来 overlap data transfer and kernel execution。对于简单的 copy, execute, copy 模式，书中考虑了两种写法

```c++
// version 1
for (int i = 0; i < nStreams; ++i) {
  int offset = i * streamSize;
  cudaMemcpyAsync(&d_a[offset], &a[offset], streamBytes, cudaMemcpyHostToDevice, stream[i]);
  kernel<<<streamSize/blockSize, blockSize, 0, stream[i]>>>(d_a, offset);
  cudaMemcpyAsync(&a[offset], &d_a[offset], streamBytes, cudaMemcpyDeviceToHost, stream[i]);
}

// version 2
for (int i = 0; i < nStreams; ++i) {
  int offset = i * streamSize;
  cudaMemcpyAsync(&d_a[offset], &a[offset], 
                  streamBytes, cudaMemcpyHostToDevice, cudaMemcpyHostToDevice, stream[i]);
}

for (int i = 0; i < nStreams; ++i) {
  int offset = i * streamSize;
  kernel<<<streamSize/blockSize, blockSize, 0, stream[i]>>>(d_a, offset);
}

for (int i = 0; i < nStreams; ++i) {
  int offset = i * streamSize;
  cudaMemcpyAsync(&a[offset], &d_a[offset], 
                  streamBytes, cudaMemcpyDeviceToHost, cudaMemcpyDeviceToHost, stream[i]);
}
```

Cuda by Example 一书中测试认为，第二种写法会取得更高的性能。书中讨论的原因大致如下：

在硬件具体执行 cuda command 时，并没有 stream 这个概念。仅有的是 cuda driver 提供的 command 间的依赖关系。这里的硬件有两类，执行 memcpy 的 Copy Engine，执行 kernel 的 gpu core。它们内部都有一个队列，队列中的 command 依次执行。**stream 这个概念起到的作用就是，告诉执行引擎相关的依赖。当仅有 default stream 时，会认为所有的 cuda command 都有次序依赖，前后顺序执行。而拆分为多个 non-default stream 后，每个 stream 内的 cuda command 有次序依赖，位于不同 stream 的 cuda command 则不再由依赖**。第一种写法性能不高的原因在于，copyback 操作依赖于 kernel execution，将 copyback 放在 Copy Engine 中靠前的位置导致所有的 cuda command 都串行执行了

上面的分析有两点问题，一个是 host to device 和 device to host 的 copy 操作不能够 overlap（因为假定了只有一个 Copy Engine），另一个是没有考虑硬件并发执行多个 cuda command（因为假定了队列中前一个 command 执行完后才执行后一个 command，但实际上可能前后的 command 并没有依赖关系，例如上面的例子中在 gpu core 队列中的 kernel 来自不同的 stream，它们不存在依赖关系）

在 [How to Overlap Data Transfers in CUDA C/C++](https://developer.nvidia.com/blog/how-overlap-data-transfers-cuda-cc/) 一文中，谈到在 Tesla C2050 机器上，version 1 的写法反而执行得更快。因为在这台机器上，host to device 和 device to host 的 copy 操作是能够并发执行的（Copy Engine 变为 H2D Engine 和 D2H Engine），以及多个 kernel 可以并发执行。至于为啥 version 2 会比 version 1 慢，文中说的理由是 kernel 并发执行导致的，但我觉得这个理由不够 strong

**TODO：这篇文章后面讲，后来的 Hyper-Q feature 使得 version 1 和 version 2 没啥区别了？不过我还是没理解啥是 Hyper-Q，为啥它使得 version 1 和 2 没区别了**

### Concurrent Summary

driver api 和 runtime api 都是线程安全的

cuda 的并发可以归结为一个四元组 （device, context, stream, thread），每个 device 可以设置其 compute mode（枚举变量 cudaComputeMode），它影响了哪些线程能够调用 cudaSetDevice

cuda runtime 会为每个进程设置 primary context，这是一个三元组（device, primary context, process）。然后是一个二元组关系（thread, current context）。每个 thread 都有自己的 current context，cuda command 都会提交到这个 context 中。而每个 device 都有一个 active context，只有该 context 对应的 process 下的 stream 中包含的 cuda command 会被 device 执行。使用 driver api 可以创建，切换 context。因此不同的进程无法同时 share 同一个 device。context 的切换开销是非平凡的（因此这里存在一个调度策略，哪个 context active，什么时候切换到下一个 context）

### Default Stream and Synchronization

legacy default stream 模式是每个 process 都有一个 NULL stream。[Stream synchronization behavior](https://docs.nvidia.com/cuda/cuda-driver-api/stream-sync-behavior.html#stream-sync-behavior) 对 NULL stream 的 synchronization 行为论述如下

> The legacy default stream is an implicit stream which synchronizes with all other streams in the same CUcontext except for non-blocking streams, described below. (For applications using the runtime APIs only, there will be one context per device.) When an action is taken in the legacy stream such as a kernel launch or cudaStreamWaitEvent(), the legacy stream first waits on all blocking streams, the action is queued in the legacy stream, and then all blocking streams wait on the legacy stream.

其中 non-blocking stream 是指用 cudaStreamNonBlocking flag 创建的 stream，它不会默认与 NULL stream 同步。另外，此模式下新创建的线程默认提交到 device 0 的 NULL stream 中

更新的是模式 default stream per thread，它默认是每个 thread 都有一个 default stream，而且这些 default stream 间没有隐式同步

文档中对 [explicit synchronization](https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html#explicit-synchronization) （例如 cudaDeviceSynchronize 这种函数）和 [implicit synchronization](https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html#implicit-synchronization) 做了更详细的总结

### Error Handling

[Asynchronous Error Handling Is Hard](http://www.cudahandbook.com/2023/11/asynchronous-error-handling-is-hard/) 中谈到了三种错误处理的范式：exception，Immediate error return，global error variable。cuda 中使用了后两种错误处理的方式。除了每个 cuda 函数都会返回是否 error 外，[Error Checking](https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html#error-checking) 文档中讲到每个 host thread 都有一个线程局部的 error variable，每次错误发生时都会设置它。可以通过 cudaPeekAtLastError 或者 cudaGetLastError 来获取这个它。仅使用 Immediate error return 是不够的，因为 cuda 中有许多异步函数，用户不知道这些异步函数是否执行成功了。这也是为什么 cuda 文档中对许多函数的描述都会有下面的一句话

> Note that this function may also return error codes from previous, asynchronous launches.

### Hyper-Q Feature and Multi-Process Service

TODO

在 [Multi-Process Service Overview](https://docs.nvidia.com/deploy/pdf/CUDA_Multi_Process_Service_Overview.pdf) 中对 MPS 的定义

> MPS is a binary-compatible client-server runtime implementation of the CUDA API which consists of several components.

具体来讲，使用 MPS 的话，所有的 cuda api 都会转发到一个本地的 daemon 进程，由这个 daemon 进程实际与 device 交互，具体的好处就是使得多个进程可以共享一个 context，提高 gpu 的利用率

### Cuda IPC

提供的功能就是在不同的进程间 share 同一块内存，主要由三个函数实现 cudaIpcGetMemHandle，cudaIpcOpenMemHandle，cudaIpcCloseMemHandle

我想底下的实现就是通过页表，把两块虚拟地址映射到同一个物理地址，而如果调用 cudaIpcOpenMemHandle 的线程使用的不同的 device，那么这个函数底下会自动调用 cudaDeviceEnablePeerAccess 来开启跨 device 的内存访问

然后在 driver api 中也有类似的函数 cuIpcGetMemHandle，cuIpcOpenMemHandle，cuIpcCloseMemHandle。不太确定能否与上面的 runtime api 混用

### Virtual Memory Management

我理解这些和本来的 cudaMalloc API 的区别在于，cudaMalloc 等 API 除了分配物理内存外，还建立了虚拟地址到物理地址的映射，最后返回的是虚拟地址的指针

现在新的 virtual memory management API 就是将分配物理内存和建立虚拟地址到物理地址的映射这两件事解耦了。马上能想到的作用之一就是可以建立地址别名。这些 API 都是 driver api，最核心的函数包括

* cuMemCreate，这个函数申请一块物理内存，然后返回一个代表这块物理内存的 handle。值得注意的是，分配哪个 device 的物理内存不是由当前的 context 决定，而是由 CUmemAllocationProp.location.id 这个结构体参数决定的
* cuMemAddressReserve，这个函数预留一块虚拟内存地址，返回指向这块虚拟内存的指针，**这个指针的类型就和 cuMemAlloc 的返回类型一样了**
* cuMemMap，这个函数负责建立虚拟地址到物理地址的映射
* cuMemSetAccess，这个函数负责设置设备访问虚拟地址的读写权限。只有当 cuMemMap 和 cuMemAccess 都调用后，cuMemAddressReserve 返回的虚拟地址才能够被 kernel 访问
* 阐述一下我认为 cuMemMap 和 cuMemSetAccess 是分开的而不是像 Linux 中的 mmap 把两个功能合并起来的理由。因为 unified virtual memory space 的存在，使用 cuMemAddressReserve 和 cuMemMap 影响的不仅仅是当前 context 对应的物理设备，而是所有与该设备共享 virtual memory space 的设备。而 cuMemSetAccess 接收了一个参数数组，用来设置在这个 virtual memory space 下的哪些设备可以访问这组刚建立好的 mapped virtual memory
* 对称的一些函数包括：cuMemRelease，cuMemAddressFree，cuMemUnmap。注意 cuMemRelease 在调用 cuMemMap 后就可以调用了，因为 cuMemRelease 调用后不会马上释放掉这块内存，而是会等到所有的 mapping 都被 unmap 之后才会释放。可以看看 cuda sample 中的 vectorAddMMAP

[10.5. Virtual Aliasing Support](https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html?highlight=ipc#virtual-aliasing-support) 中特别强调了 virtual address alias 之间的 coherence 问题

> Unless otherwise noted in the PTX ISA, writes to one proxy of the allocation are considered inconsistent and incoherent with any other proxy of the same memory until the writing device operation (grid launch, memcpy, memset, and so on) completes. Grids present on the GPU prior to a writing device operation but reading after the writing device operation completes are also considered to have inconsistent and incoherent proxies.

driver api 中也提供了一些函数来将 cuMemCreate 返回的 memory handle 共享给另外一个进程（在 cuda ipc 小节中是 share mapped virtual address，这里是 share physical memory handle）

* cuMemExportToShareableHandle

* cuMemImportFromShareableHandle

这里返回的 handle 不再使用后是需要关闭的，但是 cuda 没有提供一个关闭的函数，我看 cuda sample 的 memMapIPCDrv 中是直接使用 platform api 进行关闭的，例如在 linux 上调用 close(fd) 函数，这样看来在 Linux 平台上这个 shareable handle 是一个文件描述符？

TODO：why we need virtual memory in gpu？

### Texture

下面的话摘自 3.2.2 节 Device Memory

> Device memory can be allocated either as *linear memory* or as *CUDA arrays*.
>
> CUDA arrays are opaque memory layouts optimized for texture fetching. 

cudaMallocArray --> cudaArray_t

cudaMemcpy2DToArray

### Graphics Interoperability

cudaGraphicsMapResources

cudaGraphicsResourceSetMapFlags

#### OpenGL Interoperability

cudaGraphicsGLRegisterBuffer

cudaGraphicsGLRegisterImage

### External Resource Interoperability

cuImportExternalMemory

cuMemcpy2D 函数 copy 一个 2D array，里面的参数很多，原因在于它可以从一个大的 2D array 中 copy 一个小的 subArray 2D，然后作为 subArray 嵌入到另一个大的 2D array 中。其中 srcXInBytes 和 srcY 指定了 subArray 在 src 2D array 中的起始 X，Y 坐标，而 srcPitch 自然就指定大的 src 2D array 的宽。WidthInBytes 和 Height 就指定了 subArray 的宽度和高度



**TODO：需要看的 cuda samples：**

* **simpleHyperQ**
* **simpleCUDA2GL**
* **bindlessTexture**，What is bindless texture

TODO：Interoperate with opengl and vulkan

TODO：ue 的 cuda module 封装，代码挺少的，并且涉及到一点点和 rhi 的交互，可以看看

TODO：memcpy2d 的 pitch 对齐，[使用Padding（cudaMallocPitch）的二维数组](https://blog.csdn.net/fb_help/article/details/79806889) 中讨论了使用 pitch 和不使用 pitch 这两种情况，没理解内存效率这个概念

TODO：CUarray，CUmipmappedArray

