### Game Tags
官方文档 [Gameplay Tags](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-gameplay-tags-in-unreal-engine) 已经讲得很全了
### Ability System Component
GiveAbility
TryActivateAbility
### Gameplay Ability
Activate Ability
Commit Ability
	Apply Cooldown
	Apply Cost

cool down GE
```c++
	/** This GameplayEffect represents the cost (mana, stamina, etc) of the ability. It will be applied when the ability is committed. */
	UPROPERTY(EditDefaultsOnly, Category = Costs)
	TSubclassOf<class UGameplayEffect> CostGameplayEffectClass;

	/** This GameplayEffect represents the cooldown. It will be applied when the ability is committed and the ability cannot be used again until it is expired. */
	UPROPERTY(EditDefaultsOnly, Category = Cooldowns)
	TSubclassOf<class UGameplayEffect> CooldownGameplayEffectClass;
```

TODO：解释 GA 的 instancing policy
TODO：解释 URPGAbilityTask_PlayMontageAndWaitForEvent

 `UAbilitySystemBlueprintLibrary::SendGameplayEventToActor`
```c++
 	/** List of gameplay tag container filters, and the delegates they call */
	TArray<TPair<FGameplayTagContainer, FGameplayEventTagMulticastDelegate>> GameplayEventTagContainerDelegates;
```