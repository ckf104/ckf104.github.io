
TODO：解释服务器上的 UNetConnection 的 `OwningActor`，梳理 actor replication 流程

### 基本的宏与函数
关于下面这些宏和函数的区分
* `UE_SERVER`
* `UE_GAME`
* `WITH_SERVER_CODE`
* `FPlatformProperties::IsServerOnly`
* `FPlatformProperties::IsGameOnly`
* `FPlatformProperties::IsClientOnly`

参考
* [UE4之宏与预编译指令定义](https://www.cnblogs.com/kekec/p/18208393 "发布于 2024-05-25 16:53")
* [What’s the difference between UE_SERVER and WITH_SERVER_CODE](https://forums.unrealengine.com/t/whats-the-difference-between-ue-server-and-with-server-code/124652)
* [UE4中的网络模式](https://zhuanlan.zhihu.com/p/38074925)

`ServerReplicateActors_ProcessPrioritizedActorsRange`：根据排序好的优先级从高到低，调用 `IsActorRelevantToConnection` 检查相关性，为每个通过检测的 actor 调用 `UActorChannel::ReplicateActor`

### Note H
NetDriver 在创建时的 outer 是 Transient Package。在客户端和服务器上切换地图时，都会把 net driver 销毁掉再重新创建（就是走一套登录流程，服务器 listen，客户端先创建 pending game 然后握手这些）

TODO：文档 [Travelling in Multiplayer](https://dev.epicgames.com/documentation/en-us/unreal-engine/travelling-in-multiplayer-in-unreal-engine) 中讨论了 seamless travel，**试试 在 multiplayer 中 travel world**
### Note M
使用 `Replicated` 以及 `ReplicatedUsing` 标记了的 uproperty 都会带有 `CPF_Net`，actor channel 创建时生成 `FRepLayout` 会用到
### Note V
子对象同步与 actor 同步是类似的，设置 `bReplicates` 为 true，重载 `GetLifetimeReplicatedProps` 函数

scene component 的 relative location / rotation 是同步的，感觉同时开了 root component 的 replicate 和 actor 的 replicate movement 会造成邪恶的后果
### Note S
文档 [Object Replication](https://dev.epicgames.com/documentation/en-us/unreal-engine/replicating-uobjects-in-unreal-engine) 中讨论了如何 replicate 普通的 uobject

### Note Y
[# 关于网络同步的理解与思考](https://zhuanlan.zhihu.com/p/34721113) 中谈到从 package 中加载的对象即使没有标记为 replicate 也是可以跨网络访问的。设想一个 RPC 调用，传递了一个 uobject 指针。TODO：但我有点怀疑这个，因为都是通过 net guid 标识的，是得发送 RPC 时也同步一下 net guid 吗？得试一试才行

TODO：[Replicate Actor Properties](https://dev.epicgames.com/documentation/en-us/unreal-engine/replicate-actor-properties-in-unreal-engine) 中也特地说明了跨网络访问的 uobject 指针。而且对 replication condition 的说明很详细，可以后面再看看

### Note T：Channel 关闭
从 `EChannelCloseReason` 中可以看到有若干 channel 关闭的原因（从 `UActorChannel::CleanUp` 可以看到，客户端的 channel 释放时才会同时析构 actor）
* 当服务器上 actor destroy 时
* 文档 [Actor Relevancy](https://dev.epicgames.com/documentation/en-us/unreal-engine/actor-relevancy-in-unreal-engine) 有说明，如果 actor 在一个 connection 中一段时间不 relevancy，将会关闭这个 connection 里对应的 actor channel
* 文档 [Actor Network Dormancy](https://dev.epicgames.com/documentation/en-us/unreal-engine/actor-network-dormancy-in-unreal-engine) 中讨论了如何设置 actor dormancy（注意，dormant actor 不会再检测 relevancy），当 actor 进入 dormant 时，服务器会关闭 actor channel（具体关闭哪些 connection 的 actor channel 取决于 `ShouldActorGoDormant` 函数）
* 服务器上调用 `AActor::TearOff`。服务器会关闭所有连接中该 actor 对应的 channel，客户端会将该 actor 的 role 设置为 authority（见 `UNetDriver::ClientSetActorTornOff`）

channel 关闭的流程都是先服务器调用 `UActorChannel::Close`，然后 close bunch 到客户端，客户端析构相应的 channel（情况 1 和 2 会析构 actor，3 和 4 则不会），服务器收到客户端的 ack 后，再释放自己的 channel

TODO：解释 `AActor::FlushNetDormancy` 和 `AActor::ForceNetUpdate` 的区别
### Note N
TODO：文档 [Replicated Object Execution Order](https://dev.epicgames.com/documentation/en-us/unreal-engine/replicated-object-execution-order-in-unreal-engine) 中提到一个如果一个 unreliable rpc 在一个 reliable rpc 前调用，那么在远程客户端上这个 unreliable rpc 绝不会再 reliable rpc 后面执行，这是为什么
### Note P
TODO：移动组件的同步，看看 [Networked Movement in the Character Movement Component](https://dev.epicgames.com/documentation/en-us/unreal-engine/understanding-networked-movement-in-the-character-movement-component-for-unreal-engine) 以及 [# 移动组件详解](https://zhuanlan.zhihu.com/p/34257208)

