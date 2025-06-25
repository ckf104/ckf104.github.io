### UCLASS
Blueprintable: 表示可以用这个类作为蓝图类的父类
BlueprintType: 表示这个类可以作为变量类型在蓝图变量中使用

### UPROPERTY
EditDefaultsOnly：只能编辑变量的默认值（不能编辑放入关卡中的实例的相应字段）
EditInstanceOnly：只能编辑放入关卡中的实例的相应字段，不能编辑默认值
EditAnywhere：表示 EditDefaults 且 EditInstance
VisibleDefaultsOnly：表示该变量只能在编辑默认值的窗口可见，并且不能编辑，即与 EditXXX property 不兼容
VisibleInstanceOnly：表示该变量只能在编辑实例值的窗口可见，并且不能编辑，即与 EditXXX property 不兼容
VisibleAnywhere：表示 VisibleDefaults 且 VisibleInstance
BlueprintReadOnly：蓝图程序中只读
BlueprintReadWrite：蓝图程序中可读可写


Instanced：TODO，没看明白是啥意思，如果说表示一种 ownership 的话，`UPanelSlot` 中的 Parent 和 Content 都有这个字段，岂不是父节点和子节点循环 owner？

### UFUNCTION
BlueprintImplementableEvent：只能在蓝图中实现的函数
BlueprintNativeEvent：C++ 中可加个 `_Implementation` 后缀进行定义，或者在蓝图中进行重载

### META
AllowPrivateAccess，如果该 uproperty 使用 BlueprintReadOnly 或 BlueprintReadWrite 标记了，并且是私有成员，那么需要使用 AllowPrivateAccess 标记
BlueprintSpawnableComponent，表示可以通过 SCS 添加进 actor