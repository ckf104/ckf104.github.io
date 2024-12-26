在尝试 [using a static camera in UE](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-a-static-camera-in-unreal-engine) 时看到的一些回调函数

一个是 `Actor::NotifyActorBeginOverlap`，`Actor::NotifyActorEndOverlap`，它们在 actor 中默认是实现是分别调用 `Actor::ReceiveActorBeginOverlap`，`Actor::ReceiveActorEndOverlap` 函数，后者这俩是 `BlueprintImplementableEvent`，可以在蓝图中重载

然后是 `Actor` 的 `OnActorBeginOverlap` 与 `OnActorEndOverlap` 字段，它们是两个动态多播

再者是 primitive component 的 `OnComponentBeginOverlap` 与 `OnComponentEndOverlap` 字段，它们也是两个动态多播

这些函数都是在 `UPrimitiveComponent::BeginComponentOverlap` 和 `UPrimitiveComponent::EndComponentOverlap` 函数中被调用的

从 editor 界面的设置上来看，collision 相关的设置和 physics 相关的设置是分开的。前者专门处理 collision 和 overlap，后者不知道了，但比如 gravity 之类的显然是后者负责的

一些控制 collision 和 overlap 的因素：`bGenerateOverlapEvents` 控制是否能产生 overlap event，`bGenerateOverlapEventsDuringLevelStreaming` 控制在初始加载时是否产生 overlap，以及还有 overlap presets 等等

TODO：解释什么情况下发生 overlap，什么情况下发生碰撞。第一个问题是 box component 为什么在场景中不可见（或许应该整体看看 shape component 是怎么回事），然后是为什么是发生 overlap，而没有发生碰撞。感觉是不是和 volume 这个概念有些关系，[using a static camera in UE](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-a-static-camera-in-unreal-engine) 例子中也将这个 box component 称为 volume

TODO：看下第一人称模板中子弹的碰撞设置，我尤其关心如何设置物体的碰撞模型的。另外，我尝试在场景中设置两把枪，捡起一把枪后，向另一把枪射击子弹，子弹会被枪弹开，那为什么人可以直接走上去捡起来枪，而不是被弹开呢

官方的 collision 文档：[collision-in-unreal-engine](https://dev.epicgames.com/documentation/en-us/unreal-engine/collision-in-unreal-engine?application_version=5.4)