## MSBuild

* 在 `.csproj` 文件中 `<Project Sdk="Microsoft.NET.Sdk">` 表示 SDK style project。相比于通常的 `.csproj` 文件，会隐式导入 `Sdk.props` 和 `Sdk.targets`，提供许多额外的 property 和 targets

```xml
<Project>
  <!-- Implicit top import -->
  <Import Project="Sdk.props" Sdk="Microsoft.NET.Sdk" />
  ...
  <!-- Implicit bottom import -->
  <Import Project="Sdk.targets" Sdk="Microsoft.NET.Sdk" />
</Project>
```

* `dotnet new console` 产生的模板包含 top level statements 而不是在类中定义 main 函数等等。这是新的 csharp 的写法，参考 [top level statements](https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/program-structure/top-level-statements) 
* 参考 [理解C#项目构建配置文件——MSBuild csproj文件](https://zhuanlan.zhihu.com/p/509046784)，自定义 target 需要放在 Directory.Build.targets 文件中，试了一下，直接放在 csproj 文件中确实不行，不知道为啥。另外 [.NET project SDKs](https://learn.microsoft.com/en-us/dotnet/core/project-sdk/overview) 中推荐的是放在 build 目录中，没试过，看起来更复杂一些

## sln file

`dotnet new console` 创建的项目中除了 `.csproj` 文件外，还有一个 `.sln` 文件，它包含了所有的 project。参考 [Solution (.sln) file](https://learn.microsoft.com/en-us/visualstudio/extensibility/internals/solution-dot-sln-file?view=vs-2022)，我的理解是这样，project 之间的相互依赖都定义在 `.csproj` 中，该文件定义了最终如何编译整个项目。而 `.sln` 文件的主要目的是创建一个项目视图 `solution explorer`，在 `.sln` 中我们用 `Project, EndProject` 关键字列举出所有的 project 文件（如果 project type 为 2150E333-8FDC-42A3-9474-1A3956D46DE8 则表明是 solution folder，即在 `solution explorer` 下创建新的文件夹，关于所有可能的 project type 可参考 [What is the significance of ProjectTypeGuids tag in the visual studio project file](https://stackoverflow.com/questions/2911565/what-is-the-significance-of-projecttypeguids-tag-in-the-visual-studio-project-fi)），然后在 `GlobalSection(NestedProjects) = preSolution` 中列举各个 project 的层级关系，产生最终的项目视图，而这个项目视图本身不需要和真实的文件结构一致。项目视图的叶子节点是 project，如果展开 project 下面的层级，这些层级对应的就是真实的文件结构了

这样做的好处是创建了一个虚拟的查看项目的视图，而各个 project 本身不需要放在相邻的文件结构中。当然 sln 文件中还有需要其它的 `GlobalSection`，此处没有细究这些是干什么的了

## UBT

* debugging csharp use `coreclr` debug type, instead of `dotnet`, see [csharp debugging](https://code.visualstudio.com/docs/csharp/debugging)
* 源码中的变量 `UnrealBuildTool.RemoteIniPath` 的作用是什么
* Build 模式下的 `-XmlConfigCache=` 参数是干嘛的，和 buildGraph 有关系吗，`BuildConfiguration.xml` 在 UBT 中起到什么样的作用
* 目前看到的基本概貌是：
  * 决定 `UnrealBuildTool` 功能的决定参数是 `-Mode` 选项，每个可选的 mode 在代码中都是 `ToolMode` 的子类，`ToolMode` 有一个 `ExecuteAsync` 函数，`UnrealBuildTool` 会调用这个函数将执行权交给该 mode
  * `GlobalOptions` 中包含了 `UnrealBuildTool` 的一些全局参数，即可以通过 `-Help` 看到的参数。因此 `UnrealBuildTool` 在调用 `ExecuteAsync` 前会使用 `CommandLineArguments` 对象来预处理一波命令行参数，将能识别的值设置在 `GlobalOptions` 中。这个 `CommandLineArguments` 会原封不动地又传给 mode
* `-game` `-engine` 参数都是些啥意思，试了一下，好像 `RunUBT.sh -projectfiles -project=xx.uproject -game -engine` 才能生成相应的 code-workspace 文件

```shell
# Generate vscode project files (workspace file and .vscode directory)
$ ~/src/UnrealEngine-5.3.2-release/GenerateProjectFiles.sh -Vscode -game -engine -project=/home/ckf104/src/TP_ThirdPerson/TP_ThirdPerson.uproject
# After running above command, workspace file and `.vscode`, `Intermediate`, `Saved` folder will be generated. And `Intermediate` folder contain a `.csproj` file. By this `csproj` file, C# dev kit could generate a `sln` file for us(This is triggered when I try to jump into definition in cs file)

# Generate compile_commands.json
$ ~/src/UnrealEngine-5.3.2-release/Engine/Build/BatchFiles/RunUBT.sh TP_ThirdPersonEditor  Development Linux -project /home/ckf104/src/TP_ThirdPerson/TP_ThirdPerson.uproject -Mode=GenerateClangDatabase -OutputDir=/home/ckf104/src/TP_ThirdPerson/

# Run UHT to generate header
$ ~/src/UnrealEngine-5.3.2-release/Engine/Build/BatchFiles/RunUBT.sh -target="TP_ThirdPersonEditor Linux Development /home/ckf104/src/TP_ThirdPerson/TP_ThirdPerson.uproject"  -Mode=UnrealHeaderTool

# Now, a complete project has been created!
# We can package it!
/home/ckf104/src/UnrealEngine-5.3.2-release/Engine/Build/BatchFiles/RunUAT.sh -ScriptsForProject=/home/ckf104/src/TP_ThirdPerson/TP_ThirdPerson.uproject \
Turnkey -command=VerifySdk -platform=Linux -UpdateIfNeeded \
-EditorIO -EditorIOPort=41771 -project=/home/ckf104/src/TP_ThirdPerson/TP_ThirdPerson.uproject \
BuildCookRun -nop4 -utf8output -nocompileeditor -skipbuildeditor -cook \
-project=/home/ckf104/src/TP_ThirdPerson/TP_ThirdPerson.uproject -target=TP_ThirdPerson \
-unrealexe=/home/ckf104/src/UnrealEngine-5.3.2-release/Engine/Binaries/Linux/UnrealEditor -platform=Linux \
-stage -archive -package -build -pak -iostore -compressed -prereqs \
-archivedirectory=/home/ckf104/src/TP_ThirdPerson/ -clientconfig=Development -nocompile -nocompileuat 2 >&1 | tee log.txt
```
* 如果是想生成 UE 本身的 compile_commands.json 的话，可以使用（如果是 Linux 平台的话替换 Win64 即可）
```shell
$ ./Engine/Build/BatchFiles/RunUBT.bat  UnrealEditor Development Win64 -Mode=GenerateClangDatabase
```

* 在 windows visual studio 中需要设置 editor preference 为 vs2022，详见[VisualStudio 2022 Intellisense for engine files not working in UE5](https://forums.unrealengine.com/t/ue-5-1-visualstudio-2022-intellisense-for-engine-files-not-working-in-ue5/551166)
* 如果安装了多个 UE 版本的话，在 windows 上右键 uproject 文件 generate project file 时，会 [找不到 UnrealBuildTool](https://forums.unrealengine.com/t/missing-unrealbuildtool-exe-after-build/242198)，根据 [Generate VS Project Files by Command Line](https://forums.unrealengine.com/t/generate-vs-project-files-by-command-line/277707)，在命令行使用（如果使用的是 launcher 的二进制版本的话）
```
"C:\Program Files (x86)\Epic Games\Launcher\Engine\Binaries\Win64\UnrealVersionSelector.exe" /projectfiles "MyProject.uproject"
```
* target 为 UnrealEditor 的 compile_commands.json 不会包含编辑器默认没有启用的插件。如果 project 使用了默认没有启用的插件，那可以把 project 的 compile_commands.json 搬到引擎目录下，可以使用 clangd 的 if blocks 来合成多个 compile_commands.json，见 [Allow specifying more than one compile_commands.json file](https://github.com/clangd/clangd/issues/1092)
* 如果报错 [Clang X64 must be installed in order to build this target](https://forums.unrealengine.com/t/error-clang-must-be-installed-in-order-to-build-this-target/483325)，需要设置环境变量 `LLVM_PATH` 为 LLVM 安装的目录

TODO：
* [编译UE5.2工程时遇到的MSVC和SDK版本问题](https://zhuanlan.zhihu.com/p/16534167796) 中谈到可以选择 msvc 的版本，如何选择 visual studio 的版本？unreal 是上哪找的 visual studio？
* visual studio 可以安装 llvm 工具链，下次试试用 visual studio 装，而不是手动装

## Other tricks
使用 alt + F1 可以在 PIE 模式下开启 wireframe 渲染



