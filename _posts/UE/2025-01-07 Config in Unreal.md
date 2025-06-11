一些参考：
[UE4 Config配置文件详解]((https://gwb.tencent.com/community/detail/121619)
以及官方文档 [Configuration Files](https://dev.epicgames.com/documentation/en-us/unreal-engine/configuration-files-in-unreal-engine)
[5.4 Config not saving correctly](https://forums.unrealengine.com/t/5-4-config-not-saving-correctly/1860118)

`EKnownIniFile` 宏定义了所有的 known file,
很多 [UE4 Config配置文件详解]((https://gwb.tencent.com/community/detail/121619) 中提到的 config 类型移到了 other files 中
见 `ConfigCacheIni.cpp` 的 `LoadRemainingConfigFiles` 函数

UCLASS 的 config 设置会被继承，不能被子类取消，但可以修改
在 object initializer 的 `PostConstructInit` 函数中，如果初始化的 uobject 是 CDO，或者这个 uobject 的类使用了 PerObjectConfig 声明，那么会调用 uobject 的 `LoadConfig` 函数读取配置文件。是

PerObjectConfig


PostConstructLink，

在 uobject 的 `SaveConfig` 函数中，会检查写回的值是否与父类的 CDO 中的值相同的（TODO：为什么是检查父类呢，为什么要是这个 property 属于该子类就应该存下去呢）
```c++
// Properties that are the same as the parent class' defaults should not be saved to ini
// Before modifying any key in the section, first check to see if it is different from the parent.
const bool bPropDeprecated = Property->HasAnyPropertyFlags(CPF_Deprecated);
const bool bIsPropertyInherited = Property->GetOwnerClass() != GetClass();
const bool bShouldCheckIfIdenticalBeforeAdding = !GetClass()->HasAnyClassFlags(CLASS_ConfigDoNotCheckDefaults) && !bPerObject && bIsPropertyInherited;

if (!bPropDeprecated && (!bShouldCheckIfIdenticalBeforeAdding || !Property->Identical_InContainer(this, SuperClassDefaultObject, Index)))
{
	FString	Value;
	Property->ExportText_InContainer( Index, Value, this, this, this, PortFlags );
	Config->SetString( *Section, *Key, *Value, PropFileName );
}
```
TODO：测试 PerObjectConfig
TODO：解释 NewObject 中使用了非 CDO 的构造模板时的代码路径
TODO：InitProperty 
*  UObject::GetArchetype() 蓝图中这玩意返回了个啥
* 我觉得 arch type 想解决的问题是这样，我一开始以为 InitProperty 的行为：
	* 如果是初始化模板的 CDO，就 copy post construction link 上的 property 就行了，这个 link 上主要是一些 config 相关的，而如果它是蓝图类，因为 C++ 父类中的数据可能在编辑器中被修改过，因此 InitProperty 最后调用 Class->InitPropertiesFromCustomList 这个钩子函数来引入蓝图中的修改。而对于初始化模板不是 CDO，那么就把所有的 fproperty 都拷贝了
	* 这样就足够了。但发现还有问题，即使这个 Class 是 Native C++ Class，还是有可能作为一个蓝图类的 sub object，然后它的数据在编辑器中被修改
	* instance graph，会不会和 instanced 这个 uproperty 有关系