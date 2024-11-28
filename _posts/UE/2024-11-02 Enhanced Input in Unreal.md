### (Enhanced) input component with actor
这一节描述 input component 和 actor 之间的交互。每个 actor 都有个 input component，虽然我觉得大部分 actor 都用不上。在有了 enhanced input 后，可以在 project settings 中 input component 的默认类型为 `UInputComponent` 或者 `UEnhancedInputComponent`
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

对于一般的 actor，`AActor` 类中定义了 `EnableInput` 函数。这个函数负责创建该 actor 的 input component，然后将其推到参数指定的 player controller 的 input stack 上去
```c++
/** 
 * Pushes this actor on to the stack of input being handled by a PlayerController.
 * @param PlayerController The PlayerController whose input events we want to receive.
 */
UFUNCTION(BlueprintCallable, Category="Input")
ENGINE_API virtual void EnableInput(class APlayerController* PlayerController);

/** 
 * Removes this actor from the stack of input being handled by a PlayerController.
 * @param PlayerController The PlayerController whose input events we no longer want to receive. If null, this actor will stop receiving input from all PlayerControllers.
 */
UFUNCTION(BlueprintCallable, Category="Input")
ENGINE_API virtual void DisableInput(class APlayerController* PlayerController);
```
input component 的 `bBlockInput` 和 `Priority` 的值由 actor 的对应字段提供
```c++
/** The priority of this input component when pushed in to the stack. */
UPROPERTY(EditAnywhere, Category=Input)
int32 InputPriority;

/** If true, all input on the stack below this actor will not be considered */
UPROPERTY(EditDefaultsOnly, Category=Input)
uint8 bBlockInput:1;
```
`DisableInput` 函数则负责把该 actor 的 input component 从参数指定的 player controller 的 input stack 中移除

如果 actor 的 `AutoReceiveInput` 字段非 0，那么 `EnableInput` 将会在 `PreInitializeComponents` 函数中自动被调用
```c++
/** Automatically registers this actor to receive input from a player. */
UPROPERTY(EditAnywhere, Category=Input)
TEnumAsByte<EAutoReceiveInput::Type> AutoReceiveInput;
```
由于 player controller 和 pawn 由自己的创建 input component 的逻辑，因此它们重载了 `EnableInput` 和 `DisableInput` 函数。它们负责把 player controller 或者 pawn 的 `bInputEnabled` 字段设置为 true 或者 false。这个字段是用在 `APlayerController::BuildInputStack` 中，也是控制 player controller 和 pawn 的 input component 要不要推到 input stack 上去
### Enhanced Input Component
这一节描述 enhanced input component 中 binding 相关的函数的实现。Enhanced Input Component 相比于原来的 Input Component，额外增加了几个与 binding 相关的字段
```c++
	/** The collection of action bindings. */
	TArray<TUniquePtr<FEnhancedInputActionEventBinding>> EnhancedActionEventBindings;

	/** The collection of action value bindings. These do not have delegates and are used to store a copy of the current action value only. */
	TArray<FEnhancedInputActionValueBinding> EnhancedActionValueBindings;	// TODO: TSortedMap?
```
与我们最直接相关的就是 `FEnhancedInputActionEventBinding` 字段，`FEnhancedInputActionEventBinding` 类是一个包含 `InputAction` 指针和 trigger event 的虚基类，它包含一个 Execute 的纯虚函数。它的子类 `FEnhancedInputActionEventDelegateBinding<TSignature>` 额外包含一个代理字段（`TSignature` 就是代理的类型），用来实现 Execute 函数，即回调我们绑定的函数。这又是一个虚函数+泛型子类实现 type erasure 的例子

enhanced input component 声明了三种签名的代理，因此我们绑定的函数签名可以以下三种的任意一种，第二种是最常用的
```c++
void TSignature1();
void TSignature2(const FInputActionValue&);
void TSignature3(const FInputActionInstance&);
```
相比 `FEnhancedInputActionEventBinding` 提供了一种绑定回调函数的方式，`EnhancedActionValueBindings` 提供了一种仅获取 input action value 的方式。首先调用 `BindActionValue` 进行绑定，然后可以调用 `GetBoundActionValue` 获取此时的 input action value
```c++
/**
* Binds a UInputAction assigned via UInputMappingContext to this component.
* No delegate will be called when this action triggers. The binding simply reflects the current value of the action.
*/
FEnhancedInputActionValueBinding& BindActionValue(const UInputAction* Action);

/**
 * Helper function to pull the action value for a bound action value.
 */
UFUNCTION(BlueprintCallable, meta = (BlueprintInternalUseOnly = "true", HideSelfPin = "true", HidePin = "Action"))
FInputActionValue GetBoundActionValue(const UInputAction* Action) const;
```
### Input Mapping Context(IMC) and Input Action
这一节说明 IMC 和 input action 的组成。`UInputAction` 的成员主要是 modifier array，trigger arrary 以及其它的编辑器中的可配置的选项。而 `UInputMappingContext` 的成员主要是一个 `FEnhancedActionKeyMapping` array。而 `FEnhancedActionKeyMapping` 的成员主要是 key，input action 以及 modifier array，trigger arrary

有三件事需要注意
* 我们在 IMC 中一个 input action 下可能绑定多个按键，它对应地会生成多个 `FEnhancedActionKeyMapping`。例如 IA_MOVE 绑定了 w,a,s,d 四个按键，那么就有 4 个对应的 `FEnhancedActionKeyMapping`，这些 `FEnhancedActionKeyMapping` 的 input action 相同，但 key，modifier array，trigger array 可能不一样
* IMC 和 input action 中都可以设置 modifier 和 trigger，我们下面会看到 ue 是如何处理它们的
* IMC 中的 `FEnhancedActionKeyMapping` array 中的顺序是重要的，它会对按键的响应产生影响，在编辑器配置 IMC 时，排在前面的 input action 和 key 对应的 `FEnhancedActionKeyMapping` 也在 array 的前面
### Enhanced Input Subsystem Interface and Enhanced Input Local Player Subsystem
这一节讨论 Enhanced Input Subsystem Interface 类，以及它是如何处理我们添加的 IMC 的

enhanced input subsystem interface 类下有 `UEnhancedInputWorldSubsystem`，`UEnhancedInputLocalPlayerSubsystem`，`UMockedEnhancedInputSubsystem` 以及 `UEnhancedInputEditorSubsystem` 4 个子类，分别对应 4 种 subsystem，我们最常用的是 `UEnhancedInputLocalPlayerSubsystem`

我并没有特别理解 enhanced input subsystem interface 的定位，看起来它就是实现了一堆 helper 函数，核心的数据还是存储在 enhanced player input 中的。而它的各个子类一个必须的重载就是 `GetPlayerInput` 函数，提供获取 enhanced player input 的方法。

例如 enhanced input subsystem interface 提供的 `AddMappingContext` 方法，添加的 IMC 实际都存储在 enhanced player input 的 `AppliedInputContexts` 中

整个 enhanced input module 以插件的形式存在。module 类为 `FEnhancedInputModule`。在调用 interface 的 `AddMappingContext` 后，interface 的 `bMappingRebuildPending` 设置为 true。在 enhanced input module 的 tick 中会调用 enhanced input interface 的 `RebuildControlMappings` 函数。这个函数负责重建 enhanced player input 的 `EnhancedActionMappings` 字段。`EnhancedActionMappings` 也是一个 `FEnhancedActionKeyMapping` array，它包含了所有的 enhanced player input 中会进行处理的按键和 input action 的绑定

`RebuildControlMappings` 函数很长，我主要列出一些我们感兴趣的关键代码，中文注释是我额外添加的
```c++
void IEnhancedInputSubsystemInterface::RebuildControlMappings()
{
	UEnhancedPlayerInput* PlayerInput = GetPlayerInput();

	TMap<TObjectPtr<const UInputMappingContext>, int32> OrderedInputContexts = PlayerInput->AppliedInputContexts;
	// Order contexts by priority
	// AddMappingContext 函数的用途就在这，priority 越大的 IMC，排序后就越靠前
	// UE TMap 的文档也讲到 TMap 是可以做排序的，挺有意思的
	OrderedInputContexts.ValueSort([](const int32& A, const int32& B) { return A > B; });
	// 记录哪些按键已经被 FEnhancedActionKeyMapping 占用了
	TSet<FKey> AppliedKeys;
	// 记录哪些 FEnhancedActionKeyMapping 是 chorded action，存储的整数是在 EnhancedActionMappings 中的编号
	TArray<int32> ChordedMappings;

	for (const TPair<TObjectPtr<const UInputMappingContext>, int32>& ContextPair : OrderedInputContexts)
	{
		// Don't apply context specific keys immediately, allowing multiple mappings to the same key within the same context if required.
		// ContextAppliedKeys 中保存了即将被加入到 AppliedKeys 中的 keys
		TArray<FKey> ContextAppliedKeys;
		const UInputMappingContext* MappingContext = ContextPair.Key;
		// ReorderMappings 函数主要对 FEnhancedActionKeyMapping array 进行一个重排序。使得新的数组中 chorded + chording mapping > chording mapping > chorded mapping > others，另外这个排序是稳定的。chorded + chording mapping 的含义是这个 action 是 chorded action 同时又是 chording action。实际上从这个函数的实现中我们可以看出来为了实现一个 ctrl + shift + p 的三连按键，如果实现为 p chorded with shift, shift chorded with ctrl 这样的配置，实际上是无法触发的，因为按它的排序逻辑中 shift 的优先级是最高的，这导致后面 evalute trigger 的时候总是 shift 在 ctrl 前面执行，因此 shift 总是认为 ctrl 没有 trigger，导致 ctrl + shift + p 无法 trigger。正确的配置应该是 p chorded with shift, p chorded with ctrl。换句话说，ue 目前的实现中 chord trigger 不支持嵌套，一个 chording action 不要再套一个 chord trigger 了，否则会出现奇奇怪怪的结果
		// ReorderMappings 函数的另一个作用是填充 enhanced player input 的 DependentChordActions 字段，它记录了所有的 (chorded action,chording action) pair，它的作用在后面讨论 UEnhancedPlayerInput::EvaluateInputDelegates 函数时会看到
		TArray<FEnhancedActionKeyMapping> OrderedMappings = ReorderMappings(MappingContext->GetMappings(), PlayerInput->DependentChordActions);
		
		for (FEnhancedActionKeyMapping& Mapping : OrderedMappings)
		{
			// priority 高的 IMC 会被优先遍历，从而使得相同的按键的位于低 priority 的 IMC 中的 FEnhancedActionKeyMapping 被跳过了
			// 这会产生许多奇妙的影响，例如在高 IMC 中设置一个 ctrl + w 的连击按键，其中 ctrl 的按键绑定在 IA_CTRL1 这个 chording action 上，而在低 IMC 中设置一个 ctrl + p 的连击按键，其中 ctrl 的按键绑定在 IA_CTRL2 这个 chording action 上。这里的代码逻辑导致 IA_CTRL2 被跳过了，它永远也不会 trigger，因此对应的 ctrl + p 连击也永远不会 trigger
			if (Mapping.Action && !AppliedKeys.Contains(Mapping.Key)) 
			{
				// TODO: Wasteful query as we've already established chord state within ReorderMappings. Store TOptional bConsumeInput per mapping, allowing override? Query override via delegate?
				auto IsChord = [](const UInputTrigger* Trigger)
				{
					return Cast<const UInputTriggerChordAction>(Trigger) != nullptr;
				};
				bool bHasActionChords = HasTriggerWith(IsChord, Mapping.Action->Triggers);
				bool bHasChords = bHasActionChords || HasTriggerWith(IsChord, Mapping.Triggers);

				// Chorded actions can't consume input or they would hide the action they are chording.
				// 这下我们能理解 input action 的配置页面中的 consume input 选项的含义了，如果它为 true，那么它会将更低优先级的相同按键的 action 给覆盖掉。注意同一个 IMC 中相同按键的 action 是不会被覆盖的，因为 ContextAppliedKeys 是在一个 IMC 遍历完之后再一起并入 AppliedKeys 中
				// 检查 bHasChords 使得 chorded action 对应的按键不会覆盖掉低优先级的，换句话说，高优先级的 ctrl + w 中的 w 不会将低优先级的 w 给覆盖掉，我觉得这样做主要是因为将 ctrl + w 视为一个整体的话确实不应该将 w 给覆盖掉，因此单按一个 w 触发这个低优先级的 w，但这并不意味着如果按 ctrl + w 的话会同时触发 ctrl+w 与 w 两个 action，后面的代码逻辑我们会看到原因
				if (!bHasChords && Mapping.Action->bConsumeInput)
				{
					ContextAppliedKeys.Add(Mapping.Key);
				}
				// 将这个符合要求的 FEnhancedActionKeyMapping 加入到 enhanced player input 的 EnhancedActionMappings 字段中
				int32 NewMappingIndex = PlayerInput->AddMapping(Mapping);
				FEnhancedActionKeyMapping& NewMapping = PlayerInput->EnhancedActionMappings[NewMappingIndex];
				// Re-instance modifiers
				// 这里做一个深拷贝，而不是直接使用 IMC 中的 modifier，这是因为 modifier 可能有状态的，后面调用 modifier 时可能修改 modifier 中变量的值，要是把 IMC 中 modifier 的值改了就乱套了。下面深拷贝 trigger 也是这个原因
				DeepCopyPtrArray<UInputModifier>(Mapping.Modifiers, MutableView(NewMapping.Modifiers));
				// Re-instance triggers
				DeepCopyPtrArray<UInputTrigger>(Mapping.Triggers, MutableView(NewMapping.Triggers));
				
				if (bHasChords)
				{
					// TODO: Re-prioritize chorded mappings (within same context only?) by number of chorded actions, so Ctrl + Alt + [key] > Ctrl + [key] > [key].
					// TODO: Above example shouldn't block [key] if only Alt is down, as there is no direct Alt + [key] mapping.y
					ChordedMappings.Add(NewMappingIndex);

					// Action level chording triggers need to be evaluated at the mapping level to ensure they block early enough.
					// TODO: Continuing to evaluate these at the action level is redundant.
					// 将在 action level 中设置的 chording triggers 移到 mapping level 来执行。在后面我们会看到，IMC 中设置的 trigger 和 modifier, 以及 input action 里面设置的 trigger 和 modifier，是分为两个阶段来执行的。前一个阶段保序地执行 IMC 中的，后一个阶段不保序地执行 input action 中的。我猜这里把它移到 mapping level 的原因就是 mappping level 中的执行是保序的。因此我推荐的做法是 chording triggers 都放到 mapping level 中
					if (bHasActionChords)
					{
						for (const UInputTrigger* Trigger : Mapping.Action->Triggers)
						{
							if (IsChord(Trigger))
							{
								NewMapping.Triggers.Add(DuplicateObject(Trigger, nullptr));
							}
						}
					}
				}
			}
		}
		// 将 ContextAppliedKeys 加入到 AppliedKeys 中，阻塞低优先级的相同按键的 FEnhancedActionKeyMapping
		AppliedKeys.Append(MoveTemp(ContextAppliedKeys));
	}
	// ChordedMappings 中保存了所有的 chorded action 在 EnhancedActionMappings 中的 index，这个函数就会在所有的优先级低于 chorded action 且与它按键相同的 action 中添加一个 mapping level 的 block trigger，使得当高优先级的 chorded action 触发时，低优先级的绑定到相同按键的 action 不能触发。这就是前面提到的，如果绑定 w chorded with ctrl，同时绑定单独的一个 w，且假设前者优先级更高。如果此时按下 ctrl + w,那么此时是不会触发 w 的，因为 ctrl + w 将它 block 住了
	InjectChordBlockers(ChordedMappings);
}
```
### Enhanced Player Input
下面我们讨论在重建好 enhanced player input 的 `EnhancedActionMappings` 字段后，enhanced player input 是如何根据按键的输入执行相应的回调函数的。在 player controller 的 tick actor 函数中会调用它的 process player input 函数，这个函数负责构建一个由 input ccomponent 组成的栈，然后调用 enhanced player input 的 process input stack 函数
```c++
void APlayerController::ProcessPlayerInput(const float DeltaTime, const bool bGamePaused)
{
	static TArray<UInputComponent*> InputStack;

	// must be called non-recursively and on the game thread
	check(IsInGameThread() && !InputStack.Num());

	// process all input components in the stack, top down
	{
		SCOPE_CYCLE_COUNTER(STAT_PC_BuildInputStack);
		BuildInputStack(InputStack);
	}

	// process the desired components
	{
		SCOPE_CYCLE_COUNTER(STAT_PC_ProcessInputStack);
		PlayerInput->ProcessInputStack(InputStack, DeltaTime, bGamePaused);
	}

	InputStack.Reset();
}
```
`APlayerController::BuildInputStack` 函数相对比较简单，就不贴代码了，我们需要注意的是 input stack 中的元素的优先级，stack 中越靠近栈顶的 input component 会优先被处理，即绑定在它上面的回调函数会被优先执行。`BuildInputStack` 的压栈顺序是：pawn，level script actor，player controller，其它调用了 `EnableInput` 函数的 actors

在构建好 input stack 后，会调用最重要的 `UEnhancedPlayerInput::EvaluateInputDelegates` 函数。这个函数也比较长，我们分几部分来说明它。下面是省略了一些不重要的 corner case 的第一部分的代码
```c++
void UEnhancedPlayerInput::EvaluateInputDelegates(const TArray<UInputComponent*>& InputComponentStack, const float DeltaTime, const bool bGamePaused, const TArray<TPair<FKey, FKeyState*>>& KeysWithEvents)
{
	// Handle input devices, applying modifiers and triggers
	// 这里就用上了之前构建好的 EnhancedActionMappings，它根据 EnhancedActionMappings 中的顺序来依次 evalute 每个 action key binding 在 mapping level 的 modifier 和 trigger。因为 chorded action 的状态是依赖于 chording action 的，所以如果之前的排序使得 chorded action 排到了 chording action 的前面，那这里 chorded action 的 trigger 执行时 chording action 的 trigger 还未执行。导致 chorded action 永远不会 trigger 了
	for (FEnhancedActionKeyMapping& Mapping : EnhancedActionMappings)
	{
		FKeyState* KeyState = GetKeyState(Mapping.Key);
		
		FVector RawKeyValue = KeyState ? KeyState->RawValue : FVector::ZeroVector;
		
		// Establish update type.
		bool bDownLastTick = KeyDownPrevious.FindRef(Mapping.Key);
		// TODO: Can't just use bDown as paired axis event edges may not fire due to axial deadzoning/missing axis properties. Need to change how this is detected in PlayerInput.cpp.
		bool bKeyIsDown = KeyState && (KeyState->bDown || KeyState->EventCounts[IE_Pressed].Num() || KeyState->EventCounts[IE_Repeat].Num());
		// Analog inputs should pulse every (non-zero) tick to retain compatibility with UE4. TODO: This would be better handled at the device level.
		bKeyIsDown |= Mapping.Key.IsAnalog() && RawKeyValue.SizeSquared() > 0;

		bool bKeyIsReleased = !bKeyIsDown && bDownLastTick;
		bool bKeyIsHeld = bKeyIsDown && bDownLastTick;

		EKeyEvent KeyEvent = bKeyIsHeld ? EKeyEvent::Held : ((bKeyIsDown || bKeyIsReleased) ? EKeyEvent::Actuated : EKeyEvent::None);

		FVector* PressedThisTickValue = KeysPressedThisTick.Find(Mapping.Key);
		
		// For keys that were pressed and released within the same frame, set their RawValue so that
		// InputTriggers are aware that they have been pressed
		if(PressedThisTickValue && bKeyIsDown && KeyState->EventCounts[IE_Pressed].Num() && KeyState->EventCounts[IE_Released].Num() && RawKeyValue.IsZero())
		{
			RawKeyValue = *PressedThisTickValue;
		}

		// Perform update
		ProcessActionMappingEvent(Mapping.Action, NonDilatedDeltaTime, bGamePaused, RawKeyValue, KeyEvent, Mapping.Modifiers, Mapping.Triggers);
	}
}
```
限于篇幅，我就不贴 `ProcessActionMappingEvent` 函数的代码了。`ProcessActionMappingEvent` 主要干的事情就是对于 `KeyEvent` 不为 none 的 action key binding，调用它在 mapping level 的 modifier 和 trigger，来判断这个 action 的 trigger state，以及 input action value。`EnhancedActionMappings` 中可能包含重复的 action（多个 key 绑定到一个 action 上），因此可能调用多次处理同一个 action，对应的 key 不同，那么收到的 `RawKeyValue` 可以不同，并且可以有不同的 mapping level 的 modifier 来调整 `RawKeyValue` 的值，以及 trigger 来调整 action 的 trigger state。但是 action 的 trigger state 和 input action value 是每个 action 仅一份的，我们需要一些策略将多次对同一个调用 `ProcessActionMappingEvent` 的结果合并起来。trigger state 的合并是取最大的 trigger state，`None` < `OnGoing` < `Trigger`，这很自然。而 input action value 的合并方式可以配置，默认是 take highest absolute value，注意这个是诸维度取最大值，即 (0,1) 和 (1,0) 合并的结果是 (1,1)。 也可以设置为 cumulative，就是将各自的结果累加起来作为最终的 input action value

trigger state 和 input action value 分别合并的实现有时候会带来出乎意料的结果。我们在高优先级的 IMC 中给 input action 绑定一个 ctrl + p，而在低优先级的 IMC 中给同一个 input action 绑定一个 p，由于前面提到的 chorded action 不会阻塞低优先级的绑定，因此 ctrl + p 中的 p 和低优先级的单个 p 的绑定都会加入到 enhanced player input 的 `EnhancedActionMappings` 中，当我们单独按下 p 键时。虽然 ctrl + p 不会触发，但是由于 trigger state 和 input action value 是分别合并的，因此它的 modifier 也会影响到最终的 input action value。设想 ctrl + p 的 modifier 是一个 swizzle input axis values，那么以 take highest absolute value 的方式合并的话。单按下一个 p 键，我们的回调函数收到的 input action value 为 (1,1)

在每个 action 的 mapping level 的 modifier 和 trigger 执行完毕后。`ActionInstanceData` 作为一个 TMap，保存了 input action 到它合并后的 input action value，trigger state 等信息的映射。因此 `ActionInstanceData` 和 `EnhancedActionMappings` 的一个显著区别在于前者不再包含重复的 input action 了。它负责执行每个 input action 内的 modifier 和 trigger(第二个阶段的 action level 的执行)，得到最终的 trigger state 和 input action value，由于 `ActionInstanceData` 是一个 TMap 的结构，因此它执行各个 input action 是不保序的，因此我推荐应该将 chording trigger 放在 mapping level
```c++
	// Post tick action instance updates
	for (TPair<TObjectPtr<const UInputAction>, FInputActionInstance>& ActionPair : ActionInstanceData)
	{
		TObjectPtr<const UInputAction> Action = ActionPair.Key;
		FInputActionInstance& ActionData = ActionPair.Value;
		ETriggerState TriggerState = ETriggerState::None;

		if (ActionsWithEventsThisTick.Contains(Action))
		{
			// Apply action modifiers
			FInputActionValue RawValue = ActionData.Value; 
			ActionData.Value = ApplyModifiers(ActionData.Modifiers, ActionData.Value, NonDilatedDeltaTime);

			ETriggerState PrevState = ActionData.TriggerStateTracker.GetState();
			// Evaluate action triggers. We must always call EvaluateTriggers to update any internal state, even when paused.
			TriggerState = ActionData.TriggerStateTracker.EvaluateTriggers(this, ActionData.Triggers, ActionData.Value, NonDilatedDeltaTime);
			TriggerState = ActionData.TriggerStateTracker.GetMappingTriggerApplied() ? FMath::Min(TriggerState, PrevState) : TriggerState;
		}
	}
```
`EvaluateInputDelegates` 函数后面的东西就相对很直接了，根据这个 input action 上一帧的 trigger state 以及这一帧的 trigger state 判断发生了包括 None，Triggered，Started，Ongoing，Canceled，Completed 六种可能的哪一个 trigger event。然后从栈顶自顶向下遍历 input component，如果存在绑定了一个 input action 发生的事件的回调函数，执行该回调函数即可。另外就是将新的 input action value 更新到 input component 的 `FEnhancedInputActionValueBinding` 中，保证调用 input component 时能获取到 `GetBoundActionValue` 的值。

还有一点，当我们设置 p chorded with ctrl 这种的配置时，我们如果按下 ctrl + p，根据前面提到过的 `InjectChordBlockers` 函数添加的 chord blocker，比 p chorded with ctrl 优先级更低的绑定在 p 键上的 action 都不会触发。但同时通常我们也不希望触发 ctrl 绑定的 action。这就要用到之前填充的 `DependentChordActions` 字段了。它以 array 的形式记录了每对 chorded action 和 chording action。在调用 input action 对应的回调函数前，`EvaluateInputDelegates` 函数会检查这个 action 是否是 chording action，如果是，并且它对应的 chorded action 是 trigger 的，就不会调用这个 chording action 的回调函数

不过这个是以 action 而不是按键为判定单位的。例如我们设置 IA_P 为 p chorded with ctrl，并且 ctrl 绑定的是 IA_CTRL1，然后我们再在同一个 IMC 中单独设置一个 IA_CTRL2 也绑定在 ctrl 按键上，因此它的优先级和 IA_CTRL1 相同，那么按下 ctrl + p 时，IA_P 和 IA_CTRL2 都会触发，而 IA_CTRL1 不会触发
### Trigger Event
TODO：解释 trigger 的触发和 actor / component 的顺序先后问题（world tick 执行顺序是怎样的）
 [Enhanced Input](https://dev.epicgames.com/documentation/en-us/unreal-engine/enhanced-input-in-unreal-engine) 官方文档中详细记录了 implicit trigger 和 explicit trigger 对最终 trigger state 的影响
* Implicits == 0, Explicits == 0 - Always fires, unless the value is 0.
* Implicits == 0, Explicits > 0 - At least one explicit has been fired.
* Implicits > 0, Explicits == 0 - All implicits have been fired.
* Implicits > 0, Explicits > 0 - All implicits and at least one explicit have been fired.
* Blockers - Override all other triggers to force a trigger failure.
这对应代码中的 `FTriggerStateTracker::EvaluateTriggers` 和 `FTriggerStateTracker::GetState` 函数
Trigger State 与 Trigger Event 之间的转换关系见 `UEnhancedPlayerInput::GetTriggerStateChangeEvent` 函数

如果不设置 trigger，通常是我们希望接收连续的输入，典型的例如移动。那么按一次键盘会 trigger 多次。而如果希望按下后仅收到一次 trigger，那么使用 `UInputTriggerPressed`。如果希望松开按键后收到一次 trigger，那么使用 `UInputTriggerReleased`

在第一人称和第三人称模板中的 jump 操作希望实现的效果是按下按键时调用 `Jump` 函数，松开按键时调用 `StopJump` 函数。它的实现是，同时绑定了 `UInputTriggerPressed` 和 `UInputTriggerReleased`，然后把 `Jump` 函数绑定到 start 这个事件上，而 `StopJump` 绑定到 complete 这个事件上。因为整个按下松开的 trigger state 变化为 None -> Triggered -> Ongoing -> Triggered -> None。正好触发一次 start 和一次 complete。注意第一次 trigger 后的下一个状态是 Ongoing，因为一旦按下后 `UInputTriggerReleased` 就会进入 Ongoing 状态
### 蓝图中的动态绑定
TODO：`UInputDelegateBinding` 以及它的子类实现了在蓝图的 event graph 上写回调函数来进行绑定的方法，但没有细看是怎么实现的
### Others
[第39期 | 虎跳龙拿--新一代增强输入框架EnhancedInput](https://www.bilibili.com/video/BV14r4y1r7nz/?spm_id_from=444.41.0.0&vd_source=2f38c661a6672237a3f59835e4bfb1a5) 讲得很好，涉及到许多源码流程的分析，还对比了以前的 axis binding 那一套是怎么工作的。还讨论了 enhanced input 和 GAS 以及 game feature 的联动，虽然这些我还不太懂就是了
[【UE5：検証】Enhanced Input：Priority や Consume Input](https://ci-en.net/creator/15980/article/771199) 讨论了 input action 中设置 consume input 的作用，以及 IMC 的优先级参数在按键绑定到多个 IMC 时的意义。上面代码的分析可以与出它的实验结果相互印证

TODO：了解移动端的输入处理，gamepad 相关的输入是怎么映射到手机屏幕上的？
TODO：UI 的输入响应是在哪一部分进行处理的？
TODO：总结当有多个玩家时的输入设置关系，我尤其关系 player controller 会有多个吗
TODO：整理这些类的逻辑关系：感觉 local player 包含 player controller，player controller 包含 player input。以及 player controller 中包含 player camera manager
