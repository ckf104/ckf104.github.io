一篇自定义资产的教程：[Creating a Custom Asset Type with its own Editor in C++](https://dev.epicgames.com/community/learning/tutorials/vyKB/unreal-engine-creating-a-custom-asset-type-with-its-own-editor-in-c)

[Creating a Runtime Editable Texture in C++](https://dev.epicgames.com/community/learning/tutorials/ow9v/unreal-engine-creating-a-runtime-editable-texture-in-c)

为什么会出现内存泄露？UTexture2D->PrivatePlatformData 到底在哪被释放，完全没看到它被析构？然后就是 FTextureSourcce.BulkData 和 FTexture2DMipMap.BulkData 里的数据会在 bulkdata 被析构时释放吗？

尝试了这里面的方法感觉也不行：[UTexture2d deletion](https://forums.unrealengine.com/t/utexture2d-deletion/411798)