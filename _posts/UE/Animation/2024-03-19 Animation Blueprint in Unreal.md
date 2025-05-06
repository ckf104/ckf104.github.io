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

`USkeletalMeshComponent::InitAnim`
--> `USkeletalMeshComponent::InitializeAnimScriptInstance`
----> `UAnimInstance::InitializeAnimation`
------> `FAnimInstanceProxy::Initialize`
------> `UAnimInstance::NativeInitializeAnimation`
------> `UAnimInstance::BlueprintInitializeAnimation`
------> `FAnimInstanceProxy::InitializeRootNode`
--------> `FAnimInstanceProxy::InitializeRootNode_WithRoot`：从 root graph node 开始（即 output pose），沿着 pose link，为每个 graph node 调用 `FAnimNode_Base::Initialize_AnyThread`
----> `UAnimInstance::NativeBeginPlay`
----> `UAnimInstance::BlueprintBeginPlay`



 