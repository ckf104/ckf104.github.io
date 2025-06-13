每个 Log 有自己的详细程度，例如下面的定义表示 warning 级别的 log 才会输出
```c++
COREUOBJECT_API DECLARE_LOG_CATEGORY_EXTERN(LogGarbage, Warning, All);
```

文档 [Logging in Unreal](https://dev.epicgames.com/documentation/en-us/unreal-engine/logging-in-unreal-engine) 中谈到可以使用命令行 `-LogCmds="LogDerivedDataCache Verbose"` 来设置输出 log 的详细程度

控制台命令 ` Log LogGarbage Log` 也可以调整对应 log 的详细程度
#### 针对 StaticMeshComponent 的 GC 分析
ActorComponent：AssetUserData
SceneComponent：AttachParent，AttachChildren，ClientAttachedChildren
PrimitiveComponent：RuntimeVirtualTextures，MoveIgnoreActors，MoveIgnoreComponents,PhysMaterialOverride（在 body instance 中的引用），LODParentPrimitive，
MeshComponent：OverrideMaterials，OverlayMaterial
StaticMeshComponent：StaticMesh
#### Actor 的引用分析
Actor：AttachmentReplication 中两个，Owner，InputComponent，Instigator，Children，RootComponent，BlueprintCreatedComponents


**我们是否要区分 uproperty 是为了保持引用对象不被 GC 还是为了保证对象被 GC 时引用会被置空**


