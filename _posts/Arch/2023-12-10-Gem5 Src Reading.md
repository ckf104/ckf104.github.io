---
title: Gem5 Src Reading
date: 2023-12-10 7:58:21 +0800
categories: [tools usage]
---

这是这段时间阅读 gem5 源码时做的笔记，写得有些潦草和混乱，希望后面能有时间重新整理一下。我认为如果能用这篇笔记的内容对官网的 learning gem5 tutorial 的代码进行解释说明，是一篇很好的教程。

## Gem5 初始化过程

这里主要讨论 gem5 的 python module 是如何初始化的。一个比较重要的宏是

```c
#define GEM5_PYBIND_MODULE_INIT(name, func)

// gem5中使用了两次这个宏，这个宏在函数外使用，会定义新的名为`name`
// 的python模块，且func在main函数被调用，用来初始化该python模块
GEM5_PYBIND_MODULE_INIT(importer, importerInit);
GEM5_PYBIND_MODULE_INIT(_m5, EmbeddedPyBind::initAll)
```

因此一开始 gem5 就定义了 `importer` 和 `_m5` 这两个模块，分别调用`importerInit`和`EmbeddedPyBind::initAll`这两个函数对其进行初始化。

首先看`importerInit`这个相对简单的函数

```cpp
void
importerInit(py::module_ &m)
{
    m.def("_init_all_embedded", gem5::EmbeddedPython::initAll);
    py::str importer_code(
            reinterpret_cast<const char *>(gem5::Blobs::m5ImporterCode),
            gem5::Blobs::m5ImporterCode_len);
    py::exec(std::move(importer_code), m.attr("__dict__"));
}
```

这里神秘的`m5ImporterCode`由`site_scons/gem5_scons/builders/blob.py`这个文件在 gem5 编译时生成，其实就是把`src/python/importer.py`的内容放在`m5ImporterCode`这个字节数组里面。最终的效果是增加了一个内置的 python 模块`importer`

而`EmbeddedPyBind::initAll`则比较复杂

```cpp
void
EmbeddedPyBind::initAll(py::module_ &_m5)
{
    pybind_init_core(_m5);
    pybind_init_debug(_m5);

    pybind_init_event(_m5);
    pybind_init_stats(_m5);

    mod = &_m5;

    // Init all the modules that were waiting on the _m5 module itself.
    initPending("");
}
```

大概来说，这个函数主要工作有两件事，一个是初始化`_m5`这个 python 模块，它进一步初始化了很多`_m5`的子模块，例如`_m5.core`，`_m5.debug`等等，**`initPending`这个函数和param参数化机制有关系，我们先暂时略过**。

到目前为止我们看到，gem5 拓展了内置的 python 解释器，额外有`importer`和`_m5`这两个内置模块，而`_m5`下还进一步有许多子模块。

然后回到 gem5 的 main 函数（`src/sim/main.cc`），它在初始化 python 解释器后，马上调用了`importer.install`函数。这个`install`函数主要做两件事。一个是把`CodeImporter`加入到`sys.meta_path`中，作为额外的模块导入搜索器。那`CodeImporter`负责哪些模块的导入呢？事实上，所有在 gem5 的编译脚本中的 `PySource`以及其子类`SimObject`的实例对应的 python 文件，都是由该`CodeImporter`负责导入的。

```python
# Create an importer and add it to the meta_path so future imports can
# use it.  There's currently nothing in the importer, but calls to
# add_module can be used to add code.
def install():
    importer = CodeImporter()
    global add_module
    add_module = importer.add_module
    import sys

    sys.meta_path.insert(0, importer)

    # Injected into this module's namespace by the c++ code that loads it.
    _init_all_embedded()
```

查看`src/Sconscript`这个编译脚本，可以知道，`PySource`这个类初始化时会调用`build_tools/marshal.py`，这个脚本负责把`PySource`对应的`python`文件编译、序列化、使用 zlib 进行压缩，生成一段C++代码，把压缩的字节序列保存在`EmbeddedPython`这个类中。所有`EmbeddedPython`类实例会串在一个全局链表上。上面的`_init_all_embedded`函数，也就是`EmbeddedPython::initAll`函数，会遍历这个全局链表，为`CodeImporter`建立一个`modules`字典，key 就是模块名，如`m5.objects.HelloObject`，而 value 则是对应的 python 代码，当执行`import m5.objects.HelloObject`时，`CodeImporter`发现该模块在`modules`字典中，便会将其导入。

许多 PySource 实例都来自`src/python/SConscript`文件，例如其中有

```python
PySource('m5', 'm5/__init__.py')  # such that `import m5` is valid
PySource('m5', 'm5/core.py')      # such that `import m5.core` is valid
```

### SimObject的param结构体如何生成

在 gem5 build 过程中，`sim_object_param_struct_hh.py`文件被调用，负责生成`${SimObject}Params`结构体的定义，而`sim_object_param_struct_cc.py`则负责生成该结构体到 python 的 绑定，`${SimObject}Params`和`${SimObject}`会被绑定到`_m5.param_${SimObject}`模块中。这里的绑定有一些顺序要求，即父类需要在子类前绑定，但C++的全局变量初始化没有顺序，因此这里有一些 workarounds 来绕过去。`EmbeddedPyBind::initAll`中调用的`initPending`也是出于这个目的。总而言之，最终的结果是所有的C++中的`SimObject`和对应`${SimObject}Params`的会被绑定到`_m5.param_${SimObject}`模块中。

这里需要区分开的是，`SimObject`本来也在 python 中有定义，所有的 `SimObject` 都在 `m5.objects.${SimObject}`模块中。这里的导入实现已经在前面讨论过了：通过把 python 文件内嵌在`EmbeddedPython`结构体中，然后通过`CodeImporter`导入。

因此，可以概括地讲，gem5 中额外提供的 python 运行环境有两类，一方面是 C++ 代码到 python 的绑定，这一类对象都在`_m5`模块下。另一类是 gem5 中提供的原生的 python 对象，这类对象都在`m5`模块中。

那么在 python 中再定义一次`SimObject`有什么作用呢？首先，它用来定义 C++ 中的`SimObject`需要的参数接口。事实上，在 python 中的`SimObject`的元类都是`MetaSimObject`，后者捕获了`SimObject`中所有的`param`和`port`字段相应的信息，在编译时`sim_object_param_struct_hh.py`就是用该信息来生成`${SimObject}Params`结构体的定义，以及`sim_object_param_struct_cc.py`用该信息来生成`${SimObject}Params`到 python 中的绑定。而`SimObject`到 python 中的绑定要如何设置呢，因为`SimObject`的数据，方法完全不清楚。因此 gem5 为每个`SimObject`预留了一些特殊的字段。这些特殊字段定义在`MetaSimObject.init_keywords`中，其中之一`cxx_exports`，如果在`SimObject`中定义了这个属性，它的值通常是一个由`PyBindMethod`实例组成的列表。每个`PyBindMethod`定义了一个在`SimObject`中且需要导出到 python 中的方法。如果没有定义`cxx_exports`，那么绑定在 python 中的`SimObject`是一个空壳，只有一个类的定义，而没有定义相应的属性和方法。

### SimObject的属性

上面讨论了，python 中的`SimObject`用来定义 C++ 中的`SimObject`需要的参数，因此 python 中的每个`SimObject`的属性字段不能定义或者添加（但方法无所谓）。粗略地可以把每个`SimObject`的属性字段的功能分为下面四类

* 定义 Param，例如`xxx = Param.Latency("xxxx")`，该字段在编译时也会被`sim_object_param_struct_hh.py`解析，作为`${SimObject}Param`的一个字段，后面这个`${SimObject}Param`作为 C++ 中的`SimObject`的构造函数参数传递。
* 定义 Port，例如`xxx = RequestPort("xxxx")`，`sim_object_param_struct_hh.py`在编译时在`${SimObject}Param`中生成一个`port_${xxx}_connection_count`字段，表示该 port 的连接次数，虽然我觉得只对 VectorPort 有用？
* 定义特殊字段，例如前面提到的`cxx_exports`
* 定义 Param 的值或者 Port 的连接。即给前面两种参数进行赋值。例如在`Root`这个`SimObject`中定义了`eventq_index = 0`，这实际上给基类`SimObject`中的参数声明`eventq_index = Param.UInt32(xxxx)`进行了赋值。

从高层次上看，gem5 的 `SimObject`之间有多种关系

* 继承关系：例如`ClockedObject`继承自最基础的`SimObject`，然后`BaseCPU`又继承自`ClockedObject`等等。`sim_object_param_struct_hh.py`在生成时`${SimObject}Params`时也会生成同样的继承关系，例如`BaseCPUParams`会继承`ClockedObjectParams`。另外，python 中的 `SimObject` 只能有至多一个`SimObject`父类，且多继承时顺序必须排在第一个。`sim_object_param_struct_cc.py`在生成 C++ 中的`SimObject`到 python 的绑定时，假定 C++ 中的`SimObject`与 python 中的`SimObject`相同的继承关系。但有时候 python 中的`SimObject`的继承关系与对应 C++ 中的`SimObject`的继承关系并非完全一致，例如最基本的`SimObject`在 C++ 中有`Drainable`等父类，但在 python 中没有任何父类。可以在 python 的`SimObject`中定义`cxx_base`和`cxx_extra_bases`对此进行调整，`cxx_base`用来指定 C++ 的`SimObject`父类，而`cxx_extra_bases`用来指定额外的非`SimObject`的父类。

* 模拟对象的层级关系：每个`SimObject`实例都有`_parent`，`_children`字段。如果一个`SimObject`的参数之一是一个`SimObject`，或者手动添加字段挂上去（例如`System.cpu = xxxxCPU()`，system 类中本身是没有定义 cpu 这个属性的），都会使得前者和后者形成父子关系。这里的层级关系的作用之一是为了下面的 proxy 机制，例如`parent.any`就表示到该`SimObject`的父节点，或者进一步的祖先节点，寻找满足要求的属性值。另外，每个`SimObject`的名字也是根据这个层级关系串起来的。

  ```python
  SimObject.name = ' '.join([SimObject.parent.name, SimObject_attr_name in its parent])
  ```

* Port 的连接关系，一些`SimObject`中定义了`Port`属性，`Port`的连接关系定义这些`SimObject`间的数据流向。

在配置脚本中常见的为 `SimObject` 设置默认参数值的方法是继承该 `SimObject`，然后在子类的字段中设置属性值，例如在 官网的 learning gem5 教程中的 `two_level.py` 配置脚本中为系统配置了 L1，L2 Cache。部分代码如下

```python
class L1Cache(Cache):
    """Simple L1 Cache with default values"""

    assoc = 2
    tag_latency = 2
    data_latency = 2
    response_latency = 2
    mshrs = 4
    tgts_per_mshr = 20
```

在 `MetaSimObject` 创建该类时会对字段进行检查，如果属性字段的作用是设置了参数值，那么 L1Cache 类对象的`_values` 字典中存入参数名和默认值的映射。在 L1Cache 实例化时，`SimObject` 基类会检查类对象的 `_values` 字典并复制到自己的 `_values` 字典中。这样做的好处是不需要实例化 `Cache` 后挨着挨着设置各个属性值了。而在实例化 C++ 对象阶段，是调用该 python 对象对应的 param 结构体的 `create` 函数，而该 python 对象对应哪个 param 结构体由对象中的特殊字段 `type` 指定，实际对应的结构体为 `${type}Param`，因此只要子类不重载 `type` 字段，子类和父类对应的 C++ 对象是相同的。

### Proxy 机制

这里的 proxy 实际是就是一种 delayed resolution。在这时候我还不知道 param 的值是多少，就先用一个 proxy object 作为占位符，并存下必要的信息。等时机成熟了之后再进行 resolution，得到真正的参数值。

### Gem5 实例化

`m5.instantiate`函数干的重要事情

* unproxy
* 创建 c++ 对象
* port 连接（需要实现`SimObject`的`getPort`函数）
* c++ simobject init function callback
* initState / loadState callback

`m5.simulate`

* startup callback
* call simulate in simulate.cc

EventQueue 的创建发生在 `m5.instantiate`函数创建 C++ 的`SimObject`时。因为`SimObject`的基类`EventManager`在初始化时需要`EventQueue`指针。具体每个`SimObject`在哪个`EventQueue`中（即调用`schedule`函数时`event`会放在哪个`EventQueue`中）是由 python 中`SimObject`的参数`eventq_index`决定的。默认情况该参数值为`Root SimObject`的默认值 0，即默认下只有一个`EventQueue`。gem5 会为每个`EventQueue`创建一个线程来模拟运行，`EventQueue 0`则由主线程来模拟。

**TODO: ~~param机制~~，以及构建脚本中Source基类的作用，~~proxy机制~~（例如parent.any这种操作，对于port的proxy又有哪些用处），GlobalEvent**