官方文档 [Unreal Interfaces](https://dev.epicgames.com/documentation/en-us/unreal-engine/interfaces-in-unreal-engine) 讲得挺好的，但我有几个地方没看懂
* ~~`execute_xxx` wrapper，是只有用 UFUNCTION 修饰的才有吗，没有 UFUNCTION 修饰函数我没找到对应的 wrapper~~
* `TScriptInterface` 是个啥，为什么需要它
* 为什么 blueprint implementable interfaces 没办法用 cast 转类型，并且只能用 `Execute_` static wrapper？

通常 object 类中如果有标记了 `BlueprintNativeEvent` 的 ufunction ABC，那么 UE 这边生成这些东西
* 成员函数 ABC 的定义：它在 ufunction 列表中查找名为 ABC 的函数并执行
* 成员函数 execABC，它会被注册为名为 ABC 的 ufunction，它的定义是调用 ABC_Implementation 函数

然后我们需要定义 ABC_Implementation 函数（否则 link 时会报未定义错误），它是不是虚函数由用户决定

但是在 interface 中如果给 ufunction ABC 添加 `BlueprintNativeEvent` 标记，生成的代码如下
* 成员函数 ABC 的定义：调用会直接报错，不允许直接调用
* 声明 ABC_Implementation 虚函数
* 声明和定义一个 Execute_ABC 函数，它会查找名为 ABC 的 ufunction 或者调用 ABC_Implementation 虚函数

在 cast 的时候会检查该 interface 是否是由蓝图实现的，如果是，则转换失败。这解释了文档 [Unreal Interfaces](https://dev.epicgames.com/documentation/en-us/unreal-engine/interfaces-in-unreal-engine) 说下面的第三种转换会在涉及蓝图时转换失败
```c++
bool bIsImplemented;
 
/* bIsImplemented is true if OriginalObject implements UReactToTriggerInterface */
bIsImplemented = OriginalObject->GetClass()->ImplementsInterface(UReactToTriggerInterface::StaticClass());
 
/* bIsImplemented is true if OriginalObject implements UReactToTriggerInterface */
bIsImplemented = OriginalObject->Implements<UReactToTriggerInterface>();
 
/* ReactingObject is non-null if OriginalObject implements UReactToTriggerInterface in C++ */
IReactToTriggerInterface* ReactingObject = Cast<IReactToTriggerInterface>(OriginalObject);
```

另外 [UE4 Cast](https://zhuanlan.zhihu.com/p/427716054) 中提到了 cast flags 优化，通过标记 cast flags 而不需要在类型转换时递归地比较 UClass。不过和这里没啥关系

