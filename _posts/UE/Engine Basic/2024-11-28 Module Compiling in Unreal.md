TODO：解释 target.cs
TODO：解释 plugin 和 project 中的 module 编译的异同
TODO：uproject 中的依赖设置和 module 中的依赖设置有啥区别？

在 `ModuleName.Build.cs` 中指明依赖，否则链接时会报符号未定义的错误
注意 module 的 type 设置，例如在蓝图中继承 EUBP 子类，unreal editor 就只会在 editor module 里寻找。因此如果在 runtime module 中定义新的 EUBP 子类，编辑器的蓝图继承中会找不到的