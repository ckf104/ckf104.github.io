TODO：理解第一人称模板中的 Animation Blueprint
TODO：理解第三人称模板中的骨骼动画
## Basics
### Vertex Animation Basics
参考了视频 [VAT 1 | What are Vertex Animation Textures](https://www.youtube.com/watch?v=3ep9mkwiOjU) 和文章 [Texture Animation: Applying Morphing and Vertex Animation Techniques](https://medium.com/tech-at-wildlife-studios/texture-animation-techniques-1daecb316657) 这篇文章中还额外谈到了 animation blending 的问题

vertex animation 可以理解为二维的纹理动画在三维中的自然推广。它通过 vertex animation texture 存储了物体在每一个关键帧中的顶点坐标位置
### Skeletal Animation Basics
主要参考了一下 [learn opengl 骨骼动画](https://learnopengl-cn.github.io/08%20Guest%20Articles/2020/01%20Skeletal%20Animation/) 的实现，以及 [Thread: [Assimp-discussions] Nodes and Bones](https://sourceforge.net/p/assimp/mailman/assimp-discussions/thread/op.vmrwicttou3nzj%40flachzange/#msg26657996) 和 [can't get bones/skinning to work](https://sourceforge.net/p/assimp/discussion/817654/thread/5462cbf5/)

第一个需要理解清楚的事情是如何根据 bone matrix 和 node matrix 得到当前动画的顶点的坐标。当我们不使用 bone matrix 和 node matrix，直接使用原始的模型坐标时，渲染出来的图像是默认的模型位姿，或者称之为 bind pose

node，也称为 joint，表示了树状的骨骼层级结构。每个 node matrix 是子关节相对于父关节需要做的变换。而 bone matrix 将模型顶点从 model space 变换到 bone space。每个 bone 有唯一的一个 node 与之对应。因此属于某个 bone 的顶点在动画播放时的变换矩阵为
```
final_matrix = root_node_matrix * child1_node_matrix * child2_node_matrix * ... * childN_node_matrix * bone_matrix
```
第二个需要理解清楚的事情是一个顶点可能属于多个 bone / joint。我的理解是，对于人和动物的骨骼而言，joint 处的顶点归属不可能分得特别清楚。例如手腕旋转时手臂上靠近手腕的顶点多多少少会受到一些影响，而不可能保持完全的静止。因此让关节附近的顶点属于多个 bone 来创造渐变的过渡（不过对于机器人之类的建模可能就不需要这种过渡了）。一个顶点属于若干个 bone / joint，然后我们为这个顶点属于的每个 bone / joint 分配一个权重，这些权重的和为 1。例如随着手臂上的顶点离手腕越来越远，手腕骨骼的权重就越来越小

最后我们顶点的计算公式为
```
final_vertex = final_maxtrix1 * w1 + final_maxtrix2 * w2 + ... + final_maxtrixN * wN
```
我们考虑一个手臂上的三角形，它们都被手臂骨骼和手腕骨骼影响，但各自的权重分配并不相同。请注意，当手臂关节或者手臂关节更上层的关节运动时，这个三角形顶点之间的相对位置不会发生变化，因为手臂关节或者手臂关节更上层的关节运动会对 `final_matrix1` 和 `final_matrix2` 产生同样的影响。但是如果手腕关节运动了，此时 `final_matrix1` 不变，而 `final_matrix2` 变化，由于它们在手腕骨骼上的权重不相同，这个三角形不可避免地会发生形变。但这种形变是可以接受的，因为人和动物在关节运动处的皮肤也会有形变。一个典型的例子是，保持肘关节不动，手腕绕着手臂的轴进行旋转，那么肘关节和手腕之间的手臂就被扭曲了（或者说两者之间顶点被多个 bone / joint 影响了）

最后一个事情是动画是如何储存的，和 vertex animation 一样，只需要存储关键帧的信息，只是 skeletal animation 存储的不再是顶点的坐标，而是每个 node 在当前帧的旋转矩阵

这个 bone matrix 怎么算出来的，我觉得就是给定 skeleton 的 bind pose 后，每个 joint 相对于父节点的 transform 就确定了，回到最终矩阵变换的计算
```
final_matrix = root_node_matrix * child1_node_matrix * child2_node_matrix * ... * childN_node_matrix * bone_matrix
```
那与这个 joint 绑定的 bone 的 bone matrix 就是使得 `final_matrix` 为单位矩阵的 bone matrix。此时根据加权的顶点计算公式，计算出的每个顶点的坐标与模型的默认坐标一致，即使这个顶点被多个 bone / joint 影响。因此我们可以将一个顶点被多个 bone / joint 影响时的运动轨迹理解为，每个 bone / joint 有个自己认为的该顶点所在的位置，当位于 bind pose 时，这些 bone / joint 认为的顶点位置恰好重合，然后该顶点的实际位置是影响它的 bone / joint 认为的顶点位置的加权平均
### Skinning
将 3D 模型的每个顶点与处于 bind bose 的 skeleton 中的多个 bone / joint 关联上，并赋予权重的过程称之为蒙皮，或者 skinning。不过也有不一样的定义，例如 [UE4/UE5 动画的原理和性能优化](https://zhuanlan.zhihu.com/p/545596818) 中称从通过 joint 的 transform 层层递归算出每个顶点的坐标的过程称为 skinning，进一步根据这个算顶点坐标在 CPU 还是 GPU 上进行细分为 CPU Skinning 和 GPU Skinning

TODO：了解蒙皮算法。这种多个骨骼影响，加权平均的方法称为 Linear Blend Skinning，另外一种后续的 Dual Quaternion Skinning
### Animation Blending
TODO：当游戏中播放人物移动的动画时，假设此时人物又需要跳起来，如何平稳地从一个动画切换到另一个动画。通常制作的动画会使得开始和结束的位姿相同，这样所有的动画公用一个初始位姿的话，就可以在一个动画播放完成后流畅地切换到另一个动画上去，但如何从一个动画的中间切过去呢？
TODO：看一下 games104 的第 9 节，这节课详细地讨论了这个主题
## UE
### UE Animation
[skeletal mesh editor in unreal engine](https://dev.epicgames.com/documentation/en-us/unreal-engine/skeletal-mesh-editor-in-unreal-engine) 提到的 morph target 是什么?

Skeleton，Skeletal Mesh，Animation Sequence，这三类资产的关系是什么？它们对应三类的 [animation editor](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-editors-in-unreal-engine)

content example animation basics 中的 root motion 中 skeletal mesh 的 bone 的 root 下面一级的 ik_hand_root bone 和 ik_foot_root bone 是拿来干嘛的
### Skeleton
对应 `USkeleton` 类，它的 `ReferenceSkeleton` 中包含了原始的 joint 层次节点数据
```c++
/** Reference Skeleton */
FReferenceSkeleton ReferenceSkeleton;

struct FReferenceSkeleton
{
	//RAW BONES: Bones that exist in the original asset
	/** Reference bone related info to be serialized **/
	TArray<FMeshBoneInfo>	RawRefBoneInfo;
	/** Reference bone transform **/
	TArray<FTransform>		RawRefBonePose;
	// 上面这俩存储了原始的 joint 的层级结构，以及它们相对的 transform，下面这俩存储的是加入 virtual bones 后的
	// 最终结果，如果没有 virtual bones，那与原始的层级结构一致

	//FINAL BONES: Bones for this skeleton including user added virtual bones
	/** Reference bone related info to be serialized **/
	TArray<FMeshBoneInfo>	FinalRefBoneInfo;
	/** Reference bone transform **/
	TArray<FTransform>		FinalRefBonePose;
}
```
#### Socket
```c++
void USkinnedMeshComponent::QuerySupportedSockets(TArray<FComponentSocketDescription>& OutSockets);
```
从 `QuerySupportedSockets` 实现中可以看出，skeletal mesh component 的 socket 来源有三处，一处是 skeleton 的 `Sockets` 字段，一处是 skeletal mesh 的 `Sockets` 字段。然后所有的 bone 都可以作为 socket。前两处的 socket type 为 socket，bone 作为 socket 时的 socket type 为 bone

非 bone 的 socket 由 `USkeletalMeshSocket` 结构记录
```c++
UPROPERTY(Category="Socket Parameters", VisibleAnywhere, BlueprintReadOnly)
FName SocketName;

UPROPERTY(Category="Socket Parameters", VisibleAnywhere, BlueprintReadOnly)
FName BoneName;

UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Socket Parameters")
FVector RelativeLocation;

UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Socket Parameters")
FRotator RelativeRotation;

UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Socket Parameters")
FVector RelativeScale;
```
`USkeletalMeshSocket` 中记录了它属于哪个 bone，然后它相对于这个 bone 的变换（这感觉也可以把它理解为一个 bone 了）
在第三人称模板中，skeleton 有三个 sockets，weapon_r，foot_r，foot_l

`GetSocketTransform` 的实现很自然了，根据传入的名称，返回这个 socket / bone 相对于世界坐标的变换
```c++
FTransform USkinnedMeshComponent::GetSocketTransform(FName InSocketName, ERelativeTransformSpace TransformSpace);
```
TODO：virtual bone？
### Skeletal Mesh
对应 `USkeletalMesh` 类，它包含一个指向 skeleton 的指针，表示这个 mesh 对应的 skeleton
```c++
FReferenceSkeleton RefSkeleton;
```
TODO：这个 `RefSkeleton` 和它对应的 skeleton 的 `ReferenceSkeleton` 结构并不完全一样，为什么
### Animation Sequence
对应 `AnimSequence` 类，每个 animation sequence 都有个指向 skeleton 的指针，表示这个 animation 和哪个 skeleton 关联的
TODO: additive layer tracks 是怎么弄的，感觉是在 animation sequence 上提供额外的 bone transform 的调整
### Animation Notify
notify track 没啥用，主要是让用户可以对 notify 做一个高层的分类，不至于把所有的 notify 都混到一个 track 上看着很乱了

TODO：在 skeleton 中存 notify 和不在 skeleton 中存有啥区别，主要需要看看这些数据在 C++ 中是如何存储的
TODO：sync marker notify 是怎么用的
TODO：这个 trail notify state 做出来的特效我好喜欢，得好好看看

编辑器编辑的 Animation Notify 对应 `FAnimNotifyEvent` 类，而实际执行 notify 工作的对应 `UAnimNotify` 以及 `UAnimNotifyState` 这些类，继承这些类可自定义新的 notify

#### Montage Notify and Montage Notify Window
主要是和蓝图中的 play montage 节点进行搭配的，montage notify 触发 On Notify Begin 回调，而 montage notify window 还会额外触发 On Notify End 回调。通过 notify name 参数区分是哪个 notify 触发的回调
TODO：这个逻辑怎么通过 C++ 实现
### Animation Blueprint
animation blueprint 中的节点也在源码中有相应对应，例如 Blendspace Player 对应为 `UAnimGraphNode_BlendSpaceGraph` 类，所有的 animation node 都继承自 `UAnimGraphNode_Base`，而 `UAnimGraphNode_Base` 是 `UK2Node` 的子类。每个 animation node 包含一个特定类型的 struct，这些 struct 都是 `FAnimNode_Base` 的子类

animation blueprint 包含的逻辑由 animation graph 和 event graph 构成，前者的逻辑在 worker thread 中运行，后者在 game thread 中运行
TODO：animation graph 和 event graph 如何同步，例如 animation graph 中的 property access 会访问许多 game thread 中的数据，如何保证线程安全，以及第三人称模板中在 event graph 中更新 animation blueprint 的变量，然后在 animation graph 中获取变量，这样做是否线程安全呢？property access 的 call site 是如何决定的？

animation graph 中的 node 都包括 `On Initial Update`, `On Become Relevant`, `On Update` 这三个可以绑定的 node function，node function 接收 `FAnimUpdateContext` 和 `FAnimNodeReference` 这两个引用参数。`FAnimNodeReference` 就是 `FAnimNode_Base` 的一个 warpper

TODO：文档 [Animation Node Functions](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-blueprint-node-functions-in-unreal-engine) 中介绍了许多 node function，没太看明白
TODO：文档 [Animation Node Technical Guide](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-node-technical-guide-in-unreal-engine) 看起来是介绍如何自定义 animation node 的
	TODO：`FPoseLink` 类是拿来干嘛的，它和 `FComponentSpacePoseLink` 类有啥区别
#### State Machine
始终有一个状态处于 active，整个 state machine 的 pose 输出即为当前 active 状态的 pose 输出。当 transition rule 满足时，新的状态标记为 active，此时系统的输出为原 active 状态和新 active 状态的 pose 输出的 blending，blending 曲线和 blending 时间可以在 transition rule 的配置中指定。如果新的 active 状态还没结束 blending 马上又要切换到下一个状态，这称为 interrupt，那么此时 state machine 的 pose 输出是三个 pose（原 active，被打断的 active，以及新的 active 态的 pose）进行 blending 的结果

注意区分这里的 transition blending 和 blend space，blend space 是 blend 多个 sequence，而 transition blending 是 blend 原 active 节点和现在 active 节点的 pose。且在 blending 的过程中，原 active 节点的 pose 就固定不动了，但现 active 的 pose 是持续 evaluate 的，而不是一直和现 active 节点的初始 pose 进行 blending

有些时候我们希望动画只播放一遍，例如人物从空中落地时的动画，那可以勾选 transition rule 中的 `Automatic Rule Based on Sequence Player in State`，它与 `AutomaticRuleTriggerTime` 配合使用，在该状态的动画播放完毕之前就触发 transition，并与新的 active state 的动画开始 blending 了

TODO：transition rule 和 animation notify 的交互
### Animation Montages and Slots
对应类 `UAnimMontage`
TODO：蒙太奇的播放是如何做 blending 的？以及如何做 sync 的，因为 animation graph 中的 slot node 没有 group 相关的设置，文档 [Marker-Based Syncing](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-sync-groups-in-unreal-engine#marker-basedsyncing) 中提到 montage editor 中可以设置 sync group，但是又说它是针对 blend out 的？我们确实需要区分开 blending 的两种情况，一种是持续稳定的 blending，一种是 transition 阶段的 blending，这两种情况的 sync 方法是一致的吗。transition blending 的难点在于可能从一个动画的任何一个位置开始和另一个动画进行 blending，但其实根据具体情况，blend in 的动画也不总是需要从开头开始播，例如要从走路的动画过渡到跑，blend in 的动画从脚对齐的位置开始就行了
TODO：为什么修改 montage 资产的 slot 分类从 default slot 到其它 slot 后动画预览窗口中就没有动画了呢，slot track 是个什么概念
TODO：文档 [Animation Slots](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-slots-in-unreal-engine) 中讲要 slot group 可以是用来打断在同一个 group 中的 montage，如何理解：同一个 slot group 中只能播放一个 montage
TODO：在一个 montage 资产中创建多个 slot 有什么用，section 和 timing 又有什么用，看起来 section 是用来在 play 时指定开始位置的，如果不设置的话是默认从开始开始呢。然后 animation sequence editor 中右下角的 montage sections 是用来编辑这些 section 的播放顺序（只用于预览，还是说会对应到实际的 gameplay？）
TODO：In the **Anim Graph** within a character's **Animation Blueprint**，Slots can be used to organize which region on a character an animation is played back on. 从文档中的意思 slot 其实表示了 mesh 的一部分，它具体表示的哪一部分，这个信息存储在哪的呢
TODO：animation blueprint 中的 slot node 的 `Always Update Source Pose` 选项是啥意思
#### Montage Section
#### Slot

### Animation Blending
#### Blending Space
TODO：理解 2D blending space
TODO：文档 [Blend Spaces in Animation Blueprints](https://dev.epicgames.com/documentation/en-us/unreal-engine/blend-spaces-in-animation-blueprints-in-unreal-engine?application_version=5.4) 中谈到的 blend space graph 是个什么玩意
TODO：blend space 是怎么做 blending 的，主要是 sync group 相关的设置没办法影响 blend space，但测试三人称模板的 walk run blend space 1d 确实在 blending 时用了 walk sequence 和 run sequence 中的 sync marker
#### Sync Group
TODO：感觉文档 [Sync Groups](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-sync-groups-in-unreal-engine) 是讨论对 blending 进行细粒度的控制的
TODO：animation notify 中有一类是 sync marker，在 MM_Run_Fwd 中出现了，这是干嘛的
#### Additive Animation
TODO：添加 section 时显示 Animation Asset  MM_Land has an additive type AAT_LocalSpaceBase that does not math the target AAT_None 是什么意思
Animation Sequence 的 AdditiveAnimType 设置有 None，Local Space，Mesh Space 这三个选项，而对于 MM_Land 这个 Local Space 的 additive animation 而言，它有 Base Pose Type 和 Ref Frame Index 这些选项，这些选项都是啥含义
TODO：ue 里面没有 additive animation sequence 这种概念，它只有 animation sequence，然后可以选择一个 ref pose，将 animation sequence 与 ref pose 做差得到 additive pose，这里的细节是怎样的？然后这个需要控制 blending 时间的同步吗
### Data in Animation Sequence
TODO: 根据文档 [Animation Curves](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-curves-in-unreal-engine)，curve 的名称是存在 skeleton 里的，那 curve 的值呢？我觉得是放在 animation sequence 里的。那不同的 animation sequence 用同一个 curve 名称，但可以有不同的值吗？为啥要这样设计
TODO: 我在 animation blueprint 中使用 animation curve 为啥总是返回 0 呢？应该如何使用 animation curve？本来这也很奇怪，在 animation sequence 中定义 curve 的值，但是 animation blueprint 又不与单一的 animation sequence 进行绑定，它怎么知道该用哪个 curve 呢
### Control Rig and IK
basic ik 模块对应源码的 `FRigUnit_TwoBoneIKSimplePerItem_Execute`，源码的处理大概可以分为三步：
* 根据 pole vector 以及 bone 的长度可以计算出 mid joint 的位置（start joint 位置不变，如果能够到的话，end joint 的位置就是 effector 的位置）
* 将指定的 primary axis 旋转到 bone 现在的位置：primary axis 用来指定 start -> mid bone 在 start joint 空间中的朝向以及 mid -> end bone 在 mid joint 空间中的朝向，这隐含的要求是 start -> mid bone 和 mid-> end bone 在各自 local space 中的朝向是一致的，一般它们都是 +x 轴或者 -x 轴。而 bone 现在的朝向可以从第一步计算出的各个 joint 的位置得到。经过这一步，骨骼已经大体旋转到满足要求的姿势了
* 但此时骨骼还有一个自由度，就是它们可以绕着自身的 x 轴进行 roll，因此最后一步是根据 secondary axis 来调整骨骼 roll 的位置。源码中会将指定的 secondary axis 转到当前 bone，pole vector 组成的平面的与 bone 垂直并朝外的方向。对于 start -> mid bone 就是初始的 start joint 的 local space 的 secondary axis 方向转到与现在的 start -> mid bone 垂直并朝外的方向。对于 mid -> end bone 就是初始的 mid joint 的 local space 的 secondary axis 方向转到与现在的 mid -> end bone 垂直并朝外的方向。这里选取的 second axis 一定要是与 primary axis 是垂直的，否则旋转会改变 bone 的朝向。直观地来讲，secondary axis 指定了现在皮肤的哪个方向应该朝外，最自然的设置当然是外表皮朝外了。通常的骨骼设置中腿部和手部外表皮的方向都为 +y 轴或者 -y 轴
还有一点是，basic ik 的输入参数 pole vector，虽然名称是 vector，但实际是一个点，最终确定的骨骼平面是 pole vector，start joint，effector 三个点构成的平面。而 pole vector kind 的 direction, location 的含义是在将 pole vector 从指定的 space 变换到 model space 时要不要施加 translation（不会对 direction 类型施加 translation）
TODO：[Ask a Dev Control Rig](https://www.youtube.com/watch?v=LEJM8xLZ5kc&list=PL2A3wMhmbeArc-d471A4cku1pYA31X-ir&index=5) 系列视频接着看看
#### Constraints
TODO：回答一些 corner case，constraints 成环了会如何，constraints 中的父节点其实是在骨骼中的子节点又如何

TODO：看看与 skeleton control 相关的一系列 animation graph node
TODO：这玩意和 [IK Rig](https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-ik-rig?application_version=5.4) 的区别和联系是什么
TODO：two bone ik 在求解时选择的位姿是 ref pose，而不是 current pose，为什么
TODO：看看 [Control Rig: An axes-agnostic Basic IK Solver](https://alessandrotironigamedev.com/posts/2024/04/21/control-rig-an-axes-agnostic-basic-ik-solver/) 是怎么实现一个不需要 primary and secondary axes 的 solver 的
#### Initial, Current, and Offset Transform
编辑器中展示 control rig 有 initial, current 以及 offset 这三种 transform。我感觉 offset transform 稍微有些鸡肋。我们假定这些 transform 的调整都是在 local space 里进行（直接手动编辑 global space 感觉有些问题）。那么 control 输出的 transform 为 `current * offset * parent`，注意 ue 里左乘的矩阵是优先施加的变换
注意，不要用 control 去控制它的祖先骨骼，否则结果的表现也会很奇怪（因为祖先骨骼的变换改变了，又会反过来影响 control 的变换）
#### IK
足部 IK 在第三人称模板中的实现和 [玩转UE4/UE5动画系统 之 Control Rig + Fullbody IK版的足部IK实现](https://zhuanlan.zhihu.com/p/412251528) 中都差不多，就是从 foot 的位置发射一根射线寻找地板的位置，然后将足部的坐标 offset 一个地板 z 位置的偏移。这里解出的地板位置是相对于 root 的坐标系的，我们 offset 而不是直接将足部坐标设置为地板的 z 坐标保证了足部不会一直贴在地板上（例如我们播放跑步动画的时候肯定不希望脚一直贴在地上）。换句话说，这里的地板 z 位置偏移反映了足部所在的位置的地板与 root 所在位置的地板的相对高度，如果相对高度为 0 自然就不需要做 ik
有两个细节，一个是需要对得到的地板 z 坐标施加一个额外的偏移，这是因为地板的 z 坐标反映的是相对 root 的高度，但 root 不一定在地板上， 而脚板也不一定与 root 同一高度。因此这个额外的偏移的值是 root 的高度减去脚板的高度。第二个是要在足部当前的位置和足部目标的位置进行插值，通常会引入一个 foot speed，然后实际的 effector 位置是当前位置加上 delta 时间乘以 target 的方向向量，这来保证脚步位置不会发生突变。[玩转UE4/UE5动画系统 之 Control Rig + Fullbody IK版的足部IK实现](https://zhuanlan.zhihu.com/p/412251528) 中更进一步，还引入 foot ik 曲线做了 control rig 的 alpha 的插值。因为在 falling 的时候我们不会做 ik，因此在 falling 和 not falling 间我们做一个 alpha 插值来做是否启用 control rig 的平滑过渡
第三人称模板中默认的 IK 实现存在三个视觉上的问题
* 上下楼梯时人物抖动
* 上下楼梯时腿部穿模
* 下楼梯时后腿翘很高
经过 debug 发现，人物抖动的问题来源有两个
* 一个是默认的  sphere trace 长度不太够，导致上楼梯时有时候 trace 失败，这个加大 trace 长度就可以解决
* 第二个是 pelvis 的抖动：跑步时双腿打开时 pelvis 会下移到更下方的位置，然后双腿并拢的时候 pelvis 又会移到上边。这个可以调整 pelvis 的插值速度来实现，在 [玩转UE4/UE5动画系统 之 Control Rig + Fullbody IK版的足部IK实现](https://zhuanlan.zhihu.com/p/412251528) 中，pelvis 的插值速度是 5，而 foot 的插值速度是 15
而腿部穿模和后腿翘很高就不好做了，腿部穿模的主要原因是插值。如果提高插值速度，又会显得人物的微小移动有点一惊一乍的。而后腿翘很高是整个 pelvis 在下楼梯时会被往下拉，就显得后腿翘得高了（因为 pelvis 的插值较慢，导致 pelvis 的上升相比于后腿滞后了），如果把腿部的插值也降和 pelvis 一个速度，一个是会加剧穿模，另一个是上楼梯抬腿会变得很慢，看起来也有点奇怪

我觉得一个普适的减轻这些问题的方法是设计跑步动画时减小步幅，以及减小台阶的坡度，这样使得做 ik 的幅度小一些

TODO：不过我不开 control rig 也感觉上楼梯时人物有抖动，这是为什么？

TODO：模板中的 ik_foot 的值是怎么同步更新的，看起来就是动画里面包含了 ik_foot 的值
TODO：上台阶时人物的 root 位置是谁来调整的，这里涉及到碰撞盒高度的调整，和物理有关系，不仅仅是动画这边决定 foot ik 高度的问题
TODO：上台阶时人物抖动，应该怎么平滑一下？
TODO：如何优化第三人称模板中的 ik，关键在于判断什么时候该做 ik，ik 应该做成什么样子
* 我觉得移动时也得做 ik，不然人物跑步的时候会飘在空中
* 为了解决后腿抬得很高的问题，一种选择是在移速大于多少时不往下拉 pelvis 了，但这样的话又会导致开头说的平地上跑步人物飘在空中
* 试了一下 [玩转UE4/UE5动画系统 之 Control Rig + Fullbody IK版的足部IK实现](https://zhuanlan.zhihu.com/p/412251528) 的项目中的方法，他用了一条 FootIK 曲线来控制 control rig 的 alpha 值，这条曲线恒为 0，但是在 idle 和 run 的时候使用 modify curve 节点动态调整为 1，但我发现它做了一个插值，在起跳开始和落地前的读出的 alpha 值在 0，1 之间，这个插值应该是 blending 自动做的（因为这时候状态机也在切换嘛）
#### Debug
文档 [Control Rig Debugging](https://dev.epicgames.com/documentation/en-us/unreal-engine/control-rig-debugging-in-unreal-engine) 中介绍了如何断点和 watch value。另外有用的是一堆 draw node，可以用来可视化坐标之类的
以及如何将这些画在 game 中 [Is it possible to display Control Rig debug drawings in playing view port?](https://forums.unrealengine.com/t/is-it-possible-to-display-control-rig-debug-drawings-in-playing-view-port/491888)，经过实验，在 ue5.4 中需要同时设置 `ControlRig.EnableDrawInterfaceInGame` 和 `a.AnimNode.ControlRig.Debug` 为 1
以及不论是 control rig 或者 animation blueprint 中，都可以设置 preview 的对象，例如可以切换到 PIE 中的对象中
在 animation blueprint 中可以 log string 到控制台
TODO：测试时发现动画蓝图中计算 control rig alpha 值的逻辑没有被执行是为什么，只在初始时执行了一次，后面就没有执行过了
`ShowFlag.Bones 1` 使得 PIE 中可以展示 bone
### Root Motion
TODO
### Skeletal Mesh LOD
TODO：文档 [Skeletal Mesh LODs](https://dev.epicgames.com/documentation/en-us/unreal-engine/skeletal-mesh-lods-in-unreal-engine?application_version=5.4)
### Content Example
接着看看 Content Example 的 basics 部分
TODO：跳过了 1.2 节的 animation mirroring
TODO：1.3 节的 root motion，为啥一个有 root motion，一个没有 root motion，如何根据 skeletal mesh 找到正在播放的动画，root motion data 从哪提取出来的
TODO：如何查看动画的关键帧数目