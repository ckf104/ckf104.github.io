解释 animation track 上的各种 notify：sync marker，animation asset 中的 notify，montage notify？

以下的链接基本把 animation notify 的方方面面都讲清楚了
* [Animation Notifies](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-notifies-in-unreal-engine)
* [UE4/UE5 动画通知AnimNotify AnimNotifyState源码解析](https://zhuanlan.zhihu.com/p/664976581)
* [UE 动画系统框架源码解析](https://zhuanlan.zhihu.com/p/673924647) 

TODO：解释当 notify 用在 montage 上时，多出来的 Link Method 选项
### Notes
montage 的 notify 和组成它的 sequence 的 notify 都会触发，见 `FAnimMontageInstance::HandleEvents`

notify 按调用方式可以分为三类
* 普通的 notify：会调用 `UAnimNotify` 类的回调函数，`FAnimNotifyEvent` 中 `Notify` 字段非空
* notify state：会调用 `UAnimNotifyState` 类的回调函数，`FAnimNotifyEvent` 中 `NotifyStateClass` 字段非空
* skeleton notify：根据名称，通过反射调用 `UAnimInstance` 中相应的函数，`FAnimNotifyEvent` 中 `Notify` 和 `NotifyStateClass` 字段都为空（稍微有些区别的是，anim sequence 的 skeleton notify 名称存储在 skeleton 中，而 state machine 中 transition rule 和 state 的 notify 存储在 anim generated class  中）

如果按照调用时机可以分为两类
* queue
* branch point（仅在 montage 中适用）
### Graph Node Functions
从 [Node Functions](https://dev.epicgames.com/documentation/en-us/unreal-engine/graphing-in-animation-blueprints-in-unreal-engine) 的文档来看，它主要是方便逻辑的拆分。对于一整个动画蓝图而言，同一时刻可能只有一小部分的动画节点是活跃的，因此也只有一部分的计算逻辑需要执行。传统的做法是用户在 update function 中写一堆的 if else，根据当前的状态进行相应部分逻辑的计算，现在引入 [Node Functions](https://dev.epicgames.com/documentation/en-us/unreal-engine/graphing-in-animation-blueprints-in-unreal-engine) 后，那我可以把这个节点对应的计算逻辑直接写到这个 node 的 update function 里，而不再需要写 if else 了

另外一个我觉得更重要的作用是做细粒度的控制，因为
TODO：解释每个 graph node 上的 On Initial Update，On Become Relevant，On Update 函数，对于状态机中的 state 的 output Animation pose 而言，它还存在额外的 On State Entry，On State Fully Blended In 等函数。不过这些函数要求是 thread safe 的，是在执行动画蓝图的线程上调用的，不知道有什么作用。一个相关的讨论 [UE 5.3 Animation blueprint “The recommended approach is to use the anim node function versions”](https://forums.unrealengine.com/t/ue-5-3-animation-blueprint-the-recommended-approach-is-to-use-the-anim-node-function-versions/1298379)

