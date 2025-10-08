---
title: FName in Unreal
categories:
  - UE5
comments: true
date: 2022-10-08 15:30:11 +0800
---

整个 FName 实际上是一个哈希表，但它处理的问题和通常的哈希表有两点不同
* 字符串是变长的，所以存储上需要一些额外的处理
* 这个哈希表不会删除元素

第一个问题是我为什么要做一个字符串哈希表，就直接用 FString 不行吗？从 [String Handling](https://dev.epicgames.com/documentation/en-us/unreal-engine/string-handling-in-unreal-engine) 文档来看，FName 的最大优势在于只存了一个哈希表的索引，比较操作只需要比较索引是否相同，因此它特别适合名字等不会改变，又需要频繁比较的字符串

那为什么是哈希表呢？我做个字符串数组，存放的索引就是一个数组下标呢？这在产生新的 FName 时会出问题，为了使得索引相同等价于字符串相同，在拆入新 FName 时就需要知道是否该字符串已经在里面了，使用哈希表这个数据结构能够加速查找这个操作

我们先考虑通常的字符串哈希表的实现，例如我要把 std string 放到 unordered set 里。这是怎么把变长转为定长的呢？因为字符串的存储是另外在堆上分配的，我只在 unordered set 里存储了指向字符串的指针，字符串长度之类的元数据，而这元数据是定长的

在通常的字符串哈希表实现中，字符串数据存储占用的内存使用的是一般的堆内存分配算法，但这里我们有一个额外的假设是哈希表不会删除元素，所以 FName 中采取了更简单的 bump allocator 来分配字符串占用的内存

现在我们来看 FName 的实现就很简单了
```c++
class FName
{
private:
	/** Index into the Names array (used to find String portion of the string/number pair used for comparison) */
	FNameEntryId	ComparisonIndex;
	uint32			Number;
#if WITH_CASE_PRESERVING_NAME
	/** Index into the Names array (used to find String portion of the string/number pair used for display) */
	FNameEntryId	DisplayIndex;
#endif // WITH_CASE_PRESERVING_NAME
}
```
这个 `FNameEntryId` 类型就是表示哈希表项的索引。FName 在比较时不区分大小写，这在编辑器模式下显示 name 时有时会带来困扰（因为用户可能存了一个大写的名称，但是显示出来却是小写）。因此在编辑器模式下，有额外的 `DisplayIndex`，用来索引真实的 name。这里存在一个优化，就是我没必要总是存两份字符串，一份区分大小写的，一份不区分大小写的

举一个例子，我要存储字符串 ABcd，我在计算哈希值和字符串比较时，不区分大小写，然后发现哈希表中没有该字符串，那我把该字符串插入到哈希表中，但插入时我就区分大小写，把 ABcd，而不是 abcd 插入进去。此时我就只存储了一份数据，可以把 FName 的 `ComparisonIndex` 和 `DisplayIndex` 设置为相同的

再后续我要存储字符串 abcd，在不区分大小写的哈希值和字符串比较中，发现哈希表中有字符串 ABcd，那我就把 `ComparisonIndex` 设置为和 ABcd 对应的 `ComparisonIndex` 相同，但由于我现在还没有把真正的 abcd 插入进去，所以再做一遍区分大小写的哈希和字符串比较，将 abcd 插入到哈希表中合适的位置，然后用 `DisplayIndex` 索引这个新插入的 abcd

接下来我们看 `FNamePool` 这个全局单例，它具体实现了这个哈希表
```c++
class FNamePool
{
	FNameEntryAllocator Entries;
#if WITH_CASE_PRESERVING_NAME
	FNamePoolShard<ENameCase::CaseSensitive> DisplayShards[FNamePoolShards];
#endif
	FNamePoolShard<ENameCase::IgnoreCase> ComparisonShards[FNamePoolShards];
};

class FNamePoolShardBase : FNoncopyable
{
	uint32 UsedSlots = 0;      // 已经使用的 FNameSlot
	uint32 CapacityMask = 0;    // 数组的大小
	FNameSlot* Slots = nullptr; // `FNameSlot` 数组
	FNameEntryAllocator* Entries = nullptr;
};
```
这个哈希表有两层。字符串进行哈希，得到 64bits 整数。高 32 位的低若干位（`ShardMask`）用来索引 `ComparisonShards` 或者 `DisplayShards`（取决于是哈希时是否忽略大小写），低 32 位用来索引 `FNamePoolShard` 中的 `Slots` 数组的下标

而 `FNameSlot` 就是我们提到的固定大小的，索引字符串的元数据，也是哈希表中的元素类型。在 `UsedSlots` 超过 Capacity 一定比例时，重新申请内存，Slots 数组长度翻倍（常见的哈希表扩容方法）。在发生哈希碰撞时，从发生碰撞的位置遍历 Slots 数组，寻找没有使用的 `FNameSlot`。这样我们就看清楚了整个哈希表的结构

那具体 `FNameSlot` 是怎么索引字符串的呢？这和 `FNameEntryAllocator` 有关系。首先所有的 `FNamePoolShard` 中的 `Entries` 都引用的是 `FNamePool` 中的 `Entries` 实例。而这个 `FNameEntryAllocator` 实际上就是一个 bump allocator
```c++
static constexpr uint32 FNameMaxBlockBits = 13; // Limit block array a bit, still allowing 8k * block size = 1GB - 2G of FName entry data
static constexpr uint32 FNameBlockOffsetBits = 16;
static constexpr uint32 FNameMaxBlocks = 1 << FNameMaxBlockBits;
static constexpr uint32 FNameBlockOffsets = 1 << FNameBlockOffsetBits;
static constexpr uint32 FNameEntryIdBits = FNameBlockOffsetBits + FNameMaxBlockBits;
static constexpr uint32 FNameEntryIdMask = (1 << FNameEntryIdBits ) - 1;

class FNameEntryAllocator
{
	uint32 CurrentBlock = 0;
	uint32 CurrentByteCursor = 0;
	uint8* Blocks[FNameMaxBlocks] = {};
};
```
它的逻辑很简单，这个 `CurrentBlock` 索引 `Blocks`，返回的指针指向当前正用于分配的 block，每个 block 的大小是 `alignof(FNameEntry) * FNameBlockOffsets`，然后 `CurrentByteCursor` 表示该 block 已经分配了多少 bytes 了。如果新的分配请求会使得 `CurrentByteCursor` 超过 block 的大小，那就申请一个新的 block，地址填入 `Blocks` 数组中，然后 `CurrentBlock` 加 1

这里限制 block 的数量和 block 的大小是为了把 `FNameSlot` 做得尽可能小，`FNameSlot` 只有 4 bytes，它的低 16 位用于存储字符串在 block 中的偏移，16 - 29 位用于存储这个 block 在 `Blocks` 数组中的下标，还有 3 位用于存储字符串 64 bits 哈希值的若干位（作为一个 tag，这样发生哈希碰撞时可以先比较这个 tag，而不是完整的字符串比较）

另外，block 上填入的实际上是 header + 字符串，这个 header 用 `FNameEntry` 来描述，它包含一些字符串的元数据，主要是字符串是否是宽字符串（一个字符占 2 Bytes），以及字符串的长度

然后说一下内置的 name，这些定义在 `UnrealNames.inl` 中。通过 include 这个文件，使得每个这里面的名字都定义为了一个枚举变量 `EName`，并且在 `FNamePool` 初始化时就把这些名字插入进去了，并且存储了 EName 和 `FNameEntryId` 的映射，使得它们可以互转

最特殊的名字是 None，它在 `UnrealNames.inl` 的开头，是第一个插入到 `FNamePool` 中的名字，因此 block 和 block offset 都为 0，也即 `FNameEntryId` 为 0。因为 unused slot 也为 0，为了区分，引擎在计算 `SlotProbeHash` 时做了一点手脚
```c++
	FNameHash(uint64 Hash, int32 Len, bool IsNone, bool bIsWide)
	{
		uint32 Hi = static_cast<uint32>(Hash >> 32);
		uint32 Lo = static_cast<uint32>(Hash);

		// "None" has FNameEntryId with a value of zero
		// Always set a bit in SlotProbeHash for "None" to distinguish unused slot values from None
		// @see FNameSlot::Used()
		uint32 IsNoneBit = IsNone << FNameSlot::ProbeHashShift;

		ShardIndex = Hi & ShardMask;
		UnmaskedSlotIndex = Lo;
		SlotProbeHash = (Hi & FNameSlot::ProbeHashMask) | IsNoneBit;
}
```
最后，`FNameEntryAllocator` 和 `FNamePoolShard` 都是有锁的，因此 FName 可以在多线程环境下使用