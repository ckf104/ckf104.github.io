通常的蓝图中，蓝图变量存储在类的末尾（因为在 new obejct 的时候会询问 uclass 需要多少内存，蓝图的 uclass 返回的需要内存的大小除了 C++ 父类的大小还有蓝图变量需要占的存储。这些蓝图变量对应的 FProperty 的偏移就指向 C++ 父类占用的内存后边这块额外的蓝图变量空间

和通常的蓝图类似。动画蓝图资产对应 `UAnimBlueprint` 类，也是 `UBlueprint` 的子类
```c++
class UAnimBlueprint : public UBlueprint, public IInterface_PreviewMeshProvider
```
然后类似地有 `UAnimBlueprintGeneratedClass`
```c++
class UAnimBlueprintGeneratedClass : public UBlueprintGeneratedClass, public IAnimClassInterface
```
通常的蓝图类可以继承自任何 `UObject` 的子类，而动画蓝图类则是需要继承自 `UAnimInstance` 的子类

[4 - Animation Layer Interface and Linked Anim Layers - Bow And Arrow - UE5 Blueprints](https://www.youtube.com/watch?v=WAkiE6rQutU)  Notes

thread safe update function, property access, linked anim graph
### 流程梳理
每个 anim graph node 都是 `FAnimNode_Base` 的子类，它们通常会包含一个或多个 `FPoseLink`（表示 graph node 间的连线），它的 `LinkID` 和 `LinkedNode` 字段指向输入的 graph node
#### 初始化
`USkeletalMeshComponent::OnRegister`
--> `USkinnedMeshComponent::OnRegister`
----> `USkinnedMeshComponent::AllocateTransformData`：分配了 `ComponentSpaceTransformsArray` 和 `BoneVisibilityStates` 的空间，并 将 `bHasValidBoneTransform` 置为 false
--> `USkeletalMeshComponent::InitAnim`：初始化 `ComponentSpaceTransformsArray` 为初始 pose
----> `USkeletalMeshComponent::RecalcRequiredBones`
----> `USkeletalMeshComponent::InitializeAnimScriptInstance`
------> `UAnimInstance::InitializeAnimation`
--------> `FAnimInstanceProxy::Initialize`
--------> `UAnimInstance::NativeInitializeAnimation`
--------> `UAnimInstance::BlueprintInitializeAnimation`
--------> `FAnimInstanceProxy::InitializeRootNode`
----------> `FAnimInstanceProxy::InitializeRootNode_WithRoot`：从 root graph node 开始（即 output pose），沿着 pose link，为每个 graph node 调用 `FAnimNode_Base::Initialize_AnyThread`
------> `UAnimInstance::NativeBeginPlay`
------> `UAnimInstance::BlueprintBeginPlay`

TODO：解释 `USkeletalMeshComponent::RecalcRequiredBones`，required bone 会如何影响后面的 bone 计算
#### Tick
整个 tick 发生在 `USkeletalMeshComponent` 的 tick 函数中，在 `TG_PrePhysics` 阶段执行

`USkeletalMeshComponent::TickComponent`
--> `USkinnedMeshComponent::TickComponent`
----> `USkeletalMeshComponent::TickPose`
------>`UAnimInstance::UpdateAnimation`
--------> `UAnimInstance::PreUpdateAnimation`
----------> `FAnimInstanceProxy::PreUpdate`：为该动画蓝图中包含的每个 graph node 调用它的 `PreUpdate` 函数
--------> `UAnimInstance::UpdateMontage`
----------> `UAnimInstance::Montage_UpdateWeight`：更新 montage 淡入淡出的权重
----------> `UAnimInstance::Montage_Advance`：更新 montage 的播放进度
--------> `UAnimInstance::UpdateMontageSyncGroup`：将 sync group 非空，并且正在淡出的 montage 加入到 sync group 中
--------> `UAnimInstance::UpdateMontageEvaluationData`：将 montage 的播放进度同步给 `FAnimInstanceProxy`，便于后续在 worker thread 访问
--------> `UAnimInstance::NativeUpdateAnimation`
--------> `UAnimInstance::BlueprintUpdateAnimation`
----> `USkeletalMeshComponent::RefreshBoneTransforms`
------> `USkeletalMeshComponent::DoInstancePreEvaluation`
--------> `UAnimInstance::PreEvaluateAnimation`
------> `USkeletalMeshComponent::DispatchParallelEvaluationTasks`：该函数中启动 `FParallelAnimationEvaluationTask` 和 `FParallelAnimationCompletionTask` 两个 graph task，后者依赖于前者，并且在 game thread 上执行。在后者执行完之前，skeletal mesh component 的 tick 函数不会显示执行完成（通过 `FGraphEvent::DontCompleteUntil` API）
--------> `USkeletalMeshComponent::SwapEvaluationContextBuffers`

Notes：在存在 character movement component 时，`USkeletalMeshComponent::TickPose` 实际上是在 character movement component 的 tick 函数中触发的，并且在 `ACharacter::PostInitializeComponents` 中，设置了 tick 依赖，保证 character movement component 的 tick 总是先于 skeletal mesh component 的 tick。如果 `UAnimInstance` 的 `RootMotionMode` 为 `RootMotionFromEverything`，那么 `FAnimInstanceProxy::UpdateAnimation` 和 `UAnimInstance::PostUpdateAnimation` 会在 `UAnimInstance::UpdateAnimation`（game thread 上）提前调用，保证 tick pose 后就已经拿到所有的 root motion 信息了

##### `FParallelAnimationEvaluationTask` 中的执行流
`USkeletalMeshComponent::ParallelAnimationEvaluation`
--> `USkeletalMeshComponent::PerformAnimationProcessing`
----> `FAnimInstanceProxy::UpdateAnimation`
------> `FAnimInstanceProxy::UpdateAnimation_WithRoot`
--------> `UAnimInstance::NativeThreadSafeUpdateAnimation`
--------> `UAnimInstance::BlueprintThreadSafeUpdateAnimation`
--------> `FAnimInstanceProxy::UpdateAnimationNode_WithRoot`：从 root 节点开始，为每个 graph node 调用用户设置的 `InitialUpdate`，`BecomeRelevant`，`Update` 函数，然后调用该 graph node 的 `Update_AnyThread` 函数
----> `USkeletalMeshComponent::EvaluateAnimation`
------> `UAnimInstance::ParallelEvaluateAnimation`
--------> `FAnimInstanceProxy::EvaluateAnimationNode_WithRoot`：从 root 节点开始，递归地为每个 graph node 调用 `Evaluate_AnyThread` 函数，每个 graph node 重载的 `Evaluate_AnyThread` 会根据自己的功能和得到的输入 pose，输出新的 pose
----> `USkeletalMeshComponent::FinalizePoseEvaluationResult`
----> `USkinnedAsset::FillComponentSpaceTransforms`
--> `FAnimInstanceProxy::UpdateCurvesToEvaluationContext`：清空 `AnimationCurves`，然后将得到的 anim curve value 设置到 `AnimationCurves` 中

这表明，蓝图中的 UpdateAnimation 回调最先执行，然后是在 worker thread 上执行 Blueprint Thread Safe Update Animation，再然后是用户在每个 graph node 上设置的 `InitialUpdate`，`BecomeRelevant`，`Update` 函数，最后才 evaluate 每个 graph node 的输出 pose

在 `USkeletalMeshComponent::InitAnim` 中，或者 required bones 更新时（例如 LOD 切换）的 `USkeletalMeshComponent::RefreshBoneTransforms` 都会调用 `USkeletalMeshComponent::RecalcRequiredBones`，它会进一步调用每个 graph node 的 `CacheBones_AnyThread`，通知各个节点骨骼的层级结构更新了

TODO：什么时候 `AnimEvaluationContext.bDoInterpolation` 为 true，它为 true 时会干些啥，相应的 `ParallelDuplicateAndInterpolate` 函数做了什么
##### `FParallelAnimationCompletionTask` 中的执行流
 `USkeletalMeshComponent::CompleteParallelAnimationEvaluation`
 --> `USkeletalMeshComponent::SwapEvaluationContextBuffers`：此时就拿到这个 frame 对应的 bone space transform 和 component space transform 了
 --> `USkeletalMeshComponent::PostAnimEvaluation`
 ----> `UAnimInstance::PostUpdateAnimation`
 ----> `FAnimInstanceProxy::UpdateCurvesPostEvaluation`

#### Physical Animation
`USkeletalMeshComponent` 还有一个 `EndPhysicsTickFunction` ，它在 `TG_EndPhysics` 阶段执行进行收尾，执行流
`USkeletalMeshComponent::EndPhysicsTickComponent`
--> `UPrimitiveComponent::SyncComponentToRBPhysics`：将物理模拟的结果同步回来，使得 `USkeletalMeshComponent` 的 component to world 的 transform 与物理世界保持一致
--> `USkeletalMeshComponent::BlendInPhysicsInternal`
----> `USkeletalMeshComponent::PerformBlendPhysicsBones`：与物理世界的 bone transform 混合，得到最终的 bone space transform 与 component space transform
----> `USkeletalMeshComponent::FinalizeAnimationUpdate`：交换双缓冲，更新子 component 的 transform 和 overlaps
------> `USkeletalMeshComponent::FinalizeBoneTransform`：swap double buffer of component space transform

如果 `ShouldBlendPhysicsBones` 返回 false（即不需要物理动画）则 `USkeletalMeshComponent::FinalizeAnimationUpdate` 将会在 `USkeletalMeshComponent::PostAnimEvaluation` 中被调用
### Modular Characters
根据文档 [Working with Modular Characters](https://dev.epicgames.com/documentation/en-us/unreal-engine/working-with-modular-characters-in-unreal-engine)，源码中出现的 `LeaderPoseComponent` 原来是用作


TODO：[UE 动画系统框架源码解析](https://zhuanlan.zhihu.com/p/673924647) 讲得很全，需要再看看，以及 [UE4 图解动画系统源码](https://zhuanlan.zhihu.com/p/446851284) 也可以看看