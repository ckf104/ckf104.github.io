
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