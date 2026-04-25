---
title: Unreal Editor Extending -- Docking Tab
date: 2026-04-05 20:44:21 +0800
comments: true
categories:
  - UE5
---

通过 widget reflector 观察 swidget 的布局
## 1. window 创建

两步： 
```c++
SNew(SWindow);
FSlateApplication::Get().AddWindow;
```

## 2. Docking Tab

### 2.1 使用示例
下面给一个最小化示例，流程是：注册 spawner -> 定义 tab 内容 -> 在命令回调里调用 `TryInvokeTab` 打开。

先定义一个全局 `TabId`，后续注册和打开都用同一个名字。

```c++
static const FName Live2DTabName("Live2D");
```

在模块启动时注册 Nomad Tab 的生成回调；在模块卸载时反注册。

```c++
void FLive2DModule::StartupModule()
{
	FGlobalTabmanager::Get()->RegisterNomadTabSpawner(
		Live2DTabName,
		FOnSpawnTab::CreateRaw(this, &FLive2DModule::OnSpawnPluginTab)
	)
	.SetDisplayName(LOCTEXT("FLive2DTabTitle", "Live2D"))
	.SetMenuType(ETabSpawnerMenuType::Hidden);
}

void FLive2DModule::ShutdownModule()
{
	FGlobalTabmanager::Get()->UnregisterNomadTabSpawner(Live2DTabName);
}
```

`OnSpawnPluginTab` 负责真正创建 `SDockTab` 和其内容 widget。

```c++
TSharedRef<SDockTab> FLive2DModule::OnSpawnPluginTab(const FSpawnTabArgs& SpawnTabArgs)
{
	return SNew(SDockTab)
		.TabRole(ETabRole::NomadTab)
		[
			SNew(SBox)
			.HAlign(HAlign_Center)
			.VAlign(VAlign_Center)
			[
				SNew(STextBlock)
				.Text(LOCTEXT("Live2DTabText", "Hello Live2D Tab"))
			]
		];
}
```

最后在按钮或菜单命令回调里调用 `TryInvokeTab`：如果 tab 已存在则前置，不存在则触发上面的 spawner 创建。

```c++
void FLive2DModule::PluginButtonClicked()
{
	FGlobalTabmanager::Get()->TryInvokeTab(Live2DTabName);
}
```

### 2.2 对象总览

这一节先把 Docking Tab 相关对象按“渲染层级 + 管理层级 + 持久化层级”串起来，后面讨论拖拽和持久化时就不会混。

#### 2.2.1 渲染对象（从上到下）

Tab 画面涉及的核心对象依次是：

1. `SDockingArea`
2. `SDockingSplitter`
3. `SDockingTabStack`
4. `SDockingTabWell`
5. `SDockTab`

其中前三个都是 `SDockingNode` 体系里的节点（`SDockingArea : SDockingSplitter : SDockingNode`，以及 `SDockingTabStack : SDockingNode`）。

可以先用一个简化层级图理解位置关系（使用 widget reflector 可以更加可视化地看到这些 swidget 渲染出的布局）：

```text
SWindow
  └─ SDockingArea (root node)
	  ├─ SDockingSplitter (0..N，可递归)
	  │   └─ SDockingTabStack
	  │ 	  ├─ SDockingTabWell (tab 头部行)
	  │ 	  │   └─ SDockTab (多个)
	  │ 	  └─ ContentSlot (显示当前前景 tab 的内容)
	  └─ SWindowTitleBar
```

#### 2.2.2 每个对象的职责与在画面中的位置

`SDockingArea`

1. 是一个 Dock 区域的根节点，通常直接放在 `SWindow` 的内容区里。
2. 负责区域级行为：外层 dock target、sidebar、窗口 chrome 预留、区域清理。
3. 关键管理字段：`MyTabManager`（指向管理它的 `FTabManager`）、`ParentWindowPtr`（所在窗口）。

`SDockingSplitter`

1. 负责把区域分割成多个子节点（水平/垂直）。
2. 子节点可以继续是 splitter，也可以是 tab stack。
3. 本质是布局容器，决定“左右分栏 / 上下分栏”（`SetOrientation` 决定分栏方向，`SizeCoefficient` 调整节点面积占比）。

`SDockingTabStack`

1. 一个“tab 组”：上方是 tab 头，下方是当前前景 tab 的内容。
2. 负责 tab 的打开、关闭、前置、侧边栏迁移、内容切换。
3. 关键字段：`TabWell`（头部行）、`ContentSlot`（内容区）、`Tabs`（持久化状态镜像）。

`SDockingTabWell`

1. 负责 tab 头部行的视觉和交互：排序、前景切换、拖拽重排。
2. 持有一组 `SDockTab`（头部条目），并决定谁是 foreground。
3. 切换 foreground 时，会通知父 `SDockingTabStack` 更新内容区。

`SDockTab`

1. 表示单个 tab；既有“标签头信息”，也持有“该 tab 对应的内容 widget”。
2. 关键字段：`LayoutIdentifier`（类型为 `FTabId`，表示单个 tab）、`ParentPtr`（所属 `SDockingTabWell`）、`MyTabManager`（当前管理它的 tab manager）。
3. 只有被置为 foreground 的 tab 的内容才会显示出来。
4. `ETabRole` 主要用于 tab 的拖拽合并规则，见 2.4 节对 tab drag drop 的描述以及 `FDockingDragOperation::CanDockInNode` 函数。大致来说，除了 nomad tab，只有隶属于相同 tab manager（或者说属于同一个 layout 里）的 tab 可以合并到同一个 tab well 中

#### 2.2.4 Tab 管理：FTabManager 与 FGlobalTabmanager

`FTabManager`

1. 负责“某一组 dock 区域”的 tab 生命周期、布局恢复、布局保存。
2. 提供 tab 工厂注册与打开入口：`RegisterTabSpawner(...)`、`TryInvokeTab(...)`。
3. 管理对象与渲染对象的桥接字段：`DockAreas`、`OwnerTabPtr`、`NomadTabSpawner` 等。

`FGlobalTabmanager`

1. 是全局的单例管理器，继承自 `FTabManager`。
2. 额外提供全局 nomad 注册接口：`RegisterNomadTabSpawner(...)` / `UnregisterNomadTabSpawner(...)`。
3. 维护跨 manager 的全局状态（如 active tab、root window、sub tab managers）。

与前面的 `FTabId` 呼应：

1. 注册 spawner 时用 `TabId(TabType)` 绑定“如何创建”。
2. 调用 `TryInvokeTab(FTabId)` 时，manager 会按该 ID 查找已有 tab 或触发 spawner 创建。

#### 2.2.5 持久化对象与渲染对象的一一对应

`FTabManager` 内部有一套“纯数据布局树”，用于保存/恢复（使得可以提前指定编辑器的 layout，使得每个窗口打开在指定位置）：

1. `FLayout` 对应运行时 `FTabManager`，见 `FTabManager::SavePersistentLayout`
2. `FArea` 对应运行时 `SDockingArea`
3. `FSplitter` 对应运行时 `SDockingSplitter`
4. `FStack` 对应运行时 `SDockingTabStack`
5. `FTab` 对应运行时 `SDockTab`
6. 恢复布局时会从 `FArea/FSplitter/FStack` 递归构建 `SDockingArea/SDockingSplitter/SDockingTabStack`，再按 `FTabId` 触发 tab 生成。见 `FTabManager::RestoreArea`

#### 2.2.6 联系对象的关键字段

为了把“对象树”串起来，最关键的几个字段是：

1. `SDockingNode::ParentNodePtr`
含义：当前 docking node 的父节点（`SDockingSplitter`）。用于在 docking 树中向上回溯。

2. `FTabManager::DockAreas`
含义：当前 manager 管理的所有 live `SDockingArea`。

3. `FTabManager::CollapsedDockAreas`
含义：当前 manager 管理的所有关闭的 `SDockingArea`。

4. `SDockingArea::MyTabManager`
含义：反向指回管理该区域的 `FTabManager`。

5. `SDockTab::ParentPtr`
含义：当前 tab 所在的 `SDockingTabWell`。

6. `SDockTab::LayoutIdentifier`
含义：tab 的稳定标识（`FTabId`），用于查找、复用、布局持久化匹配。

### 2.3 Tab 的打开、关闭与持久化处理

#### 2.3.1 打开 Tab 的流程

这一节聚焦 `FTabManager::TryInvokeTab -> InvokeTab_Internal` 这一条主链路。

整体可以分成三段：

1. 先检查 spawner，并尝试复用已有 live tab。
2. 复用失败时，尝试找到该 tab 对应的 `SDockingTabStack`（collapsed / live）。
3. 如果找不到 `SDockingTabStack`，则新建 `SDockingArea + SDockingTabStack`（通常表现为新开一个 window）。

关键代码框架如下：

```c++
TSharedPtr<SDockTab> FTabManager::InvokeTab_Internal(const FTabId& TabId, bool bInvokeAsInactive, bool bForceOpenWindowIfNeeded)
{
	...
	TSharedPtr<FTabSpawnerEntry> Spawner = FindTabSpawnerFor(TabId.TabType);
	...
	TSharedPtr<SDockTab> ExistingTab = Spawner->OnFindTabToReuse.IsBound()
		? Spawner->OnFindTabToReuse.Execute(TabId)
		: Spawner->SpawnedTabPtr.Pin();

	if (ExistingTab.IsValid())
	{
		...
		return ExistingTab.ToSharedRef();
	}

	TSharedPtr<SDockingTabStack> StackToSpawnIn = bForceOpenWindowIfNeeded
		? AttemptToOpenTab(TabId, true)
		: FindPotentiallyClosedTab(TabId);

	if (StackToSpawnIn.IsValid())
	{
		const TSharedPtr<SDockTab> NewTab = SpawnTab(TabId, TSharedPtr<SWindow>());
		if (NewTab.IsValid())
		{
			StackToSpawnIn->OpenTab(NewTab.ToSharedRef(), INDEX_NONE, bInvokeAsInactive);
			...
		}
		return NewTab;
	}
	else if (FGlobalTabmanager::Get() != SharedThis(this) && NomadTabSpawner->Contains(TabId.TabType))
	{
		return FGlobalTabmanager::Get()->InvokeTab_Internal(TabId, bInvokeAsInactive, bForceOpenWindowIfNeeded);
	}
	else
	{
		const TSharedRef<FArea> NewAreaForTab = GetAreaForTabId(TabId);
		NewAreaForTab->Split(FTabManager::NewStack()->AddTab(TabId, ETabState::OpenedTab));

		TSharedPtr<SDockingArea> DockingArea = RestoreArea(NewAreaForTab, GetPrivateApi().GetParentWindow());
		...
	}
}
```

##### 1) 检查 spawner 与复用已有 tab

先通过 `FindTabSpawnerFor(TabId.TabType)` 找到 spawner，然后优先复用：

1. 如果绑定了 `OnFindTabToReuse`，优先由调用方决定复用哪个 tab。
2. 否则使用 `Spawner->SpawnedTabPtr.Pin()`（weak ptr 指向上次生成的实例）。
3. 如果 `ExistingTab.IsValid()`，直接 `DrawAttention` / 前置后返回，不创建新 tab。

这一步命中时，不会进入后续 `StackToSpawnIn` 查找。

##### 2) 如何定位 `SDockingTabStack`

当 tab is not live 时，会调用 `AttemptToOpenTab`。该函数本质上在“持久化布局 + live 布局”中找目标 stack：

1. 先查 `CollapsedDockAreas`。
   - 通过 `FindTabInCollapsedAreas(TabMatcher)` 找到包含目标 tab 的 collapsed area。
   - 调用 `RestoreArea(...)` 把这块 collapsed area 恢复为 live widget 树。
   - 从 `CollapsedDockAreas` 中移除该 area。
   - 在恢复出的 area 上调用 `FindTabInLiveArea(...)`，拿到目标 `SDockingTabStack`。
2. 如果 collapsed 没命中，再查 live area。
   - `FindTabInLiveAreas(TabMatcher)` 会遍历所有 live `SDockingArea`，
   - 再遍历其中所有 stack，调用 `HasTab(TabMatcher)` 匹配。

定位成功后，直接调用：

```c++
StackToSpawnIn->OpenTab(NewTab.ToSharedRef(), INDEX_NONE, bInvokeAsInactive);
```

也就是“在原有 stack 位置打开该 tab”。

##### 3) 找不到 stack 时：新建 `SDockingArea + SDockingTabStack`

	如果 `StackToSpawnIn` 为空：

1. 若当前不是全局 manager 且该 tab 是 nomad，转发给 `FGlobalTabmanager` 再尝试一次。
2. 否则走新建路径：
   - `GetAreaForTabId(TabId)` 生成一个 area（可能复用初始布局中的浮窗位置信息）。
   - `NewAreaForTab->Split(NewStack()->AddTab(TabId, OpenedTab))` 创建初始 stack。
   - `RestoreArea(NewAreaForTab, ParentWindow)` 生成运行时 `SDockingArea/SDockingTabStack`。

这一支通常表现为“打开了一个新的 window（或新的 dock 区）”。

##### 4) 打开 tab 后，哪些数据结构发生变化

下面按“管理层 + 持久化层 + 可视层”总结。

1. `FTabSpawnerEntry`
   - 新建成功时，`Spawner->SpawnedTabPtr = NewTabWidget`。

2. `SDockTab`
   - `SetLayoutIdentifier(TabId)`：写入稳定标识 `LayoutIdentifier`。
   - `SetTabManager(...)`：`MyTabManager` 指向当前 manager（nomad tab 进入某个 stack 时会继承该 stack 所属 manager）。

3. `FTabManager`
   - 若从 collapsed 恢复：`CollapsedDockAreas.Remove(...)`。
   - 若新建 area：`OnDockAreaCreated -> DockAreas.Add(NewlyCreatedDockArea)`。

4. `SDockingTabStack::Tabs`（持久化镜像）
   - `OpenPersistentTab` 会把已有 `ClosedTab/SidebarTab` 改回打开态，或插入新的 `FTab`。

5. `SDockingTabWell`
   - `Tabs.Add/Insert(InTab)`：tab 头进入 tab well。
   - `ForegroundTabIndex` 更新到前景 tab。
   - `RefreshParentContent()` 触发内容区切换。

6. 全局激活态 + 内容区
   - `FGlobalTabmanager::SetActiveTab(ForegroundTab)` 更新 `ActiveTabPtr`。
   - `SDockingTabStack::SetNodeContent(ForegroundTab->GetContent(), ...)`，即 `ContentSlot` 切到当前前景 tab 的内容。

这一点非常关键：`SDockTab` 本身既是“tab 条目”，也持有内容 widget；真正显示在内容区的是“当前 foreground tab 的 content”。

#### 2.3.2 关闭 Tab 的流程

##### 1) 入口：`SDockTab::RequestCloseTab`

典型入口是点击 tab 的关闭按钮，最终调用：

```c++
bool SDockTab::RequestCloseTab()
{
	this->PersistVisualState();

	const bool bCanCloseTabNow = CanCloseTab();

	if (bCanCloseTabNow)
	{
		if (GetParentDockTabStack() &&
			GetParentDockTabStack()->GetDockArea() &&
			GetParentDockTabStack()->GetDockArea()->IsTabInSidebar(SharedThis(this)))
		{
			OnTabClosed.ExecuteIfBound(SharedThis(this));
			GetParentDockTabStack()->GetDockArea()->RemoveTabFromSidebar(SharedThis(this));
		}
		else
		{
			RemoveTabFromParent();
		}
	}

	return bCanCloseTabNow;
}
```

这里做了三件事：

1. 持久化视觉状态（`PersistVisualState`）。
2. 调用 `CanCloseTab`，综合判断是否允许关闭（例如主 tab 不可关、业务侧 `OnCanCloseTab` 返回 false）。
3. 根据 tab 当前是否在 sidebar 走不同分支。

##### 2) 普通 tab（不在 sidebar）关闭路径

调用链可简化为：

1. `SDockTab::RequestCloseTab`
2. `SDockTab::RemoveTabFromParent`
3. `SDockingTabWell::RemoveAndDestroyTab`
4. `SDockingTabStack::OnTabClosed`
5. `SDockingArea::CleanUp`
6. （可选）`FTabManager::FPrivateApi::OnDockAreaClosing`

关键代码（TabWell 移除 live tab）：

```c++
void SDockingTabWell::RemoveAndDestroyTab(const TSharedRef<SDockTab>& TabToRemove, SDockingNode::ELayoutModification RemovalMethod)
{
	int32 TabIndex = Tabs.Find(TabToRemove);
	...
	BringTabToFront(TabIndex);
	Tabs.RemoveAt(TabIndex);
	ForegroundTabIndex = INDEX_NONE;
	...
	ParentTabStack->OnTabClosed(TabToRemove, RemovalMethod);
	...
	DockAreaPtr->CleanUp(RemovalMethod);
}
```

这一步会同时影响“运行时可视结构”和“持久化结构”：

1. 可视层：`SDockingTabWell::Tabs` 删除一个 `SDockTab`，并重算 `ForegroundTabIndex`。
2. 持久化层：`SDockingTabStack::OnTabClosed` 更新 `SDockingTabStack::Tabs`（`FTabManager::FTab` 列表）。

`OnTabClosed` 的核心规则：

```c++
void SDockingTabStack::OnTabClosed(const TSharedRef<SDockTab>& ClosedTab, SDockingNode::ELayoutModification RemovalMethod)
{
	const FTabId& TabIdBeingClosed = ClosedTab->GetLayoutIdentifier();
	const bool bIsTabPersistable = TabIdBeingClosed.IsTabPersistable();

	if (bIsTabPersistable)
	{
		if (RemovalMethod != SDockingNode::ELayoutModification::TabRemoval_Sidebar)
		{
			ClosePersistentTab(TabIdBeingClosed); // TabState -> ClosedTab
		}
	}
	else
	{
		RemovePersistentTab(TabIdBeingClosed); // 直接从 Tabs 数组移除
	}
}
```

这意味着：

1. 可持久化 tab 通常只是把状态改为 `ClosedTab`，而不是物理删除记录。
2. 不可持久化 tab 会从持久化数组中直接删掉。

##### 3) sidebar tab 关闭路径

sidebar 关闭菜单走 `STabSidebar::OnCloseTab`，会先 `RequestCloseTab`，随后显式：

1. `RemoveTab(TabToClose)`：从 sidebar 容器里移除。
2. `TabToClose->GetParentDockTabStack()->OnTabClosed(..., TabRemoval_Closed)`：把持久化层也更新为“关闭”。

所以 sidebar 场景里，除了 tab well / stack 的变化，还会影响 `SDockingArea` 里的左右 sidebar 容器（`LeftSidebar / RightSidebar`）。

##### 4) area 清理与 window 行为

每次 tab 从 tab well 移除后都会调用 `SDockingArea::CleanUp(RemovalMethod)`。该步骤会：

1. 递归清理 docking 树（`SDockingSplitter::CleanUpNodes`）。
2. 移除无 tab 的冗余节点、必要时折叠只有历史 tab 的节点。
3. 如果 area 受管窗口为空，可能触发窗口关闭。

关键分支：

```c++
void SDockingArea::CleanUp(ELayoutModification RemovalMethod)
{
	const ECleanupRetVal CleanupResult = CleanUpNodes();
	...
	if (bManageParentWindow && ParentWindow.IsValid())
	{
		if (RemovalMethod == TabRemoval_Closed)
		{
			MyTabManager.Pin()->GetPrivateApi().OnDockAreaClosing(SharedThis(this));
			ParentWindow->RequestDestroyWindow();
		}
	}
}
```

`OnDockAreaClosing` 会把该 area 的持久化布局塞入 `FTabManager::CollapsedDockAreas`，用于后续恢复。

##### 5) TabManager / GlobalTabmanager 在关闭流程中的角色

1. `FTabManager::FPrivateApi::OnTabClosing -> FTabManager::OnTabClosing`：当前实现是空函数，默认不改状态。
2. `FGlobalTabmanager::OnTabClosing`：如果关闭的是一个 MajorTab（并且它绑定了 sub tab manager），会触发该子 manager 的 `OnTabManagerClosing`，做整组 manager 的收尾与布局保存。

##### 6) 关闭 tab 时数据结构变化总表

1. `SDockingTabWell::Tabs`：删除被关闭 tab（live widget 集合）。
2. `SDockingTabWell::ForegroundTabIndex`：置空并重算前景。
3. `FGlobalTabmanager::ActiveTabPtr`：可能切换到新前景 tab，或在无前景时清空。
4. `SDockingTabStack::Tabs`（`TArray<FTabManager::FTab>`）：
   - 可持久化 tab：`TabState` 从 `OpenedTab/SidebarTab` 变为 `ClosedTab`。
   - 不可持久化 tab：条目被移除。
5. `SDockingSplitter::Children` / `SDockingArea` 节点树：清理后可能删除空节点、合并冗余 splitter。
6. `FTabManager::CollapsedDockAreas`：当某个 managed dock area 因关闭而收起时，新增该 area 的持久化布局快照。

从这个角度看，“关闭 tab”不只是删一个 widget，而是同时修改：

1. tab well 的 live 视图状态；
2. stack 的持久化 tab 状态；
3. docking 树的结构；
4. manager 的 collapsed area 缓存。

### 2.4 drag and drop

这一段讨论 dock tab 的拖拽流程。它的核心不是单个 widget 的鼠标事件，而是 `SDockTab`、`SDockingTabWell`、`SDockingTabStack`、`SDockingArea` 和 `FDockingDragOperation` 这几层一起协作完成的。

#### 2.4.1 drag 开始时的处理

拖拽起点在 `SDockTab::OnMouseButtonDown` / `SDockTab::OnDragDetected`。

1. `SDockTab` 先把自己激活，然后触发拖拽检测。
2. `OnDragDetected` 会计算鼠标抓取点在 tab 内部的相对位置，得到 `TabGrabOffsetFraction`。
3. 然后真正由 `SDockingTabWell::StartDraggingTab` 接管：
	- 记录当前拖拽的 tab 到 `TabBeingDraggedPtr`
	- 记录抓取偏移 `TabGrabOffsetFraction`
	- 记录拖拽时的布局偏移 `ChildBeingDraggedOffset`
	- 从 `SDockingTabWell::Tabs` 中临时移除这个 tab
	- 如果允许 tab 离开当前 tab well，则把 `ForegroundTabIndex` 置为 `INDEX_NONE`
	- 同时通知父 `SDockingTabStack`，把持久化数据里的该 tab 也改掉：`OnTabRemoved` -> `RemovePersistentTab`

也就是说，拖拽刚开始时会同时影响两套结构：

1. 运行时可视结构：`SDockingTabWell::Tabs`
2. 持久化布局结构：`SDockingTabStack::Tabs`

如果这个 tab 允许“离开 tab well”进行真正的 docking drag，`StartDraggingTab` 会创建 `FDockingDragOperation` 并调用 `BeginDragDrop`；如果不允许离开，则只会 capture mouse，后续只是 tab well 内部重排。

#### 2.4.2 drag 中途的处理

拖拽过程中，Slate 会按 widget path 进行冒泡式路由，越内层的 widget 越先收到 `OnDragOver`。

这意味着同一次拖拽里，通常会先命中 `SDockingTabWell`，再到 `SDockingTabStack`，最后才是 `SDockingArea`，前提是前面的 widget 没有把事件消费掉。

##### 1) 经过 `SDockingTabWell`

`SDockingTabWell` 负责 tab 之间的“重排”和“临时预览”。

1. `OnDragEnter`
	- 如果拖拽对象能停靠进当前 tab well，就调用 `FDockingDragOperation::OnTabWellEntered`
	- 把 `TabBeingDraggedPtr` 临时指向正在拖的 tab
	- 把这个 tab 临时加入 `Tabs`，用于布局预览
	- 更新 `TabGrabOffsetFraction`
	- 用拖拽 tab 的内容刷新父 `SDockingTabStack` 的内容区，让用户看到当前 tab 的内容预览

2. `OnDragOver`
	- 只更新拖拽中的 tab 在 tab well 里的横向位置
	- 通过 `ComputeDraggedTabOffset` 计算 `ChildBeingDraggedOffset`
	- 这一步不改变最终布局，只是让 tab 的“插入位置”实时跟着鼠标动

3. `OnDragLeave`
	- 如果 tab 离开当前 tab well，会把临时加入的 tab 移除
	- 清空 `TabBeingDraggedPtr`
	- 如果当前 tab well 为空，会通知 `SDockingTabStack::OnLastTabRemoved`
	- 否则会把前景 tab 切回之前的 tab
	- 再调用 `FDockingDragOperation::OnTabWellLeft`，让拖拽预览回到浮动窗口状态

`SDockingTabWell` 这一层的本质是：

1. 负责 tab 组内排序
2. 负责当前 tab 内容预览
3. 负责把“拖进来 / 拖出去”变成可见的局部状态变化

##### 2) 经过 `SDockingTabStack`

`SDockingTabStack` 主要处理“能不能在这个 stack 上停靠”和“是否显示 split 十字”。

1. `OnDragOver`
	- 先判断 `FDockingDragOperation::CanDockInNode(..., DockingViaTarget)`
	- 再检查鼠标是否位于 `ContentAreaOverlay` 范围内
	- 如果在，就调用 `ShowCross()`；否则 `HideCross()`

2. `ShowCross()`
	- 通过 `OverlayManagement.ContentAreaOverlay->AddSlot()` 动态插入一个 `SDockingCross`
	- 这不是永久对象，而是拖拽时才出现的临时 overlay
	- 同时会把 `OverlayManagement.bShowingCross` 置为 true

3. `HideCross()`
	- 从 overlay 中移除这个临时 slot
	- 把 `bShowingCross` 置回 false

所以 `SDockingTabStack` 这一层不直接完成 dock，它只是把“可分裂的投放区域”显式画出来。

##### 3) `SDockingCross` 的作用

`SDockingCross` 是 `SDockingTabStack` 里的临时投放面板，负责把鼠标位置映射成方向：`Above`、`Below`、`LeftOf`、`RightOf`。

1. `OnDragOver`
	- 根据鼠标在 cross 内的位置，计算出一个 `FDockTarget`
	- 再调用 `FDockingDragOperation::SetHoveredTarget`
	- 这样拖拽预览窗口会变形到对应方向，告诉用户 drop 后会发生 split

2. `OnDrop`
	- 把 `FDockTarget` 交给目标节点的 `OnUserAttemptingDock`
	- 对 `SDockingTabStack` 来说，这通常会走 `CreateNewTabStackBySplitting(Direction)->OpenTab(...)`
	- 对 `SDockingArea` 来说，会走 `DockFromOutside(...)` 或创建新 stack

##### 4) `SDockingArea` 的作用

`SDockingArea` 也有自己的 `OnDragOver`，它更多是区域级别的兜底目标（当下级的 `SDockingTabStack` 等没有响应 `OnDragOver` 时）。

当拖拽命中 `SDockingArea` 时，它会显示自己的 cross overlay，并在 drop 时决定是否：

1. 在中心区域把 tab 放进一个新的 `SDockingTabStack`
2. 在边缘区域把 layout 分裂开，重新组织 splitter

#### 2.4.3 drag 结束时的处理

拖拽结束要分三种主路径看：

##### 1) 结束时位于 tab well

这代表 drop 进了现有 tab 组，属于“合并 / 重排”路径。

1. `SDockingTabWell::OnDrop`
	- 计算最终插入位置 `DropLocationIndex`
	- 把临时拖拽中的 tab 从 `Tabs` 中移除
	- 调用 `ParentTabStackPtr.Pin()->OpenTab(TabBeingDragged, DropLocationIndex)`

2. `SDockingTabStack::OpenTab`
	- 调用 `OpenPersistentTab` 更新持久化布局里的 `FTabManager::FTab`
	- 再调用 `AddTabWidget` 把 tab 放回运行时 tab well
	- 最后刷新 parent content

这个路径的结果是：tab 被重新插回某个现有 stack，属于“同一层级内合并”。

##### 2) 结束时位于 split 区域

这代表 drop 到了 `SDockingCross` 或 `SDockingTarget` 指定的方向区域，属于“分裂布局”路径。

1. `SDockingCross::OnDrop` 先算出方向
2. 然后交给目标节点的 `OnUserAttemptingDock`
3. `SDockingTabStack::OnUserAttemptingDock`
	- 通过 `CreateNewTabStackBySplitting(Direction)` 新建一个 stack
	- 再把拖拽中的 tab `OpenTab` 到这个新 stack
4. `SDockingArea::OnUserAttemptingDock`
	- 如果是 `Center`，会新建一个 `SDockingTabStack` 再 `OpenTab`
	- 如果是边缘方向，会走 `DockFromOutside`，必要时重排 splitter 方向，再插入新 stack

这个路径的结果是：不是把 tab 放回原来的组，而是把布局树切开，生成新的分支。

##### 3) 结束时没有命中任何有效 drop 目标，或是单独浮动成窗口

如果没有任何 widget 处理 drop，`FDockingDragOperation::OnDrop(false, ...)` 会走 `DroppedOntoNothing()`。

这时会：

1. 新建一个 `SWindow`
2. 新建一个 `SDockingArea`
3. 新建一个 `SDockingTabStack`
4. 把拖拽中的 tab 放进新 stack

这就是 tab 被拖成单独窗口的路径。

对于不同 tab role，后续窗口归属也不同：

1. `MajorTab` / `NomadTab` 可能会进入顶层窗口或 root window 体系
2. 其他 tab 往往作为子窗口管理

#### 2.4.4 这一流程里最关键的数据变化

1. `SDockingTabWell::Tabs`
	- 开始拖拽时：临时移除
	- 进入别的 tab well 时：临时加入做预览
	- 结束时：要么重排并正式插回，要么被新 stack 接管

2. `SDockingTabStack::Tabs`
	- 开始真正可离栈拖拽时：对应的持久化 tab 会被移除或转成关闭态相关状态
	- drop 成功后：`OpenPersistentTab` 会把它重新标成 `OpenedTab`，或在新位置插入

3. `FDockingDragOperation`
	- 持有当前拖拽的 tab
	- 跟踪 hover 目标、预览窗口、抓取偏移
	- 在 tab well / cross / area 之间切换时不断更新状态

4. `SDockingArea` / `SDockingSplitter`
	- split 路径会改布局树结构
	- 有时还会重排 splitter 方向，保证新节点能插入正确位置

总结一下：

1. tab well 负责“组内移动与合并”
2. tab stack 负责“显示 split 目标与触发分裂”
3. docking area 负责“更高层级的区域分裂和窗口级处理”
4. drag operation 负责“拖拽态的临时状态与预览窗口”

## 3 Tab Manager，Major Tab，Primary Area

本节我们通过引擎的编辑器界面的初始化流程对多 tab manager 的管理，major tab，primary area 进行梳理。

每个 tab manager 会有一个与之关联的 `SWindow`，除了是我们知道，`TabManger 的定位是处理一个布局下的所有 area 管理。

首先是在 MainFrame 模块中创建 root window

```c++
		TSharedRef<SWindow> RootWindow = SNew(SWindow)
			.AutoCenter(WindowConfig.CenterRules)
			.Title( WindowConfig.WindowTitle )
			//...
			
		FSlateApplication::Get().AddWindow( RootWindow, bShowRootWindowImmediately );

		FGlobalTabmanager::Get()->SetRootWindow(RootWindow);
		FGlobalTabmanager::Get()->SetAllowWindowMenuBar(true);
```

每个 tab manager 会有一个与之关联的 `SWindow`，表示它关联的布局是位于哪个窗口下。通过 `FTabManager::FPrivateApi::GetParentWindow` 接口可以获取该 `SWindow`，这里的root window 就是 global tab manager 关联的 `SWindow`。然后 MainFrame 模块会构造编辑器的默认布局。这些恢复的 area 都存储在 global tab manager 的 `DockAreas` 或 `CollapsedDockAreas` 中

```cpp
const FName LayoutName = TEXT("UnrealEd_Layout_v1.5");
const TSharedRef<FTabManager::FLayout> DefaultLayout =
	FTabManager::NewLayout(LayoutName)
	->AddArea(
		FTabManager::NewPrimaryArea()
		->Split(
			FTabManager::NewStack()
			->SetSizeCoefficient(2.0f)
			->AddTab("LevelEditor", ETabState::OpenedTab)
			->AddTab("DockedToolkit", ETabState::ClosedTab)
		)
	)
	->AddArea(
		FTabManager::NewArea(WindowSize)
		->Split(
			FTabManager::NewStack()
			->AddTab("StandaloneToolkit", ETabState::ClosedTab)
		)
	)
	->AddArea
	(
		// settings window
		FTabManager::NewArea(WindowSize)
		->Split
		(
			FTabManager::NewStack()
			->AddTab("EditorSettings", ETabState::ClosedTab)
			->AddTab("ProjectSettings", ETabState::ClosedTab)
			->AddTab("PluginsEditor", ETabState::ClosedTab)
		)
	);

const TSharedRef<FTabManager::FLayout> LoadedLayout =
	FLayoutSaveRestore::LoadFromConfig(GEditorLayoutIni, DefaultLayout, OutputCanBeNullptr, RemovedOlderLayoutVersions);

MainFrameContent =
	FGlobalTabmanager::Get()->RestoreFrom(LoadedLayout, RootWindow, WindowConfig.bEmbedTitleAreaContent, OutputCanBeNullptr);
```

一个 layout 下可以包含多个 area，但是只能有一个 primary area。primary area 与 area 的区别有两点：

* `WindowPlacement` 设置为 `Placement_NoWindow`，在 tab manager restore 该 area 时不会创建和挂载 area 到新的 `SWindow`，而是将该 area 的 parent window 设置为该 tab manager 关联的 window（见 `FTabManager::RestoreArea_Helper`），要求用户自行将 `SDockingArea` 挂在 parent window 中的某个 swidget 下
* 无论 primary area 是否存在 opened tab，restore 该 area 时总是会将该 area 打开（置于 `DockAreas` 中而不是 `CollapsedDockAreas` 中）

换言之，这个 primary area 就是该 layout 对应的显示主区域，而打开其它的 area 时，则以新窗口的形式呈现。

注意到在 level editor tab 位于 primary area 并默认是打开状态，因此在 restore main frame area 的过程中会使用 global tab manager 打开 level editor tab，触发 `FLevelEditorModule::SpawnLevelEditor`，该函数会创建新的 dock tab，其内容设置为 `SLevelEditor`

```cpp
TSharedRef<SDockTab> LevelEditorTab = SNew(SDockTab)
	.TabRole(ETabRole::MajorTab)
	.ContentPadding(FMargin(0));

LevelEditorTab->SetContent(SAssignNew(LevelEditorTmp, SLevelEditor));
LevelEditorTmp->Initialize(LevelEditorTab, OwnerWindow.ToSharedRef());
```

`SLevelEditor::Initialize` 会调用 `RestoreContentArea`：

```cpp
void SLevelEditor::Initialize(const TSharedRef<SDockTab>& OwnerTab, const TSharedRef<SWindow>& OwnerWindow)
{
	// ...
	TSharedRef<SWidget> ContentArea = RestoreContentArea(OwnerTab, OwnerWindow);
	// ...
}
```
`RestoreContentArea` 内部会：

1. 绑定/创建 `LevelEditorTabManager`（新的 tab manager）
2. 加载并使用 `LevelEditorTabManager` 恢复 `LevelEditor_Layout_*`

```cpp
LevelEditorModule.SetLevelEditorTabManager(OwnerTab);

// FLevelEditorModule::SetLevelEditorTabManager
LevelEditorTabManager = FGlobalTabmanager::Get()->NewTabManager(OwnerTab.ToSharedRef());
LevelEditorTabManager->SetOnPersistLayout(
	FTabManager::FOnPersistLayout::CreateRaw(this, &FLevelEditorModule::HandleTabManagerPersistLayout)
);

// ... RegisterTabSpawner(LevelEditorTabIds::...)

const FName LayoutName = TEXT("LevelEditor_Layout_v1.8");
const TSharedRef<FTabManager::FLayout> DefaultLayout =
	FLayoutSaveRestore::LoadFromConfig(
		GEditorLayoutIni,
		FTabManager::NewLayout(LayoutName)
		->AddArea(
			FTabManager::NewPrimaryArea()
			// ...
			->Split(FTabManager::NewStack()->AddTab(LevelEditorTabIds::LevelEditorViewport, ETabState::OpenedTab))
			// ...
		)
	);

const TSharedRef<FTabManager::FLayout> Layout =
	FLayoutSaveRestore::LoadFromConfig(GEditorLayoutIni, DefaultLayout, OutputCanBeNullptr, RemovedOlderLayoutVersions);

TSharedPtr<SWidget> ContentAreaWidget =
	LevelEditorTabManager->RestoreFrom(Layout, OwnerWindow, bEmbedTitleAreaContent, OutputCanBeNullptr);
```

`LevelEditorTabManager` 设置 level editor tab 作为自己的 major tab，一起存储在 global tab manager 的 `SubTabManagers` 字段中（这个数组貌似只增不减）。对于普通的 tab manager 来说，它关联的 `SWindow` 就是 major tab 所在的 window。

```cpp
TSharedPtr<SWindow> FTabManager::FPrivateApi::GetParentWindow() const
{
	TSharedPtr<SDockTab> OwnerTab = TabManager.OwnerTabPtr.Pin();
	if ( OwnerTab.IsValid() )
	{
		// The tab was dragged out of some context that is owned by a MajorTab.
		// Whichever window possesses the MajorTab should be the parent of the newly created window.
		TSharedPtr<SWindow> ParentWindow = FSlateApplication::Get().FindWidgetWindow( OwnerTab.ToSharedRef() );
		return ParentWindow;
	}
	else
	{
		// This tab is not nested within a major tab, so it is a major tab itself.
		// Ask the global tab manager for its root window.
		return FGlobalTabmanager::Get()->GetRootWindow();
	}
}
```

注意这个 major tab 虽然与 `LevelEditorTabManager` 关联在一起，但它是从属于 global tab manager 的

恢复出的 primary area 后续被手动挂载在 `SLevelEditor` 下的一个 vertical box slot 中

```c++
	ChildSlot
	[
		SNew(SVerticalBox)
		+SVerticalBox::Slot()
		.Padding(FMargin(0.0f,0.0f,0.0f,2.0f))
		.AutoHeight()
		[
			FLevelEditorToolBar::MakeLevelEditorToolBar(LevelEditorCommands.ToSharedRef(), SharedThis(this))
		]
		+SVerticalBox::Slot()
		.Padding(FMargin(0.0f,0.0f,0.0f,2.0f))
		.AutoHeight()
		[
			SecondaryModeToolbarWidget.ToSharedRef()
		]
		+SVerticalBox::Slot()
		.Padding(4.0f, 2.f, 4.f, 2.f)
		.FillHeight( 1.0f )
		[
			ContentArea
		]
		+SVerticalBox::Slot()
		.Padding(0.0f, 2.0f, 0.0f, 0.0f)
		.AutoHeight()
		[
			GEditor->GetEditorSubsystem<UStatusBarSubsystem>()->MakeStatusBarWidget(GetStatusBarName(), OwnerTab)
		]
	];
```

用下方这张示意图会更好理解，整个 UE 的编辑器界面是 main frame 创建的 window，然后由 global tab manager 管理它的布局，level editor 是这个布局中的一个 docking stack 下打开的 tab，这个 tab 的内容是 `SLevelEditor`，然后红框部分是 level editor 下创建的 layout，由 level editor 创建的新的 tab manager 进行管理。可以看到，该 area 被进一步 split 为 4 个 `SDockingTabStack`（其中 viewport 的 tab 栏被隐藏了）

![UE editor layout overview](/assets/img/posts/ue/docking-tab/ue-editor-layout-overview.png)

新建 tab manager 的原因

* 关闭 major tab 时可以把所有该布局下的 tab 一起关了（见第 2 节中关于关闭 tab 逻辑的描述）
* 不希望混淆、合并不同编辑器的 tab（因为不同 tab manager 创建的 tab 不可合并，见第 2 节关于 tab drag drop 逻辑的描述）

## 3. Document Tab

TODO：完善这一节

双击 data asset 时，`FSimpleAssetEditor` 也会使用 global tab manager 创建新的 major tab 以及与之关联的 tab manager，不过这个新的 tab manager 是作为 document tab 插入到 global tab manager 中的

这其中的原因在于，data asset editor 会存在多个示例（而不像 level editor 全局唯一），没办法一个 editor 界面关联唯一的 tab id，所以使用 document tab 的 API

## 4. Window Title Bar

通常来讲，`SDockingArea` 寄宿的 window 下不会让 `SWindow` 自行创建 title bar，例如在 `FTabManager::RestoreArea_Helper` 中如果需要为 `SDockingArea` 创建一个新的 window，会将其 `bCreateTitleBar` 标记为 false

```cpp
	const bool bAutoPlacement = (NodeAsArea->WindowPlacement == FArea::Placement_Automatic);
	TSharedRef<SWindow> NewWindow = (bAutoPlacement)
		? SNew(SWindow)
			.AutoCenter( EAutoCenter::PreferredWorkArea )
			.ClientSize( NodeAsArea->UnscaledWindowSize )
			.CreateTitleBar( false )
			.IsInitiallyMaximized( NodeAsArea->bIsMaximized )
		: SNew(SWindow)
			.AutoCenter( EAutoCenter::None )
			.ScreenPosition( NodeAsArea->UnscaledWindowPosition )
			.ClientSize( NodeAsArea->UnscaledWindowSize )
			.CreateTitleBar( false )
			.IsInitiallyMaximized( NodeAsArea->bIsMaximized );
```

`SDockingArea` 在设置 parent window 时会自行创建一个内容为空的 `SWindowTitleBar`，它与 `SDockingSplitter` 同作为 overlay 的 slot 共享布局空间

```c++
void SDockingArea::SetParentWindow(const TSharedRef<SWindow>& NewParentWindow)
{
	// ... 省略 window destroy override 等逻辑

	TSharedPtr<IWindowTitleBar> TitleBar;

	FWindowTitleBarArgs Args(NewParentWindow);
	Args.CenterContent = SNullWidget::NullWidget;
	Args.CenterContentAlignment = HAlign_Fill;

	TSharedRef<SWidget> TitleBarWidget = FSlateApplication::Get().MakeWindowTitleBar(Args, TitleBar);
	(*WindowControlsArea)
	[
		TitleBarWidget
	];

	NewParentWindow->SetTitleBar(TitleBar);

	ParentWindowPtr = NewParentWindow;
	NewParentWindow->GetOnWindowActivatedEvent().AddSP(this, &SDockingArea::OnOwningWindowActivated);
}
```

最终由 tab manager 的 `MenuWidget` 字段来决定 `SWindowTitleBar` 的内容

```c++
class FTabManager : public TSharedFromThis<FTabManager>
{
		/** The current menu multi-box for the tab, used to construct platform native main menus */
		TSharedPtr<FMultiBox> MenuMultiBox;
		TSharedPtr<SWidget> MenuWidget;
};
```

当某个 tab 被激活时，`SDockingTabWell::BringTabToFront` 会调用 `FTabManager::UpdateMainMenu`，tab manager 会使用自己的 `MenuWidget` 更新 window title bar 的内容

```c++
void FTabManager::UpdateMainMenu(TSharedPtr<SDockTab> ForTab, const bool bForce)
{
	bool bIsMajorTab = true;

	TSharedPtr<SWindow> ParentWindowOfOwningTab;
	if (ForTab && (ForTab->GetTabRole() == ETabRole::MajorTab || ForTab->GetVisualTabRole() == ETabRole::MajorTab))
	{
		ParentWindowOfOwningTab = ForTab->GetParentWindow();
	}
	
	// ...
	
	if (bAllowPerWindowMenu)
	{
		if (ParentWindowOfOwningTab)
		{
			ParentWindowOfOwningTab->GetTitleBar()->UpdateWindowMenu(MenuWidget);
		}
	}
}
```

见 `SDockingArea::UpdateWindowChromeAndSidebar` 和 `SDockingTabStack::ReserveSpaceForWindowChrome` 如何为 title bar 预留空间，避免 docking stack 与 title bar 重叠

例如在 MainFrame 模块中为 global tab manager 设置好了 `MenuWidget`，通过定制化 tab manager 的 `MenuWidget`，就可以定制化对应窗口的 title bar

```c++
		FToolMenuContext EmptyContext;
		MakeMainMenu(FGlobalTabmanager::Get(), "MainFrame.NomadMainMenu", EmptyContext);
```

MainFrame 模块的 `FMainMenu::MakeMainMenu` 接口函数提供了生成和设置 menu widget 的接口

```c++
TSharedRef<SWidget> FMainMenu::MakeMainMenu(const TSharedPtr<FTabManager>& TabManager, const FName MenuName, FToolMenuContext& ToolMenuContext)
{
	// 第一次调用，MainFrame.MainMenu 尚未注册时触发
	UToolMenus::Get()->RegisterMenu(...);
	// Create the menu bar!
	TSharedRef<SWidget> MenuBarWidget = UToolMenus::Get()->GenerateWidget(MenuName, ToolMenuContext);
	// 设置 multibox 将 menu bar 挂在 window title bar 下面
	TSharedRef<SMultiBoxWidget> MultiBoxWidget = StaticCastSharedRef<SMultiBoxWidget>(MenuBarWidget);
	TabManager->SetMenuMultiBox(ConstCastSharedRef<FMultiBox>(MultiBoxWidget->GetMultiBox()), MultiBoxWidget);
	
}

void FTabManager::SetMenuMultiBox(const TSharedPtr<FMultiBox> NewMenuMutliBox, const TSharedPtr<SWidget> NewMenuWidget)
{
	// We only use the platform native global menu bar on Mac
	MenuMultiBox = NewMenuMutliBox;
	MenuWidget = NewMenuWidget;

	UpdateMainMenu(OwnerTabPtr.Pin(), false);
}
```

title bar 是否显示还与 major tab 有关，如果 tab manager 下管理的所有 tab 都不是 major tab，那么也不会显示 title bar，这也是单独拎出一个 nomad tab 不显示 title bar 的原因

```c++
void SDockingArea::UpdateWindowChromeAndSidebar()
{
	// ... 省略 node 遍历与 sidebar 逻辑

	bool bAccountForMenuBarPadding = false;
	if (MyTabManager.Pin()->AllowsWindowMenuBar())
	{
		TArray<TSharedRef<SDockTab>> AllTabs = GetAllChildTabs();
		for (auto& Tab : AllTabs)
		{
			if (Tab->GetParentWindow() == ParentWindow && Tab->GetTabRole() == ETabRole::MajorTab)
			{
				bAccountForMenuBarPadding = true;
				break;
			}
		}
	}

	if (ParentWindow->GetTitleBar())
	{
		ParentWindow->GetTitleBar()->SetAllowMenuBar(bAccountForMenuBarPadding);
	}
}
```

此外，level editor 下的 docking area 的 `UpdateWindowChromeAndSidebar` 函数不会对 title bar 产生影响，是因为它的 parent window 为空（见 `FTabManager::RestoreFrom` 的 `bEmbedTitleAreaContent` 参数的效果），因此嵌套的 docking area 不会争抢 title bar 的设置




TODO：
* `FStack` 和 `FArea` 的 `ExtensionId` 字段

## Reference

* [《调教UE5：编辑器拓展指南》Tab 探索](https://zhuanlan.zhihu.com/p/628655599)
* [UE5-Runtime下的Editor实现（一）-关于DockTab](https://zhuanlan.zhihu.com/p/653717900)
* [UE5-Runtime下的Editor实现（二）-多DockTab布局](https://zhuanlan.zhihu.com/p/654427478)
