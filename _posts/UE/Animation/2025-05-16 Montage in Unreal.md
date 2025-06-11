### Key Concepts
#### Slot Tracks
```c++
class UAnimMontage : public UAnimCompositeBase
{
	// slot data, each slot contains anim track
	UPROPERTY()
	TArray<struct FSlotAnimationTrack> SlotAnimTracks;
};

/**
 * Each slot data referenced by Animation Slot 
 * contains slot name, and animation data 
 */
USTRUCT()
struct FSlotAnimationTrack
{
	GENERATED_USTRUCT_BODY()

	UPROPERTY(EditAnywhere, Category=Slot)
	FName SlotName;

	UPROPERTY(EditAnywhere, Category=Slot)
	FAnimTrack AnimTrack;

	ENGINE_API FSlotAnimationTrack();
};
```
一个  montage 由多个 slot track 组成，每个 slot track 的 `SlotName` 与动画蓝图中的 slot 节点的 slot name 相对应，并且这些 slot 必须属于同一个 slot group。每个 slot track（表示为 `FAnimTrack` 结构体）由多个基本的 animation asset 拼接而成，拼接的 animation asset 可以只是原本的 animation asset 的一部分（由 `FAnimSegment` 的 `AnimStartTime` 和 `AnimEndTime` 控制）
```c++
/** This is list of anim segments for this track 
 * For now this is only one TArray, but in the future 
 * we should define more transition/blending behaviors
 **/
USTRUCT()
struct FAnimTrack
{
	UPROPERTY(EditAnywhere, Category=AnimTrack, EditFixedSize)
	TArray<FAnimSegment>	AnimSegments;
};

/** this is anim segment that defines what animation and how **/
USTRUCT()
struct FAnimSegment
{
	UPROPERTY(EditAnywhere, Category=AnimSegment, meta=(DisplayName = "Animation Reference"))
	TObjectPtr<UAnimSequenceBase> AnimReference;

	/** Start Pos within this AnimCompositeBase */
	UPROPERTY(VisibleAnywhere, Category=AnimSegment, meta=(DisplayName = "Starting Position"))
	float StartPos;

	/** Time to start playing AnimSequence at. */
	UPROPERTY(EditAnywhere, Category=AnimSegment, meta=(DisplayName = "Start Time"))
	float AnimStartTime;

	/** Time to end playing the AnimSequence at. */
	UPROPERTY(EditAnywhere, Category=AnimSegment, meta=(DisplayName = "End Time"))
	float AnimEndTime;

	/** Playback speed of this animation. If you'd like to reverse, set -1*/
	UPROPERTY(EditAnywhere, Category=AnimSegment, meta=(DisplayName = "Play Rate"))
	float AnimPlayRate;

	UPROPERTY(EditAnywhere, Category=AnimSegment, meta=(DisplayName = "Loop Count"))
	int32 LoopingCount;
};
```
#### Slot and Slot Group
montage 能使用的所有的 slot 和 slot group 保存在 `USkeleton` 的 `SlotGroups` 中，`SlotToGroupNameMap` 用于快速查找，在 skeleton 反序列化时根据 `SlotGroups` 构建的
```c++
	// serialized slot groups and slot names.
	UPROPERTY()
	TArray<FAnimSlotGroup> SlotGroups;

	/** SlotName to GroupName TMap, only at runtime, not serialized. **/
	TMap<FName, FName> SlotToGroupNameMap;
```
虽然 [Animation Slots](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-slots-in-unreal-engine) 文档中说同一个 group 中只能有一个 montage 处于播放状态，但实际上是可以有多个的
```c++
	/** Plays an animation montage. Returns the length of the animation montage in seconds. Returns 0.f if failed to play. */
	UFUNCTION(BlueprintCallable, Category = "Animation|Montage")
	ENGINE_API float Montage_Play(UAnimMontage* MontageToPlay, float InPlayRate = 1.f, EMontagePlayReturnType ReturnValueType = EMontagePlayReturnType::MontageLength, float InTimeToStartMontageAt=0.f, bool bStopAllMontages = true);
```
其中参数 `bStopAllMontages` 默认值为 true，表示停止同一个 group 的其它 montage。但如果调用该函数时传入的 `bStopAllMontages` 为 false，则同一个 group，甚至同一个 slot 中，可以有多个 montage 同时播放

所有权重非零的 montage 都记录在 `UAnimInstance` 的 `MontageInstances` 字段，虽然它注释中也说要求 group 中至多一个 montage 在播放
```c++
	/** AnimMontage instances that are running currently
	* - only one is primarily active per group, and the other ones are blending out
	*/
	TArray<struct FAnimMontageInstance*> MontageInstances;
```
如果希望 group 中只有一个 montage 在播放，同时又想多个激活 group 中的多个 slot，只需要给这个 montage 添加多个 slot track 即可

具体 graph node 的 slot 是如何进行混合的，见 Animation Blending in Unreal 中的说明
#### Section
整个播放进度条可以划分为若干 section，每个 section 的名称，开始时间，连接的下一个 section 等信息存放在 `CompositeSections` 中
```c++
class UAnimMontage : public UAnimCompositeBase
{
	// composite section. 
	UPROPERTY()
	TArray<FCompositeSection> CompositeSections;
};

/**
 * Section data for each track. Reference of data will be stored in the child class for the way they want
 * AnimComposite vs AnimMontage have different requirement for the actual data reference
 * This only contains composite section information. (vertical sequences)
 */
USTRUCT()
struct FCompositeSection : public FAnimLinkableElement
{
	/** Section Name */
	UPROPERTY(EditAnywhere, Category=Section)
	FName SectionName;

	/** Should this animation loop. */
	UPROPERTY(VisibleAnywhere, Category=Section)
	FName NextSectionName;
};
```
