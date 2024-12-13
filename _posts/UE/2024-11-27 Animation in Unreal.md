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
#### Slot Groups
```c++
	// serialized slot groups and slot names.
	UPROPERTY()
	TArray<FAnimSlotGroup> SlotGroups;

	/** SlotName to GroupName TMap, only at runtime, not serialized. **/
	TMap<FName, FName> SlotToGroupNameMap;
```
感觉是用来对动画做分类的，在第三人称模板中有两个 slot group，default group 和 additive group，然后例如 default group 中又包含 default slot，full body，upper body 等等 slot
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
TODO：bone proxy？在 animation sequence editor 中可以查看动画中每帧中每个 bone 的 local transform 和 reference transform 以及 mesh relative transform，local transform 就是相对父节点的 transform，reference transform 就是标准位姿下这个 bone 的 transform，那 mesh relative transform 是个啥玩意
### Skeletal Mesh
对应 `USkeletalMesh` 类，它包含一个指向 skeleton 的指针，表示这个 mesh 对应的 skeleton
```c++
FReferenceSkeleton RefSkeleton;
```
TODO：这个 `RefSkeleton` 和它对应的 skeleton 的 `ReferenceSkeleton` 结构并不完全一样，为什么
### Animation Sequence
对应 `AnimSequence` 类，每个 animation sequence 都有个指向 skeleton 的指针，表示这个 animation 和哪个 skeleton 关联的
### Animation Notify
TODO：为啥 notify 有多个 track
TODO：在 skeleton 中存 notify 和不在 skeleton 中存有啥区别
TODO：这个 trail notify state 做出来的特效我好喜欢，得好好看看
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
TODO：蒙太奇的播放是如何做 blending 的？
TODO：slot node 的 `Always Update Source Pose` 选项是啥意思
TODO：为什么修改 montage 资产的 slot 分类从 default slot 到其它 slot 后动画预览窗口中就没有动画了呢，slot track 是个什么概念
TODO：文档 [Animation Slots](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-slots-in-unreal-engine) 中讲要 slot group 可以是用来打断在同一个 group 中的 montage，如何理解
TODO：在一个 montage 资产中创建多个 slot 有什么用，section 和 timing 又有什么用，看起来 section 是用来在 play 时指定开始位置的，如果不设置的话是默认从开始开始呢。然后 animation sequence editor 中右下角的 montage sections 是用来编辑这些 section 的播放顺序（只用于预览，还是说会对应到实际的 gameplay？）
TODO：In the **Anim Graph** within a character's **Animation Blueprint**，Slots can be used to organize which region on a character an animation is played back on. 从文档中的意思 slot 其实表示了 mesh 的一部分，它具体表示的哪一部分，这个信息存储在哪的呢

对应类 `UAnimMontage`
#### Montage Section
#### Slot

### Animation Blending
#### Blending Node
TODO：文档 [Blend Nodes](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-blueprint-blend-nodes-in-unreal-engine?application_version=5.4) 中介绍了 animation blueprint 中可以使用的各种 blend 模式

相比对最终的顶点进行 blending，显然逐关节的变换进行 blending 更合适，这样过渡会更加自然
TODO：apply additive 节点和 apply mesh space additive 节点，这个加法要怎么做呢，[ozz-animation samples](https://guillaumeblanc.github.io/ozz-animation/samples/) 中有做 additive animation 的例子，很有必要看看。另外 mesh space vs local space，看起来 local space 其实就是 bone space，而 mesh space 就是 model space，apply additive 和 apply mesh space additive 分别适用于 local space additive animation 和 mesh space animation，类似地 layered blend per bone 而也有 Mesh Space Rotation Blend 和 Mesh Space Scale Blend 选项，我尤其关心计算细节，需要看看源码，用公式把这个 blending 表示出来
* 我实际试了一个例子，在三人称模板中用 layered blend per bone 混合 base pose 为 idle 的第 0 帧和 base pose 0 为 run fwd 第 0 帧，感觉开启 Mesh Space Rotation Blend 选项后的结果更符合预期。应该说，开启该选项后，混合后的结果更贴近单纯 run fwd 输出的结果。我目前的解释是因为 Mesh Space 的混合会考虑父节点的效果。例如我设置从关节 spine_02 开始混合，如果为 local space 的混合，那么在 spine_02 处混合后，最终 spine_02 的关节的矩阵应该还有乘以父节点等等的旋转结果，但是由于是从 spine_02 开始混合的，它以上的变换完全丢失了，因此最终看到的结果差异很大，但如果是 mesh space 的混合，是先算出 spine_02 在 mesh space 下的变换矩阵再进行混合，由于这个变换矩阵已经考虑过 spine_01 这些父关节的变换了，因此得到了一个与原来的位姿更接近的结果
* 但上面的理解无法解释为什么我开启 Mesh Space Rotation Blend 后，将 blend 的关节从 spine_02 下调到 spine_03 后，动画中人物手的位置发生了移动。因为根据上面的理解，节点的 mesh space 变换矩阵不依赖于设置的混合的位置才对
* 另外一个问题，我将 layered blend per bone 中的 bone 设置为 root，且 blend pose 0 的权重设置为 1，得到的结果就和 blend pose 0 完全一样了。这个应该还好理解，这说明它就是做一个纯粹的 blend，而不是 additive 那种，所以权重设置为 1 就表示完全地使用 blend pose 0 的结果
* layered blend per bone 的 Curve Blend Option 选项是怎么用的
#### Blending Space
TODO：理解 2D blending space
#### Sync Group
TODO：感觉文档 [Sync Groups](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-sync-groups-in-unreal-engine) 是讨论对 blending 进行细粒度的控制的
TODO：animation notify 中有一类是 sync marker，在 MM_Run_Fwd 中出现了，这是干嘛的
#### Additive Animation
TODO：添加 section 时显示 Animation Asset  MM_Land has an additive type AAT_LocalSpaceBase that does not math the target AAT_None 是什么意思
Animation Sequence 的 AdditiveAnimType 设置有 None，Local Space，Mesh Space 这三个选项，而对于 MM_Land 这个 Local Space 的 additive animation 而言，它有 Base Pose Type 和 Ref Frame Index 这些选项，这些选项都是啥含义
### Data in Animation Sequence
TODO: 根据文档 [Animation Curves](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-curves-in-unreal-engine)，curve 的名称是存在 skeleton 里的，那 curve 的值呢？我觉得是放在 animation sequence 里的。那不同的 animation sequence 用同一个 curve 名称，但可以有不同的值吗？为啥要这样设计
TODO: 我在 animation blueprint 中使用 animation curve 为啥总是返回 0 呢？应该如何使用 animation curve？本来这也很奇怪，在 animation sequence 中定义 curve 的值，但是 animation blueprint 又不与单一的 animation sequence 进行绑定，它怎么知道该用哪个 curve 呢
### Control Rig
TODO：什么是 control rigs，第三人称模板中是如何做到动画紧贴地面的（依据人物所处的环境，动画实际的骨骼参数略有不同）
### Skeletal Mesh LOD
TODO：文档 [Skeletal Mesh LODs](https://dev.epicgames.com/documentation/en-us/unreal-engine/skeletal-mesh-lods-in-unreal-engine?application_version=5.4)
### Content Example
接着看看 Content Example 的 basics 部分
TODO：跳过了 1.2 节的 animation mirroring
TODO：1.3 节的 root motion，为啥一个有 root motion，一个没有 root motion，如何根据 skeletal mesh 找到正在播放的动画，root motion data 从哪提取出来的
TODO：如何查看动画的关键帧数目