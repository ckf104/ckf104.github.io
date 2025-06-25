---
title: Asset Manager in Unreal
categories:
  - UE5
date: 2025-01-14 21:44:51 +0800
comments: true
---

### Package Loading / Unloading
`LoadPackage`，`LoadObject` 以及 `FStreamableManager` 相关的 loading 函数，它们底下都是调用全局的 async package loader 提供的 load package async 接口

试着调用了一下 `UPackageTools::UnloadPackages`，观察到的现象是
* 如果此时没有指针指向这个 package 中的对象，那么这个 package 就能被 unload
* 如果有指针指向这个 package 中的对象（或者是任何子对象），这个 package 就仍然在内存中

查看 `UPackageTools::UnloadPackages` 的源码，它其实就是调用 `CollectGarbage` 来手动触发 GC。大概的流程如下
* 首先将需要 unload 的 package 加入到 gc root 中，避免 package 和它的 `MetaData` 被回收
* 由于编辑器模式下带有 `RF_StandAlone` 标记的 uobject 会被视为 root object，因此把需要卸载的 package 包含的 objects（所有在该 package 中的 objects，不仅仅是 outer 为该 package 的 objects）的 `RF_StandAlone` 标记都 clear 掉
* 调用 `CollectGarbage` 触发垃圾回收
* 如果有该 package 中的 object 没有被回收，并且它的 `RF_StandAlone` 标记在之前被 clear 掉了，那么重新 set 它的 `RF_StandAlone` 标记
* 将 package 从 gc root 中移除，清除掉 package 的 `MetaData` 的 `RF_StandAlone` 标记，再次调用 `CollectGarbage` 触发垃圾回收

TODO：看看 `RF_StandAlone` 哪来的，是不是只有在编辑器模式下才有
TODO：解释为什么要调用两次 `CollectGarbage` 来分批回收
TODO：看看官方文档 [Asset Metadata](https://dev.epicgames.com/documentation/en-us/unreal-engine/asset-metadata-in-unreal-engine?application_version=5.4)，这玩意好像只是在编辑器模式下有用
### Asset Registry
asset registry 是 asset manager 以及 content browser 依赖的更底层的资产管理模块。它会扫描目录中的 uasset 文件，每个 uasset 文件通过一个 `FAssetData` 结构来描述
```c++
struct FAssetData
{	
	/** The name of the package in which the asset is found, this is the full long package name such as /Game/Path/Package */
	FName PackageName;
	/** The path to the package in which the asset is found, this is /Game/Path with the Package stripped off */
	FName PackagePath;
	/** The name of the asset without the package */
	FName AssetName;
	/** The path of the asset's class, e.g. /Script/Engine.StaticMesh */
	FTopLevelAssetPath AssetClassPath;
	/** The map of values for properties that were marked AssetRegistrySearchable or added by GetAssetRegistryTags */
	FAssetDataTagMapSharedView TagsAndValues;
	/**
	 * The 'AssetBundles' tag key is separated from TagsAndValues and typed for performance reasons.
	 * This is likely a temporary solution that will be generalized in some other fashion. 	
	 */
	TSharedPtr<FAssetBundleData, ESPMode::ThreadSafe> TaggedAssetBundles;
	// 其它字段.....
};
```
展示的 `FAssetData` 的前三个字段用来描述 asset 的路径，第四个字段描述 asset 的 object 类型，后两个字段是与该 asset 相关的，用户可自定义的额外信息，`TagsAndValues` 和 `TaggedAssetBundles` 将分别在 Customize Asset Details 和 Asset Bundle 小节进行描述

asset data 对应的 uobject 可能并没有加载到内存中。如果需要获取对应的 uobject，调用 asset data 的 `GetAsset` 函数即可，该函数内部会调用 `LoadPackage` 同步地加载 package，然后返回对应的 uobject

而 asset path 到 asset data 的映射维护在 `FAssetRegistryState` 中，一些更详细的讨论以及对其它字段的描述可以参考 [UE4 AssetRegistry分析](https://zhuanlan.zhihu.com/p/76964514)
#### Customize Asset Details
`TagsAndValues` 字段以 key, value 的形式记录了 asset 的额外信息，也就是当我们将鼠标放置于编辑器的 asset 图标上时显示的信息。用户可以重载 uobject 的 `GetAssetRegistryTags` 函数来定义自己的 key，value pair
```c++
/**
* Gathers a list of asset registry searchable tags which are name/value pairs with some type information
* This only needs to be implemented for asset objects
*
* @param	OutTags		A list of key-value pairs associated with this object and their types
*/
COREUOBJECT_API virtual void GetAssetRegistryTags(FAssetRegistryTagsContext Context) const;
```
一个简单的应用例子可以见 `UDataTable`，这使得 data table 的资产会额外显示一个 `RowStructure` 字段，表示这个 data table 使用的 ustruct 是谁
```c++
void UDataTable::GetAssetRegistryTags(FAssetRegistryTagsContext Context) const
{
	if (AssetImportData)
	{
		Context.AddTag( FAssetRegistryTag(SourceFileTagName(), AssetImportData->GetSourceData().ToJson(), FAssetRegistryTag::TT_Hidden) );
	}

	// Add the row structure tag
	{
		static const FName RowStructureTag = "RowStructure";
		Context.AddTag( FAssetRegistryTag(RowStructureTag, GetRowStructPathName().ToString(), FAssetRegistryTag::TT_Alphabetical) );
	}

	Super::GetAssetRegistryTags(Context);
}
```
另外一种自定义资产显示的 key, value pair 的方式是使用 `AssetRegistrySearchable` uproperty 进行标记。在 uobject 的 `GetAssetRegistryTags` 函数中，会搜索自己所有的带有 `CPF_AssetRegistrySearchable` 标记的 uproperty，然后将其加入到这个 `FAssetRegistryTagsContext` 参数中。具体的逻辑见 `GetAssetRegistryTagFromProperty` 函数。[UE 中利用反射为资产建立属性缓存](https://imzlp.com/posts/71162/) 对此也描述得挺不错的

在 save package 时，会调用 uobject 的 `GetAssetRegistryTags` 函数来获取 uobject 所有的 key，value pairs，然后将其序列化到磁盘中

我测试的时候发现，一个微妙的地方在于，如果 `FAssetData` 中包含了某个 key，而这个 asset 对应的类的 CDO 中没有这个 key，那么编辑器的 asset detail 面板仍然不会显示这个 key。一个典型的例子是 primary asset name 和 primary asset type。[虚幻引擎资产管理总结](https://zhuanlan.zhihu.com/p/503069332) 谈到区分 primary asset 和 secondary asset 的简单方法就是看这个 asset 的 detail 面板中是否包含 primary asset name 和 primary asset type。但当我自定义一个继承于 `UPrimaryDataAsset` 的资产，且没有重载 `UPrimaryDataAsset` 提供的 `GetPrimaryAssetId` 函数时，却发现这个资产的 detail 面板没有显示 primary asset name 和 primary asset type 字段，即使我们可以通过 asset data 的 `EnumerateTags` 函数将它们枚举出来

首先我们说明为什么应该显示出这俩字段，这是因为在 uobject 的 `GetAssetRegistryTags` 函数中会获取该 uobject 的 primary asset id，如果确实存在，就会将其加入到资产的 key value pair 中
```c++
	FPrimaryAssetId PrimaryAssetId = GetPrimaryAssetId();
	if (PrimaryAssetId.IsValid())
	{
		Context.AddTag(FAssetRegistryTag(FPrimaryAssetId::PrimaryAssetTypeTag, PrimaryAssetId.PrimaryAssetType.ToString(),
			UObject::FAssetRegistryTag::TT_Alphabetical));
		Context.AddTag(FAssetRegistryTag(FPrimaryAssetId::PrimaryAssetNameTag, PrimaryAssetId.PrimaryAssetName.ToString(),
			UObject::FAssetRegistryTag::TT_Alphabetical));
	}
```
而在 `UPrimaryDataAsset` 提供的 `GetPrimaryAssetId` 实现中，它会对 native C++ 类的 CDO 返回空的 primary asset id，这就导致了 CDO 中没有这俩字段，进而导致 asset detail 面板没有显示 primary asset name 和 primary asset type 字段

具体地，在 `FAssetPropertyTagCache::GetCacheForClass` 函数里，它调用 CDO 的 `GetAssetRegistryTags` 函数来获取这个类的 key value pairs，将整个信息存储在 `FClassPropertyTagCache` 结构体中。我猜后面需要展示这个对应 key 的值的时候再从对应的 asset data 中获取吧，大概是这样一个逻辑

TODO：看看 SavePackages研究一下 uasset 在磁盘上的存储格式
TODO：解释 `UAssetImportData` 类
TODO：解释 `UPackage` 类以及 `FAssetPackageData`，在 cook 之后的 game 中还存在 `UPackage` 吗
TODO：结合 [UE4 AssetRegistry分析](https://zhuanlan.zhihu.com/p/76964514) 阐述一下 asset registry 其它的字段
### Asset Manager
asset manager 帮助我们管理 primary asset，它获取 asset 的信息时依赖于底层的 asset registry 模块

primary asset 的类型根据 `FPrimaryAssetType` 进行区分，具体有哪些 `FPrimaryAssetType` 可以在 project settings 中的 asset manager 模块中进行设置，这个信息实际存储在 `UAssetManagerSettings` 类中。一个 primary asset 实例用一个 `FPrimaryAssetId` 唯一标记。`FPrimaryAssetType` 内部就是一个 `FName`，而 `FPrimaryAssetId` 内部是两个 `FName`，一个表示 primary asset type，一个表示 primary asset name。要定义一个 uobject 的 `FPrimaryAssetId`，可以重载 `UObject::GetPrimaryAssetId` 函数

asset manager 的 `AssetTypeMap` 字段建立了 primary asset type 到其相关数据的映射
```c++
	/** Per-type asset information, cannot be accessed by children as it is defined in CPP file */
	TMap<FName, TSharedRef<FPrimaryAssetTypeData>> AssetTypeMap;
```
`FPrimaryAssetTypeData` 主要包含两部分内容，一个是 `AssetMap` 字段，建立了 primary asset name 到 `FPrimaryAssetData` 的映射。另一个是 `Info` 字段，它包含了我们在 project settings 的 asset manager 模块中对 primary asset type 的配置
```c++
struct FPrimaryAssetTypeData
{
	/** The public info struct */
	FPrimaryAssetTypeInfo Info;
private:
	/** Map of scanned assets */
	TMap<FName, FPrimaryAssetData> AssetMap;
};
```
asset manager 的全局单例保存在 `UEngine` 的 `AssetManager` 字段中，`UEngine::Init` 函数中，会调用 new object 创建 `AssetManager`，然后调用 asset manager 的 `StartInitialLoading`，这会调用 `ScanPrimaryAssetTypesFromConfig`，这个函数中 asset manager 会读取 `UAssetManagerSettings` 中的配置信息，为 primary asset type 初始化它的 `FPrimaryAssetTypeData` 结构的 `Info` 字段，然后根据 `Info` 中的 search path，调用 asset registry 的 `EnumerateAssets` 来寻找路径上符合要求的 asset data，对每个找到的 asset data 初始化一个 `FPrimaryAssetData` 结构

然后我们来看下 `FPrimaryAssetData` 包含了哪些数据
```c++
struct FPrimaryAssetData
{
private:
	// These are used as the keys in a reverse map and cannot be modified except when modifying the reversemap as well
	FSoftObjectPtr AssetPtr;
	FSoftObjectPath ARLookupPath;

public:
	/** Current state of this asset */
	FPrimaryAssetLoadState CurrentState;
	/** Pending state of this asset, will be copied to CurrentState when load finishes */
	FPrimaryAssetLoadState PendingState;
};
```
`ARLookupPath` 表示这个 asset 的路径，`FSoftObjectPtr` 是 `TSoftObjectPtr<T>` 去掉泛型的内部表示，这个指针类型的含义见 Template Pointer in Unreal。因此 `AssetPtr` 实际上是 asset 的软引用，对于非蓝图类，它指向的就是 asset 对应的 uobject，而对于蓝图类，它指向的是 blueprint generated class。`CurrentState` 和 `PendingState` 表示这个 primary asset 当前的加载状态。接下来讨论 primary asset loading 时会解释它们的含义
#### Streamable Manager
primary asset loading 是基于 asset manager 内部的 `StreamableManager`，因此我们先讨论一下 streamable manager 的实现
```c++
	/** The streamable manager used for all primary asset loading */
	FStreamableManager StreamableManager;
```
streamable manager 提供了对异步加载的 package 的管理。它的加载 package 的接口函数为
```c++
	/** 
	 * This is the primary streamable operation. Requests streaming of one or more target objects. When complete, a delegate function is called. Returns a Streamable Handle.
	 *
	 * @param TargetsToStream		Assets to load off disk
	 * @param DelegateToCall		Delegate to call when load finishes. Will be called on the next tick if asset is already loaded, or many seconds later
	 * @param Priority				Priority to pass to the streaming system, higher priority will be loaded first
	 * @param bManageActiveHandle	If true, the manager will keep the streamable handle active until explicitly released
	 * @param bStartStalled			If true, the handle will start in a stalled state and will not attempt to actually async load until StartStalledHandle is called on it
	 * @param DebugName				Name of this handle, will be reported in debug tools
	 */
	ENGINE_API TSharedPtr<FStreamableHandle> RequestAsyncLoad(TArray<FSoftObjectPath> TargetsToStream, FStreamableDelegate DelegateToCall = FStreamableDelegate(), TAsyncLoadPriority Priority = DefaultAsyncLoadPriority, bool bManageActiveHandle = false, bool bStartStalled = false, FString DebugName = TEXT("ArrayDelegate"));
```
接受一个 asset 路径数组，以及一个加载完成的回调函数，返回一个 streamable handle 与 streamable manager 进行交互。如果 `bManageActiveHandle` 为 false，那么返回的 `TSharedPtr<FStreamableHandle>` 的引用计数默认为 1，用户需要自己记录返回的 handle，否则 handle 就自动析构了。如果 `bManageActiveHandle` 设置为 true，那么 handle 会被加入到 streamable manager 的 `ManagedActiveHandles` 字段中。这样用户后续可以通过 `FStreamableManager::GetActiveHandles` 函数根据 asset 路径又拿回 handle
```c++
/** List of explicitly held handles */
TArray<TSharedRef<FStreamableHandle>> ManagedActiveHandles;
```
streamable manager 内部使用 `FStreamable` 结构来追踪单个 asset 的加载情况，它的 `StreamableItems` 字段中记录了 asset 路径到 `FStreamable` 结构的映射
```c++
/** Map of paths to streamable objects, this will be the post-redirector name */
typedef TMap<FSoftObjectPath, struct FStreamable*> TStreamableMap;
TStreamableMap StreamableItems;
```
而 handle 的 `RequestedAssets` 字段记录了这个 handle 请求的所有 asset 的路径
```c++
	/** List of assets that were referenced by this handle */
	TArray<FSoftObjectPath> RequestedAssets;
```
`FStreamable` 结构体内部的数据如下，`ActiveHandles` 中记录所有与这个 `FStreamable` 相关联的 asset 的 handle，如果这个 asset 正在 loading 中，那么 `LoadingHandles` 会持有与之关联的 handle 的共享指针，避免这个 handle 被析构了
```c++
/** Internal object, one of these per object paths managed by this system */
struct FStreamable
{
	/** Hard GC pointer to object */
	TObjectPtr<UObject> Target = nullptr;

	/** Live handles keeping this alive. Handles may be duplicated. */
	TArray<FStreamableHandle*> ActiveHandles;

	/** Handles waiting for this to load. Handles may be duplicated with redirectors. */
	TArray< TSharedRef< FStreamableHandle> > LoadingHandles;

	/** Id for async load request with async loading system */
	int32 RequestId = INDEX_NONE;

	/** If this object is currently being loaded */
	bool bAsyncLoadRequestOutstanding = false;

	/** If this object failed to load, don't try again */
	bool bLoadFailed = false;
};
```
这样整个数据结构的关联就清楚了，每个 handle 通过自己的 `RequestedAssets` 字段关联上 asset，而 `StreamableItems` 字段则建立了 asset 与 `FStreamable` 的关系。然后 `FStreamable` 又通过 `ActiveHandles` 字段记录了与之关联的 handle 有哪些

最后说一下 `RequestAsyncLoad` 的实现。它会创建一个新的 handle，设置 `RequestedAssets` 字段为用户传入的 asset path，用户传入的回调保存在 handle 的 `CompleteDelegate` 字段中，然后为每个 asset path 找到或者创建一个 `FStreamable` 结构。在根据 asset path 异步加载 package 前，它会首先在内存中寻找，如果找不到才调用 `LoadPackageAsync` 函数进行加载，并设置 handle 的 `AsyncLoadCallbackWrapper` 函数作为 asset 加载完成的回调。因为 handle 持有 streamable manager 的指针，因此这个回调函数又会调用 `FStreamableManager::AsyncLoadCallback`，而 streamable manager 的这个回调函数则根据加载上来的 asset，置空对应的 `FStreamable` 结构的 `LoadingHandles` 字段，并设置 `Target` 字段记录加载上来的 uobject。如果 handle 关联的 asset 都加载完成了，那么调用存储在 handle 的 `CompleteDelegate` 字段中的用户回调

最后说一下 streamable manager 中与垃圾回收相关的部分。在 handle 析构，或者手动调用 handle 的 `CancelHandle` 或 `ReleaseHandle` 时，它会找到所有与自己关联的 `FStreamable`，然后将自己从 `FStreamable` 的 `ActiveHandles` 中移除。streamable manager 继承自 `FGCObject`，重载了它的 `AddReferencedObjects` 方法，来保证 `FStreamable` 引用的 `Target` 都不会被 GC 移除。同时 streamable manager 在自己的构造函数中，注册了一个 pre garbage collect 回调 `OnPreGarbageCollect`，这个回调函数在垃圾回收开始执行之前调用，它会将所有 `ActiveHandles` 为空的 `FStreamable` 从 `StreamableItems` 这个 map 中移除

如果与 asset 相关联的 handle 都被 release 掉了，那 streamable manager 将不再持有这个 asset 的引用，如果此时 asset 也没有其它的引用了，且在非编辑器模式下，这个 asset 就会被垃圾回收掉。但在编辑器模式下，由于 asset 对应的 object 持有 `RF_StandAlone` 标记，因此它将仍然保留在内存中，除非手动调用 `UPackageTools::UnloadPackages`
#### Primary Asset Loading
streamable manager 是通过 asset path 来对 asset 进行加载。而更上层的 asset manager 提供了 `LoadPrimaryAsset` 函数，根据 primary asset id 来加载 asset。同样的，可以指定一个回调函数，在加载完成时调用。返回 `TSharedPtr<FStreamableHandle>`
```c++
	/** 
	 * Loads a list of Primary Assets. This will start an async load of those assets, calling callback on completion.
	 * These assets will stay in memory until explicitly unloaded.
	 * You can wait on the returned streamable request or poll as needed.
	 * If there is no work to do, returned handle will be null and delegate will get called before function returns.
	 *
	 * @param AssetsToLoad		List of primary assets to load
	 * @param LoadBundles		List of bundles to load for those assets
	 * @param DelegateToCall	Delegate that will be called on completion, may be called before function returns if assets are already loaded
	 * @param Priority			Async loading priority for this request
	 * @return					Streamable Handle that can be used to poll or wait. You do not need to keep this handle to stop the assets from being unloaded
	 */
	ENGINE_API virtual TSharedPtr<FStreamableHandle> LoadPrimaryAssets(const TArray<FPrimaryAssetId>& AssetsToLoad, const TArray<FName>& LoadBundles = TArray<FName>(), FStreamableDelegate DelegateToCall = FStreamableDelegate(), TAsyncLoadPriority Priority = FStreamableManager::DefaultAsyncLoadPriority);
```
不过在使用 asset manager 加载 primary asset 时，每个 primary asset 都会对应一个 handle，但最后返回的只有一个 handle，因此 streamable manager 提供了 `CreateCombinedHandle` 函数将多个 handle 合并为一个，这个 combined handle 的 `bIsCombinedHandle` 字段为 true，并且 `ChildHandles` 字段中记录了所有的 child handle，当所有的 child handle 加载完成时，combined handle 才加载完成，同时 child handle 的 `ParentHandles` 记录了自己的 parent handle 是谁。注意，`ChildHandles` 字段使用了 shared ptr，而 `ParentHandles` 字段使用了 weak ptr 来打破循环引用。由于 `LoadPrimaryAssets` 返回了 parent handle，这样保证了用户不释放手里的 handle，与之关联的 child handle 就不会被释放
```c++
	/** List of handles this depends on, these will keep the child references alive */
	TArray<TSharedPtr<FStreamableHandle> > ChildHandles;

	/** Backpointer to handles that depend on this */
	TArray<TWeakPtr<FStreamableHandle> > ParentHandles;
```
现在我们可以回头看下这个 `FPrimaryAssetData` 中的 `CurrentState` 和 `PendingState` 了，它保存了目前负责加载这个 asset 的 handle。额外的 `BundleName` 字段在 Asset Bundle 一节会进行解释
```c++
struct FPrimaryAssetLoadState
{
	/** The handle to the streamable state for this asset, this keeps the objects in memory. If handle is invalid, not in memory at all */
	TSharedPtr<FStreamableHandle> Handle;
	/** The set of bundles to be loaded by the handle */
	TArray<FName> BundleNames;
};
```
如果 asset 此前已经通过 `LoadPrimaryAsset` 函数加载进来了，那么 `LoadPrimaryAsset` 会检测到这个 asset 的 `FPrimaryAssetData` 的 current state 已经被设置为一个合法的 handle 了，就会跳过加载。如果所有的 asset 都是这样，该函数就会返回一个空的 handle

而如果 asset 此前是直接调用 `LoadPakcge` 或 streamable manager 的 `RequestAsyncLoad`，绕过了 asset manager 加载进来的。由于 asset manager 没有相关的信息，那么正常调用 streamable manager 的 `RequestAsyncLoad` 函数接口。但正如前面所说，streamable manager 会先检查一下这个 asset 是否已经在内存中，如果找到了，streamable manager 会直接调用 handle 的 `CompleteLoad` 函数，标记这个 handle 已经加载完成了

这里稍微有些微妙的是，handle 完成加载时，不会马上调用 `CompleteDelegate` 字段上绑定的回调，而是会延后一个 tick。也就是说，调用 streamable manager 的 `RequestAsyncLoad` 时，即使 asset 已经被加载到内存中的，回调函数也不会马上被执行。但 asset manager 这里又希望如果 asset 在内存中时，回调能够马上执行。因此在 `LoadPrimaryAssets` 函数中，调用 `RequestAsyncLoad` 时没有传递回调函数，如果返回的 handle 已经加载完成了，那么将这个 handle 存入对应的 `FPrimaryAssetData` 的 `CurrentState` 中，直接执行用户传入的回调函数。否则，将 handle `CompleteDelegate` 回调设置为 asset manager 的 `OnAssetStateChangeCompleted` 函数，并将 handle 存入 `PendingState` 中。`OnAssetStateChangeCompleted` 函数会负责将 handle 从 `PendingState` 移到 `CurrentState`，并调用用户指定的回调函数

我们可以考虑一下返回的 `TSharedPtr<FStreamableHandle>` 的引用计数。对于 asset 已经在内存中的 handle，它的引用计数为 2
* 返回的 handle 贡献一个引用计数
* `FPrimaryAssetData` 的 `CurrentState` 贡献一个引用计数
而如果 asset 需要异步加载，那么返回的 handle 引用计数会更多
* 返回的 handle 贡献一个引用计数
* `FPrimaryAssetData` 的 `PendingState` 贡献一个引用计数
* streamable manager 中 handle 对应的 `FStreamable` 结构体 `LoadingHandles` 会贡献引用计数
* handle 的 `CompleteDelegate` 除了绑定 asset manager 的 `OnAssetStateChangeCompleted` 回调外，还绑定了这个函数的参数。其中一个参数就是这个 handle 自己，因此这里又会贡献一个引用计数

可以看到，在加载完成后，与直接调用 streamable manager 的加载函数相比，`FPrimaryAssetData` 的 `CurrentState` 会额外贡献一个引用计数

与 `LoadPrimaryAsset` 相对应的是 `UnloadPrimaryAsset` 函数，它会把 primary asset id 对应的 `FPrimaryAssetData` 持有的 handle 清空，并
调用 handle 的 `CancelHandle` 函数将该 handle 从 streamable manager 中移除（此时该 handle 就没用了，即使用户手里还持有它的引用，让它没有析构）
#### Asset Bundle
在 `ObjectMacros.h` 中定义了 UE 中所有的拓展宏，其中 `AssetBundles` 是用于 uproperty 的 metadata。从注释可以看到，用 `AssetBundles` 修饰的字段应位于 primary data asset 中并且类型是 `SoftObjectPtr` 或 `SoftObjectPath`
```C++
		/// [PropertyMetadata] Used for SoftObjectPtr/SoftObjectPath properties. Comma separated list of Bundle names used inside PrimaryDataAssets to specify which bundles this reference is part of
		AssetBundles,
```
它用于指示字段属于哪些 bundle。通常情况下，`SoftObjectPath` 和 `SoftObjectPtr` 作为一种软链接，在 primary data asset 加载到内存中时，它们指向的 asset 不会被加载。但 asset manager 的 `LoadPrimaryAssets` 函数接受一个 `LoadBundles` 参数，指示属于哪些 bundle 的 asset 需要也加载进来。此时这个 primary data asset 对应的 streamable handle 的 `RequestedAssets` 字段包括的 asset 除了 primary data asset 外，还包括需要加载的 bundle 中含义的 asset

查看保存的 uasset 文件可以发现，`AssetBundles` metadata 信息会序列化到磁盘。由此我们可以拿到每个 primary data asset 的 bundle 组成。在内存中这些信息保存在 `FAssetData` 的 `TaggedAssetBundles` 字段中
```c++
	/**
	 * The 'AssetBundles' tag key is separated from TagsAndValues and typed for performance reasons.
	 * This is likely a temporary solution that will be generalized in some other fashion. 	
	 */
	TSharedPtr<FAssetBundleData, ESPMode::ThreadSafe> TaggedAssetBundles;
```
也会 cache 在 asset manager 的 `CachedAssetBundles` 字段
```c++
	/** Cached map of asset bundles, global and per primary asset */
	TMap<FPrimaryAssetId, TSharedPtr<FAssetBundleData, ESPMode::ThreadSafe>> CachedAssetBundles;
```
`FAssetBundleData` 结构体包含了一个 primary data asset 的全部 bundle 信息
```c++
struct FAssetBundleEntry
{
	/** Specific name of this bundle, should be unique for a given scope */
	FName BundleName;
	/** List of references to top-level assets contained in this bundle */
	TArray<FTopLevelAssetPath> AssetPaths;
};

struct FAssetBundleData
{
	/** List of bundles defined */
	TArray<FAssetBundleEntry> Bundles;
};
```
由于一个 `SoftObjectPath` 或 `SoftObjectPtr` 可以设置为属于多个 bundle，因此 `FAssetBundleData` 中可能包含重复的 asset 路径

最后是 `FPrimaryAssetLoadState` 也包含 `BundleNames` 字段，用来指示这个 primary data assset 的哪些 bundle 被加载上来了
```c++
	/** The set of bundles to be loaded by the handle */
	TArray<FName> BundleNames;
```
或者称为当前的 bundle state 更为恰当，例如我们设置了名为 game 和名为 menu 的两个 bundle，一开始用 asset manager 的 `LoadPrimaryAssets` 加载了 game bundle，如果第二次调用 `LoadPrimaryAssets` 时选择加载 menu bundle，那么 game bundle 对应的资产在没有用户的引用时被垃圾回收掉。一个示例见 [UE的runtime资产管理（1）- 基于AssetManager的资源加载与释放的实现](https://zhuanlan.zhihu.com/p/17972602309)。其中还提到了实时更新 handle 的 asset 加载进度的方法，这也挺有意思的

TODO：解释 asset manager settings 中的选项，例如 rules 等，
TODO：官方文档 [Asset Management](https://dev.epicgames.com/documentation/en-us/unreal-engine/asset-management-in-unreal-engine?application_version=5.4) 还讨论了 Blueprint Primary Asset，和 C++ 有什么区别吗
**TODO：解释 chunk 这个概念**，看看官方文档 [Cooking and Chunking](https://dev.epicgames.com/documentation/en-us/unreal-engine/cooking-content-and-creating-chunks-in-unreal-engine?application_version=5.4)
TODO：解释 `UPrimaryAssetLabel` 类的作用，[虚幻引擎资产管理总结](https://zhuanlan.zhihu.com/p/503069332) 中提到它和资产的 chunk 分块有关系
TODO：重新看看 [Asset Manager 阐述](https://www.bilibili.com/video/BV1ag41177C1/?spm_id_from=333.788.videopod.sections&vd_source=2f38c661a6672237a3f59835e4bfb1a5)，它除了提到 asset bundle，chunking，还有 asset manager 涉及到 cooking 和 packaging 的一些东西
TODO：[加载资源的方式（七）使用AssetManager进行加载](https://www.cnblogs.com/sin998/p/15553121.html) 这个系列可以再看看，其中提到了 `UObjectLibrary` 也与资源加载有关，不知道现在还用不用这个了，官方文档 [Asynchronous Asset Loading](https://dev.epicgames.com/documentation/en-us/unreal-engine/asynchronous-asset-loading-in-unreal-engine) 也提到了这个
### Custom Asset
继承 `UFactory`，一些简单的例子可以参考 `UDataAssetFactory`，`UDataTableFactory`，这本质上是定义了 asset 在内存中的 uobject 类型

TODO：解释 `IAssetFactoryInterface` 接口以及 `UActorFactory`，它和 `UFactory` 没有关系，用来根据 asset 创建 actor 放置进关卡的。看看 [编辑器扩展:自定义PlaceActors](https://supervj.top/2021/08/13/%E7%BC%96%E8%BE%91%E5%99%A8%E6%89%A9%E5%B1%95%EF%BC%9A%E8%87%AA%E5%AE%9A%E4%B9%89PlaceActors/)

TODO：整理下面这个
[# UObject Constructor, PostInitProperties and PostLoad](https://heapcleaner.wordpress.com/2016/06/11/uobject-constructor-postinitproperties-and-postload/) 写得挺好的。自定义 `UMyDataAsset` 继承自 `UDataAsset`，在编辑器创建这个资产并进行编辑时，在 `LoadPackage` 函数中，创建了一个新的 `UMyDataAsset` 对象，并调用了它的 `PostLoad` 方法，它的路径是 `/Game/ThirdPerson/NewDataAsset.NewDataAsset`，因此我们在编辑器中编辑的是这个对象，而非 CDO。另外就是，这个对象有 `RF_StandAlone` 标记，不会被 GC 回收。另外，解释 NeedLoad NeedPostLoad NeedPostLoadSubObjects 等相关的 flag

TODO：清理 asset manager 相关的标签页