### Animation Blending
在 graph node 的 `Update_AnyThread` 从根节点开始递归执行时，会递归地传递每个 graph node 的 blending weight，以最简单的 two way blend 节点为例，如果传递到它这里的权重为 0.5，并且它的混合 alpha 设置为 0.7，那么传递给它的两个输入节点的权重就分别为 0.35 和 0.15 了

当一个 graph node 的权重为 0 时，我们称它的 relevancy 为 false，否则为 true。通常情况下这个 graph node 的 `Update_AnyThread` 和 `Evaluate_AnyThread` 将不再被调用。后续当动画蓝图的输入发生变化，这个 graph node 的权重又大于 0 时，会调用这个 graph node 的 `Initialize_AnyThread` 重新初始化，此后 `Update_AnyThread` 和 `Evaluate_AnyThread` 将会正常调用

但这些函数是否调用取决于祖先节点的设置，仍然以 two way blend 节点为例，用户可以设置它的 `bResetChildOnActivation` 字段，控制 two way blend 是否要在子节点的 relevancy 从 false 变为 true 时，调用子节点的 `Initialize_AnyThread` 函数，而 `bAlwaysUpdateChildren` 字段控制 two way blend 是否要在子节点的 relevancy 为 false 时仍然调用子节点的 `Update_AnyThread`

因此，各个 asset player 本身是对 blending 无感知的，它们只需要在 `Update_AnyThread` 被调用时更新自己的播放进度，在 `Initialize_AnyThread` 时重置播放进度，在 `Evaluate_AnyThread` 时计算当前播放进度对应的 pose 即可。也即，当动画蓝图输入变化，输出的 pose 从 asset player A 播放的 pose 过渡到 asset player B 播放的 pose 时，在这个过渡时期，asset player A 和 asset player B 都正常播放（如果有 sync group，就按照 sync group 的节奏播放）
#### State Machine 中的 Blending
这些 asset player 可能是在某个 state machine 的其中一个 state 里，而 state 之间也可能切换，这里也存在 state 间的 blending。[状态机节点 StateMachine源码分析](https://zhuanlan.zhihu.com/p/376821209) 讲得很好

大致来说，state machine 由 state 和 transition rule 构成。每次 `Update_AnyThread` 调用时，它检查当前的状态是否满足 transition 条件，如果是，就迁移到新的状态，同时在 `ActiveTransitionArray` 的栈顶压入一个新的 transition entry
```c++
	// The set of active transitions, if there are any
	TArray<FAnimationActiveTransitionEntry> ActiveTransitionArray;
```
`ActiveTransitionArray` 记录了当前所有活跃的 transition，会有多个是因为例如我们从 A 迁移到 B 状态，设置的 cross fade duration 是 0.4 秒，可能在这 0.4 秒之间我们又从 B 状态迁移到了 C 状态（当然也允许迁移回 A 状态），那么此时就有两个活跃的 transition 了

那 state machine 输出的 pose 是如何计算的呢？还是假设此时有 A -> B，B -> C 两个活跃的迁移，那么最终 pose 的计算是 A 状态的 pose 和 B 状态的 pose 进行混合（混合权重由对应的 transition entry 当前的 alpha 值决定），混合后的 pose 再与 C 状态的 pose 进行混合，得到最终的输出 pose

Note：对于 A -> B -> A 的迁移情况，仍然是 A 与 B 先混合，混合结果再与 A 混合，而不是计算出 A 和 B 分别的权重，然后一次混合就完了。我想这样设计的主要原因在于多个 rotation 的混合是没有结合律和交换律的，为了避免去歧义就采取了这种混合方式，即使 `FAnimNode_StateMachine::GetStateWeight` 在计算各个 state 的权重时确实是计算的总的权重
#### Montage Blending
用户可以设置 montage 停止播放的规则，`UAnimMontage` 的 `bEnableAutoBlendOut` 字段和 state machine 中 transition rule 的 `bAutomaticRuleBasedOnSequencePlayerInState` 字段非常相似，然后 `BlendOutTriggerTime` 对标 transition rule 的 `AutomaticRuleTriggerTime`。这些字段用于在 montage 播放到末尾时自动停止播放。如果 `bEnableAutoBlendOut` 为 false，那么就需要用户手动停止 montage 的播放（取决于 montage 的 section 连接方式，如果 section 间是一个循环，那么该 montage 就类似于一个循环动画，没又末尾，因此也不会自动停止播放，否则就类似于非循环动画，如果播放完毕还没有停止播放，就呈现最后一帧的状态）

可以将动画蓝图中的 slot 节点理解为一个混合节点，它根据自己的 slot name，找出当前所有在该 slot 上播放的 montage。这样的 montage 可能不止一个，设想我们停止一个在该 slot 上播放的 montage 后，该 montage 开始淡出，同时我们播放新的 montage，如果这两个 montage 有相同的 slot track，那么这两个 montage 加上 slot 节点的 source pose，slot 节点的输出就是这三个 pose 的混合

具体 slot 节点中各个 pose 混合的权重见 `FAnimInstanceProxy::SlotEvaluatePose` 函数，大概的计算方法是，各个 montage 的混合权重由设置的 blending 曲线和当前淡入淡出的时间控制，如果它们的权重之和小于 1，那么剩下的部分就是 source pose 的权重了
#### Curve and Attribute Blending
anim curve 在 blend 时的行为大致是 curve value 的加权求和，这里的权重是 pose weight，如果混合的两个 pose 包含的 curve 不同，不存在的 curve 的值认为是 0（如果是加性动画的 blend 就是将加性动画的曲线值乘以权重叠加到 base pose 上）

有些 graph node 提供了额外的选项自定义混合的行为，例如 layered blend per bone 中可以设置 curve blend option

TODO：解释 anim attribute 的混合行为
#### Blend Space and Blendspace Graphs
TODO：看看 [Unreal 动画系统：从编辑器到Runtime——混合空间 Blendspace节点原理分析](https://zhuanlan.zhihu.com/p/381967985) 以及 [BlendSpace源码执行流程浅析](https://zhuanlan.zhihu.com/p/571226465)

大致的计算流程
* 根据这一帧的输入和历史输入对每一个维度的值进行加权过滤，见 `UBlendSpace::FilterInput`。因此 blend space 中确定动画权重时使用的采样值是一个平滑过滤的值
* 根据采样值获取各个动画的混合权重，见 `UBlendSpace::GetSamplesFromBlendInput`
* 如果设置 blend space 的 Weight Speed 大于 0，或者有 per bone 的平滑设置，那么会调用 `UBlendSpace::InterpolateWeightOfSampleData` 来平滑一下动画的权重（上一帧的动画权重通过 blend space player 的 `BlendSampleDataCache` 字段传入
* 根据 sync group 进行 tick

总结有关动画表现的重要选项
* Wrap Input：如果为 true，那么将对应的输入维度的值视为一个环而不是一个数轴
* Smoothing Time：设置输入的平滑时间
* Axis to Scale Animation：它和 Smoothing Time 紧密相关，输入的 smoothing 导致采样使用的输入值和实际的输入值不一样，对于 speed 这样的属性，这会导致角色滑步，因此设置 Axis to Scale Animation 到 speed 轴上会根据使用的输入值和实际的输入值的差异来调整 play rate 从而避免滑步
* Weight Speed：设置权重的平滑速度
* Smoothing：设置权重的平滑方式，为 true 则使用弹簧模型，false 则是线性插值
### Animation Relevancy and Update
需要解决的问题是如何处理权重为 0 的动画节点。最简单粗暴的办法是正常调用它们的 `Update_AnyThread` 来正常更新播放进度，但这样做太浪费了，因为一个动画蓝图中同一时刻可能只有一小部分的节点处于活跃状态

如果不更新权重为 0 的动画节点，那当该动画节点权重大于 0 时，应该从哪里开始播放呢？在 UE 中有三种可能的处理
* 重新初始化该动画节点，从用户设置的 start position 开始播放
* 从之前的暂停处继续播放
* 如果有 sync group，从 sync marker 指示的位置开始播放

UE 具体采样哪种处理方式依赖于节点类型和用户设置（或者说 UE 做得有点半身不遂）
* 对于状态机内的状态迁移，如果一个状态从不活跃变为活跃，内部的动画节点会重新初始化
* 对于一部分混合节点，例如 two way blend，用户可以设置 Always Update Children 选项使得权重为 0 的动画节点也继续更新，以及设置 Reset Child on Activation 决定是否要在动画节点变为活跃时重新初始化它。但另一些混合节点，例如 blend multi，则没有提供类似的选项，重新变为活跃的动画节点将从暂停处继续播放
### Blending Algorithm
#### Additive Animation
`UAnimSequence` 的 `AdditiveAnimType` 决定该动画资产的类型：普通的动画资产，在 local space 下叠加的动画资产，在 mesh space 下叠加的动画资产
```c++
	/** Additive animation type. **/
	UPROPERTY(EditAnywhere, Category=AdditiveSettings, AssetRegistrySearchable)
	TEnumAsByte<enum EAdditiveAnimationType> AdditiveAnimType;

	/* Additive refrerence pose type. Refer above enum type */
	UPROPERTY(EditAnywhere, Category=AdditiveSettings, meta=(DisplayName = "Base Pose Type"))
	TEnumAsByte<enum EAdditiveBasePoseType> RefPoseType;

	/* Additve reference frame if RefPoseType == AnimFrame **/
	UPROPERTY(EditAnywhere, Category = AdditiveSettings)
	int32 RefFrameIndex;
	
	/* Additive reference animation if it's relevant - i.e. AnimScaled or AnimFrame **/
	UPROPERTY(EditAnywhere, Category=AdditiveSettings, meta=(DisplayName = "Base Pose Animation"))
	TObjectPtr<class UAnimSequence> RefPoseSeq;
```
因为导入的动画由一个个关键帧的 pose 组成，要将导入的动画转化为加性动画，自然需要一个参考 pose，将导入的动画的每一帧 pose 减去参考 pose，就得到了我们要的加性 pose。参考 pose 的类型由 `RefPoseType` 指定，它可以是骨骼的 reference pose，或者本动画或者其它动画的某一帧，也可以是一整段动画作为 ref pose，根据本动画当前的播放进度对应到另一个动画的相应位置，与之对应的 pose 就作为 ref pose

从 `UAnimSequence::GetAnimationPose` 函数的实现上看，在 cook 前 UE 会保留原生的动画数据（`UAnimSequenceBase` 的 `DataModelInterface` 字段），每次我们在编辑器中修改会影响实际的动画 pose 的选项时（例如从普通动画变为加性动画），`UAnimSequence::PostEditChangeProperty` 回调中会启动异步线程计算新的动画 pose，最终存储在 `UAnimSequence` 的 `CompressedData` 字段中。cook 之后应该就只保留 `CompressedData` 了（我想这也是为什么把加性动画的设置放在这里而不放到动画蓝图里，因为这样可以预计算）

根据 `AdditiveAnimType` 是 local space 还是 mesh space，加性动画减去 ref pose 时的方法稍微不同。如果是 local space，那么就在 bone space 下对应的 bone rotation / translation / scale 分别计算 delta 即可。如果是 mesh space，那么在 bone space 系计算 bone translation / scale 的 delta，但是对于 rotatioon，则是将 bone rotation 先转到 model space 下，然后逐 bone 计算 delta，最后也不会将 bone rotation 转回 bone space（这意味着，如果 `AdditiveAnimType` 是 mesh space，则输出的 pose 中 bone rotation 是在 model space 中的，而 rotation 和 scale 是 bone space 中的）
#### Blending
Blending 可以从两个维度上分类：是通常的 blending 还是加性的 blending？blending 在 bone / local space 下进行还是 mesh / model space 下进行

对于通常的 blending，alpha 表示各自混合的权重，translation 都是在 bone space 下进行混合，而 rotation 和 scale 在 bone space 还是 model space 取决于动画节点的设置（例如 `FAnimNode_LayeredBoneBlend` 节点有 `bMeshSpaceRotationBlend` 和 `bMeshSpaceScaleBlend` 设置）。

对于 additive blending，alpha 表示 additive pose 和 identity transform 的混合。translation 和 scale 都是在 bone space 下进行混合，而 rotation 在 bone space 还是 model space 取决于动画节点的设置（例如是 `FAnimNode_ApplyAdditive` 和 `FAnimNode_ApplyMeshSpaceAdditive`，但这通常也需要与动画资产中 `AdditiveAnimType` 相同），混合完成后，在 bone space 下与 base pose 叠加 translation 和 scale，rotation 的叠加空间与之前混合的空间一致

注意，UE 中混合 rotation 时都是使用的 linear lerp
#### Blending Profiles and Masks

TODO：解释文档 [Blend Masks and Blend Profiles](https://dev.epicgames.com/documentation/en-us/unreal-engine/blend-masks-and-blend-profiles-in-unreal-engine)

weight blend profile 中值越大，混合越快。time blend profile 中值越小，混合越快

所有的 blend profiles 和 masks 也都是保存在 skeleton 中的
```c++
	/** List of blend profiles available in this skeleton */
	UPROPERTY(Instanced)
	TArray<TObjectPtr<UBlendProfile>> BlendProfiles;
```

#### Inertial Blending
TODO：解释 Inertial Blending

TODO：解释 anim curve 和 anim attribute 的混合方法