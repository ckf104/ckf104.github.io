### MISC

cmd 命令 `ShowFlag.Collision 1` 可以在编辑器和游戏中显示 static mesh 的碰撞体，而 level editor 的 show -> collision 只会在编辑器中显示碰撞体 

下面这些是以前的东西
## Material Editor

**任何不理解的地方，看看编译出来的 Shader code 多半就知道了**

Q：**材质编辑器中的 texcoord 从哪来的？**

A：在左上角的 preview 窗口可以选择不同的 preview mesh，texcoord 来自 preview mesh  的纹理坐标，**我感觉对于有 UVs 作为 input 的节点，如果这个节点没有连接，就会默认选择 texcoord 0**

Q：为什么有些材质节点的默认输入显示为 DefaultValue = Custom expression？

A：双击节点，展开这个函数内部的实现，就可以看到这类输入输入的默认值是通过另外一堆节点构造出来的，因此为了看到默认值，就需要展开函数内部的实现看看

Q：Value Step 节点是怎么用的

A：首先解释一下这个 gradient 输入，其实就可以把它理解为一张二维纹理输入，只是它们值的变化具有梯度的概念（不好讲），然后这个 Value Step 干的事情就是，输出一个只有黑白值的新梯度，将原来的某个的梯度范围变为黑的，另外的一个范围变为白的，例如设置 Number Before White Result 为 2，那么以 3 为周期，0 - 2 的梯度值变为黑，2 - 3 的梯度值变为白。而如果设置为 5，那么就是 0 - 5 的梯度值为黑，5 - 6 的梯度值为白。这样输出的新梯度具有更具区分度的结构

**Q：Dynamic Parameter 节点是怎么用的？什么是 Particle Color？**

这其实是 Niagara System 与 Material 的交互，除了 Particle Color，还有 Particle Direction 等等一系列的输入节点，使得 Material 能够根据 Particle 的性质动态改变，而 Dynamic Parameter 节点就完全是 Particle 这边自定义的值了，在 Niagara System 中使用 Dynamic Material Parameters 模块可以设置 Dynamic Parameter 的值

Q：什么是双面材质（Two Sided Material）？

一般这种材质用在二维的物体上，使得它不会做背面剔除，材质编辑器中 TwoSidedSign 节点表示是渲染物体的方向是正面还是背面，**TODO：理解草以及树叶等这些特别薄的物体是如何渲染的**

## Niagara Editor

Q：什么是  Module Locals / Module Outputs

Module Locals 变量仅在 module 内部可以被 read / write，Module Outputs 可以在一个 stage 内部的 Module 间共享

Q：什么是 Static Switch Inputs

这玩意就是一个三元运算符 ? : 中控制输出的 bool 变量，在 Material Editor 中也有类似的节点。它的值可以在 Editor 界面控制。需要强调的是，假设它为 true，那么 false 的输入不会用到，ue 保证在编译期就会将其优化掉，**一部分路径就不会再执行。但这部分被优化的路径上可能也有一个 static switch，这个 static switch 都不会显示在 Editor 界面**！这就是为什么在 Niagara Editor 中有一部分的 Static Switch Inputs 都没有显示出来。**对于 Module Input Parameter 也是一样的，因为 Static Switch Inputs 的优化，导致一部分 Module Input Parameter 没有被用上，这些也不会显示在 Editor 中**。另外，每个 Module Input Parameter 还可以设置自己的 **Visible Condition**，表示什么时候才会显示出来

Q：什么是 Inline Edit Condition Toggle

[unreal-engine-property-edit-conditions](https://dev.epicgames.com/community/learning/knowledge-base/baX0/unreal-engine-property-edit-conditions) 中讲得特别好，虽然它是针对 UProperty 中来说的，不过也适用于 Niagara Editor。当给一个 bool 类型的 parameter 勾选上这个后。其它的变量的 **Edit Condition** 这一栏加入这个 bool 变量，就达到了 Inline Edit Condition 的效果

Q：什么是 Dynamic Inputs

在设置普通的 Module Input Parameter 的值时，可以将它的值设置为 Dynamic Inputs，这个 Input Value 实际上是另一个 Module 的输出

Q：Niagara 中有 local，world，simulation 这三种 coordinate space，它们的区别是什么？

local, word coordinate space 是相对于 level 里面来说的（就是 actor 和 component 它们的 local, world 这些概念），而 simulation space 的含义为

```
simulation space = Emitter.LocalSpace ? local space : word space
```

而 Emitter.LocalSpace 可以在 Emitter 的 Properites 这一栏设置，虽然我不知道为啥直接用 Set Parameter 模块不行 

Q：Velocity 和 Acceleration Force 的区别是什么？

区别感觉就是物理上的，设置 Acceleration Force 来影响加速度，并最终影响速度，而 Velocity 会直接调整速度。在 Particle Update Group 中添加 Solve Force and Velocity 模块，它负责求解 Acceleration Force，并修改 Velocity

[Lesson 5: Particle Update: Forces](https://www.youtube.com/watch?v=ZViv64_1CBA) 中讲了 Niagara 中许多预设的 force 模块

Q：Emitter State 中的参数都是什么意思，例如 Life Cycle Mode，Loop Behavior，Scalability Mode 等等

Emitter 是以 Loop 为周期发射粒子的，Loop Duration 参数决定了一个 Loop 周期的长度。而 Loop Behavior 的取值（Infinite，Once，Multiple）决定了 Loop 的次数。当取值为 Multiple 时，Loop Count 参数决定了 Loop 的次数，Loop Delay 则决定了不同周期的间隔。当 Emitter 执行完所有的 Loop 后，进入到 inactive state。Inactive Response 参数决定了当 Emitter 进入 inactive state 后的行为（默认是等所有粒子都消失后 kill 掉自己）

而 Life Cycle Mode 以及 Scalability Mode 这些就是指上面这些参数从 system 中获取还是 Emitter 单独设置

Q：Render 的作用

Sprite Render，Mesh Render，Light Render

Q：在 Sprite Smoke 教程中，在 Particle Spawn 中用到了 Sub UV Animation 模块，这是干嘛的？另外，在 Sprite Renderer 中，也设置了 Sub UV 相关的参数，这些参数又是啥意思？

[Lec 8 Render Options](https://www.youtube.com/watch?v=QlM7WUma0wk&list=PLXPlawJCxIVwJeTpoPOa20OcS96a1PkMu&index=9) 讨论了这些东西。Sub UV 从概念上来讲就是 uv 坐标只索引图像上的一小块（或者说是 layered iamge？）。Sub UV Animation 会根据用户配置的逻辑设置 SubImageIndex。Sprite Renderer 中的 sub uv 参数主要用来告诉 render 在给定 SubImageIndex 后，应该选择图像上的哪一块（例如 4 x 4 的 grid 而 SubImageIndex 的值为 2 就应该选择第二行第一列的那块图像）。因为 SubImageIndex 是个浮点数，如果勾选 Sub UV Blending Enabled 之后，Sprite Render 能自动帮我们插值

Q：Niagara System 如何与 Game Play 互动？

Niagara System Asset 在 C++ 代码中对应 UNiagaraSystem 类，它通常被包含在 UNiagaraComponent 中，只需要把这个 Component attach 到其它 Actor 上就创建出了粒子效果。我们将一个 Niagara System Asset 直接拖拽到 Level 中时，实际上创建了一个 ANiagaraActor，它包含一个 UNiagaraComponent，这个 Component 包含了我们拖拽的 Niagara System

另外，在参数设置上，使用 User Parameter 能够将 Niagara System 参数暴露给蓝图，使得能在蓝图中对粒子效果动态调整

**关于粒子的管理这些，module 之间是有一个约定俗成的规则的，例如 lifetime 设置粒子的生命周期，velocity 设置粒子的速度这些，这样不同的 module 才能合作起来**，在 [UE4 Niagara Tutorial Series Part 4: Niagara Events](https://www.youtube.com/watch?v=HWfbBWamZQI) 中，从零开始搭建了一个 Emitter，很好地展示了这一点

Q：Event in Niagara System？

目前不知道有没有办法自定义 Event，UE 原生提供了三种 Event：Location Event，Death Event，Collision Event。这些 Event 在 Particle Group 里添加。然后每个 Emitter 添加自己的 Event Handler，Handler 中定义接收的 Event 类型。然后 Event 下面的 Module 会在每个 spawned particle 上依次执行（也可能是在每个 particle 上执行，取决于 Handler 的 Execution Mode）。Handler 中可以添加的特殊 Module 为 Receive Location / Death / Collsion Event，这些 Module 负责将 Event 中传入的粒子信息（产生该 Event 的粒子的 Location，Velocity 等等）写入到 Module Outputs 中，供后面的 Module 使用

Q：Stack Context Sensitive 变量是什么？Transient 变量是什么？Local 变量是什么？Data Instance 是什么？

见 [UE4：Niagara的变量与HLSL](https://zhuanlan.zhihu.com/p/342315125)

Q：Simulation Stage？Data Interface 参数类型？Particle attributes reader？grid 2d / 3d? 

Q：Data Interface？感觉是继承自 UNiagaraDataInterface 的类

## Niagara Data Interface

UNiagaraMergeable

​	-> UNiagaraDataInterfaceBase

​		-> UNiagaraDataInterface

FNiagaraTypeDefinitionHandle

FNiagaraTypeDefinition

FNiagaraVariable

FNiagaraFunctionSignature

### TODO

UMaterialInterface

​	-> UMaterial

​	-> UMaterialInstance

​		-> UMaterialInstanceConstant

​		-> UMaterialInstanceDynamic

`MeterialInstanceDynamic` 是个啥玩意，**Constant Material Instance 的参数真的可以在蓝图里每帧改吗**

MeshComponent 中的 OverrideMaterials 和 StaticMesh 中的 StaticMaterials 或者 SkeletalMesh 中的 Materials 是什么关系

**我没搞明白的是，ue 是如何对应 mesh 和纹理的，目前我的理解是，每个 mesh 有自己的纹理坐标，因此乱贴纹理会看上去很奇怪之类的？**



TODO：UE 中关注的点

* 垃圾回收机制
* Render 线程，Game 线程，RHI 线程之间的同步
* Material Shader 的实现？结合 PBR 看看？
* 向往在博客园中的blog 描述了 UE 的渲染子系统，顺着看一遍捋一下
* niagara 渲染实现，niagara 的渲染是如何加入到 ue 的渲染管线中的
* PCG 系统
* skeletal mesh 和 animation





### 多 render 一致性

一些随机的因素

* BP/Obstacles/TrafficSign/Single_TrafficSign/SO_TrafficSignLimitBase 是众多路牌的基类，它有两个随机需求
  * 随机从 array 中选一个元素
  * 从给定范围中选择一个浮点数
* BP/Pedestrian/BP_AnimPed_ChildSimple **等等一堆（因为它随机的逻辑写在子类里的）**
  * 若干预定义 array 中有若干颜色，从每个 array 中选择一个随机的元素
* 汽车里边还有一个地方是车灯的随机
* stencil id

~~taggerComponent color？~~

stencil id 的设置方式：(ECityObjectLabel << 16) + id -> uint32 stencil

UTagger::TagActorbyLabelComponent，根据 Actor 中的某一个特定的 component，将所有的设置为了同一个 stencil 值

UTagger::TagActorbyName，根据 component 的名字，为 Actor 的每个 component 单独设置 stencil 值
