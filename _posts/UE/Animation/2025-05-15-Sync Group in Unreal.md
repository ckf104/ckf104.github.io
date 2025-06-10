### Overview
整个 sync group 逻辑运行的流程大概是
#### 1. `FAnimInstanceProxy::UpdateAnimation`
这里调用了所有 asset player 的 graph node 的 `Update_AnyThread` 函数，该函数将 asset player 封装为一个 `FAnimTickRecord` 加入到 `FAnimInstanceProxy` 的 sync group 中，这些 sync group 信息都存放在 `Sync` 字段。接下来以 `UAnimSequence` 作为 asset player，并且前向播放来说明 sync group 是如何工作的
```c++
	/** Synchronizes animations according to sync groups/markers */
	UE::Anim::FAnimSync Sync;
```
然后是调用 `FAnimSync::TickAssetPlayerInstances`，这个函数选出每个 sync group 的 leader，然后先调用 leader 的 `TickAssetPlayer`，随后调用各个 follower 的 `TickAssetPlayer`

#### 2. `UAnimSequence::TickAssetPlayer`
如果它是 leader 的话，会以自然速度设置播放 delta time 前的时间点和播放 delta time 后的时间点相对于 marker 的位置。时间点相对于 marker 的位置用 `FMarkerSyncAnimPosition` 结构体表示
```c++
//Represent a current play position in an animation
//based on sync markers
USTRUCT(BlueprintType)
struct FMarkerSyncAnimPosition
{
	GENERATED_USTRUCT_BODY()

	/** The marker we have passed*/
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = Sync)
	FName PreviousMarkerName;

	/** The marker we are heading towards */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = Sync)
	FName NextMarkerName;

	/** Value between 0 and 1 representing where we are:
	0   we are at PreviousMarker
	1   we are at NextMarker
	0.5 we are half way between the two */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = Sync)
	float PositionBetweenMarkers;
};
class FMarkerTickContext
{
private:
	// Structure representing our sync position based on markers before tick
	// This is used to allow new animations to play from the right marker position
	FMarkerSyncAnimPosition MarkerSyncStartPostion;

	// Structure representing our sync position based on markers after tick
	FMarkerSyncAnimPosition MarkerSyncEndPostion;

	// Valid marker names for this sync group
	const TArray<FName>* ValidMarkers;
};
```
`PreviousMarkerName` 和 `NextMarkerName` 表示把时间点夹在中间的前后两个 marker 的名字，播放前后两个时间点的位置一起存放在 `FMarkerTickContext` 中。这个 `FMarkerTickContext` 是后续 follower 更新时间的依据

无论是 follower 还是 leader，它们都需要保存当前时间点自己的播放进度相对于 marker 的位置（因为不同的 asset player 的 marker 排布可能不一样）
```c++
/**
* Information about an animation asset that needs to be ticked
*/
USTRUCT()
struct FAnimTickRecord
{
	// marker sync related data
	// 指向 `FAnimNode_AssetPlayerBase` 的 `MarkerTickRecord` 字段
	FMarkerTickRecord* MarkerTickRecord = nullptr;
};
struct FMarkerTickRecord
{
	//Current Position in marker space, equivalent to TimeAccumulator
	FMarkerPair PreviousMarker;
	FMarkerPair NextMarker;
};
struct FMarkerPair
{
	int32 MarkerIndex;
	float TimeToMarker;
}
```
`MarkerIndex` 是对该 asset player 的 marker 索引，`TimeToMarker` 则表示当前的播放进度到该 marker 的有符号距离（因此在前向播放时，`PreviousMarker` 的 `TimeToMarker` 通常是负值）

因此在 `TickAssetPlayer` 函数中会更新 tick 后的播放进度对应的 `FMarkerTickRecord`

具体 follower 是如何根据 `FMarkerTickContext` 来更新自己的 `FMarkerTickRecord`（因而比较前后的 `FMarkerTickRecord` 能得到自己的 delta time）呢？

大致来说，首先它会根据 leader 提供的 `MarkerSyncStartPostion` 找到一个与上一次播放进度最接近的时间以及对应的 marker 位置（这是 `UAnimSequence::GetMarkerIndicesForPosition` 函数的工作），当然一个优化是，如果 `FMarkerTickRecord` 中包含合法的数据，我们就复用上一帧结束时的 `FMarkerTickRecord`，

最简单的情况是如果 leader 在这一次 tick 没有越过任何的 marker，那么 `FMarkerTickRecord` 中的 marker 不变，我们只要根据 `MarkerSyncEndPostion` 来更新播放进度距离 marker 的相对位置即可。麻烦一点的情况是如果 leader 在 tick 中越过了若干 marker，follower 的逻辑是同样地越过这些 marker，最后 `PreviousMarker` 设置为 leader 最后越过的 marker，而 `NextMarker` 设置为从 `PreviousMarker` 开始找到的第一个匹配 `MarkerSyncEndPostion` 的 `NextMarkerName` 的 marker

安排 follower 越过相同的 marker 然后最终设置 `PreviousMarker` 和 `NextMarker` 而不是直接根据 `MarkerSyncEndPostion` 来设置 `PreviousMarker` 和 `NextMarker`，我觉得主要是为了播放的连贯性吧

计算出 follower 和 leader 实际的 delta time 和新的 current time，`TickAssetPlayer` 会将这个信息保存在 `DeltaTimeRecord` 和 `TimeAccumulator` 中
```c++
USTRUCT()
struct FAnimTickRecord
{
	float* TimeAccumulator = nullptr;
	// Asset players (and other nodes) have ownership of their respective DeltaTimeRecord value/state,
	// while an asset's tick update will forward the time-line through the tick record
	FDeltaTimeRecord* DeltaTimeRecord = nullptr;
};
```
#### 3. `FAnimNode_SequencePlayerBase::Evaluate_AnyThread`
这个函数根据之前的 `DeltaTimeRecord` 和 `TimeAccumulator` 信息从动画资产中提取当前帧的 animation pose
### 对文中提到的陷阱的解释
[UE4 UE5 你真的会用同步标记吗](https://zhuanlan.zhihu.com/p/614854028)  讲得挺好，这里对文中提到的陷阱做一些自己的解释。这些问题可以分为循环动画会发生和仅非循环动画会发生
#### 循环动画也会发生的问题
##### 陷阱1
这个比较简单，因为 marker 是基于名字去匹配，而不是基于 index 去匹配的，明白这一点就好了
##### 陷阱 2
感觉就是一个单纯的 bug，出 bug 的原因在于 `FMarkerSyncAnimPosition` 标记当前的播放位置具有歧义性。如果 `FMarkerTickRecord` 中不包含合法的 marker 信息时，`UAnimSequence::GetMarkerIndicesForPosition` 使用 `FMarkerSyncAnimPosition` 来在多个满足要求的播放位置中，选择与之前播放位置最相近的位置
```c++
				// Find marker indices closest to input time position.
				const float ThisDiff = FMath::Abs(ThisCurrentTime - CurrentInputTime);
				if (ThisDiff < DiffToCurrentTime)
				{
					DiffToCurrentTime = ThisDiff;
					OutPrevMarker.MarkerIndex = PrevMarkerIdx;
					OutNextMarker.MarkerIndex = NextMarkerIdx;
					OutCurrentTime = GetCurrentTimeFromMarkers(OutPrevMarker, OutNextMarker, SyncPosition.PositionBetweenMarkers);
				}
```
源码通过计算两个时间的之差来计算它们的距离，但对于循环动画来讲，应该还要考虑 loop，动画末尾的时间和动画开头的时间应该认为很相近才是（即使它们的差很大）
##### 陷阱 6
根源在于 `UAnimSequence::AdvanceMarkerPhaseAsFollower` 中下列逻辑， follower 在跟随 leader 越过 marker 之后，此时 `NextMarker` 应该指向 leader 最后越过的 marker，现在把值赋给 `PreviousMarker` 后，`NextMarker` 从当前的 index 开始找下一个合适的 marker，而不是从当前的 index + 1 开始找
```c++
		// Ensure next marker matches leader's next marker after tick.
		if (NextMarker.MarkerIndex != MarkerIndexSpecialValues::AnimationBoundary && Context.MarkersPassedThisTick.Num() > 0)
		{
			PreviousMarker.MarkerIndex = NextMarker.MarkerIndex;
			
			AdvanceMarkerForwards(NextMarker.MarkerIndex, LeaderEndPosition.NextMarkerName, bLooping, AuthoredSyncMarkers, MirrorTable);
		}
```
当连续的 marker 名字相同时，NextMarker 就不会往前步进，导致 `PreviousMarker` 和 `NextMarker` 指向同一个位置，表现出两个 marker 间的间距是整个动画长度，导致了超快的播放速度
#### 非循环动画引发的问题
循环动画可以越过播放边界地搜索 marker，但非循环动画不会这么做，这产生了一些微妙的问题

首先 `FAnimSync::TickAssetPlayerInstances` 中选择 sync group 的 leader 时，从评定的 leader score 从高到低遍历，调用 `UAnimSequence::TickAssetPlayer`，如果这个 asset player 没能设置合法的 `MarkerSyncEndPostion`，就不能把它选为 leader（TODO：这也挺微妙的，为啥要求 end position，而不是 start position 之类的）

由于对于非循环动画来说，在它的播放进度到达第一个 marker 前，它的 `MarkerSyncStartPostion` 和 `MarkerSyncEndPostion` 都是非法的（因为找不到合适的 `PreviousMarkerName`），因此若干非循环动画在同一个 sync group 里时，一开始是没有 leader 的，大家都正常播放

一旦有一个非循环动画跨过了第一个 marker，它能成为合法的 leader，然后此时还没有其它非循环动画跨过第一个 marker，就会导致陷阱 3 里说的非循环动画的停滞现象，直到 leader 越过第二个 marker 时停滞才会解除

TODO：结合 [Sync Groups](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-sync-groups-in-unreal-engine) 文档里说
> When blending with non-looping animations, such as run and walk starts and stops. Additionally with this case, the start and stop animations should be set to **Always Leader**.

我感觉我还是没有理解清楚非循环动画中应该如何使用 sync group，想明白这个可能才能更好理解为啥引擎要这么去设计
### Blend Space 中的同步标记
TODO：解释 Blend Space 是如何利用同步标记的，可以看看 [UE4动画系统之同步组源码浅析](https://zhuanlan.zhihu.com/p/651145624)
### Montage 中的同步标记
`UAnimMontage` 中设置 `SyncGroup` 和 `SyncSlotIndex` 表明这个 montage 的 sync group，以及应该在哪个 slot track 上搜集 marker
```c++
	/** If you're using marker based sync for this montage, make sure to add sync group name. For now we only support one group */
	UPROPERTY(EditAnywhere, Category = SyncGroup)
	FName SyncGroup;

	/** Index of the slot track used for collecting sync markers */
	UPROPERTY(EditAnywhere, Category = SyncGroup)
	int32 SyncSlotIndex;

	UPROPERTY()
	struct FMarkerSyncData	MarkerData;
```
`UAnimMontage::CollectMarkers` 负责实际地收集 marker，存放在 `MarkerData` 中。搜集的方法也很简单，就是这个 slot track 上按时间顺序出现的 `FAnimSegment` 对应的 animation asset 的时间轴上的 marker

然后在 `FAnimMontageInstance::Advance` 正常步进，当 montage 处于淡出状态时，才会搜集步进过程中跨越的 marker（由于用户可以任意设置 section 的连接顺序，步进的过程和时间轴上 `FAnimSegment` 的先后顺序可能不一样），在 `UAnimInstance::UpdateMontageSyncGroup` 中将 montage 当前的播放状态作为一个 `FAnimTickRecord` 加入到对应的 sync group 中。这些都是在 game thread 上完成的

然后 `UAnimMontage` 重载了 `TickAssetPlayer` 函数，因为之前已经在 game thread 上步进过了，因此重载后的函数只需要设置在该 montage 是 leader 时设置 `FAnimAssetTickContext` 的各项数据即可

TODO：由于 section 导致 montage 的播放顺序和时间轴上 `FAnimSegment` 的先后顺序可能不太一样，而且 montage 标记 `PreviousTime` 和 `CurrentTime` 是用的时间轴上的时间，而不是实际的播放时间，因此我感觉在用 sync group 且不用 sync marker，并且设置跳跃连接的 section 时会导致 follower 跳跃的情况....

Notes：`UAnimInstance` 提供的 `MontageSync_Follow` 函数是用来让多个 montage 同步播放的（在淡入和正常播放时有效，开始淡出时就无效了，因此它的作用和 sync group 没有关系）



TODO：解释 transition leader 和 transition follower 的作用