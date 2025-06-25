官方文档 [Unreal Interfaces](https://dev.epicgames.com/documentation/en-us/unreal-engine/interfaces-in-unreal-engine) 讲得挺好的，但我有几个地方没看懂
* `execute_xxx` wrapper，是只有用 UFUNCTION 修饰的才有吗，没有 UFUNCTION 修饰函数我没找到对应的 wrapper
* `TScriptInterface` 是个啥，为什么需要它
* 为什么 blueprint implementable interfaces 没办法用 cast 转类型，并且只能用 `Execute_` static wrapper？