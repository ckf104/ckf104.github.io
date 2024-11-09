看看 [Enhanced Input](https://dev.epicgames.com/documentation/en-us/unreal-engine/enhanced-input-in-unreal-engine) 的文档，写一下这个怎么用的，讨论第三人称模板中是如何实现的

每个 actor 都有个 input component，虽然我觉得大部分 actor 都用不上，在有了 enhanced input 后，可以在 project settings 中 input component 的默认类型为 `UInputComponent` 或者 `UEnhancedInputComponent`
```c++
/** Component that handles input for this actor, if input is enabled. */
UPROPERTY(DuplicateTransient)
TObjectPtr<class UInputComponent> InputComponent;
```
或者会接收 input 的 actor 子类一般会有相应的字段单独设置 input component 的类型，例如在 player controller 的下面两个字段决定了 player input 和 input component 的类型
```c++
	/** Default class type for player input object. May be overridden by player controller. */
	UPROPERTY(config, EditAnywhere, NoClear, Category = DefaultClasses)
	TSoftClassPtr<UPlayerInput> DefaultPlayerInputClass;

	/** Default class type for pawn input components. */
	UPROPERTY(config, EditAnywhere, NoClear, Category = DefaultClasses)
	TSoftClassPtr<UInputComponent> DefaultInputComponentClass;
```
然后 `pawn` 中也有 `OverrideInputComponentClass` 字段来设置自己的 input component 类型

player controller 和 pawn 都有自己的逻辑来创建 input component。例如游戏开始时，会调用 player controller 的 `SetPlayer` 函数来设置 player。这里会调用 `InitInputSystem` 来创建 player input 和 input component。而 pawn 会被调用自己的 `PawnClientRestart` 函数，该函数内也会创建 input component，并作为参数传递给 `SetupPlayerInputComponent`，这个我们经常重载的，用来绑定 input 回调的函数
### Trigger Event
TODO：解释和实验 trigger event 的状态机转化

TODO：解释 trigger 的触发和 actor / component 的顺序先后问题（world tick 执行顺序是怎样的）
### Enhanced Input Component
Enhanced Input Component 相比于原来的 Input Component，额外增加了几个与 binding 相关的字段
```c++
	/** The collection of action bindings. */
	TArray<TUniquePtr<FEnhancedInputActionEventBinding>> EnhancedActionEventBindings;

	/** The collection of action value bindings. These do not have delegates and are used to store a copy of the current action value only. */
	TArray<FEnhancedInputActionValueBinding> EnhancedActionValueBindings;	// TODO: TSortedMap?
```
TODO：没看懂 `EnhancedActionValueBindings` 的作用以及相关的 BindActionValue 函数

与我们最直接相关的就是 `FEnhancedInputActionEventBinding` 字段，`FEnhancedInputActionEventBinding` 类是一个包含 `InputAction` 指针和 trigger event 的虚基类，它包含一个 Execute 的纯虚函数。它的子类 `FEnhancedInputActionEventDelegateBinding<TSignature>` 额外包含一个代理字段（`TSignature` 就是代理的类型），用来实现 Execute 函数，即回调我们绑定的函数。这又是一个虚函数+泛型子类实现 type erasure 的例子

enhanced input component 声明了三种签名的代理，因此我们绑定的函数签名可以以下三种的任意一种，第二种是最常用的
```c++
void TSignature1();
void TSignature2(const FInputActionValue&);
void TSignature3(const FInputActionInstance&);
```
### Enhanced Input Subsystem Interface and Enhanced Input Local Player Subsystem

### Enhanced Player Input




player controller 重载的 `TickActor` 函数中

[第39期 | 虎跳龙拿--新一代增强输入框架EnhancedInput](https://www.bilibili.com/video/BV14r4y1r7nz/?spm_id_from=444.41.0.0&vd_source=2f38c661a6672237a3f59835e4bfb1a5) 讲得很好，里面提到了 `InputAction->BindAction` 的调用和 `Subsystem->AddMappingContext` 的顺序没有关系，需要看下源码理解其中的原因

另外视频中一些关键的点
* 以前的 `PlayerInput` 关联 key 与 ActionName/AxisName，而 `InputComponent` 关联 ActionName/AxisName 与 Delegate
* 在高优先级的 IMC 中的 key 绑定会覆盖低优先级的 IMC 的 key 绑定

TODO：结合桌面的 stateChange.png 测试各个 trigger event，多个 trigger（例如 hold + release） 时是如何处理的，没有 trigger 又意味着什么, 测试一个 input action 包含在多个 IMC 中会怎样，一个按键映射到多个 input action，多个按键映射到一个 input，chorded action
Implicits == 0, Explicits == 0 - Always fires, unless the value is 0.

	Implicits == 0, Explicits > 0 - At least one explicit has been fired.

	Implicits > 0, Explicits == 0 - All implicits have been fired.

	Implicits > 0, Explicits > 0 - All implicits and at least one explicit have been fired.

	Blockers - Override all other triggers to force a trigger failure.

视频中有人问 ctrl + A 会不会把绑定到 A 的 input action 也触发了，我感觉使用 chorded action 就会触发呀？而且 chorded action 是怎么保证它依赖的 action已经被执行了呢？
consume lower priority input settings of inputaction


一些有关 input action 的设置：
* Accumulation Behavior：它默认为 take highest absolute value，例如当多个按键绑定到一个 action 上时，同时按多个按键，最后这个 action 收到的 input value 是这些按键的 input value 中绝对值最大的那个。需要注意的是，在代码中是应用了 modifier 后逐维度取绝对值最大（见 `UEnhancedPlayerInput::ProcessActionMappingEvent` 函数），例如经典的 `IA_Move` action 有一个 swizzle modifier，因此 w 和 d 一起按时，它们对应的 input value 是 (1,0,0) 和 (0,1,0)，逐维度取最大后得到的 input value 是 (1,1,0)。还有一个 Accumulation Behavior 是 cumulative，它就是对 input value 做累加嘛
* Comsume Input
[【UE5：検証】Enhanced Input：Priority や Consume Input](https://ci-en.net/creator/15980/article/771199) 讨论了 input action 中设置 consume input 的作用，以及 IMC 的优先级参数在按键绑定到多个 IMC 时的意义。
TODO：我目前尤其关心的问题在于同一个按键绑定到同一个 IMC 的多个 input action 会发生什么。一个典型的例子是 chorded action 实现组合按键，但是 ctrl + a 会不会触发原来绑定到 a 上的行为呢，我发现是不会触发的，为什么？以及 chorded action 的实现显然是有一个顺序上的问题的，因为按下 a 之后需要评估 ctrl 是否 trigger 了，那代码是如何保证这个顺序的呢，我认为有必要再看看 `UEnhancedPlayerInput::EvaluateInputDelegates` 等函数的代码