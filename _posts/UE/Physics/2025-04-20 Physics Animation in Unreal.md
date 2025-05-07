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
### Skeletal Mesh Component 中的物理
`SetAllBodiesBelowSimulatePhysics` --> 设置 body instance 是否激活物理
`SetAllBodiesBelowPhysicsBlendWeight` --> 设置 body instance 的 blending weight
`PerformBlendPhysicsBones` --> 根据 body instance 的 blending weight 来混合 animation pose 和 physics pose，得到最终的渲染 pose

`FBodyInstance` 中包含 `InstanceBodyIndex` 和 `InstanceBoneIndex`，后者是这个 body instance 对应的 bone 在 skeleton 中的 bone 编号，而前者是 skeletal mesh 的 physics asset 中的 body 编号，用来索引 skeletal mesh component 的 `Bodies` 字段

TODO：不太理解的地方是，如果一部分的 bone 是 simulating physics 的，另一部分是 kinematic 的，kinematic 的 bone 在连接处会给 physics 的 bone 怎样的力？这个力又是如何计算的？（我看 content example 中 physical animation level 中的表现挺像那么回事的，就是 kinematic bone 在运动时会给 physics bone 施加力）

TODO：解释 [Using Kinematic Bodies with Simulated Parents](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-kinematic-bodies-with-simulated-parents-in-unreal-engine)，涉及到的选项有
* body instance 的 `bUpdateKinematicFromSimulation`
* body setup core 的 `PhysicsType`  
* skeletal mesh component 的 `PhysicsTransformUpdateMode`
* skeletal mesh component 的 `bUpdateMeshWhenKinematic`

TODO：render 的 pose 是怎么同步给物理模拟的？
