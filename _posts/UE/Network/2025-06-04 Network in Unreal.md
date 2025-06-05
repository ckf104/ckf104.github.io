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


Flow
* 服务器启动，`UEngine::LoadMap` 打开地图后 world::listen，创建 `UNetDriver`
* 客户端启动，`UEngine::Browse` 中创建 `UPendingNetGame` 和 `UNetDriver`，与服务器建立连接，通过 control channel 与服务器交互 control message，默认情况下交互的 control message 见 [UE5 网络剖析(三) 登录](https://yuerer.com/UE5%20%E7%BD%91%E7%BB%9C%E5%89%96%E6%9E%90(%E4%B8%89)%20%E7%99%BB%E5%BD%95/)，这里客户端从服务器获得需要打开的 map
* 后续客户端的 tick 时加载该 map，加载完成后 `UPendingNetGame` 的 `UNetDriver` 迁移到新的 world 中。然后客户端会创建本地的 player controller（注意 player controller 不会 replicate），最后向服务器发送 `NMT_Join`
* 服务器收到 `NMT_Join` 后，创建 player controller 和 character，这里的 player controller 对应的 `UPlayer` 就不再是 `ULocalPlayer`，而是 `UNetConnection`
* character replication 给 client

character 和 game state base 都是 breplicate 为 true，然后得到
APlayerState 会同步，然后 game mode 不同步


TODO：理解清楚 replication 的流程，谁负责为 replication 为 true 的 actor 同步
TODO：初始的 character 和 player controller 的创建
TODO：如果有两张 map，每张 map 都有玩家，那服务器上是同时有两个 world 在跑？还是说我可以开两个服务器，每个服务器跑一个 map？
TODO：指针是要怎么 replicate，比如 actor 的 owner，pawn 的 owner 是 player controller，这又是怎么同步的
TODO：区分 Replicates 和 `Replicate Movement`，看看 [这篇](https://www.cnblogs.com/AnKen/p/8602233.html) 中做的实验
TODO：为什么 Actor 的 Role 和 Remote Role 也是 replicated，以及 owner 也是 replicated 的？为什么 APlayerController 也被同步进来了，还是应该研究清楚什么时候同步，哪些会同步