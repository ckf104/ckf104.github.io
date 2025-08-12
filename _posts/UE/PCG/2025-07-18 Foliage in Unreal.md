
unreal 的 `UProceduralFoliageSpawner` 用来生成植被，感觉可以看看，官方文档是 [Procedural Foliage Tool](https://dev.epicgames.com/documentation/en-us/unreal-engine/procedural-foliage-tool-in-unreal-engine)

foliage 这边感觉有些乱七八糟的，
Instanced Foliage Actor
UFoliageInstancedStaticMeshComponent

UFoliageType
	UFoliageType_InstancedStaticMesh
	 UFoliageType_Actor

[Foliage Mode](https://dev.epicgames.com/documentation/en-us/unreal-engine/foliage-mode-in-unreal-engine) 的官方文档也写得不错

总的来说，感觉就是 foliage type 是 static mesh 的 wrapper，然后 procedural foliage volume 和编辑器的 foliage mode 都是用这个 foliage type 来实例化 mesh，这些实例化的 mesh 由 instanced foliage actor 来统一管理

foliage type 中一些字段可能只适用于 procedural foliage volume 或者 foliage mode（例如典型的 painting 下面的字段只适用于 foliage mode）
