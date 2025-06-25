TODO：解释 LOD 切换时 required bone 如何计算，以及 required bone 减少后，animation blueprint 的计算会如何减少

[Skeletons](https://dev.epicgames.com/documentation/en-us/unreal-engine/skeletons-in-unreal-engine) 文档中解释了 skeleton tree 中每个图标的含义

TODO：解释 skeleton only bone（this socket is on the skeleton only），解释 no weight bone（The bone is used by the current mesh，but has no vertices weighted against it），我感觉 skeletal mesh 中的 RefSkeleton 和 skeleton 中的 RefSkeleton 可能不一样？

TODO：socket vs virtual bone

Skeleton 和 skeletal mesh 中都有这个字段
```c++
	/** 
	 *	Array of named socket locations, set up in editor and used as a shortcut instead of specifying 
	 *	everything explicitly to AttachComponent in the SkeletalMeshComponent.
	 */
	UPROPERTY()
	TArray<TObjectPtr<class USkeletalMeshSocket>> Sockets;
```
