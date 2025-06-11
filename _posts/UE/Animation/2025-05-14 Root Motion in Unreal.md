动画部分的 root motion 逻辑只是根骨骼移动了，但是 skeletal mesh component 的 transform 还是没有移动

TODO：但是如果加上 character movement component，就发现 skeletal mesh component 和 capsule 的坐标都正确更新了，解释原因

TODO：root motion content example 中 MM_Death_Front_03 和 MM_Death_Front_03_ExtractedRM 有啥区别，一个是 root 的 bone transform 在变，一个是 root 的 mesh relative transform 在变
### Overview
root motion 就是动画资产的根骨骼的变换。在动画蓝图运行时如果要提取 root motion，那么根骨骼的变换就被提取到 `UAnimInstance` 的 `ExtractedRootMotion` 字段中，而不会参与 bone transform 的计算。character movement component 组件会使用提取出的 root motion，计算胶囊体新的世界坐标（在动画编辑器中，就会看到 root bone 的 bone transform 不变，但是 mesh relative transform 在不断变换）

有几个因素会影响动画蓝图运行中是否要提取 root motion
* `UAnimSequence` 的 `bEnableRootMotion` 字段
* `UAnimInstance` 的 `RootMotionMode` 字段

当 `UAnimSequence` 的 `bEnableRootMotion` 为 false 时，不会提取 root motion，因此如果动画中包含根骨骼变换，就会表现出人物在移动，但是胶囊体没移动的状态（在动画编辑器中，就会看到 root bone 的 bone transform 在不断变换，但是 mesh relative transform 没有变化）

当 `UAnimSequence` 的 `bEnableRootMotion` 为 true 时，是否提取 root motion 依赖于`UAnimInstance` 的 `RootMotionMode` 字段
* `NoRootMotionExtraction`：不提取 root motion
* `IgnoreRootMotion`：提取 root motion 但是不使用它，就相当于动画没有 root motion
* `RootMotionFromEverything`：从所有在播放的动画资产中提取 root motion
* `RootMotionFromMontagesOnly`：只从 montage 中提取 root motion

如果希望禁用个别动画的 root motion，可以将 `UAnimSequence` 的 `bForceRootLock` 设置为 true
### Root Motion Extraction
#### Asset Player 中的 Root Motion
在 `UAnimSequence::HandleAssetPlayerTickedInternal` 中会将根骨骼的变换提取出来，设置到 `FAnimAssetTickContext` 的 `RootMotionMovementParams` 中，随后在 `FAnimSync::TickAssetPlayerInstances` 函数中累积到 `FAnimInstanceProxy` 的 `ExtractedRootMotion` 字段中 

后续的 `UAnimSequence::GetBonePose` 调用 `DecompressPose` 来根据当前的播放进度获取骨骼 pose，`DecompressPose` 会检查是否要提取 root motion，如果是，那么将提取出的根骨骼 transform 设置为空
#### Montage 中的 Root Motion
在 `FAnimMontageInstance::Advance` 步进时也会提取 montage 中 animation asset 的 root motion，所有 slot track 上的 root motion 都会提取，但是只有 slot track 0 上的 root motion 会作用于角色移动。并且同一时刻只能有一个 montage 的 root motion 生效（`UAnimInstance` 的 `RootMotionMontageInstance` 字段），其它 slot track 或者其它的 montage 的 root motion 信息会被提取，但是不会作用到胶囊体的移动上

取决于 `RootMotionMode` 是 `RootMotionFromEverything` 还是 `RootMotionFromMontagesOnly`，montage 的 root motion 信息会存放在 `UAnimInstance` 的 `RootMotionBlendQueue` 中或者 `ExtractedRootMotion` 中

最后 `UAnimInstance::PostUpdateAnimation` 中将 `FAnimInstanceProxy` 的 `ExtractedRootMotion` 和 `RootMotionBlendQueue` 中的 root motion 信息都合并到自己的 `ExtractedRootMotion` 字段中
### Root Motion Consumption
在 `UCharacterMovementComponent::TickCharacterPose` 中触发 tick pose 后，调用 `USkeletalMeshComponent::ConsumeRootMotion` 将这一帧的 root motion 信息存放到自己的 `RootMotionParams` 字段中

后续速度的计算不再根据当前的 `Acceleration`（对应用户输入的 `InputVector`），而是使用 `RootMotionParams` 中的位移除以这一帧的 delta time。有了速度后，具体的移动还是遵循 Movement Component in Unreal 中的讨论。移动完成后，再将 root motion 的旋转叠加到当前胶囊体的旋转上
### Root Motion 的计算
一开始看到 root motion 的 accumulate 有些奇怪，因为在 UE 中 transform 相乘时，乘在左边的 transform 会先对坐标进行变换。但是按道理来说，accumulate 上来的 transform 显然应该在后边进行变换
```c++
	void Accumulate(const FTransform& InTransform)
	{
		if (!bHasRootMotion)
		{
			Set(InTransform);
		}
		else
		{
			RootMotionTransform = InTransform * RootMotionTransform;
			RootMotionTransform.SetScale3D(RootMotionScale);
		}
	}
```
后面发现原因在于 `UAnimSequence::ExtractRootMotionFromRange` 中最后返回的 root motion 为
```c++
	// Transform to Component Space
	const FTransform RootToComponent = RootTransformRefPose.Inverse();
	StartTransform = RootToComponent * StartTransform;
	EndTransform = RootToComponent * EndTransform;

	return EndTransform.GetRelativeTransform(StartTransform);
```
而不是 `StartTransform` 的逆变换乘以 `EndTransform`

究其原因，因为在 `USkeletalMeshComponent::ConvertLocalRootMotionToWorld` 中计算要将 skeletal mesh 在 model space 中变换 root motion 对应的 transform，整个 actor 在 world space 下需要如何变换时，需要将原来的 skeletal mesh 中包含的 `StartTransform` 剔除出去，替换为新的 `EndTransform`，root motion 的 transform 以 `EndTransform` 乘以 `StartTransform` 的逆变换的形式表达计算会更方便一些

TODO：解释 mirror axis 对 root motion 的影响

TODO：看看 [RootMotion详解](https://zhuanlan.zhihu.com/p/74554876)，解释 root motion 的网络同步和非动画的 root motion