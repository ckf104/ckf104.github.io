TODO：区分 `NM_Standalone` 和 `NM_DedicatedServer` 等，以及
```c++
UENUM()
enum ENetRole
{
	/** No role at all. */
	ROLE_None,
	/** Locally simulated proxy of this actor. */
	ROLE_SimulatedProxy,
	/** Locally autonomous proxy of this actor. */
	ROLE_AutonomousProxy,
	/** Authoritative control over the actor. */
	ROLE_Authority,
	ROLE_MAX,
};
```

### Note 1
Flow
* 服务器启动，`UEngine::LoadMap` 打开地图后 world::listen，创建 `UNetDriver`
* 客户端启动，`UEngine::Browse` 中创建 `UPendingNetGame` 和 `UNetDriver`，与服务器建立连接，通过 control channel 与服务器交互 control message，默认情况下交互的 control message 见 [UE5 网络剖析(三) 登录](https://yuerer.com/UE5%20%E7%BD%91%E7%BB%9C%E5%89%96%E6%9E%90(%E4%B8%89)%20%E7%99%BB%E5%BD%95/)，这里客户端从服务器获得需要打开的 map
* 后续客户端的 tick 时加载该 map，加载完成后 `UPendingNetGame` 的 `UNetDriver` 迁移到新的 world 中。然后客户端会创建本地的 player controller（注意 player controller 不会 replicate），最后向服务器发送 `NMT_Join`
* 服务器收到 `NMT_Join` 后，创建 player controller 和 character，这里会设置 player controller 的 `bReplicates` 为 true，这里的 player controller 对应的 `UPlayer` 就不再是 `ULocalPlayer`，而是 `UNetConnection`
* character replication 给 client

character 和 game state base，player controller 都是 breplicate 为 true，会从服务器同步到客户端。客户端在加载完地图后会生成一个 place holder 的 player controller，在新的 player controller 同步过来后，`APlayerController::OnActorChannelOpen` 中会将 place holder 的 player controller 析构掉，然后设置 local player 指向新的 player controller，并且设置 net connection 的 `OwningActor` 为该 player controller（如果客户端有多个 player controller，那么 `NetPlayerIndex` 为 0 的作为 net connection 的 `OwningActor`）

在服务器这端，收到客户端的 join 信息

APlayerState 会同步，然后 game mode 不同步
### Note 2：关于 role 和 remote role 的设置
对于静态的 actor，`ULevel::InitializeNetworkActors` 在客户端的逻辑会为每个 actor 调用 `AActor::ExchangeNetRoles`，这样就保证客户端中 actor 与服务器上的 actor 的 role 匹配了（注意，非 replicated 的静态 actor 在客户端上的 role 是 none，服务器上是 Authority）

在 actor 的构造函数中设置了 role 的默认值为 Authority，而在 `AActor::PostInitProperties` 中根据当前的 `bReplicates` 设置 remote role 为 simulated proxy 或者 none

`AActor::PostSpawnInitialize` 中会调用 `AActor::ExchangeNetRoles`，如果在客户端上且是服务器同步过来的 actor，交换 role 和 remote role 的值，保证客户端中 actor 与服务器上的 actor 的 role 匹配
### Note 3
每个有 net guid 的 actor 的 outer 也有 net guid

看起来 UE 会区分静态对象和动态对象，静态对象大概是 CDO 以及 map 上本来就有的，而动态对象是运行时 spawn 创建出来的

静态对象的 net guid 传过去后不会创建新的 actor，客户端会根据传递的路径找到该对象，将其和收到的 Net GUID 关联起来，这部分的逻辑见 `UPackageMapClient::ReceiveNetGUIDBunch`

对于新对象而言，会创建对应的 actor channel，然后 `UPackageMapClient::SerializeNewActor` 中创建新的 actor，
### Note 4
`UNetDriver::ServerReplicateActors`

`ServerReplicateActors_PrepConnections`：更新每个 net connection 的 view target

`ServerReplicateActors_BuildConsiderList`：根据一些条件筛选需要同步的 network actor，通过的筛选的加入 consider list，并调用这些 actor 的 `CallPreReplication` 函数

`ServerReplicateActors_PrioritizeActors`：对 consider list 中的 actor 进行优先级排序（每个 connection 都要排一次）
### Note 5：push model
Push Model，看看 [UE4网络同步-PushModel](https://zhuanlan.zhihu.com/p/534300330)

[UE 网络同步进阶之路](https://blog.csdn.net/qq_52179126/article/details/138967260) 对 push model 谈得更多一些，讨论了 `COND_Custom` 是怎么同步的

TODO：理解清楚 replication 的流程，谁负责为 replication 为 true 的 actor 同步
TODO：初始的 character 和 player controller 的创建
TODO：如果有两张 map，每张 map 都有玩家，那服务器上是同时有两个 world 在跑？还是说我可以开两个服务器，每个服务器跑一个 map？
TODO：指针是要怎么 replicate，比如 actor 的 owner，pawn 的 owner 是 player controller，这又是怎么同步的
TODO：子对象是怎么同步的，character 的所有子对象都同步了吗（不然服务器如何跟踪 character 的 view 来计算 relevancy），control rotation 又是怎么同步的
TODO：区分 Replicates 和 `Replicate Movement`，看看 [这篇](https://www.cnblogs.com/AnKen/p/8602233.html) 中做的实验
TODO：为什么 Actor 的 Role 和 Remote Role 也是 replicated，测试一下如果改变 server 端的 role 会发生什么事
TODO：解释服务器上的 UNetConnection 的 `OwningActor`，梳理 actor replication 流程
### Note 6: Actor Movement Replication and Character Movement Component Sync
TODO

### Note 7：Camera Views Replication
`APlayerCameraManager` 的 `bUseClientSideCameraUpdates` 默认为 true，此时客户端会把 camera 的数据同步给服务器，见 `APlayerController::ServerUpdateCamera`

那如果 `bUseClientSideCameraUpdates` 为 false 呢？看起来 character movement component 会把 control rotation 同步给 player controller....见 `UCharacterMovementComponent::ServerMove_PerformMovement`




[网络同步原理深入（下）原理分析](https://zhuanlan.zhihu.com/p/55596030) 中讨论了 `FNetworkGUID` 与指针同步的关系


参考
* [UE5 网络剖析(三) 登录](https://yuerer.com/UE5%20%E7%BD%91%E7%BB%9C%E5%89%96%E6%9E%90(%E4%B8%89)%20%E7%99%BB%E5%BD%95/)
* [网络同步原理深入（下）原理分析](https://zhuanlan.zhihu.com/p/55596030)
* [这篇](https://www.cnblogs.com/AnKen/p/8602233.html)
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