---
title: UBT Compiling in Unreal
date: 2026-04-02 22:15:30 +0800
comments: true
categories:
  - UE5
  - tools usage
---

## 概述

之前使用 vscode 看别人的 UE 项目时经常遇到编译能过，但是 clangd 报错的问题，本文尝试分析该问题出现的原因并修改 compile_commands.json 的生成逻辑来解决这个问题。

---
## 0. PCH 的含义

关于 PCH 的说明见 [Using Precompiled Headers](https://gcc.gnu.org/onlinedocs/gcc/Precompiled-Headers.html)，关键：
* gcc 等编译器在预处理 include 时优先查找对应的 pch 文件，找不到才查找该名称的头文件
* 将 pch 放在第一个 include 的位置，这样后续即使 include 了 pch 中包含的头文件，可以被 include guard 忽略掉，不存在额外开销

Unreal Build Tool (UBT) 大量使用预编译头 (Precompiled Header, PCH) 来加速编译。本文从 UBT 源码出发，剖析以下三个问题：UBT 如何决定一个模块使用 **哪种 PCH 模式**、PCH 最终 **包含哪些头文件**、以及编译好的 PCH **如何到达每个编译单元** —— 包括为什么 clangd 经常和真正的编译器"意见不合"。

以下源码路径均相对于 UE 5.4.3 源码树中的 `Engine/Source/Programs/UnrealBuildTool/`。
## 1. PCHUsageMode：五种模式

定义于 `Configuration/ModuleRules.cs:193-219`：

```csharp
public enum PCHUsageMode
{
    Default,                    // 读取时根据上下文动态解析
    NoPCHs,                     // 完全不使用任何 PCH
    NoSharedPCHs,               // 不使用 Shared PCH，仅使用 Private PCH
    UseSharedPCHs,              // 使用 Shared PCH，忽略 PrivatePCHHeaderFile
    UseExplicitOrSharedPCHs,    // 若设置了 PrivatePCHHeaderFile 则用 Private，否则回退到 Shared
}
```

### 1.1 `Default` 的解析逻辑

`Default` 不会被直接存储。`PCHUsage` getter（`ModuleRules.cs:755-785`）会在读取时动态解析：

```csharp
public PCHUsageMode PCHUsage
{
    get
    {
        if (PCHUsagePrivate.HasValue)
            return PCHUsagePrivate.Value;               // 显式覆盖
        else if (Target.bEnableCppModules)
            return PCHUsageMode.NoPCHs;                 // C++ Modules → 禁用 PCH
        else if (Target.bIWYU || DefaultBuildSettings >= BuildSettingsVersion.V2)
            return PCHUsageMode.UseExplicitOrSharedPCHs; // 现代默认值
        else if (Plugin != null)
            return PCHUsageMode.UseSharedPCHs;           // 旧版插件
        else
            return PCHUsageMode.NoSharedPCHs;            // 旧版游戏模块
    }
}
```

| 条件                                             | 解析结果                      |
| ---------------------------------------------- | ------------------------- |
| `bEnableCppModules == true`                    | `NoPCHs`                  |
| `bIWYU == true` 或 `BuildSettingsVersion >= V2` | `UseExplicitOrSharedPCHs` |
| 模块是插件（旧版）                                      | `UseSharedPCHs`           |
| 其他情况（旧版游戏模块）                                   | `NoSharedPCHs`            |

### 1.2 各模式如何驱动 `SetupPrecompiledHeaders()`

核心决策树位于 `Configuration/UEBuildModuleCPP.cs:1636-1707`：

```csharp
CppCompileEnvironment SetupPrecompiledHeaders(...)
{
    // 关卡 1：NoPCHs 直接跳过一切
    if (Target.bUsePCHFiles && Rules.PCHUsage != PCHUsageMode.NoPCHs)
    {
        // 关卡 2：满足条件时创建 Private PCH
        if (Rules.PrivatePCHHeaderFile != null
            && (Rules.PCHUsage == PCHUsageMode.NoSharedPCHs
             || Rules.PCHUsage == PCHUsageMode.UseExplicitOrSharedPCHs))
        {
            → CreatePrivatePCH()
        }

        // 关卡 3：若未创建 Private PCH，回退到 Shared PCH
        if (!bHasPrecompiledHeader
            && SharedPCHs.Count > 0
            && !bIsBuildingLibrary
            && Rules.PCHUsage != PCHUsageMode.NoSharedPCHs)
        {
            → FindOrCreateSharedPCH()
        }
    }
}
```

下表总结了每种模式的行为：

| 模式 | Private PCH | Shared PCH | 典型使用场景 |
|---|---|---|---|
| `NoPCHs` | 不使用 | 不使用 | C++ Modules、调试 PCH 问题 |
| `NoSharedPCHs` | 使用（需设置 `PrivatePCHHeaderFile`） | 不使用 | 旧版大型游戏模块，自带独立 PCH |
| `UseSharedPCHs` | 不使用（即使设置了也忽略） | 使用 | 旧版小型插件 |
| `UseExplicitOrSharedPCHs` | 优先使用（若已设置），否则回退 Shared | 作为回退 | **现代默认值**（IWYU） |
| `Default` | 运行时解析 | 运行时解析 | 根据上下文自动判断 |

---

## 2. PCH 最终包含哪些头文件？

PCH 中的头文件**不是自动发现的**。它们来源于模块作者在 `.Build.cs` 中指定的一个**手工编写的头文件**。UBT 只是将该文件与一个 Definitions 头文件组合成 wrapper，然后编译它。

### 2.1 Private PCH

通过 `.Build.cs` 中的 `PrivatePCHHeaderFile` 指定：

```csharp
// 例如 Engine.Build.cs
PrivatePCHHeaderFile = "Private/EnginePrivatePCH.h";
```

UBT 生成 wrapper 文件（`UEBuildModuleCPP.cs:1105-1131`，`CreatePrivatePCH`）：

```
PCH.{ModuleName}.h                    ← 生成的 wrapper 文件
  │
  ├─ #include "Definitions.{ModuleName}.h"    ← 自动生成的 #define 宏列表
  │
  └─ #include "{PrivatePCHHeaderFile}"        ← 手工编写的头文件
```

wrapper 的生成逻辑极其简单 —— `CreatePCHWrapperFile()`（`UEBuildModuleCPP.cs:1779-1788`）：

```csharp
WrapperContents.AppendLine("// PCH for {0}", IncludeFileString);
WrapperContents.AppendLine("#include \"{0}\"", DefinitionsFileString);
WrapperContents.AppendLine("#include \"{0}\"", IncludeFileString);
```

只有两行 `#include`。PCH 最终包含的所有内容完全取决于手工编写的头文件及其传递包含的头文件。

### 2.2 Shared PCH

通过 `.Build.cs` 中的 `SharedPCHHeaderFile` 指定。整个引擎中只有少数几个模块声明了它：

```csharp
// Core.Build.cs
SharedPCHHeaderFile = "Public/CoreSharedPCH.h";

// CoreUObject.Build.cs
SharedPCHHeaderFile = "Public/CoreUObjectSharedPCH.h";

// Slate.Build.cs
SharedPCHHeaderFile = "Public/SlateSharedPCH.h";

// Engine.Build.cs
SharedPCHHeaderFile = "Public/EngineSharedPCH.h";

// UnrealEd.Build.cs
SharedPCHHeaderFile = "Public/UnrealEdSharedPCH.h";
```

UBT 生成 wrapper 文件（`FindOrCreateSharedPCH`，`UEBuildModuleCPP.cs:1142-1275`）：

```
SharedPCH.{ModuleName}{Variant}.h                ← 生成的 wrapper 文件
  │
  ├─ #include "SharedDefinitions.{ModuleName}{Variant}.h"  ← 自动生成的 #define 宏
  │
  └─ #include "{SharedPCHHeaderFile}"                      ← 手工编写的头文件
```

`{Variant}` 后缀（如 `.Cpp20`、`.Project.ValApi.Cpp20`）由 `GetSuffixForSharedPCH()` 计算，取决于消费模块的编译环境与模板基础环境之间的差异（是否为引擎模块、include order 版本、格式字符串验证、内部 API 验证等标志）。

### 2.3 Shared PCH 的层级包含链

这些手工编写的 SharedPCH 头文件构成一个层层嵌套的包含链：

```
CoreSharedPCH.h              (~250 个 Core 头文件：容器、数学、HAL、序列化...)
  └─ CoreUObjectSharedPCH.h  (+ UObject 子系统头文件)
       └─ SlateSharedPCH.h   (+ SlateCore + Slate 控件，包括 SImage.h)
            └─ EngineSharedPCH.h    (+ RHI、RenderCore、Engine 类，~180 个头文件)
                 └─ UnrealEdSharedPCH.h  (+ Editor 类、BlueprintGraph、ToolMenus)
```

每一层 `#include` 上一层的内容，并添加自己模块及依赖模块特有的头文件。

### 2.4 UBT 如何为消费模块选择 Shared PCH

在 Target 构建阶段（`UEBuildTarget.cs:3640-3676`），UBT：

1. **收集**所有声明了 `SharedPCHHeaderFile` 的模块。
2. **按优先级排序**：优先级 = 该模块依赖链中包含的其他 SharedPCH 模块数量（降序排列）。最终产生如下顺序：

   ```
   UnrealEd > Engine > Slate > CoreUObject > Core
   ```

3. **存储**这个有序列表到 `GlobalCompileEnvironment.SharedPCHs`。

当消费模块调用 `SetupPrecompiledHeaders()`（`UEBuildModuleCPP.cs:1655-1659`）时，UBT 选择有序列表中**第一个**（即最大的）兼容模板：

```csharp
PrecompiledHeaderTemplate? Template = CompileEnvironment.SharedPCHs
    .FirstOrDefault(x =>
        !x.ModuleDependencies.Contains(this)     // 不产生循环依赖
        && AllDependencies.Contains(x.Module)     // 本模块确实依赖该 PCH 模块
        && x.IsValidFor(CompileEnvironment));     // 编译标志兼容
```

因此，一个模块总是会获得它所依赖的**最大的兼容 Shared PCH**。

### 2.5 Definitions 头文件

`Definitions.h` / `SharedDefinitions.h` 文件由 `CompileEnvironment.Definitions` 列表自动生成。它们**仅包含 `#define` 宏**（如 `SLATE_API DLLIMPORT`、平台标志等），不包含任何 `#include` 指令。所有实际的头文件内容都来自手工编写的 PCH 头文件及其传递包含。

### 2.6 总结图示

```
                        ┌─────────────────────────────────┐
                        │  模块作者编写 .Build.cs           │
                        └─────────┬───────────────────────┘
                                  │
                 ┌────────────────┴────────────────┐
                 │                                 │
    PrivatePCHHeaderFile = "..."      SharedPCHHeaderFile = "..."
                 │                                 │
                 ▼                                 ▼
       手工编写的头文件                   手工编写的头文件
    (如 EnginePrivatePCH.h)         (如 EngineSharedPCH.h)
                 │                                 │
                 │    ┌────────────────────────┐   │
                 │    │  UBT 生成 wrapper       │   │
                 │    │  (CreatePCHWrapperFile)│   │
                 │    └────────────────────────┘   │
                 ▼                                 ▼
    PCH.{Module}.h                    SharedPCH.{Module}{Variant}.h
      #include Definitions.h            #include SharedDefinitions.h
      #include {PrivatePCH}             #include {SharedPCH}
                 │                                 │
                 ▼                                 ▼
         /Yc 编译生成 PCH               /Yc 编译生成 PCH
         /Yu 供模块自身 .cpp 使用        /Yu 供消费模块使用
```

---

## 3. PCH 文件的存放位置

所有生成的 PCH 文件位于项目的 `Intermediate` 目录下：

```
Intermediate/Build/Win64/x64/{Target}/{Configuration}/{Module}/
```

| 文件                                 | 说明                                          |
| ---------------------------------- | ------------------------------------------- |
| `SharedPCH.{Name}.Cpp20.h`         | UBT 生成的 PCH wrapper 头文件（仅两行 `#include`）     |
| `SharedPCH.{Name}.Cpp20.cpp`       | 空 `.cpp`，`#include` 上述 wrapper（用于触发 PCH 编译） |
| `SharedPCH.{Name}.Cpp20.h.pch`     | **编译后的二进制 PCH 文件**（MSVC `.pch` 格式）          |
| `SharedPCH.{Name}.Cpp20.h.obj.rsp` | 编译 PCH 时的响应文件（编译器参数）                        |
| `SharedDefinitions.{Name}.Cpp20.h` | 自动生成的 Shared PCH `#define` 宏文件              |
| `PCH.{Module}.h`                   | Private PCH wrapper（若模块使用 Private PCH）      |
| `PCH.{Module}.h.pch`               | 编译后的 Private PCH 二进制文件                      |
| `Definitions.{Module}.h`           | 自动生成的 Private PCH / 逐模块覆盖 `#define` 宏文件     |

---

## 4. 编译标志：PCH 如何到达每个 `.cpp`

### 4.1 MSVC (`cl.exe`)

由 `Platform/Windows/VCCompileAction.cs:514-522` 生成：

| 操作         | 编译标志                                   |
| ---------- | -------------------------------------- |
| **创建** PCH | `/Yc"{PCHHeader}"` `/Fp"{Output.pch}"` |
| **使用** PCH | `/Yu"{PCHHeader}"` `/Fp"{Input.pch}"`  |
| **强制包含**   | `/FI"{Header}"` （在任何源码之前注入 PCH 头文件）    |

### 4.2 Clang

由 `ToolChain/ClangToolChain.cs:519-527` 生成：

| 操作         | 编译标志                           |
| ---------- | ------------------------------ |
| **使用** PCH | `-include-pch {PCHFile}`       |
| **创建** PCH | 将文件类型指定为 `c++-header` 而非 `c++` |

---

## 5. 实例分析：为什么 clangd 报错而 UBT 编译正常通过

以 `UnrealMCP` 插件模块为具体案例。

### 5.1 实际 UBT 编译（MSVC `cl.exe`）

响应文件 `Module.UnrealMCP.cpp.obj.rsp`（位于 `UnrealEditor/` target 下）：

```
"Module.UnrealMCP.cpp"                                          ← Unity Build 入口文件
/FI"SharedPCH.UnrealEd.Project.ValApi.Cpp20.h"                 ← 强制包含 PCH 头文件
/Yu"SharedPCH.UnrealEd.Project.ValApi.Cpp20.h"                 ← 使用预编译头
/Fp"SharedPCH.UnrealEd.Project.ValApi.Cpp20.h.pch"             ← PCH 二进制文件
```

`SImage.h` 的完整包含链路：

```
Module.UnrealMCP.cpp
  │
  ├─ /FI (force include) ──→ SharedPCH.UnrealEd.Project.ValApi.Cpp20.h
  │                            │
  │                            └─→ UnrealEdSharedPCH.h
  │                                  │
  │                                  └─→ EngineSharedPCH.h  (第 5 行)
  │                                        │
  │                                        └─→ SlateSharedPCH.h  (第 5 行)
  │                                              │
  │                                              └─→ #include "Widgets/Images/SImage.h"  (第 121 行) ✅
  │
  └─ #include "UnrealMCP.cpp"  (Unity 文件第 10 行)
       │
       └─ SNew(SImage)  ← SImage 完整定义已可见 ✅
```

### 5.2 `compile_commands.json`（clangd 所见）

响应文件 `UnrealMCP.cpp.obj.rsp`（位于 `UnrealEditorGCD/` target 下）：

```
"UnrealMCP.cpp"                              ← 单文件编译（非 Unity Build）
/FI"Definitions.UnrealMCP.h"                 ← 仅宏定义，无 PCH
@"UnrealMCP.Shared.rsp"                      ← 仅 /I 搜索路径
                                               无 /Yu、无 /Fp、无 PCH！
```

clangd 实际走过的包含链路：

```
UnrealMCP.cpp
  │
  ├─ /FI ──→ Definitions.UnrealMCP.h          ← 仅 #define 宏，无类型定义
  │
  ├─ #include "Widgets/SWindow.h"
  │    └─ class SImage;                        ← 仅前向声明 ❌
  │
  └─ SNew(SImage)                              ← incomplete type! ❌
```

### 5.3 根因对比

| | 实际编译 (UBT/MSVC) | clangd |
|---|---|---|
| 编译单元 | `Module.UnrealMCP.cpp` (Unity Build) | `UnrealMCP.cpp` (单文件) |
| PCH | `/Yu` + `/Fp` → `SharedPCH.UnrealEd...pch` | 无 |
| 强制包含 | `SharedPCH.UnrealEd...h`（包含几乎所有引擎头文件） | `Definitions.h`（仅宏定义） |
| `SImage` 来源 | PCH → `UnrealEdSharedPCH.h` → `EngineSharedPCH.h` → `SlateSharedPCH.h` → `SImage.h` | 不可用 |

`compile_commands.json` 是 UBT **专门为 IDE 工具链生成的**（注意 target 目录名为 `UnrealEditorGCD` 而非实际编译使用的 `UnrealEditor`）。它**故意剥离了 PCH 和 Unity Build**，以便 clangd 能逐文件分析。副作用是：如果源码本身没有显式 `#include` 某个头文件，clangd 就无法找到对应的定义 —— 尽管真正的构建通过 PCH 透明地提供了它。

---

## 6. Unity Build：将多个编译单元合而为一

### 6.1 什么是 Unity Build

C++ 项目的编译时间主要耗费在两个地方：头文件的重复解析和链接时的符号处理。假设一个模块有 100 个 `.cpp` 文件，每个都 `#include` 了大量引擎头文件，编译器就需要将这些头文件解析 100 次。Unity Build（也称 Jumbo Build 或 Unified Build）的思路极为直接——生成一个"聚合"文件，用 `#include` 把多个源文件拼到一起，让编译器将它们作为单个编译单元处理：

```cpp
// Module.UnrealMCP.cpp — 由 UBT 自动生成
// This file is automatically generated at compile-time to include some subset of the user-created cpp files.
#include "C:/.../UnrealMCP/Intermediate/.../MCPSettings.gen.cpp"
#include "C:/.../UnrealMCP/Intermediate/.../UnrealMCP.init.gen.cpp"
#include "C:/.../UnrealMCP/Source/UnrealMCP/Private/MCPCommandHandlers.cpp"
#include "C:/.../UnrealMCP/Source/UnrealMCP/Private/MCPConstants.cpp"
#include "C:/.../UnrealMCP/Source/UnrealMCP/Private/MCPTCPServer.cpp"
#include "C:/.../UnrealMCP/Source/UnrealMCP/Private/UnrealMCP.cpp"
```

这样，原本需要 6 次编译器调用、6 次头文件解析的工作，缩减为 1 次。配合预编译头（PCH），单次编译几乎不需要从零解析任何头文件，构建速度因此大幅提升。

### 6.2 UBT 如何决定是否启用 Unity Build

这是一个多层决策过程，判断逻辑位于 `Configuration/UEBuildModuleCPP.cs` 的 `CompileModuleFiles` 方法中：

```
Target.bUseUnityBuild 或 Target.bForceUnityBuild 为 true？
│
├─ 否 → 不使用 Unity Build
│
└─ 是 → 进入模块级判断
     │
     ├─ Target.bForceUnityBuild == true？
     │    └─ 强制启用，跳过一切后续检查
     │
     ├─ Rules.bUseUnity == false？
     │    └─ 模块主动禁用
     │
     ├─ 源文件数 < MinSourceFilesForUnityBuild？
     │    └─ 文件太少，不值得合并
     │
     └─ 其他情况 → 启用 Unity Build
```

涉及的配置项分布在 Target 和 Module 两个层级：

**Target 级别**（在 `.Target.cs` 中设置，定义于 `Configuration/TargetRules.cs`）：

| 配置项 | 默认值 | 含义 |
|--------|--------|------|
| `bUseUnityBuild` | `true`（非 C++ Modules 模式时） | 全局开关 |
| `bForceUnityBuild` | `false` | 强制所有模块启用，覆盖模块级设置 |
| `MinGameModuleSourceFilesForUnityBuild` | `32` | 游戏模块的最低源文件数阈值 |
| `DisableUnityBuildForModules` | `null` | 按模块名禁用，如 `new string[]{ "MyModule" }` |

**Module 级别**（在 `.Build.cs` 中设置，定义于 `Configuration/ModuleRules.cs`）：

| 配置项 | 默认值 | 含义 |
|--------|--------|------|
| `bUseUnity` | `true` | 本模块是否参与 Unity Build |
| `MinSourceFilesForUnityBuildOverride` | `0`（不覆盖） | 覆盖最低文件数阈值 |
| `NumIncludedBytesPerUnityCPPOverride` | `0`（不覆盖） | 覆盖单个 Unity 文件的大小上限 |

`bUseUnity` 的 getter（`ModuleRules.cs:1031-1040`）：

```csharp
private bool? bUseUnityOverride;
public bool bUseUnity
{
    set => bUseUnityOverride = value;
    get => bUseUnityOverride ?? Target.DisableUnityBuildForModules?.Contains(Name) != true;
}
```

即：模块 `.Build.cs` 中可显式设 `bUseUnity = false`，否则看 Target 的黑名单。

**MinSourceFilesForUnityBuild 的确定**（`UEBuildModuleCPP.cs:597-607`）：

```csharp
if (Rules.MinSourceFilesForUnityBuildOverride != 0)
    MinSourceFilesForUnityBuild = Rules.MinSourceFilesForUnityBuildOverride;  // 模块覆盖
else if (是游戏模块)  // 源文件在 ProjectFile/Source/ 下
    MinSourceFilesForUnityBuild = Target.MinGameModuleSourceFilesForUnityBuild;  // 默认 32
else
    MinSourceFilesForUnityBuild = 0;  // 引擎模块：无最低限制，总是启用
```

这里有一个关键区分：**引擎模块**的最低文件数阈值为 0，即只要全局开关开启就一定启用；而**游戏模块**的阈值默认为 32——Epic 认为小型游戏模块更应追求单文件修改后的快速增量编译，而非全量构建速度。

### 6.3 分组策略：哪些文件合并到同一个 Unity 文件

分组逻辑在 `System/Unity.cs` 的 `GenerateUnityCPPs()` 方法中实现。

**第一步：排序。** 所有待合并的 `.cpp` 文件按以下规则排序（`Unity.cs:196-216`）：

```csharp
SortedCPPFiles.Sort((A, B) =>
{
    bool bAIsGenerated = A.AbsolutePath.EndsWith(".gen.cpp");
    bool bBIsGenerated = B.AbsolutePath.EndsWith(".gen.cpp");
    if (bAIsGenerated && !bBIsGenerated) return -1;
    if (!bAIsGenerated && bBIsGenerated) return 1;
    return String.Compare(A.AbsolutePath, B.AbsolutePath, 
                          StringComparison.OrdinalIgnoreCase);
});
```

UHT 生成的 `.gen.cpp` 文件必须排在最前面——它们包含模板特化的定义，若排在使用方之后会触发 MSVC 的 `C2908: explicit specialization has already been instantiated` 错误。其余文件按路径字典序排列，确保不同机器上的分组结果一致。

**第二步：按大小切分。** UBT 维护了一个 `UnityFileBuilder`（`Unity.cs:67-141`），将文件逐个加入当前块，当累计大小超过阈值时自动开启新块：

```csharp
UnityFileBuilder CPPUnityFileBuilder = new UnityFileBuilder(
    bForceIntoSingleUnityFile ? -1 : NumIncludedBytesPerUnityCPP);  // 默认 384KB

foreach (FileItem CPPFile in SortedCPPFiles)
{
    CPPUnityFileBuilder.AddFile(CPPFile);
    // AddFile 内部：当 VirtualLength > SplitLength 时自动 EndCurrentUnityFile()
}
```

`AddFile()` 的实现（`Unity.cs:89-96`）：

```csharp
public void AddFile(FileItem File)
{
    CurrentCollection.AddFile(File);
    if (SplitLength != -1 && CurrentCollection.VirtualLength > SplitLength)
    {
        EndCurrentUnityFile();  // 超过 384KB，开启新的 Unity 文件
    }
}
```

默认阈值 `NumIncludedBytesPerUnityCPP` 为 `384 * 1024`（384 KB，`TargetRules.cs:1793`）。这是一个经验值——太小则 Unity Build 失去意义，太大则增量编译时一个文件的修改会触发过多代码的重编。

有一个特殊优化：如果模块的所有源文件总大小不到阈值的两倍（即本来就只会产生一两个 Unity 文件），且启用了 PCH，则强制合并为单个文件（`Unity.cs:184`）。这避免了产生数量过少的 Unity 文件导致 PCH 创建效率低下的问题：

```csharp
bool bForceIntoSingleUnityFile = Target.bStressTestUnity || 
    (TotalBytesInCPPFiles < NumIncludedBytesPerUnityCPP * 2 && Target.bUsePCHFiles);
```

**第三步：生成 Unity 文件。** 每个分组被写入一个 Unity 文件（`Unity.cs:248-311`）。命名规则：

| 场景 | 文件名 |
|------|--------|
| 模块只产生一个 Unity 文件 | `Module.{ModuleName}.cpp` |
| 模块产生多个 Unity 文件 | `Module.{ModuleName}.1.cpp`, `Module.{ModuleName}.2.cpp`, ... |
| 启用 `bDetailedUnityFiles` | `Module.{ModuleName}.1_of_5.cpp`, ... |

文件内容就是一系列 `#include` 指令，指向原始源文件的路径（`Unity.cs:278-293`）：

```csharp
foreach (FileItem CPPFile in UnityFile.Files)
{
    string CPPFileString = CPPFile.AbsolutePath;
    if (CPPFile.Location.IsUnderDirectory(Unreal.RootDirectory))
    {
        CPPFileString = CPPFile.Location.MakeRelativeTo(Unreal.EngineSourceDirectory);
    }
    OutputUnityCPPWriter.WriteLine("#include \"{0}\"", CPPFileString.Replace('\\', '/'));
}
```

### 6.4 Adaptive Unity Build：兼顾全量速度与增量体验

Unity Build 有一个固有矛盾：它加速了全量构建，却拖慢了增量构建——你只改了一个 `.cpp` 文件，却要重新编译它所在的整个 Unity 块（可能包含几十个文件）。

UBT 的解决方案是 **Adaptive Unity Build**（通过 `bUseAdaptiveUnityBuild` 启用，默认开启）。它维护一个"工作集"（working set），记录开发者近期正在活跃编辑的源文件。这些文件会被从 Unity 块中剥离出来，作为独立编译单元单独编译。

实现细节上，被剥离的文件通过 `AddVirtualFile()` 而非 `AddFile()` 加入分组器（`Unity.cs:227-241`）：

```csharp
if (AdaptiveFileSet.Contains(CPPFile))
{
    CPPUnityFileBuilder.AddVirtualFile(CPPFile);  // 只占位，不实际加入
}
else
{
    CPPUnityFileBuilder.AddFile(CPPFile);          // 正常参与合并
}
```

`AddVirtualFile()` 是一个精妙的设计（`Unity.cs:50-60`）：它不把文件写入 Unity 块的 `#include` 列表，但仍将其大小计入分组器的 `VirtualLength`。这意味着即使工作集发生变化，其余 Unity 块的分组边界也不会改变，从而避免了因一个文件的进出导致相邻块的内容重新洗牌、触发大面积重编的问题。

与 Adaptive Unity 相关的配置项（均在 `TargetRules.cs` 中定义）：

| 配置项 | 默认值 | 含义 |
|--------|--------|------|
| `bUseAdaptiveUnityBuild` | `true` | 总开关 |
| `bAdaptiveUnityDisablesOptimizations` | — | 对剥离出的文件禁用优化，进一步加速增量编译 |
| `bAdaptiveUnityDisablesPCH` | — | 对剥离出的文件不使用 PCH |
| `bAdaptiveUnityCreatesDedicatedPCH` | — | 为每个剥离出的文件创建专属 PCH |
| `bAdaptiveUnityCompilesHeaderFiles` | `false` | 为修改的头文件也生成对应的编译单元 |

### 6.5 Unity Build 与 PCH 的协作

Unity Build 和 PCH 是 UBT 编译加速的两大支柱，二者紧密配合。如前文所述，实际编译命令中，PCH 通过 `/FI`（Force Include）注入到 Unity 文件之前，而 Unity 文件再通过 `#include` 聚合所有源文件：

```
编译器实际处理顺序：

/FI SharedPCH.UnrealEd.Project.ValApi.Cpp20.h    ← PCH（已预编译，瞬间加载）
    └→ UnrealEdSharedPCH.h → EngineSharedPCH.h → SlateSharedPCH.h → ...

Module.UnrealMCP.cpp                              ← Unity 文件
    #include "MCPSettings.gen.cpp"
    #include "UnrealMCP.init.gen.cpp"
    #include "MCPCommandHandlers.cpp"
    #include "MCPTCPServer.cpp"
    #include "UnrealMCP.cpp"
```

PCH 消除了头文件的重复解析开销，Unity Build 消除了编译单元的重复启动和链接开销。对于一个几百个模块、上万个源文件的 UE 项目而言，两者叠加的效果是将全量构建时间从小时级压缩到分钟级。

但这也正是 clangd 等语言服务器误报的根源——`compile_commands.json` 中记录的是为 IDE 工具生成的单文件编译命令，既没有 PCH 的 `/Yu` 参数，也没有 Unity Build 的聚合效果。clangd 按照这些命令分析单个 `.cpp` 文件时，看不到 PCH 隐式注入的头文件，也看不到同一 Unity 块中其他 `.cpp` 文件带来的定义，因此会报出 `incomplete type` 或 `unknown type name` 之类在实际编译中不存在的错误。

### 6.6 整体流程图

```
Target.bUseUnityBuild (全局开关，默认 true)
  │
  ▼
Module.bUseUnity (模块开关，默认 true)
  │
  ▼
FileCount >= MinSourceFilesForUnityBuild？
  │   引擎模块：阈值 = 0（总是通过）
  │   游戏模块：阈值 = 32
  │
  ▼
  ✅ 启用 Unity Build
  │
  ▼
收集所有 .cpp 文件
  │
  ▼
排序：.gen.cpp 在前，其余按路径字典序
  │
  ▼
Adaptive Unity：剥离活跃编辑文件（AddVirtualFile 占位保持分组稳定）
  │
  ▼
按 NumIncludedBytesPerUnityCPP (384KB) 分组
  │  如果总大小 < 768KB 且启用 PCH → 强制合为一个文件
  │
  ▼
生成 Module.{Name}[.N].cpp，内容为 #include 原始文件
```

---

## 7. `-Mode=GenerateClangDatabase`：`compile_commands.json` 的生成机制

### 7.1 入口与模式注册

`-Mode=GenerateClangDatabase` 是 UBT 的一个独立运行模式，入口类定义于 `Modes/GenerateClangDatabase.cs`：

```csharp
[ToolMode("GenerateClangDatabase",
    ToolModeOptions.XmlConfig | ToolModeOptions.BuildPlatforms |
    ToolModeOptions.SingleInstance | ToolModeOptions.StartPrefetchingEngine |
    ToolModeOptions.ShowExecutionTime)]
class GenerateClangDatabase : ToolMode
```

UBT 通过反射（`UnrealBuildTool.cs:340-356`）扫描所有带 `[ToolMode]` 特性的子类，建立名称到类型的静态映射，在收到 `-Mode=GenerateClangDatabase` 参数时实例化并调用其 `ExecuteAsync()`。

### 7.2 与普通编译模式的关键差异

在 `ExecuteAsync()` 中，UBT 对每个 `TargetDescriptor` 做了以下修改，**然后才构建 Target**：

```csharp
// GenerateClangDatabase.cs:83-92
TargetDescriptor.bUseUnityBuild = false;                              // ① 禁用 Unity Build
TargetDescriptor.IntermediateEnvironment =
    UnrealIntermediateEnvironment.GenerateClangDatabase;              // ② 中间目录加 "GCD" 后缀

// 首次构建：不使用 PCH（面向 clangd 的通用命令）
await GenerateCompileCommandsForTargetAsync(..., bUsePCH: false, ...);

// 可选第二次构建：对指定模块启用 PCH（通过 -PCHModule= 参数指定）
if (PCHModuleNames.Count > 0)
    await GenerateCompileCommandsForTargetAsync(..., bUsePCH: true, ...);
```

`CreateClangDatabaseArguments()` 负责拼接附加参数：

```csharp
// GenerateClangDatabase.cs:151-163
private static CommandLineArguments CreateClangDatabaseArguments(
    CommandLineArguments BaseArguments, bool bUsePCH)
{
    CommandLineArguments Arguments = BaseArguments;
    if (!bUsePCH)
        Arguments = Arguments.Append(new string[] { "-NoPCH" });     // ③ 禁用 PCH
    if (!Arguments.Any(x => x.StartsWith("-Compiler=", ...)))
        Arguments = Arguments.Append(new string[] { "-Compiler=Clang" }); // ④ 默认用 Clang
    return Arguments;
}
```

`UnrealIntermediateEnvironment.GenerateClangDatabase` 的影响体现在两处（`UEBuildTarget.cs`）：

```csharp
// 目录后缀（第 1905-1906 行）
case UnrealIntermediateEnvironment.GenerateClangDatabase:
    TargetFolderName += "GCD";     // → UnrealEditorGCD/

// IsUnity() 判断（第 1154-1156 行）
case UnrealIntermediateEnvironment.GenerateClangDatabase:
    return false;                  // Unity Build 在此层面再次被禁止
```

| 维度            | 普通编译 (BuildMode)                    | GenerateClangDatabase   |
| ------------- | ----------------------------------- | ----------------------- |
| 编译单元          | `Module.{Name}.cpp`（Unity Build）    | `UnrealMCP.cpp`（单文件）    |
| 中间目录          | `UnrealEditor/`                     | `UnrealEditorGCD/`      |
| 编译器           | MSVC `cl.exe`                       | LLVM `clang-cl.exe`（默认） |
| PCH           | `/FI` + `/Yu` + `/Fp` (SharedPCH)   | 无（`-NoPCH`）             |
| Force Include | `SharedPCH.*.h` + `Definitions.*.h` | 仅 `Definitions.h`       |

### 7.3 `.obj.rsp` 文件的生成链路

无论哪种模式，每个编译 Action 对应的 `.obj.rsp` 均由 `VCToolChain.CompileCPPFiles()` 中调用 `CompileAction.WriteResponseFile()` 写出（`VCToolChain.cs:1844`，`VCCompileAction.cs:476`）：

```csharp
public void WriteResponseFile(IActionGraphBuilder Graph, ILogger Logger)
{
    if (ResponseFile != null)
        Graph.CreateIntermediateTextFile(ResponseFile, GetCompilerArguments(Logger));
}
```

`GetCompilerArguments()` 按顺序拼接以下内容（`VCCompileAction.cs:484-561`）：

```
① SourceFile          → "UnrealMCP.cpp"（GCD 模式）或 "Module.UnrealMCP.cpp"（普通编译）
② IncludePaths        → 已移交 Shared.rsp，此处为空
③ SystemIncludePaths  → 已移交 Shared.rsp，此处为空
④ ForceIncludeFiles   → /FI"Definitions.h"（GCD）或 /FI"SharedPCH.*.h" /FI"Definitions.*.h"（普通）
⑤ if (UsingPchFile != null && CompilerType.IsMSVC())
       → /Yu"SharedPCH.*.h" /Fp"SharedPCH.*.pch"  ← GCD 模式跳过此分支
⑥ ObjectFile          → /Fo"....obj"
⑦ AdditionalArguments → 包含 @"...Shared.rsp" 引用及编译器 flags
```

**GCD 模式**中，`SetupPrecompiledHeaders()` 因 `Target.bUsePCHFiles == false` 而完全跳过，导致：
- `CompileEnvironment.PrecompiledHeaderAction == None`
- `UsingPchFile == null`

因此第 ⑤ 步的 `if` 分支不执行，`/Yu`、`/Fp` 不出现在 `.obj.rsp` 中。

响应文件的路径由以下规则确定（`UEToolChain.cs:195-199`）：

```csharp
public virtual FileReference GetResponseFileName(
    CppCompileEnvironment CompileEnvironment, FileItem OutputFile)
{
    // 在 .obj 扩展名后追加 .rsp
    return OutputFile.Location.ChangeExtension(
        OutputFile.Location.GetExtension() + ResponseExt);
    // "UnrealMCP.cpp.obj" → "UnrealMCP.cpp.obj.rsp"
}
```

### 7.4 `{Module}.Shared.rsp` 的生成逻辑

在 PCH 配置完成后、实际编译各 `.cpp` 之前，`UEBuildModuleCPP.cs` 第 472-474 行会为每个模块生成一个 Shared response file：

```csharp
// UEBuildModuleCPP.cs:472-474
FileReference SharedResponseFile = FileReference.Combine(
    IntermediateDirectory, $"{Rules.ShortName ?? Name}.Shared{UEToolChain.ResponseExt}");
// → "UnrealMCP.Shared.rsp"

CompileEnvironment = ToolChain.CreateSharedResponseFile(CompileEnvironment, SharedResponseFile, Graph);
```

`VCToolChain.CreateSharedResponseFile()` 将所有 include 路径提取并写入该文件，同时清空 `CompileEnvironment` 中的对应集合（`VCToolChain.cs:2307-2343`）：

```csharp
public override CppCompileEnvironment CreateSharedResponseFile(...)
{
    foreach (var IncludePath in NewCompileEnvironment.UserIncludePaths)
        AddIncludePath(Arguments, IncludePath, ...);     // → /I "..."

    foreach (var IncludePath in NewCompileEnvironment.SystemIncludePaths)
        AddSystemIncludePath(Arguments, IncludePath, ...); // → /imsvc "..."

    foreach (var IncludePath in EnvVars.IncludePaths)    // MSVC/Windows SDK 路径
        AddSystemIncludePath(Arguments, IncludePath, ...); // → /imsvc "..."

    Graph.CreateIntermediateTextFile(FileItem, Arguments);

    NewCompileEnvironment.UserIncludePaths.Clear();
    NewCompileEnvironment.SystemIncludePaths.Clear();
    NewCompileEnvironment.AdditionalResponseFiles.Add(FileItem);  // 注册到环境
    NewCompileEnvironment.bHasSharedResponseFile = true;
}
```

其中 `UserIncludePaths` 和 `SystemIncludePaths` 由 `SetupPrivateCompileEnvironment()`（`UEBuildModule.cs:694`）递归收集而来：它从模块自身的 `PrivateIncludePaths` 出发，沿依赖树调用 `AddModuleToCompileEnvironment()`，将每个依赖模块的 `PublicIncludePaths`（含 UHT/VNI 生成目录）逐一加入。这一过程的输入来源于 `.Build.cs` 中的 `PublicDependencyModuleNames` / `PrivateDependencyModuleNames` 以及 UHT 生成目录，从而产生了 Shared.rsp 中多达几百行的 `/I` 路径。

Shared.rsp 写出后，在 `CreateBaseCompileAction()` 中被引用（`VCToolChain.cs:1481-1484`）：

```csharp
foreach (FileItem AdditionalRsp in CompileEnvironment.AdditionalResponseFiles)
{
    BaseCompileAction.Arguments.Add($"@\"{NormalizeCommandLinePath(AdditionalRsp.Location)}\"");
}
// 最终出现在 .obj.rsp 中：@"...UnrealMCP.Shared.rsp"
```

同时，`bHasSharedResponseFile == true` 会阻止 `EnvVars.IncludePaths`（MSVC 编译器自带路径）被重复写入单文件的 `.obj.rsp`（`VCToolChain.cs:1494-1497`）：

```csharp
if (!CompileEnvironment.bHasSharedResponseFile)
{
    BaseCompileAction.SystemIncludePaths.AddRange(EnvVars.IncludePaths);
}
```

**两种模式共用同一套 Shared.rsp 生成逻辑**，区别仅在于中间目录不同（`UnrealEditor/` vs `UnrealEditorGCD/`），内容完全由 `.Build.cs` 模块依赖决定，与 PCH 无关。Shared.rsp 是纯粹的 include 路径容器，PCH 差异完全体现在各自的 `.obj.rsp` 中。

### 7.5 `compile_commands.json` 的写出

`GenerateCompileCommandsForTargetAsync()` 遍历所有 `ActionType.Compile` 类型的 Action，从每个 Action 中提取源文件和输出文件，拼接完整命令（`GenerateClangDatabase.cs:197-234`）：

```csharp
foreach (IExternalAction Action in Actions
    .Where(x => x.ActionType == ActionType.Compile)
    .Where(x => x.PrerequisiteItems.Any()))
{
    FileItem? SourceFile = Action.PrerequisiteItems
        .FirstOrDefault(x => x.HasExtension(".cpp") || x.HasExtension(".cc") || x.HasExtension(".c"));
    FileItem? OutputFile = Action.ProducedItems
        .FirstOrDefault(x => x.HasExtension(".obj") || x.HasExtension(".o"));

    // ...过滤逻辑（-PCHModule= 指定的目录范围）...

    StringBuilder CommandBuilder = new StringBuilder();
    CommandBuilder.AppendFormat("{0} {1}", CommandPath, Action.CommandArguments);
    // Action.CommandArguments → VCCompileAction.GetClArguments()
    //   → return $"@\"{ResponseFile}\"";  即引用 .obj.rsp

    FileToCommand[Tuple.Create(SourceFile.FullName, OutputFile.FullName)] = CommandBuilder.ToString();
}
```

`Action.CommandArguments` 由 `VCCompileAction.GetClArguments()` 返回（`VCCompileAction.cs:564-581`）：

```csharp
string GetClArguments()
{
    if (ResponseFile == null)
        return String.Join(" ", Arguments);
    else
        return String.Format("@{0}", Utils.MakePathSafeToUseWithCommandLine(ResponseFile));
        // → @"C:/.../UnrealEditorGCD/.../UnrealMCP.cpp.obj.rsp"
}
```

最终 `compile_commands.json` 中每条记录的结构为：

```json
{
  "file":      "C:/.../UnrealMCP/Source/UnrealMCP/Private/UnrealMCP.cpp",
  "command":   "\"C:/Program Files/LLVM/bin/clang-cl.exe\" @\"C:/.../UnrealEditorGCD/.../UnrealMCP.cpp.obj.rsp\"",
  "directory": "C:/.../Engine/Source",
  "output":    "C:/.../UnrealEditorGCD/.../UnrealMCP.cpp.obj"
}
```

clangd 读取 `"command"` 字段，展开 `@...rsp` 响应文件，进而找到 `@"...Shared.rsp"`，得到所有 include 路径。但 `.obj.rsp` 中不含 `/Yu`、`/Fp` 等 PCH 参数，clangd 因此无法获得 PCH 隐式注入的头文件定义，这正是它与实际编译产生分歧的根源。

### 7.6 完整链路总览

```
UBT -Mode=GenerateClangDatabase
  │
  ├─ bUseUnityBuild = false
  ├─ IntermediateEnvironment = GenerateClangDatabase  →  目录后缀 "GCD"
  │
  ├─ CreateClangDatabaseArguments(bUsePCH: false)
  │    └─ 附加 "-NoPCH"、"-Compiler=Clang"
  │
  ├─ UEBuildTarget.Create()
  │    └─ bUsePCHFiles = false（因 -NoPCH）
  │
  ├─ Target.BuildAsync()
  │    │
  │    ├─ SetupPrecompiledHeaders()  →  bUsePCHFiles=false，整体跳过
  │    │    └─ PrecompiledHeaderAction = None
  │    │       UsingPchFile = null
  │    │       ForceIncludeFiles = []（无 SharedPCH 头）
  │    │
  │    ├─ CreateHeaderForDefinitions()  →  Definitions.UnrealMCP.h
  │    │
  │    ├─ CreateSharedResponseFile()  →  UnrealMCP.Shared.rsp
  │    │    内容：由依赖树递归收集的全部 /I 和 /imsvc 路径
  │    │
  │    └─ VCToolChain.CompileCPPFiles()（逐文件，非 Unity）
  │         └─ 对每个 .cpp 创建 VCCompileAction
  │              │
  │              ├─ ResponseFile = "UnrealMCP.cpp.obj.rsp"
  │              └─ WriteResponseFile()
  │                   └─ GetCompilerArguments()
  │                        ├─ "UnrealMCP.cpp"
  │                        ├─ /FI"Definitions.UnrealMCP.h"
  │                        ├─ @"UnrealMCP.Shared.rsp"
  │                        ├─ /Fo"UnrealMCP.cpp.obj"
  │                        └─ [编译器 flags，无 /Yu /Fp]
  │
  ├─ 遍历 ActionType.Compile Actions
  │    └─ Action.CommandArguments → @"...UnrealMCP.cpp.obj.rsp"
  │
  └─ 写出 compile_commands.json
       └─ { "file": "UnrealMCP.cpp",
            "command": "clang-cl.exe @\"...GCD/.../UnrealMCP.cpp.obj.rsp\"",
            "directory": "Engine/Source",
            "output": "...UnrealMCP.cpp.obj" }
```
---
## 8. 修复

经过上面的分析我们知道问题的根源在于 `compile_commands.json` 包含的编译命令缺失了 PCH 和 Unity Build 引入的额外头文件。

这个问题可以从两个层面修复：

1. 在项目源码中补齐 IWYU 所需 `#include`，让单文件分析与真实编译环境对齐。
2. 修改 UBT 的 `GenerateClangDatabase` 逻辑，让 `compile_commands.json` 在指定模块上保留 PCH 信息（没有处理 Unity Build 引入的额外头文件，因为 Unity Build 的聚合 cpp 文件的方式可能变化，而且保留 PCH 已经能覆盖绝大多数情况）。

下面先给出源码侧修复，再给出两种 UBT 方案。两种 UBT 方案对外接口保持一致，都是通过 `-PCHModule=<ModuleName>` 指定需要使用 PCH 方式生成 compile command 的模块。

### 8.1 方法 1：修改项目源文件

最直接的方法是在源文件中显式添加缺失的 `#include` 指令。这既满足 clangd 的需要，也符合 IWYU (Include What You Use) 原则，而真正的构建只是使用 PCH 中已缓存的同一头文件：

```cpp
// UnrealMCP.cpp
#include "Widgets/Images/SImage.h"  // 为 IWYU / clangd 显式包含

// UnrealMCP.h
#include "Framework/MultiBox/MultiBoxBuilder.h"  // 为 FToolBarBuilder 显式包含
```

这种方式的优点是改动最小、与上游 UBT 无耦合、长期维护成本最低。缺点也很明显：当第三方模块规模很大，或者项目里存在大量历史代码依赖 PCH 隐式注入时，手工补齐 include 的工作量会比较高。

因此下面进入第二类方案：不改业务源码，而是改 UBT 生成 `compile_commands.json` 的过程。

### 8.2 方法 2：双 Pass 生成（简单直接）

这个方案的核心思路是把生成过程拆成两次：

1. Pass 1：保持原始 `GenerateClangDatabase` 行为（`-NoPCH`），生成全量 no-PCH compile commands。
2. Pass 2：仅对 `-PCHModule` 指定模块再跑一次，启用 PCH 生成对应 compile commands，并覆盖 Pass 1 的同源文件条目。

为了避免两次运行中间文件冲突，这个方案新增了一个中间目录环境：`GenerateClangDatabasePCH`，目录后缀为 `GCDPCH`。

优点：

* 实现直接，逻辑清晰，改动集中在 `GenerateClangDatabase` 模式本身。
* 不需要改变 `UEBuildTarget` 的创建流程和模块发现流程。

缺点：

* 会额外生成一份中间文件（`GCDPCH`）。
* 对 `UnrealEditor` 这种大目标，额外磁盘占用大约在 50 MB 左右。

完整改动如下：

```diff
diff --git a/Engine/Source/Programs/UnrealBuildTool/Configuration/UEBuildTarget.cs b/Engine/Source/Programs/UnrealBuildTool/Configuration/UEBuildTarget.cs
index 528530e5a721..edbe6fdb1c2e 100644
--- a/Engine/Source/Programs/UnrealBuildTool/Configuration/UEBuildTarget.cs
+++ b/Engine/Source/Programs/UnrealBuildTool/Configuration/UEBuildTarget.cs
@@ -1115,6 +1115,10 @@ namespace UnrealBuildTool
 		/// </summary>
 		GenerateClangDatabase,
 		/// <summary>
+		/// Generate clang database with PCH enabled for selected modules
+		/// </summary>
+		GenerateClangDatabasePCH,
+		/// <summary>
 		/// Include what you use
 		/// </summary>
 		IWYU,
@@ -1152,6 +1156,7 @@ namespace UnrealBuildTool
 			{
 				case UnrealIntermediateEnvironment.IWYU:
 				case UnrealIntermediateEnvironment.GenerateClangDatabase:
+				case UnrealIntermediateEnvironment.GenerateClangDatabasePCH:
 				case UnrealIntermediateEnvironment.NonUnity:
 					return false;
 			}
@@ -1905,6 +1910,9 @@ namespace UnrealBuildTool
 				case UnrealIntermediateEnvironment.GenerateClangDatabase:
 					TargetFolderName += "GCD";
 					break;
+				case UnrealIntermediateEnvironment.GenerateClangDatabasePCH:
+					TargetFolderName += "GCDPCH";
+					break;
 				case UnrealIntermediateEnvironment.GenerateProjectFiles:
 					TargetFolderName += "GPF";
 					break;
diff --git a/Engine/Source/Programs/UnrealBuildTool/Modes/GenerateClangDatabase.cs b/Engine/Source/Programs/UnrealBuildTool/Modes/GenerateClangDatabase.cs
index 2cad012297fb..03cb5388dfe3 100644
--- a/Engine/Source/Programs/UnrealBuildTool/Modes/GenerateClangDatabase.cs
+++ b/Engine/Source/Programs/UnrealBuildTool/Modes/GenerateClangDatabase.cs
@@ -30,6 +30,15 @@ namespace UnrealBuildTool
 		[CommandLine("-NoExecCodeGenActions", Value = "false")]
 		public bool bExecCodeGenActions = true;
 
+		/// <summary>
+		/// Set of module names that should use PCH-enabled compile commands.
+		/// When specified, a second build pass with PCH enabled is performed for these modules,
+		/// producing compile commands that include SharedPCH force-includes so that clangd can
+		/// correctly resolve all types provided by the precompiled header chain.
+		/// </summary>
+		[CommandLine("-PCHModule=")]
+		HashSet<string> PCHModuleNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
+
 		/// <summary>
 		/// Execute the command
 		/// </summary>
@@ -66,73 +75,23 @@ namespace UnrealBuildTool
 			using (ISourceFileWorkingSet WorkingSet = new EmptySourceFileWorkingSet())
 			{
 				// Find the compile commands for each file in the target
-				Dictionary<Tuple<string, string>, string> FileToCommand = new();
+				// Key: source file path, Value: (command string, output file path)
+				Dictionary<string, (string Command, string OutputFile)> FileToCommand = new();
+
 				foreach (TargetDescriptor TargetDescriptor in TargetDescriptors)
 				{
-					// Disable PCHs and unity builds for the target
-					TargetDescriptor.bUseUnityBuild = false;
-					TargetDescriptor.IntermediateEnvironment = UnrealIntermediateEnvironment.GenerateClangDatabase;
-					TargetDescriptor.AdditionalArguments = TargetDescriptor.AdditionalArguments.Append(new string[] { "-NoPCH" });
-					// Default the compiler to clang
-					if (!TargetDescriptor.AdditionalArguments.Any(x => x.StartsWith("-Compiler=", StringComparison.OrdinalIgnoreCase)))
-					{
-						TargetDescriptor.AdditionalArguments = TargetDescriptor.AdditionalArguments.Append(new string[] { "-Compiler=Clang" });
-					}
-
-					// Create a makefile for the target
-					Logger.LogInformation("Creating target...");
-					UEBuildTarget Target = UEBuildTarget.Create(TargetDescriptor, BuildConfiguration, Logger);
-					UEToolChain TargetToolChain = Target.CreateToolchain(Target.Platform, Logger);
-
-					// Create the makefile
-					TargetMakefile Makefile = await Target.BuildAsync(BuildConfiguration, WorkingSet, TargetDescriptor, Logger);
-					List<LinkedAction> Actions = Makefile.Actions.ConvertAll(x => new LinkedAction(x, TargetDescriptor));
-					ActionGraph.Link(Actions, Logger);
+					// Save the original AdditionalArguments before any modifications
+					CommandLineArguments OriginalArguments = TargetDescriptor.AdditionalArguments;
 
-					if (bExecCodeGenActions)
+					if (PCHModuleNames.Count > 0)
 					{
-						// Filter all the actions to execute
-						HashSet<FileItem> PrerequisiteItems = new HashSet<FileItem>(Makefile.Actions.SelectMany(x => x.ProducedItems).Where(x => x.HasExtension(".h") || x.HasExtension(".cpp") || x.HasExtension(".cc") || x.HasExtension(".c")));
-						List<LinkedAction> PrerequisiteActions = ActionGraph.GatherPrerequisiteActions(Actions, PrerequisiteItems);
-
-						Utils.ExecuteCustomBuildSteps(Makefile.PreBuildScripts, Logger);
-
-						// Execute code generation actions
-						if (PrerequisiteActions.Any())
-						{
-							Logger.LogInformation("Executing actions that produce source files...");
-							await ActionGraph.ExecuteActionsAsync(BuildConfiguration, PrerequisiteActions, new List<TargetDescriptor> { TargetDescriptor }, Logger);
-						}
+						// === Two-pass mode: selected modules get PCH-enabled commands ===
+						await ExecuteTwoPassAsync(TargetDescriptor, OriginalArguments, BuildConfiguration, WorkingSet, FileToCommand, Logger);
 					}
-
-					Logger.LogInformation("Filtering compile actions...");
-
-					IEnumerable<IExternalAction> CompileActions = Actions
-						.Where(x => x.ActionType == ActionType.Compile)
-						.Where(x => x.PrerequisiteItems.Any());
-
-					if (CompileActions.Any())
+					else
 					{
-						foreach (IExternalAction Action in CompileActions)
-						{
-							FileItem? SourceFile = Action.PrerequisiteItems.FirstOrDefault(x => x.HasExtension(".cpp") || x.HasExtension(".cc") || x.HasExtension(".c")) ?? Action.PrerequisiteItems.FirstOrDefault(x => x.HasExtension(".h"));
-							FileItem? OutputFile = Action.ProducedItems.FirstOrDefault(x => x.HasExtension(".obj") | x.HasExtension(".o"));
-							if (SourceFile == null || OutputFile == null)
-							{
-								continue;
-							}
-							// Create the command
-							StringBuilder CommandBuilder = new StringBuilder();
-							string CommandPath = Action.CommandPath.FullName.Contains(' ') ? Utils.MakePathSafeToUseWithCommandLine(Action.CommandPath) : Action.CommandPath.FullName;
-							CommandBuilder.AppendFormat("{0} {1}", CommandPath, Action.CommandArguments);
-
-							foreach (string ExtraArgument in GetExtraPlatformArguments(TargetToolChain))
-							{
-								CommandBuilder.AppendFormat(" {0}", ExtraArgument);
-							}
-
-							FileToCommand[Tuple.Create(SourceFile.FullName, OutputFile.FullName)] = CommandBuilder.ToString();
-						}
+						// === Single-pass mode: original behavior, no PCH for any module ===
+						await ExecuteSinglePassAsync(TargetDescriptor, OriginalArguments, BuildConfiguration, WorkingSet, FileToCommand, Logger);
 					}
 				}
 
@@ -144,13 +103,13 @@ namespace UnrealBuildTool
 				using (JsonWriter Writer = new JsonWriter(DatabaseFile))
 				{
 					Writer.WriteArrayStart();
-					foreach (KeyValuePair<Tuple<string, string>, string> FileCommandPair in FileToCommand.OrderBy(x => x.Key.Item1))
+					foreach (KeyValuePair<string, (string Command, string OutputFile)> FileCommandPair in FileToCommand.OrderBy(x => x.Key))
 					{
 						Writer.WriteObjectStart();
-						Writer.WriteValue("file", FileCommandPair.Key.Item1.Replace('\\', '/'));
-						Writer.WriteValue("command", FileCommandPair.Value.Replace('\\', '/'));
+						Writer.WriteValue("file", FileCommandPair.Key.Replace('\\', '/'));
+						Writer.WriteValue("command", FileCommandPair.Value.Command.Replace('\\', '/'));
 						Writer.WriteValue("directory", Unreal.EngineSourceDirectory.FullName.Replace('\\', '/'));
-						Writer.WriteValue("output", FileCommandPair.Key.Item2.Replace('\\', '/'));
+						Writer.WriteValue("output", FileCommandPair.Value.OutputFile.Replace('\\', '/'));
 						Writer.WriteObjectEnd();
 					}
 					Writer.WriteArrayEnd();
@@ -162,6 +121,195 @@ namespace UnrealBuildTool
 			return 0;
 		}
 
+		/// <summary>
+		/// Original single-pass behavior: all modules compiled without PCH.
+		/// </summary>
+		private async Task ExecuteSinglePassAsync(
+			TargetDescriptor TargetDescriptor,
+			CommandLineArguments OriginalArguments,
+			BuildConfiguration BuildConfiguration,
+			ISourceFileWorkingSet WorkingSet,
+			Dictionary<string, (string Command, string OutputFile)> FileToCommand,
+			ILogger Logger)
+		{
+			// Disable PCHs and unity builds for the target
+			TargetDescriptor.bUseUnityBuild = false;
+			TargetDescriptor.IntermediateEnvironment = UnrealIntermediateEnvironment.GenerateClangDatabase;
+			TargetDescriptor.AdditionalArguments = OriginalArguments.Append(new string[] { "-NoPCH" });
+			// Default the compiler to clang
+			if (!TargetDescriptor.AdditionalArguments.Any(x => x.StartsWith("-Compiler=", StringComparison.OrdinalIgnoreCase)))
+			{
+				TargetDescriptor.AdditionalArguments = TargetDescriptor.AdditionalArguments.Append(new string[] { "-Compiler=Clang" });
+			}
+
+			// Create and build the target
+			UEBuildTarget Target = UEBuildTarget.Create(TargetDescriptor, BuildConfiguration, Logger);
+			UEToolChain TargetToolChain = Target.CreateToolchain(Target.Platform, Logger);
+
+			Logger.LogInformation("Creating target...");
+			TargetMakefile Makefile = await Target.BuildAsync(BuildConfiguration, WorkingSet, TargetDescriptor, Logger);
+			List<LinkedAction> Actions = Makefile.Actions.ConvertAll(x => new LinkedAction(x, TargetDescriptor));
+			ActionGraph.Link(Actions, Logger);
+
+			if (bExecCodeGenActions)
+			{
+				await ExecuteCodeGenActionsAsync(Makefile, Actions, BuildConfiguration, TargetDescriptor, Logger);
+			}
+
+			Logger.LogInformation("Filtering compile actions...");
+			CollectCompileCommands(Actions, TargetToolChain, FileToCommand, null, Logger);
+		}
+
+		/// <summary>
+		/// Two-pass mode: Pass 1 generates no-PCH commands for non-selected modules,
+		/// Pass 2 generates PCH-enabled commands for selected modules.
+		/// </summary>
+		private async Task ExecuteTwoPassAsync(
+			TargetDescriptor TargetDescriptor,
+			CommandLineArguments OriginalArguments,
+			BuildConfiguration BuildConfiguration,
+			ISourceFileWorkingSet WorkingSet,
+			Dictionary<string, (string Command, string OutputFile)> FileToCommand,
+			ILogger Logger)
+		{
+			// ====== Pass 1: No PCH (for non-selected modules) ======
+			Logger.LogInformation("Pass 1: Creating target without PCH...");
+			TargetDescriptor.bUseUnityBuild = false;
+			TargetDescriptor.IntermediateEnvironment = UnrealIntermediateEnvironment.GenerateClangDatabase;
+			TargetDescriptor.AdditionalArguments = OriginalArguments.Append(new string[] { "-NoPCH" });
+			if (!TargetDescriptor.AdditionalArguments.Any(x => x.StartsWith("-Compiler=", StringComparison.OrdinalIgnoreCase)))
+			{
+				TargetDescriptor.AdditionalArguments = TargetDescriptor.AdditionalArguments.Append(new string[] { "-Compiler=Clang" });
+			}
+
+			UEBuildTarget Target1 = UEBuildTarget.Create(TargetDescriptor, BuildConfiguration, Logger);
+			UEToolChain ToolChain1 = Target1.CreateToolchain(Target1.Platform, Logger);
+
+			TargetMakefile Makefile1 = await Target1.BuildAsync(BuildConfiguration, WorkingSet, TargetDescriptor, Logger);
+			List<LinkedAction> Actions1 = Makefile1.Actions.ConvertAll(x => new LinkedAction(x, TargetDescriptor));
+			ActionGraph.Link(Actions1, Logger);
+
+			// Execute code generation actions only in Pass 1
+			if (bExecCodeGenActions)
+			{
+				await ExecuteCodeGenActionsAsync(Makefile1, Actions1, BuildConfiguration, TargetDescriptor, Logger);
+			}
+
+			Logger.LogInformation("Pass 1: Collecting compile commands for non-PCH modules...");
+			CollectCompileCommands(Actions1, ToolChain1, FileToCommand, PCHModuleNames, Logger, includePCHModules: false);
+
+			// ====== Pass 2: With PCH (for selected modules) ======
+			Logger.LogInformation("Pass 2: Creating target with PCH...");
+			TargetDescriptor.IntermediateEnvironment = UnrealIntermediateEnvironment.GenerateClangDatabasePCH;
+			TargetDescriptor.AdditionalArguments = OriginalArguments; // No -NoPCH => bUsePCHFiles=true
+			if (!TargetDescriptor.AdditionalArguments.Any(x => x.StartsWith("-Compiler=", StringComparison.OrdinalIgnoreCase)))
+			{
+				TargetDescriptor.AdditionalArguments = TargetDescriptor.AdditionalArguments.Append(new string[] { "-Compiler=Clang" });
+			}
+			TargetDescriptor.bUseUnityBuild = false; // Still non-unity for per-file commands
+
+			UEBuildTarget Target2 = UEBuildTarget.Create(TargetDescriptor, BuildConfiguration, Logger);
+			UEToolChain ToolChain2 = Target2.CreateToolchain(Target2.Platform, Logger);
+
+			TargetMakefile Makefile2 = await Target2.BuildAsync(BuildConfiguration, WorkingSet, TargetDescriptor, Logger);
+			List<LinkedAction> Actions2 = Makefile2.Actions.ConvertAll(x => new LinkedAction(x, TargetDescriptor));
+			ActionGraph.Link(Actions2, Logger);
+			// Skip code generation actions in Pass 2 (already done in Pass 1)
+
+			Logger.LogInformation("Pass 2: Collecting compile commands for PCH modules...");
+			CollectCompileCommands(Actions2, ToolChain2, FileToCommand, PCHModuleNames, Logger, includePCHModules: true);
+		}
+
+		/// <summary>
+		/// Execute code generation actions (e.g. ISPC compilation) that produce source files.
+		/// </summary>
+		private async Task ExecuteCodeGenActionsAsync(
+			TargetMakefile Makefile,
+			List<LinkedAction> Actions,
+			BuildConfiguration BuildConfiguration,
+			TargetDescriptor TargetDescriptor,
+			ILogger Logger)
+		{
+			HashSet<FileItem> PrerequisiteItems = new HashSet<FileItem>(Makefile.Actions.SelectMany(x => x.ProducedItems).Where(x => x.HasExtension(".h") || x.HasExtension(".cpp") || x.HasExtension(".cc") || x.HasExtension(".c")));
+			List<LinkedAction> PrerequisiteActions = ActionGraph.GatherPrerequisiteActions(Actions, PrerequisiteItems);
+
+			Utils.ExecuteCustomBuildSteps(Makefile.PreBuildScripts, Logger);
+
+			if (PrerequisiteActions.Any())
+			{
+				Logger.LogInformation("Executing actions that produce source files...");
+				await ActionGraph.ExecuteActionsAsync(BuildConfiguration, PrerequisiteActions, new List<TargetDescriptor> { TargetDescriptor }, Logger);
+			}
+		}
+
+		/// <summary>
+		/// Collect compile commands from actions into the FileToCommand dictionary.
+		///
+		/// When pchModuleNames is null (single-pass mode), all compile actions are collected.
+		/// When pchModuleNames is provided (two-pass mode), only actions matching the module filter are collected:
+		///   - includePCHModules=true:  collect only actions for modules in pchModuleNames
+		///   - includePCHModules=false: collect only actions for modules NOT in pchModuleNames
+		/// </summary>
+		private void CollectCompileCommands(
+			List<LinkedAction> Actions,
+			UEToolChain TargetToolChain,
+			Dictionary<string, (string Command, string OutputFile)> FileToCommand,
+			HashSet<string>? pchModuleNames,
+			ILogger Logger,
+			bool includePCHModules = false)
+		{
+			IEnumerable<IExternalAction> CompileActions = Actions
+				.Where(x => x.ActionType == ActionType.Compile)
+				.Where(x => x.PrerequisiteItems.Any());
+
+			if (!CompileActions.Any())
+			{
+				return;
+			}
+
+			foreach (IExternalAction Action in CompileActions)
+			{
+				FileItem? SourceFile = Action.PrerequisiteItems.FirstOrDefault(x => x.HasExtension(".cpp") || x.HasExtension(".cc") || x.HasExtension(".c")) ?? Action.PrerequisiteItems.FirstOrDefault(x => x.HasExtension(".h"));
+				FileItem? OutputFile = Action.ProducedItems.FirstOrDefault(x => x.HasExtension(".obj") | x.HasExtension(".o"));
+				if (SourceFile == null || OutputFile == null)
+				{
+					continue;
+				}
+
+				// Apply module filter if in two-pass mode.
+				// The output directory of each compile action is already grouped by module name,
+				// so use that directly rather than trying to infer the module from link outputs.
+				if (pchModuleNames != null)
+				{
+					string? ModuleName = OutputFile.Directory.Name;
+					bool IsInPCHModuleSet = ModuleName != null && pchModuleNames.Contains(ModuleName);
+					if (IsInPCHModuleSet)
+					{
+						Logger.LogInformation("PCH module matched: {ModuleName} -> {SourceFile}", ModuleName, SourceFile.FullName);
+					}
+
+					if (includePCHModules != IsInPCHModuleSet)
+					{
+						continue;
+					}
+				}
+
+				// Create the command
+				StringBuilder CommandBuilder = new StringBuilder();
+				string CommandPath = Action.CommandPath.FullName.Contains(' ') ? Utils.MakePathSafeToUseWithCommandLine(Action.CommandPath) : Action.CommandPath.FullName;
+				CommandBuilder.AppendFormat("{0} {1}", CommandPath, Action.CommandArguments);
+
+				foreach (string ExtraArgument in GetExtraPlatformArguments(TargetToolChain))
+				{
+					CommandBuilder.AppendFormat(" {0}", ExtraArgument);
+				}
+
+				FileToCommand[SourceFile.FullName] = (CommandBuilder.ToString(), OutputFile.FullName);
+			}
+		}
+
+
+
 		private IEnumerable<string> GetExtraPlatformArguments(UEToolChain TargetToolChain)
 		{
 			IList<string> ExtraPlatformArguments = new List<string>();
```

### 8.3 方法 3：在 UEBuildTarget 侧过滤（更侵入，但更省空间）

这个方案仍然保留相同的外部接口：`-PCHModule=<ModuleName>`。

不同点在于，它不是通过新增 `GCDPCH` 目录跑完整第二遍，而是在 `UEBuildTarget` 创建好模块图与 binary 后进行过滤：

1. 完整模块发现先正常进行，保证 shared PCH 候选与 compile environment 的分析信息完整。
2. 当执行 PCH pass 时，仅保留 `-PCHModule` 命中的 binary 进入后续构建。
3. compile command 收集阶段只从这些模块目录提取条目并覆盖首轮 no-PCH 结果。

这样第二次运行只会生成指定模块需要的中间文件，不需要新增临时目录，磁盘占用明显更低。

代价是实现更侵入：需要修改 `TargetDescriptor`、`UEBuildTarget` 以及 `GenerateClangDatabase` 的协作逻辑，并引入新的过滤入口。

完整改动如下：

```diff
diff --git a/Engine/Source/Programs/UnrealBuildTool/Configuration/TargetDescriptor.cs b/Engine/Source/Programs/UnrealBuildTool/Configuration/TargetDescriptor.cs
index d88708c1463e..74e33254ddd3 100644
--- a/Engine/Source/Programs/UnrealBuildTool/Configuration/TargetDescriptor.cs
+++ b/Engine/Source/Programs/UnrealBuildTool/Configuration/TargetDescriptor.cs
@@ -59,6 +59,11 @@ namespace UnrealBuildTool
 		[CommandLine("-Module=")]
 		public HashSet<string> OnlyModuleNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
 
+		/// <summary>
+		/// Set of module names for which GenerateClangDatabase should emit compile commands with PCH enabled.
+		/// </summary>
+		public HashSet<string> ClangDatabasePCHModuleNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
+
 		/// <summary>
 		/// Lists of files to compile
 		/// </summary>
diff --git a/Engine/Source/Programs/UnrealBuildTool/Configuration/UEBuildTarget.cs b/Engine/Source/Programs/UnrealBuildTool/Configuration/UEBuildTarget.cs
index 528530e5a721..bcf8162a9c0f 100644
--- a/Engine/Source/Programs/UnrealBuildTool/Configuration/UEBuildTarget.cs
+++ b/Engine/Source/Programs/UnrealBuildTool/Configuration/UEBuildTarget.cs
@@ -1391,6 +1391,10 @@ namespace UnrealBuildTool
 			{
 				Target.PreBuildSetup(Logger);
 			}
+			using (GlobalTracer.Instance.BuildSpan("UEBuildTarget.ApplyClangDatabasePCHModuleFilter()").StartActive())
+			{
+				Target.ApplyClangDatabasePCHModuleFilter(Descriptor, Logger);
+			}
 
 			return Target;
 		}
@@ -2451,7 +2455,8 @@ namespace UnrealBuildTool
 			UEToolChain TargetToolChain = CreateToolchain(Platform, Logger);
 			SetupGlobalEnvironment(TargetToolChain, GlobalCompileEnvironment, GlobalLinkEnvironment);
 
-			FindSharedPCHs(Binaries, GlobalCompileEnvironment, Logger);
+			List<UEBuildBinary> SharedPCHBinaries = NonFilteredModules.Count > 0 ? NonFilteredModules : Binaries;
+			FindSharedPCHs(SharedPCHBinaries, GlobalCompileEnvironment, Logger);
 
 			return GlobalCompileEnvironment;
 		}
@@ -2474,6 +2479,7 @@ namespace UnrealBuildTool
 
 			// Save off the original list of binaries. We'll use this to figure out which PCHs to create later, to avoid switching PCHs when compiling single modules.
 			List<UEBuildBinary> OriginalBinaries = Binaries;
+			List<UEBuildBinary> SharedPCHBinaries = NonFilteredModules.Count > 0 ? NonFilteredModules : OriginalBinaries;
 
 			// For installed builds, filter out all the binaries that aren't in mods
 			if (UnrealBuildTool.IsProjectInstalled())
@@ -2588,7 +2594,7 @@ namespace UnrealBuildTool
 			if (Rules.bUseSharedPCHs)
 			{
 				// Find all the shared PCHs.
-				FindSharedPCHs(OriginalBinaries, GlobalCompileEnvironment, Logger);
+				FindSharedPCHs(SharedPCHBinaries, GlobalCompileEnvironment, Logger);
 
 				// Create all the shared PCH instances before processing the modules
 				CreateSharedPCHInstances(Rules, TargetToolChain, OriginalBinaries, GlobalCompileEnvironment, MakefileBuilder, Logger);
@@ -3463,6 +3469,72 @@ namespace UnrealBuildTool
 			}
 		}
 
+		/// <summary>
+		/// Restricts the binaries that are built for the PCH-enabled clang database pass. Module discovery still happens
+		/// before this filter runs, allowing compile environments and shared PCH discovery to use the complete module graph.
+		/// </summary>
+		/// <param name="Descriptor">Descriptor containing the requested PCH modules</param>
+		/// <param name="Logger">Logger for output</param>
+		public void ApplyClangDatabasePCHModuleFilter(TargetDescriptor Descriptor, ILogger Logger)
+		{
+			if (Descriptor.ClangDatabasePCHModuleNames.Count == 0)
+			{
+				return;
+			}
+
+			HashSet<UEBuildBinary> FilteredBinaries = new();
+			foreach (string ModuleName in Descriptor.ClangDatabasePCHModuleNames)
+			{
+				if (!Modules.TryGetValue(ModuleName, out UEBuildModule? Module))
+				{
+					throw new BuildException("Unable to find PCH module '{0}' while generating clang database for target '{1}'.", ModuleName, TargetName);
+				}
+				if (Module is not UEBuildModuleCPP ModuleCPP)
+				{
+					throw new BuildException("PCH module '{0}' is not a C++ module.", ModuleName);
+				}
+				if (ModuleCPP.Binary == null)
+				{
+					throw new BuildException("PCH module '{0}' is not bound to a binary.", ModuleName);
+				}
+
+				FilteredBinaries.Add(ModuleCPP.Binary);
+			}
+
+			NonFilteredModules = new List<UEBuildBinary>(Binaries);
+			Binaries = Binaries.Where(Binary => FilteredBinaries.Contains(Binary)).ToList();
+
+			Logger.LogDebug("Filtered clang database PCH pass to {BinaryCount} binaries for modules: {ModuleNames}", Binaries.Count, String.Join(", ", Descriptor.ClangDatabasePCHModuleNames.OrderBy(x => x)));
+		}
+
+		/// <summary>
+		/// Gets all source and intermediate directories for the given modules.
+		/// </summary>
+		/// <param name="ModuleNames">Names of the modules to query</param>
+		/// <returns>Directories which may contain source files compiled for these modules</returns>
+		public HashSet<DirectoryReference> GetClangDatabaseDirectoriesForModules(IEnumerable<string> ModuleNames)
+		{
+			HashSet<DirectoryReference> Directories = new();
+
+			foreach (string ModuleName in ModuleNames)
+			{
+				if (!Modules.TryGetValue(ModuleName, out UEBuildModule? Module))
+				{
+					throw new BuildException("Unable to find clang database module '{0}' for target '{1}'.", ModuleName, TargetName);
+				}
+				if (Module is not UEBuildModuleCPP ModuleCPP)
+				{
+					throw new BuildException("Clang database module '{0}' is not a C++ module.", ModuleName);
+				}
+
+				Directories.UnionWith(ModuleCPP.ModuleDirectories);
+				Directories.Add(ModuleCPP.IntermediateDirectory);
+				Directories.Add(ModuleCPP.IntermediateDirectoryNoArch);
+			}
+
+			return Directories;
+		}
+
 		/// <summary>
 		/// Creates scripts for executing the pre-build scripts
 		/// </summary>
diff --git a/Engine/Source/Programs/UnrealBuildTool/Modes/GenerateClangDatabase.cs b/Engine/Source/Programs/UnrealBuildTool/Modes/GenerateClangDatabase.cs
index 2cad012297fb..d7cbe2d04c82 100644
--- a/Engine/Source/Programs/UnrealBuildTool/Modes/GenerateClangDatabase.cs
+++ b/Engine/Source/Programs/UnrealBuildTool/Modes/GenerateClangDatabase.cs
@@ -30,6 +30,12 @@ namespace UnrealBuildTool
 		[CommandLine("-NoExecCodeGenActions", Value = "false")]
 		public bool bExecCodeGenActions = true;
 
+		/// <summary>
+		/// Modules for which compile commands should be regenerated with PCH enabled.
+		/// </summary>
+		[CommandLine("-PCHModule=")]
+		List<string> PCHModuleRules = new List<string>();
+
 		/// <summary>
 		/// Execute the command
 		/// </summary>
@@ -65,74 +71,21 @@ namespace UnrealBuildTool
 			// Generate the compile DB for each target
 			using (ISourceFileWorkingSet WorkingSet = new EmptySourceFileWorkingSet())
 			{
+				HashSet<string> PCHModuleNames = ParseModuleList(PCHModuleRules);
+
 				// Find the compile commands for each file in the target
 				Dictionary<Tuple<string, string>, string> FileToCommand = new();
 				foreach (TargetDescriptor TargetDescriptor in TargetDescriptors)
 				{
-					// Disable PCHs and unity builds for the target
+					CommandLineArguments BaseArguments = TargetDescriptor.AdditionalArguments;
 					TargetDescriptor.bUseUnityBuild = false;
 					TargetDescriptor.IntermediateEnvironment = UnrealIntermediateEnvironment.GenerateClangDatabase;
-					TargetDescriptor.AdditionalArguments = TargetDescriptor.AdditionalArguments.Append(new string[] { "-NoPCH" });
-					// Default the compiler to clang
-					if (!TargetDescriptor.AdditionalArguments.Any(x => x.StartsWith("-Compiler=", StringComparison.OrdinalIgnoreCase)))
-					{
-						TargetDescriptor.AdditionalArguments = TargetDescriptor.AdditionalArguments.Append(new string[] { "-Compiler=Clang" });
-					}
+
+					await GenerateCompileCommandsForTargetAsync(TargetDescriptor, BuildConfiguration, WorkingSet, CreateClangDatabaseArguments(BaseArguments, bUsePCH: false), FileToCommand, null, bExecCodeGenActions, Logger);
 
-					// Create a makefile for the target
-					Logger.LogInformation("Creating target...");
-					UEBuildTarget Target = UEBuildTarget.Create(TargetDescriptor, BuildConfiguration, Logger);
-					UEToolChain TargetToolChain = Target.CreateToolchain(Target.Platform, Logger);
-
-					// Create the makefile
-					TargetMakefile Makefile = await Target.BuildAsync(BuildConfiguration, WorkingSet, TargetDescriptor, Logger);
-					List<LinkedAction> Actions = Makefile.Actions.ConvertAll(x => new LinkedAction(x, TargetDescriptor));
-					ActionGraph.Link(Actions, Logger);
-
-					if (bExecCodeGenActions)
+					if (PCHModuleNames.Count > 0)
 					{
-						// Filter all the actions to execute
-						HashSet<FileItem> PrerequisiteItems = new HashSet<FileItem>(Makefile.Actions.SelectMany(x => x.ProducedItems).Where(x => x.HasExtension(".h") || x.HasExtension(".cpp") || x.HasExtension(".cc") || x.HasExtension(".c")));
-						List<LinkedAction> PrerequisiteActions = ActionGraph.GatherPrerequisiteActions(Actions, PrerequisiteItems);
-
-						Utils.ExecuteCustomBuildSteps(Makefile.PreBuildScripts, Logger);
-
-						// Execute code generation actions
-						if (PrerequisiteActions.Any())
-						{
-							Logger.LogInformation("Executing actions that produce source files...");
-							await ActionGraph.ExecuteActionsAsync(BuildConfiguration, PrerequisiteActions, new List<TargetDescriptor> { TargetDescriptor }, Logger);
-						}
-					}
-
-					Logger.LogInformation("Filtering compile actions...");
-
-					IEnumerable<IExternalAction> CompileActions = Actions
-						.Where(x => x.ActionType == ActionType.Compile)
-						.Where(x => x.PrerequisiteItems.Any());
-
-					if (CompileActions.Any())
-					{
-						foreach (IExternalAction Action in CompileActions)
-						{
-							FileItem? SourceFile = Action.PrerequisiteItems.FirstOrDefault(x => x.HasExtension(".cpp") || x.HasExtension(".cc") || x.HasExtension(".c")) ?? Action.PrerequisiteItems.FirstOrDefault(x => x.HasExtension(".h"));
-							FileItem? OutputFile = Action.ProducedItems.FirstOrDefault(x => x.HasExtension(".obj") | x.HasExtension(".o"));
-							if (SourceFile == null || OutputFile == null)
-							{
-								continue;
-							}
-							// Create the command
-							StringBuilder CommandBuilder = new StringBuilder();
-							string CommandPath = Action.CommandPath.FullName.Contains(' ') ? Utils.MakePathSafeToUseWithCommandLine(Action.CommandPath) : Action.CommandPath.FullName;
-							CommandBuilder.AppendFormat("{0} {1}", CommandPath, Action.CommandArguments);
-
-							foreach (string ExtraArgument in GetExtraPlatformArguments(TargetToolChain))
-							{
-								CommandBuilder.AppendFormat(" {0}", ExtraArgument);
-							}
-
-							FileToCommand[Tuple.Create(SourceFile.FullName, OutputFile.FullName)] = CommandBuilder.ToString();
-						}
+						await GenerateCompileCommandsForTargetAsync(TargetDescriptor, BuildConfiguration, WorkingSet, CreateClangDatabaseArguments(BaseArguments, bUsePCH: true), FileToCommand, PCHModuleNames, false, Logger);
 					}
 				}
 
@@ -174,5 +127,104 @@ namespace UnrealBuildTool
 
 			return ExtraPlatformArguments;
 		}
+
+		private static HashSet<string> ParseModuleList(IEnumerable<string> ModuleRules)
+		{
+			HashSet<string> ModuleNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
+			foreach (string ModuleRule in ModuleRules)
+			{
+				foreach (string ModuleName in ModuleRule.Split(new char[] { ';', ',' }, StringSplitOptions.RemoveEmptyEntries))
+				{
+					string TrimmedModuleName = ModuleName.Trim();
+					if (TrimmedModuleName.Length > 0)
+					{
+						ModuleNames.Add(TrimmedModuleName);
+					}
+				}
+			}
+			return ModuleNames;
+		}
+
+		private static CommandLineArguments CreateClangDatabaseArguments(CommandLineArguments BaseArguments, bool bUsePCH)
+		{
+			CommandLineArguments Arguments = BaseArguments;
+			if (!bUsePCH)
+			{
+				Arguments = Arguments.Append(new string[] { "-NoPCH" });
+			}
+			if (!Arguments.Any(x => x.StartsWith("-Compiler=", StringComparison.OrdinalIgnoreCase)))
+			{
+				Arguments = Arguments.Append(new string[] { "-Compiler=Clang" });
+			}
+			return Arguments;
+		}
+
+		private async Task GenerateCompileCommandsForTargetAsync(TargetDescriptor TargetDescriptor, BuildConfiguration BuildConfiguration, ISourceFileWorkingSet WorkingSet, CommandLineArguments AdditionalArguments, Dictionary<Tuple<string, string>, string> FileToCommand, HashSet<string>? PCHModuleNames, bool bExecuteCodeGenActions, ILogger Logger)
+		{
+			TargetDescriptor.AdditionalArguments = AdditionalArguments;
+			TargetDescriptor.ClangDatabasePCHModuleNames = PCHModuleNames != null
+				? new HashSet<string>(PCHModuleNames, StringComparer.OrdinalIgnoreCase)
+				: new HashSet<string>(StringComparer.OrdinalIgnoreCase);
+
+			Logger.LogInformation("Creating target...");
+			UEBuildTarget Target = UEBuildTarget.Create(TargetDescriptor, BuildConfiguration, Logger);
+			UEToolChain TargetToolChain = Target.CreateToolchain(Target.Platform, Logger);
+			HashSet<DirectoryReference>? SelectedDirectories = PCHModuleNames != null ? Target.GetClangDatabaseDirectoriesForModules(PCHModuleNames) : null;
+
+			TargetMakefile Makefile = await Target.BuildAsync(BuildConfiguration, WorkingSet, TargetDescriptor, Logger);
+			List<LinkedAction> Actions = Makefile.Actions.ConvertAll(x => new LinkedAction(x, TargetDescriptor));
+			ActionGraph.Link(Actions, Logger);
+
+			if (bExecuteCodeGenActions)
+			{
+				HashSet<FileItem> PrerequisiteItems = new HashSet<FileItem>(Makefile.Actions.SelectMany(x => x.ProducedItems).Where(x => x.HasExtension(".h") || x.HasExtension(".cpp") || x.HasExtension(".cc") || x.HasExtension(".c")));
+				List<LinkedAction> PrerequisiteActions = ActionGraph.GatherPrerequisiteActions(Actions, PrerequisiteItems);
+
+				Utils.ExecuteCustomBuildSteps(Makefile.PreBuildScripts, Logger);
+
+				if (PrerequisiteActions.Any())
+				{
+					Logger.LogInformation("Executing actions that produce source files...");
+					await ActionGraph.ExecuteActionsAsync(BuildConfiguration, PrerequisiteActions, new List<TargetDescriptor> { TargetDescriptor }, Logger);
+				}
+			}
+
+			Logger.LogInformation("Filtering compile actions...");
+
+			foreach (IExternalAction Action in Actions.Where(x => x.ActionType == ActionType.Compile).Where(x => x.PrerequisiteItems.Any()))
+			{
+				FileItem? SourceFile = Action.PrerequisiteItems.FirstOrDefault(x => x.HasExtension(".cpp") || x.HasExtension(".cc") || x.HasExtension(".c"));
+				if (SourceFile == null)
+				{
+					if (SelectedDirectories != null)
+					{
+						continue;
+					}
+
+					SourceFile = Action.PrerequisiteItems.FirstOrDefault(x => x.HasExtension(".h"));
+				}
+
+				FileItem? OutputFile = Action.ProducedItems.FirstOrDefault(x => x.HasExtension(".obj") || x.HasExtension(".o"));
+				if (SourceFile == null || OutputFile == null)
+				{
+					continue;
+				}
+				if (SelectedDirectories != null && !SelectedDirectories.Any(Directory => SourceFile.Location.IsUnderDirectory(Directory)))
+				{
+					continue;
+				}
+
+				StringBuilder CommandBuilder = new StringBuilder();
+				string CommandPath = Action.CommandPath.FullName.Contains(' ') ? Utils.MakePathSafeToUseWithCommandLine(Action.CommandPath) : Action.CommandPath.FullName;
+				CommandBuilder.AppendFormat("{0} {1}", CommandPath, Action.CommandArguments);
+
+				foreach (string ExtraArgument in GetExtraPlatformArguments(TargetToolChain))
+				{
+					CommandBuilder.AppendFormat(" {0}", ExtraArgument);
+				}
+
+				FileToCommand[Tuple.Create(SourceFile.FullName, OutputFile.FullName)] = CommandBuilder.ToString();
+			}
+		}
 	}
 }
```

## Reference

[UE5 模块,PrivateDependencyModuleNames](https://zhuanlan.zhihu.com/p/107270501) 对 UBT 编译中涉及的配置有较为全面的梳理