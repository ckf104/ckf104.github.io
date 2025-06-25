[《InsideUE4》GamePlay架构（十一）Subsystems](https://zhuanlan.zhihu.com/p/158717151) 讲得很好了
* Subsystem 是单例，需要多个 subsystem 就通过继承创建出多个类型
* Subsystem 可以根据 outer 分出 UEditorSubsystem，UEngineSubsystem，UGameInstanceSubsystem，UWorldSubsystem，ULocalPlayerSubsystem
