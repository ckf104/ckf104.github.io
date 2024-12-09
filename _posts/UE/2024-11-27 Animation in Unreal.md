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
### Skeletal Mesh
对应 `USkeletalMesh` 类，它包含一个指向 skeleton 的指针，表示这个 mesh 对应的 skeleton
```c++
FReferenceSkeleton RefSkeleton;
```
TODO：这个 `RefSkeleton` 和它对应的 skeleton 的 `ReferenceSkeleton` 结构并不完全一样，为什么
### Animation Sequence
对应 `AnimSequence` 类，每个 animation sequence 都有个指向 skeleton 的指针，表示这个 animation 和哪个 skeleton 关联的

### Content Example
接着看看 Content Example 的 basics 部分
TODO：跳过了 1.2 节的 animation mirroring
TODO：1.3 节的 root motion，为啥一个有 root motion，一个没有 root motion，如何根据 skeletal mesh 找到正在播放的动画，root motion data 从哪提取出来的