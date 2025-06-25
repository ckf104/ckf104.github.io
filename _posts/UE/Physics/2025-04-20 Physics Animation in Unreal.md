`UPhysicalAnimationComponent`：从源码来看这玩意就是设置了一个 kinematic 的物理角色（包含哪些关节由用户控制），这个 kinematic 的物理角色的 target 是当前的 animation pose，然后设置 constraint，使得这些用户设置的关节的物理 pose 会朝着 animation pose 移动

`UPhysicsHandleComponent`：这个 KinematicHandle 到底起个什么样的作用，为啥我读取它的 physics pose 一直不变呢（即使 target transform 一直在变）

`UPhysicsConstraintComponent`

`FPhysicsActorHandle`，`FPhysicsConstraintHandle`，

`FSuspensionConstraint`，`FJointConstraint`

文档 [Physics Components](https://dev.epicgames.com/documentation/en-us/unreal-engine/physics-components-in-unreal-engine) 中列举了 unreal 中的 physics component

Physics Asset，Physical Material

`URadialForceComponent`

TODO：这个 body instance 中的 weld 是什么意思，把多个 body instance weld 到一起意味着什么 

TODO：bUpdateKinematicFromSimulation 选项是什么意思

TODO：这个 `FPhysicsAggregateHandle` 类型是什么，`Aggregate` 是多个物理 actor 的聚合？这意味着什么？


[Physics Animation in Uncharted 4: A Thief's End](https://www.youtube.com/watch?v=7S-_vuoKgR4) 中讨论了两种驱动方式
Powered Constraint Controller： Tries to drive the rigid bodies to the desired pose by using the motors of the powered constraints that attach those rigid bodies.（Works in local space）

Rigid Body Controller：Tries to drive the rigid bodies of the ragdoll to the desired pose by setting their linear and angular velocities.(Works in world space)

这里使用 local space 或者 world space 会产生什么样的区别，在 UPhysicalAnimationComponent 中也有一个 bLocalSimulation 的选项，但我也没看出来是什么意思（我感觉不也用的是世界坐标吗？）
### Physics Animation Overview
physics asset 决定了 skeletal mesh 在物理世界的碰撞表示，物理属性和各个关节的约束。`FBodyInstance` 中包含 `InstanceBodyIndex` 和 `InstanceBoneIndex`，后者是这个 body instance 对应的 bone 在 skeleton 中的 bone 编号，而前者是 skeletal mesh 的 physics asset 中的 body 编号，用来索引 skeletal mesh component 的 `Bodies` 字段

在 physics asset editor 中可以设置各个关节的 `UBodySetupCore` 的 `PhysicsType` 字段，它有三种取值
```c++
UENUM()
enum EPhysicsType : int
{
	/** Follow owner. */
	PhysType_Default UMETA(DisplayName="Default"),
	/** Do not follow owner, but make kinematic. */
	PhysType_Kinematic	UMETA(DisplayName="Kinematic"),
	/** Do not follow owner, but simulate. */
	PhysType_Simulated	UMETA(DisplayName="Simulated")
};
```
`Simulated` 和 `Kinematic` 分别表示这个关节做和不做物理模拟，`Default` 表示由 skeletal mesh component 中的设置，也即它的父类 primitive component 中的 body instance 的 `bSimulatePhysics` 字段决定是否要做物理模拟

每一帧的物理模拟完成后，`USkeletalMeshComponent::PerformBlendPhysicsBones` 会将 animation pose 和 physics pose 在 bone space 下混合，得到最终 render 的 pose，每根骨骼的混合权重由 body instance 的 `PhysicsBlendWeight` 字段决定

skeletal mesh component 也提供了许多 API 来在运行调整物理模拟的设置
* `SetAllBodiesBelowSimulatePhysics` --> 设置 body instance 是否进行物理模拟
* `SetAllBodiesBelowPhysicsBlendWeight` --> 设置 body instance 的 `PhysicsBlendWeight`
* `SetConstraintProfile` --> 切换 physics asset 的 constraint 设置

对于 simulated bone，它的物理位置受关节约束和物理规律控制，而对于 kinematic bone，默认情况下它会不断朝着 animation pose 设置的 bone 位置移动。这个行为由 `KinematicBonesUpdateType` 字段控制。如果是默认值 `SkipSimulatingBones`，在 animation pose 更新完成后，在 `USkeletalMeshComponent::PostAnimEvaluation` 中会调用 `USkeletalMeshComponent::UpdateKinematicBonesToAnim`，这个函数会将所有的 kinematic bone 的 kinematic target 设置为 animation pose 中 bone 的世界坐标（此时这一帧的物理模拟还未开始），但如果设置为 `SkipAllBones`，则 kinematic bone 默认保持不动，不会与 animation pose 同步

TODO：不太理解的地方是，如果一部分的 bone 是 simulating physics 的，另一部分是 kinematic 的，kinematic bone 在连接处会给 physics 的 bone 怎样的力？这个力又是如何计算的？（想了想，好像也不太需要特殊的处理，因为有 constraint 约束，当 kinematic bone 被动画驱动时，simulated bone 自然也会跟着动）

TODO：解释 `USkeletalBodySetup` 的 animation profile
TODO：解释 `USkeletalMeshComponent::UpdateRBJointMotors`
### 一些其它的选项
`PhysicsTransformUpdateMode`：它的默认值为 `SimulationUpatesComponentTransform`，这表示物理模拟会更新 component to world transform，更新的逻辑在 `UPrimitiveComponent::SyncComponentToRBPhysics` 中，就是物理模拟中 root 的变换改变了 delta，就会将 skeletal mesh component 的 component to world transform 相应地改变 delta
```c++
UENUM()
namespace EPhysicsTransformUpdateMode
{
	enum Type : int
	{
		SimulationUpatesComponentTransform,
		ComponentTransformIsKinematic
	};
}
```
而如果设置它的值为 `ComponentTransformIsKinematic`，那么 skeletal mesh component 的 component to world transform 不受物理模拟的影响

`bDeferKinematicBoneUpdate`：我们前面提到过，在 animation pose 确定后，会调用 `UpdateKinematicBonesToAnim` 将 animation pose 同步给 kinematic bone。但同步的情况不止于此。例如 skeletal mesh component 的 component to world 变换发生变化时，on update transform 回调中里也会调用 `USkeletalMeshComponent::UpdateKinematicBonesToAnim`，给 kinematic bone 同步新的坐标，`bDeferKinematicBoneUpdate` 的默认值为 false，如果它为 true，那么这个同步就会推迟到物理模拟开始时（避免重复的同步）

`bUpdateMeshWhenKinematic`：控制 kinematic bone 是否参与 `PerformBlendPhysicsBones` 中的 bone 混合

TODO：body instance 的 `bUpdateKinematicFromSimulation`：我勾选和不勾选没看出来有啥影响？
TODO：[Welding Physics Bodies in the Physics Asset Editor](https://dev.epicgames.com/documentation/en-us/unreal-engine/welding-physics-bodies-in-unreal-engine-by-using-the-physics-asset-editor)：为什么需要 welding physics bodies？
### Physical Animation Component
TODO：解释 `USkeletalMeshComponent::UpdateRBJointMotors`
TODO：解释 physical animation component 的工作原理，比较 local simulation 和 world simulation
### Physics in Animation Blueprint
[Anim Dynamics](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-blueprint-animdynamics-in-unreal-engine) 和 [RigidBody](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-blueprint-rigid-body-in-unreal-engine) 这俩动画节点也和物理模拟有些关系，可以看看
### Debug
在 physics asset editor 中，ctrl + 鼠标右键可以拖动骨骼（或者说给指定骨骼施加力？）
在 PIE 模式下，SHOW PREPHYSBONES 命令可以显示 animation pose，方便 debug



### RagDoll
[Ragdolling and how to recover from it](https://dev.epicgames.com/community/learning/tutorials/mvvL/unreal-engine-ragdolling-and-how-to-recover-from-it)
关闭 skip first update transition？测试一下效果
slomo 0.5 减速，可以更容易看清楚哪里出了问题（slow motion 的意思）
不同强度的 angular motor 对 ragdoll 的姿势有什么影响
进入 ragdoll 后的 camera 控制（或者说控制 capsule 的位置？）