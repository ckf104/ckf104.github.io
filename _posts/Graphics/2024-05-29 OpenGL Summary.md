记录读 OpenGL Programming Guide 的一些笔记

```c++
void glGenBuffers(GLsizei n, GLuint * buffers); // 分配 n 个 buffer

void glBindBuffer(GLenum target, GLuint buffer); // 绑定分配的 buffer 到 target 上
// taregt 有很多，最常用的是 GL_ARRAY_BUFFER，表示 vertex attributes
```

## Glad and GLFW

glfw 库在 x11 桌面系统中会首先加载 xlib 库，所有的对 xlib 库的函数的调用都是使用 dlsym 动态查找来进行的（而不是引用 xlib 的头文件，然后寄希望于动态链接器来重定位）

```c++
void* module = _glfwPlatformLoadModule("libX11.so.6");
```

我的电脑上有如下的 lilbGL 库

```shell
libGLX.so.0  -->  /usr/lib/x86_64-linux-gnu/libGLX.so.0.0.0
libGL.so, libGL.so.1 --> /usr/lib/mesa-diverted/x86_64-linux-gnu/libGL.so.1.7.0

libGLX_mesa.so.0 --> /usr/lib/x86_64-linux-gnu/libGLX_mesa.so.0.0.0
libGLX_nvidia.so.0 --> /usr/lib/x86_64-linux-gnu/nvidia/current/libGLX_nvidia.so.0
```

还有一些其它乱七八糟的

* glew：类似于 glad ，用来动态加载 opengl 的库
* glu：OpenGL Utility Library，一个基于 opengl 的，提供更高层次绘制函数的库

### GLX

Khronos Group 的 [OpenGL-Registry](https://github.com/KhronosGroup/OpenGL-Registry) 仓库定义了 OpenGL 相关的库，与 glx 相关的标准有两个，一个是 glx1.4，一个是 glxencode1.3，看起来 glx 是为 X window 提供了 OpenGL 拓展，使得能够使用 opengl 来绘制 X window

在 LearnOpenGL 教程中，所有的 OpenGL 函数在 glad 头文件中定义，glad.c 中会根据传入的 load function，来将 glad 头文件中定义的 opengl 函数赋上正确的地址（关于 khrplatform.h 的作用，见 [What is the KHR Platform header doing?](https://stackoverflow.com/questions/49683210/what-is-the-khr-platform-header-doing)）。这个传入的 load function 是 glfw 中定义的，在 x11 中，最终会调用到 getProcAddressGLX 函数，这里 GetProcAddress 和 GetProcAddressARB 都是从 libGLX 中加载的函数，如果这俩都没有，则会使用 dlsym，直接在 libGLX 中搜索这个 procname 函数

```c++
// glx_context.c
static GLFWglproc getProcAddressGLX(const char* procname)
{
    if (_glfw.glx.GetProcAddress)
        return _glfw.glx.GetProcAddress((const GLubyte*) procname);
    else if (_glfw.glx.GetProcAddressARB)
        return _glfw.glx.GetProcAddressARB((const GLubyte*) procname);
    else
    {
        // NOTE: glvnd provides GLX 1.4, so this can only happen with libGL
        return _glfwPlatformGetModuleSymbol(_glfw.glx.handle, procname);
    }
}
```

 **TODO：X window 和 glx 拓展** 

## OpenGL Context

[OpenGL Context](https://www.khronos.org/opengl/wiki/OpenGL_Context) 中讨论了 context 这个概念。下面是原文中的一段话，最重要的点在于 OpenGL 要求多个线程不能同时使用一个 Context

> In order for any OpenGL commands to work, a context must be *current*; all OpenGL commands affect the state of whichever context is current. The current context is a thread-local variable, so a single process can have several threads, each of which has its own current context. However, a single context cannot be current in multiple threads at the same time.

## Buffer Object

GLBindBuffer:

* ~~GL_ARRAY_BUFFER~~
* ~~GL_ELEMENT_ARRAY_BUFFER~~
* GL_TEXTURE_BUFFER
* GL_SHADER_STORAGE_BUFFER
* ~~GL_UNIFORM_BUFFER~~
* GL_TRANSFORM_FEEDBACK_BUFFER
* GL_PIXEL_PACK_BUFFER，GL_PIXEL_UNPACK_BUFFER（[PBO](https://www.khronos.org/opengl/wiki/Pixel_Buffer_Object) 相关）

### VAO，VBO，EBO

这三个类的整体关系是这样

* Vertex Buffer Object（VBO）存储了实际的顶点数据，会绑定到 GL_ARRAY_BUFFER 中
* Vertex Attribute Object（VAO）里是一个 Attribute 数组，每个 Attribute 代表一组顶点的输入数据（例如顶点坐标或者顶点纹理坐标等），通过 glVertexAttribPointer 来设置 Attribute，它实际存储的是指向 VBO 的指针。与 VBO 和 EBO 是通常的 buffer 不同，VAO 通过 glGenVertexArrays 产生
* Element Buffer Object（EBO）存储的是实际顶点数据的索引，它绑定到 GL_ELEMENT_ARRAY_BUFFER 上，当使用 glDrawElements 绘制时，**它使用这里面的 index 去索引顶点数据（不仅仅是顶点坐标）**，这可能有助于重复利用顶点数据，节省内存
* [Hello Triangle](http://www.learnopengl.com/#!Getting-started/Hello-Triangle) 中特别强调了在绑定 VAO 时可以解绑 VBO，但是不能解绑 EBO。其根本原因在于 VAO 中 Attribute 数组中最后一个元素存储了指向 EBO 的指针，当绑定 VAO 时，调用 glBindBuffer 绑定 EBO 时会将这个 EBO 绑定到 VAO 的 Attribute 数组中，如果此时解绑了 EBO，VAO 中的 EBO 指针也同时被解绑了

在有 Texture Buffer 或者 SSBO 后，理论上讲，我们是可以舍弃掉 VAO，VBO，EBO 等了，我不太确定性能上的差异，[In modern OpenGL, are VAOs "outdated" in favor of SSBOs or UBOs?](https://www.reddit.com/r/opengl/comments/iyi398/in_modern_opengl_are_vaos_outdated_in_favor_of/)

### Uniform Variable and Uniform Buffer Object

普通的 Uniform Variable 是存储在 Program Object 中的，而 Interface Block 中的 Uniform 是独立于 Program Object，存储在 Buffer 中（buffer-backed blocks），因此可以跨 Program Object 共享

对于 Uniform Variable 而言，通常使用 [glGetUniformLocation](https://registry.khronos.org/OpenGL-Refpages/gl4/html/glGetUniformLocation.xhtml) 获取它在 Program Object 中的 location，然后使用 [glUniform*](https://registry.khronos.org/OpenGL-Refpages/gl4/html/glUniform.xhtml) 系列 API 来设置它的值。在调用 [glUniform*](https://registry.khronos.org/OpenGL-Refpages/gl4/html/glUniform.xhtml) 前，需要调用 glUseProgram 来 activate 需要设置变量的 Program Object。从 OpenGL 4.3 开始，可以使用 [layout qualifer](https://www.khronos.org/opengl/wiki/Layout_Qualifier_(GLSL)) 在 glsl 程序中显式指定 uniform variable 的 location。每个 basic type 会占据一个 location，因此 array 类型会占据连续多个 location，包括结构体等一系列的占据 location 的规则可参考 [Uniform (GLSL)](https://www.khronos.org/opengl/wiki/Uniform_(GLSL))

Uniform Buffer Object（UBO）的使用则更加复杂一些，类似于 Texture，OpenGL Context 中存在若干数量的 uniform buffer binding location，我们需要同时在 Program Object 侧和 Buffer 侧将其绑定到同一个 binding location 上：

* 使用 [glGetUniformBlockIndex](https://registry.khronos.org/OpenGL-Refpages/gl4/html/glGetUniformBlockIndex.xhtml) 获取它在 Program Object 中的 block index，然后调用 [glUniformBlockBinding](https://registry.khronos.org/OpenGL-Refpages/gl4/html/glUniformBlockBinding.xhtml) 将 Program 侧的 UBO 绑定到指定的 binding location 上，可以通过 [layout qualifer](https://www.khronos.org/opengl/wiki/Layout_Qualifier_(GLSL)) 在 glsl 中显式指定 binding location（可以指定 block index 吗？）
* 使用 glGenBuffer 创建 GL_UNIFORM_BUFFER
* 使用 [glBindBufferBase](https://registry.khronos.org/OpenGL-Refpages/gl4/html/glBindBufferBase.xhtml) 或者 [glBindBufferRange](https://registry.khronos.org/OpenGL-Refpages/gl4/html/glBindBufferRange.xhtml) 将 Buffer Object 绑定到指定的 binding location 上，需要设置 Target 参数为 GL_UNIFORM_BUFFER（我猜想需要 Target 的参数的原因是不同的 target 有自己的 binding location space？），[glBindBufferRange](https://registry.khronos.org/OpenGL-Refpages/gl4/html/glBindBufferRange.xhtml) 是绑定 buffer 的一个 subRange 到 binding location 上
* 通过 [glBufferData](https://registry.khronos.org/OpenGL-Refpages/gl4/html/glBufferData.xhtml) 和 [glBufferSubData](https://registry.khronos.org/OpenGL-Refpages/gl4/html/glBufferSubData.xhtml) 设置 Buffer Object 的数据

TODO：UBO Layout 

TODO：Shader Storage Buffer Object

### Buffer Texture

表示纹理的底下的 memory 是一个  Bufer Object

## Texture / Image Format

当我们谈到纹理对象（以二维纹理为例），长宽表示了这块纹理对象占用的内存大小，最重要的就是纹理的 format，它表示我们应该如何理解这块内存上的数据。我们可以从各个维度对 format 进行分类

按类型分

* cube, array, 1D, 2D, 3D...
* mipmap, multisample

纹理对象包含的存储，image storage，texture parameter，sampler parameter

glGenerateMipmap, glGenerateTextureMipmap，生成的 mipmap 纹理级数由 GL_TEXTURE_MAX_LEVEL 和 GL_TEXTURE_BASE_LEVEL 指定

### Image Format

[Image_Format](https://www.khronos.org/opengl/wiki/Image_Format#Color_formats) 讲得很好：主要有三种存储方式，normalized integer，integer，float。其中 normalized integer 是说写入的时候要求范围在 0 - 1 的浮点，但实际存的以整数形式存储（感觉就是 fixed point）

depth format，depth stencil format，stencil only

### Texture vs Sampler

主要说一下 Sampler 是怎么用的

[Comparison mode](https://www.khronos.org/opengl/wiki/Sampler_Object) 进行采样 depth format 时，设置 GL_TEXTURE_COMPARE_MODE 和 GL_TEXTURE_COMPARE_FUNC 这两个纹理参数，然后 sampler 需要使用 [shadow sampler](https://www.khronos.org/opengl/wiki/Sampler_(GLSL))

### MultiSampling

[Multisampling](https://www.khronos.org/opengl/wiki/Multisampling) 的大概想法：depth test 和 stencil test 是逐 sample 的，而 fragment shader 是逐 fragment 运行的。primitive 占据的同一个 fragment 中的 sample 会得到相同的颜色

Sample Coverage，Sample Mask，我大概理解它们的意思，但是没咋明白它们有什么用。Sample Coverage 会指定一个 0 1 之间的浮点，具体的底层实现会将其转换为一个 sample mask，或者可以在 fragment shader 中输出 gl_SampleMask 的方式来决定这个 fragment 占多少个 sample，但这个 sample mask 会与这个 fragment 实际占的 sample 做 and 运算，所以设置这些只会占得更少的 sample，某个 sample 的 sample mask 为 1 时，fragment color 才会写入到这个 sample 中（所以我能想到的唯一作用就是做 blending 了）

另外，从 [percentage coverage of pixel](https://stackoverflow.com/questions/66073247/any-way-to-obtain-percentage-coverage-of-fragment-pixel-by-primitive-in-hlsl-g) 中看来，一个 fragment 不一定代表一个 pixel，例如硬件可能以 4:1 来运行 fragment shader，那么 64 sample 会导致一个 pixel 上会跑 16 个 fragment shader，这导致 fragment shader 看到的输入的 sample mask 中不可能超过 4 个 1

### Mipmap, LOD, and Anisotropic Filtering

texture 的 mipmap 层级由 GL_TEXTURE_BASE_LEVEL 和 GL_TEXTURE_MAX_LEVEL 这两个 texture parameter 指定，在使用 glTexImage2D 时可以指定要初始化的 mipmap level。除了手动初始化各个 level 外，可以调用 glGenerateMipmap 来让 OpenGL 自动生成 mipmap 纹理

纹理采样时具体选择哪一级的 mipmap 纹理，具体算法在 OpenGL 4.5 spec 的 8.14 Texture Minification 一节（选择 4.5 spec 是因为 4.6 中引入了 Anisotropic filtering，算法讨论更加复杂了），最核心的公式是 $\rho$ 值的计算
$$
\rho(x,y) = max\left\{\sqrt{(\frac{ \partial u }{ \partial x })^2 + (\frac{ \partial v }{ \partial x })^2 + (\frac{ \partial w }{ \partial x })^2}, \sqrt{(\frac{ \partial u }{ \partial y })^2 + (\frac{ \partial v }{ \partial y })^2 + (\frac{ \partial w }{ \partial y })^2}\right\}
$$
其中 $x,y$ 是屏幕坐标，而 $u,v,w$ 是纹理坐标（如果是二维纹理，$w=0$）。对 $\rho$ 值的直观理解上，在这个三角形内，屏幕坐标移动单位 1，纹理坐标会移动 $\rho$，这意味着屏幕坐标中的一个像素相当于纹理空间的 $\rho^2$ 个纹素，由此可以理解为什么要选取 $log_2\rho$ 层的 mipmap 采样

实际采样的 mipmap 层级 $\lambda(x,y)$ 为
$$
\lambda(x,y) = clamp(log_2\rho(x,y)+bias)
$$
其中 bios 可以通过纹理参数 GL_TEXTURE_LOD_BIAS 指定，而 clamp 截取的范围可以通过 GL_TEXTURE_MAX_LOD 和 GL_TEXTURE_MIN_LOD 指定（既然可以指定 mipmap 的层级了，要这个 clamp 参数有啥作用？）

官方 wiki 说

> A positive bias means that larger mipmaps will be selected even when the texture is viewed from farther away. This can cause visual aliasing, but in small quantities it can make textures a bit more sharp.

**从上述公式来看，感觉是不是说反了，应该 negative bias 才是上述效果？**

Games101 的 lecture 9 也讲到了 Anisotropic Filtering，它相比于 mipmap，还存储了各种长宽不等比例压缩的纹理图。直观来说，假设一个矩阵的每个元素是一个纹理图，那么 mipmap 存储的是对角线上的元素，而 Anisotropic Filtering 则存储了矩阵中所有的元素。但这样的 Anisotropic Filtering 只能处理水平矩形的 minification

OpenGL 4.6 中也引入了 Anisotropic Filtering，但在 8.14 节 Texture Minification 中的阐述相比于 Games101，我认为更加准确，实际，合理。这里的 Anisotropic Filtering 实际上存储的纹理和 mipmap 没有区别，但在采样时会采样多次进行 blending（本质上讲，这些效果都可以在 level 0 纹理上采样多次并 blending 实现，存储多重纹理是一种空间换时间的做法）

具体的采样方式由下面的公式给出（以二维为例）
$$
\rho_x = \sqrt{(\frac{ \partial u }{ \partial x })^2 + (\frac{ \partial v }{ \partial x })^2}
\\
\rho_y = \sqrt{(\frac{ \partial u }{ \partial y })^2 + (\frac{ \partial v }{ \partial y })^2}
\\
\rho_{max} = max(\rho_x, \rho_y)
\\
\rho_{min} = min(\rho_x, \rho_y)
\\
N = min(\lceil\frac{\rho_{max}}{\rho_{min}}\rceil, maxAniso)
\\
\lambda = clamp(log_2\rho_{min}+bias)
$$
这里的 $\lambda$ 和 mipmap 时相同，用来决定采样的层级，$N$ 值则表示了矩形的长宽比，$N$ 越大，说明它的各向异性越大，可以设置纹理参数 GL_TEXTURE_MAX_ANISOTROPY 来调整 maxAniso 的值（当这个值为 1 时，退化为常规的 mipmap）。最终会在层级 $\lambda$ 的纹理上采样 $N$ 次，最终的采样结果由下面的公式给出
$$
\tau_{\text {aniso }}= \begin{cases}\frac{1}{N} \sum_{i=1}^N \tau\left(u\left(x-\frac{1}{2}+\frac{i}{N+1}, y\right), v\left(x-\frac{1}{2}+\frac{i}{N+1}, y\right)\right), & P_x>P_y \\ \frac{1}{N} \sum_{i=1}^N \tau\left(u\left(x, y-\frac{1}{2}+\frac{i}{N+1}\right), v\left(x, y-\frac{1}{2}+\frac{i}{N+1}\right)\right), & P_y \geq P_x\end{cases}
$$
也可以近似为
$$
\tau_{\text {aniso }}= \begin{cases}\frac{1}{N} \sum_{i=1}^N \tau\left(u(x, y)+\frac{\partial u}{\partial x}\left(\frac{i}{N+1}-\frac{1}{2}\right), v(x, y)+\frac{\partial v}{\partial x}\left(\frac{i}{N+1}-\frac{1}{2}\right)\right), & P_x>P_y \\ \frac{1}{N} \sum_{i=1}^N \tau\left(u(x, y)+\frac{\partial u}{\partial y}\left(\frac{i}{N+1}-\frac{1}{2}\right), v(x, y)+\frac{\partial v}{\partial y}\left(\frac{i}{N+1}-\frac{1}{2}\right)\right), & P_y \geq P_x\end{cases}
$$
**注意这里采样是按照梯度方向去采样的，意味着也能够处理斜矩形的 minification 的情况**

不难想象上述公式在三维纹理的情况：这里沿着一条线去采样的，三维的时候就需要对一个矩形去采样的，而矩形的两条边长度分别为
$$
\frac{\rho_{max}}{\rho_{min}}, \quad \frac{\rho_{mid}}{\rho_{min}}
$$

最后，在 fragment shader 中，可以使用 dFdx\*，dFdy\* 来显式地获取梯度，根据官网的描述，这个 genType 是一个 expression，我目前的理解就是：只要随 fragment 变化的值就可以传入进去（例如 tex coord）

```
genType dFdx(genType p);
genType dFdy(genType p);
```

### Texture image units

下面这段话摘自 [Texture image units](https://www.khronos.org/opengl/wiki/texture#Texture_image_units)，过于迷惑

> **Note:** This sounds suspiciously like you can use the same texture image unit for different samplers, as long as they have different texture types. *Do not do this.* The spec explicitly disallows it; if two different GLSL samplers have different texture types, but are associated with the same texture image unit, then rendering will fail. Give each sampler a different texture image unit.

一些有关这段话的讨论

1. [Samplers of different types use the same texture image unit.](https://community.khronos.org/t/samplers-of-different-types-use-the-same-textur/66329/3) ，用 glValidateProgram 检查是个好主意

2. [Question regarding texture units](https://www.reddit.com/r/opengl/comments/cl6og9/question_regarding_texture_units/)

3. [OpenGL4.5 - bind multiple textures and samplers](https://stackoverflow.com/questions/45233643/opengl4-5-bind-multiple-textures-and-samplers)，从历史的角度讲了一下为啥 API 长这样

4. [Differences and relationship between glActiveTexture and glBindTexture](https://stackoverflow.com/questions/8866904/differences-and-relationship-between-glactivetexture-and-glbindtexture)，高赞回答讲得太好了

总结：这样的设计是历史原因。与 texture image units 相关的是 glActiveTexture 函数，它决定将哪个 texture unit 设置为 current，texture unit 上可以调用 glBindTexture 绑定所有类型的纹理（正如链接 4 所说，这里的状态是一个二维数组，第一维是 texture unit，第二维是 texture type）。但实际在 shader 里，每个 texture unit 只能对应一张纹理。因此 texture unit 的数目决定了在 shader 中能使用的最大纹理数目，那 texture sampler 具体对应哪一张纹理呢？是由下面的伪代码决定的

```c++ 
uniform sampler2D sampler;
sampled_texture = texState[sampler.tex_unit][sampler.type]
```

前面提到了，每个纹理是在二维数组的索引里，因此 texture unit 和 type 这两个维度就找出了要采用的纹理。sampler 的texture unit 是需要在运行 shader 前调用 glUniform1i 设置，而 sampler 的 type 和 texture type 具有一一对应关系。下面的论述摘自 [wiki Texture](https://www.khronos.org/opengl/wiki/Texture)（这就和 ue 中的 HLSL 很不一样了，因为 texture 对象没有显式地声明出来，而是包含在 sampler 里面，而且采用函数也只有一个 texture，具体采样的类型方法等也都在 sampler 里面了，而不是像 cuda 里还有 texture3D 等等一堆采样函数）

> A *sampler* in [GLSL](https://www.khronos.org/opengl/wiki/GLSL) is a uniform variable that represents an accessible texture. It cannot be set from within a program; it can only be set by the user of the program. Sampler types correspond to OpenGL texture types.

每个 shader stage 可以使用的最大 texture unit 数目可以通过 glGetIntegerv 查询

```c++
// vertex shader texture unit
glGetIntegerv(GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS, &MaxVertexTextureImageUnits);
// fragment shader texture unit
glGetIntegerv(GL_MAX_TEXTURE_IMAGE_UNITS, &MaxTextureImageUnits);
// Total texture unit in all shader stages
glGetIntegerv(GL_MAX_COMB`INED_TEXTURE_IMAGE_UNITS, &MaxCombinedTextureImageUnits);
```

[What is GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS?](https://gamedev.stackexchange.com/questions/192149/what-is-gl-max-combined-texture-image-units) 中提到如果**一个 texture 在多个 shader stage 中使用了，那么它会占用多个 texture unit**

我目前是这样理解的：这个 GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS 查到的值限定了调用 glActiveTexture 时能传入的最大 texture unit 的值。而其它的例如 GL_MAX_TEXTURE_IMAGE_UNITS 等值只是限定了在 fragment shader 中能使用的最大纹理数目，并不是说限定 fragment shader 中的 sampler 占用的 texture unit 不能超过GL_MAX_TEXTURE_IMAGE_UNITS。**注意，vertex shader 和 fragment shader 这些不是分离的，它们会被 link 到一个 program 里**。因此当一个纹理在多个 shader stage 中使用时，只需要在这些 shader 中声明 sampler 时使用相同的名字，然后调用一次 glUniform1i 来设置它的 texture unit 即可

### Texture Compression

EDAN35 的 [lec8 Texture Compression](https://fileadmin.cs.lth.se/cs/Education/EDAN35/lectures/L8-texcomp.pdf) 算是对这一话题的入门介绍，一些关键的点包括

* 纹理压缩的好处（带宽，能耗，甚至于图像质量 --> 纹理压缩使得我们能使用更高分辨率的纹理）
* 纹理压缩与图像压缩的区别，例如为什么不直接使用 jpeg 里的压缩方法
  * 纹理压缩和 jpeg 压缩都采用了分区块的方式，即逐 block 进行压缩（例如 4x4 的 block）
  * jpeg 采取的是变长的压缩方法，每个 block 压缩后的 bytes 可能都不一样，颜色值分布越松散的 block，压缩后的 bytes 越多
  * 纹理压缩必须采取定长的压缩方法，否则需要解压整个图像才知道某个位置的像素值，这对于纹理采样是不可接受的
* Block Truncation Coding，这是下面的 S3TC 以及 BPTC 的基础，[BTC wiki](https://en.wikipedia.org/wiki/Block_Truncation_Coding) 对 BTC 的解释更清晰
* S3TC 压缩方法，它对应 DXT 1，3，5 这三个标准
* 简要解释了 BPTC 压缩

OpenGL 官方 wiki [S3 Texture Compression](https://www.khronos.org/opengl/wiki/S3_Texture_Compression) 对 DXT 1, 3, 5 解释更加标准详细，并且额外阐述了如何在 sRGB 中使用 DXT，主要的区分在于实现上是先将 sRGB 转到 linear RGB 再进行插值，还是插值完了再转到 linear RGB。另外是官方 wiki [BPTC](https://www.khronos.org/opengl/wiki/BPTC_Texture_Compression)

## FrameBuffer

GL_DRAW_FRAMEBUFFER vs GL_READ_FRAMEBUFFER

在 learn opengl shadow mapping 中调用 glDrawBuffer，glReadBuffer 设置为 None，为啥？



FrameBuffer 的组成部分

* [Stencil Buffer](https://www.khronos.org/opengl/wiki/Stencil_Test)
* [Depth Buffer](https://www.khronos.org/opengl/wiki/Depth_Test)

## Blending

[OpenGL Wiki Blending](https://www.khronos.org/opengl/wiki/Blending) 中描述了基本的 OpenGL 对 blending 操作的支持

[Transparency Sorting](https://www.khronos.org/opengl/wiki/Transparency_Sorting) 讨论了如何合理的 blending。最简单的 alpha test，不需要启用 blending，只区分完全透明和完全不透明（让完全透明的像素不更新 depth buffer 即可）

在需要 blending 的情况，标准的做法是先渲染不透明的物体，再渲染透明物体。透明物体首先根据深度进行排序，然后**从后往前依次渲染**，混合公式使用 $c=c_{src}*alpha_{src} + c_{dst}*(1-alpha_{src})$，最终的颜色为
$$
c = c_1 * alpha_1 + c_2 * (1 - alpha_1) * alpha_2 + c_3 * (1 - alpha_1) * (1 - alpha_2) * alpha_3 \dots
$$
其中 $c_i$ 是深度排序中从前往后第 $i$ 个元素

但以物体为粒度进行深度排序是不够的，因为物体间可能相互遮挡，A 物体一部分在 B 前面，另一部分在 B 后面这种（**所以一般渲染半透明物体时都会关闭深度测试**）

## Primitive Type and Geometry Shader
在 `glDrawArrays` 的 mode 参数中接收的图元以及与之对应的 geometry shader 的 input
* GL_POINTS --> points
* GL_LINES，GL_LINE_STRIP，GL_LINE_LOOP  --> lines
* GL_LINE_STRIP_ADJACENCY，GL_LINES_ADJACENCY  --> lines_adjacency
* GL_TRIANGLE_STRIP，GL_TRIANGLE_FAN，GL_TRIANGLES  --> triangles
* GL_TRIANGLE_STRIP_ADJACENCY，GL_TRIANGLES_ADJACENCY--> triangles_adjacency
* GL_PATCHES

ADJCENCY 后缀的 primitive 是为 geometry shader 提供额外的相邻 primitive 的信息，见 OpenGL Programming Guide 的 Geometry Shader 中对此的讨论

Geometry Shader 中新生成的 primitive 的顶点属性是怎么弄的？看起来是要在 Geometry Shader 中接收 Vertex Shader 中的输出，然后 Geometry Shader 中自己输出新的 attribute，这个再由 Fragment Shader 接收（**重点就是 Fragment Shader 的 input 不再来自 Vertex Shader 了**）

由于 geometry shader 位于 vertex shader 之后，如果把 projection 放在 vertex shader 里，geometry shader 就得处理非线性的数据了，可能造成一些
不便，所以如果使用 geometry shader 的话，通常会把 projection 放在 geometry shader 中进行处理

TODO：https://www.khronos.org/opengl/wiki/Geometry_Shader，关注 Instanced GS 和 Transform Feedback
## Resource View

**TODO：关注一下 glTextureView 函数，这和 ue 里面的 resource view 感觉差不多**

## Operation after Fragment Shader

### Scissor test

[What is the purpose of glScissor?](https://gamedev.stackexchange.com/questions/40704/what-is-the-purpose-of-glscissor) 中讲得很好，但我还是有一点不明白的是，如果不启用这个 Scissor test，在设置了 glViewport 之后，什么情况下会画到 glViewport 设置的窗口之外，回答中提到的一种情况是使用 glClear 时（为什么？）。但评论中还提到了 line thickness > 1 等等情况，如何理解？TODO：见 [Vertex Post Processing](https://www.khronos.org/opengl/wiki/Vertex_Post-Processing#Viewport_transform)

~~另外我最不理解的一点在于，opengl 是如何做 clip 的。因为我感觉在 MVP 变换之后，如果有顶点在 clip space 外，也不能够草率地将这个顶点扔掉，很容易设想一种情况，三角形的三个顶点都在 clip space 外，但它的一部分面积在 clip space 内，且是可见的~~，TODO：见 [Vertex Post Processing](https://www.khronos.org/opengl/wiki/Vertex_Post-Processing#Viewport_transform)，它讨论了 point，line，triangle 是怎么做 clip 的

### Multisample fragment operations

### Stencil test
注意 stencil test 在 depth test 前面
### Depth test

### Blending

### Logic operation



TODO：看看 [Per Sample Processing](https://www.khronos.org/opengl/wiki/Per-Sample_Processing) 以及 spec 4.6 的 14.9 节。它规定了 Scissor test，multisample fragment operation 以及 pixel ownership test 都应该在 fragment shader 之前完成

TODO：目前最关心的一些关键点

* 简单看下 SPIR-V？

* FrameBuffer（看看 opengl programming guide）
* [Image Load Store](https://www.khronos.org/opengl/wiki/Image_Load_Store)
* Instance 方法
* Primitive Type，除了 triangle，还有 line, point 这些？
* Blending --> 延迟渲染，如何结合的？
* Bindless Texture？Proxy Texture？Texture View？（看看 opengl programming guide）
* Tessellation Shader？Geometry Shader？Compute Shader？理解整个图形管线（看看 opengl programming guide）
* Buffer vs Texture？
* 整个看看 opengl programming guide，看看还有没有感兴趣的点
* **最后，games201**
* [RTX GPU Ray-Tracing](https://developer.nvidia.com/rtx/ray-tracing)，以及集成在 Vulkan 和 DX 中的 API
* TBR 为什么能减少带宽消耗？以及 [猴子也能看懂的渲染管线](https://zhuanlan.zhihu.com/p/137780634) 中谈到 Tessellation Stage 可以用来做 Displacement Mapping，了解一下

