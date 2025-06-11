### Translation Retargeting
UE 的 translation retargeting 处理的是骨骼结构相似这种简单情况的 retargeting。我们首先假设需要 retargeting 的两个 skeleton 的骨骼名称和层级结构完全一致
#### Deal with different Reference Pose
这里的 reference pose 是说当 skeleton 每个关节的 rotation 都是 identity 时，skeleton 的 pose 形状（我感觉 UE 的 skeleton 都比较像 I pose，这样子关节的 translation 通常是沿着父关节的 X 轴方向）。如果两个 skeleton 它们的 reference pose 不同，那么要变换到一个给定的 pose，这俩 skeleton 的 rotation 是不同的

不妨假设我们有两个 skeleton 在 A pose 下的各个关节的 rotation。现在又知道对于给定的 pose，source skeleton 的 joint rotation，现在推导 target skeleton 的 joint rotation。下面的推导主要参考了 Games105 的 Lec4

对于一个给定的关节，我们设在 source skeleton 和 target skeleton 的 A pose 下，它的 model space rotation 为 $C_S$ 和 $C_T$，然后在新的 pose 下的 model space rotation 为 $S$ 和 $T$。由于在 A pose 和新的 pose 中，这些变换使得两个 skeleton 在 model space 中的位姿是一致的，因此对于任何一个点 P，假设它在两个 skeleton 的给定关节的局部坐标系下的坐标为 $P_{T}$ 和 $P_S$，那么有
$$
\displaylines{
C_S*P_S = C_T*P_T \\
S*P_S = T*P_T
}
$$
由于上式对任意点 P 都成立，因此有
$$
T*C_T^{-1} = S*C_S^{-1}
$$
我们需要的是 bone space 中变换的对应关系，因此再考虑这个给定的关节的父关节，设它在两个 skeleton 的 A pose 中的 model space rotation 为 $C_{SP}$ 和 $C_{TP}$，在新的 pose 下的 model space rotation 为 $S_P$ 和 $T_P$，同样有
$$
T_P*C_{TP}^{-1} = S_P*C_{SP}^{-1}
$$
记给定关节在两个 skeleton 的新 pose 下的 bone space 中的变换为 $T_L$ 和 $S_L$，有
$$
T_L = T_P^{-1}*T,\quad S_L = S_P^{-1}*S
$$
代入得到
$$
T_L = C_{TP}^{-1}*C_{SP}*S_{L}*C_{S}^{-1}*C_{T}
$$
这就是我们需要的 rotation 变换关系式。对于 bone space 的加性动画而言，它记录的 rotation 是两个 pose 的 joint rotation 间的差值。类似地记给定关节在两个 skeleton 中的加性 rotation 为 $T_{LA}$ 和 $S_{LA}$，我们有
$$
\displaylines{
T_{L1} = C_{TP}^{-1}*C_{SP}*S_{L1}*C_{S}^{-1}*C_{T} \\
T_{L2} = C_{TP}^{-1}*C_{SP}*S_{L2}*C_{S}^{-1}*C_{T} \\
T_{LA} = T_{L2}*T_{L1}^{-1} = C_{TP}^{-1}*C_{SP}*S_{LA}*C_{SP}^{-1}*C_{TP}
}
$$
类似地，可以推出不需要对 mesh space 中的加性动画的 rotation 进行任何修正

然后是 translation 的修正，对任意给定的关节，假设在两个 skeleton 中，该关节相对于父节点的 translation 分别为 $P_T$ 和 $P_S$，然后父节点的 rotation 分别为 $T_P$ 和 $T_S$，因此 $T_P*P_T = S_P*P_S$，因此（容易知道，对于加性动画，translation 仍然是下面的修正公式）
$$
P_T = C_{TP}^{-1}*C_{SP}*P_S
$$
UE 中实现这些逻辑的代码见 `FSkeletonRemapping::GenerateMapping`。在 `DecompressPose` 中提取中 animation sequence pose 后，会使用 `FSkeletonRemapping` 中预计算出的修正项，对提取出的 pose 进行修正
#### Deal with Different Translation
由于不同 skeleton 的关节长度可能不一致，所以我们在对 ref pose 的不同进行修正后，还需要根据 skeleton 的长度进行修正。UE 定义了五种处理 translation 的方式
```c++
/** Bone translation retargeting mode. */
UENUM()
namespace EBoneTranslationRetargetingMode
{
	enum Type : int
	{
		/** Use translation from animation data. */
		Animation,
		/** Use fixed translation from Skeleton. */
		Skeleton,
		/** Use Translation from animation, but scale length by Skeleton's proportions. */
		AnimationScaled,
		/** Use Translation from animation, but also play the difference from retargeting pose as an additive. */
		AnimationRelative,
		/** Apply delta orientation and scale from ref pose */
		OrientAndScale,
	};
}
```
Skeleton 的 `BoneTree` 字段保存了每个 bone 的 translation retargeting mode
```c++
	/** Skeleton bone tree - each contains name and parent index**/
	UPROPERTY(VisibleAnywhere, Category=Skeleton)
	TArray<struct FBoneNode> BoneTree;
```
具体每种 translation retargeting mode 如何工作的可以参考 `DecompressPose` 提取 animation sequence pose 后的修正处理

TODO：解释 `AnimationRelative` 和 `OrientAndScale` 这两种 mode

TODO：解释文档 [Animation Retargeting](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-retargeting-in-unreal-engine) 中建议 Root Bone, IK Bones, weapon bones 使用 Animation mode。以及 Retarget Manager 的作用
```c++
	/** Serializable retarget sources for this skeleton **/
	TMap< FName, FReferencePose > AnimRetargetSources;
```

TODO：右键点击 animation sequence，出现 retarget animation 选项，这个 retarget 是 IKRig 插件实现的