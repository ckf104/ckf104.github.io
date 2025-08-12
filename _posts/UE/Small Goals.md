### 骨骼动画与 character 移动
1. 如何慢播放动画，使得能够看清楚动画是如何与场景中其它物体交互的

弄清楚transformation：这个初步完成了，虽然物理相关的跳过了（collision，overlap之类的）

研究一下模板设置中的光照，体积云，天空球等设置
弄清楚 camera，player controller，player start 这些

我关心在点击游戏运行后，ue 具体干了些啥，更进一步，编辑器模式和游戏模式有啥区别

点击游戏运行后，在一系列调用栈后，game mode 调用这个 `SpawnDefaultPawnAtTransform` 函数，这个函数内调用 `UWorld::SpawnActor`，生成 `DefaultPawnClass` 这个 `UClass` 对应的类型的实例。这就是为什么编辑器的 level 中没有看到我们要操作的 actor。另外这个 actor 的初始 `FTransform` 由 `PlayerStart` 的 `FTransform` 提供

TODO：没看明白编辑器中 actor 的一堆可编辑的 property 是如何组织出来的，直观上看起来是递归地反射出该 actor 中所有的编辑器中可编辑的 uproperty，但这显然存在的一个问题是，如果 actor 中包含两个相同类型的成员，它们就存在相同的 uproperty，应该如何显示呢？我仔细考察了一下 CameraActor 的显示，它包含的 Camera Component 就很奇怪，一个是 PostProcessBlendWeight 明明 Category 是 Post Process，但编辑器的显示却在 Camera Options 目录下。另外，切换 Projection Mode 字段会影响编辑中 Camera Settings 目录的可编辑项的显示，但我没看出来这是如何办到的

如何设置重力和物理

level transition
relationship between ULevel and UWorld

crazy game 上那个碰碰球游戏的复刻，加入本地双人，远程双人，重放等功能
试试在 [Project Titan](https://www.unrealengine.com/en-US/news/the-project-titan-sample-game-is-now-available-explore-this-huge-open-world) 上加入战斗系统等？先用 control rig 做一个拳击动画试试吧
场景的雨水，闪电效果，天气的模拟
场景的淡入淡出，切换场景时的过场动画
3D UI 做一个那种升级系统
写一个 vscode 插件来阅读 uasset，统计重载 C++ 类和函数的蓝图，以 C++20 的形式自动生成一些创建新类的模板代码

在看动画系统代码时关注的点：
* pose 的数据组成
* blending 的实现？transition blending 和 clip blending 的 sync 方法有区别吗
* event graph 和 animation graph 之间如何同步数据？


自己的渲染器在实现 microfacet brdf 时要做 furnace test

一些可以考虑的美术资源
* Content Example
* Unreal Learning Kit
* FANTASTIC - Village Pack

旷野之息：摄像机控制，高处延长 spring arm，出现射击图标时 spring arm 偏移，使得人物偏离画面中心，人物的半透明效果
目前遇到的一些问题：
* 半透明的箭头效果进行移动，TAA 的表现会很糟糕，将 r.TemporalAASamples 设置为 64 也没啥明显的效果（会不会是因为纹理坐标偏移的移动导致的？但也说不通呀，因为静态的时候箭头也会移动），将 AA 切换为 MSAA 就好了。见 [TAA Limitations](https://forums.unrealengine.com/t/taa-limitations/1853715)
* 另一个是在 LearningKit_Games_Showcase 的地图上，箭头会与特效混在一起偏白，感觉像是半透明的排序没有做对，有时间 debug 找找原因（看起来像是后处理的问题？）
* 材质中的 Used with Spline Meshes 选项是什么意思，以及与 spline 相关的节点 spline based model deformation 如何使用
* 为什么在 blocking hit 时使用 teleport 的设置将物体往上移动，最后停止时反弹那么大（我想怎么用 chaos 的 debugger 看看这其中发生了什么事），虽然我发现使用 physical material 把反弹系数调小就好了

看看 unreal learning kit 中的角色 SK_EpicCharacter 和 SK_EpicCharacter_Optimized 

看看 content example 中的 ice shader：/Game/ExampleContent/Blueprint_Communication/Materials/M_Ice_Interactive

[GDC 2020技术导览-Ragdoll Motion Matching](https://zhuanlan.zhihu.com/p/129009008) 中谈到 GDC 2020 Machine Learning Summit: Ragdoll Motion Matching 这个挺有意思的，感觉和我关注的物理驱动角色挺有关联的

为什么 fbx scene import factory 与 fbx factory 不太一样，对于柜子的例子，fbx factory 开启 remove degenerate triangles 删除了很少的三角形，但是 fbx scene import factory 删除了快 1 / 3 的三角形

第一步：起步，停步，八项移动，原地转身，磁铁功能时，人物切换为八向移动，原地转身，扭身体，并且身体比脚更快动，移动时如何一边跑一边转身？

处理 spring arm 的遮挡，应该发射多根射线判断遮挡？或者更好的做法是设置 trace visibility，例如旷野之息中人物站在树后边，已经完全看不到了，但 spring arm 还是没有移动，估计是设置了 trace visibility。

然后 spring arm 该如何平滑移动也是一个问题

如何解决 bumpy stair 问题？看看 [Fixing Bumpy Stairs in UE5](https://www.youtube.com/watch?v=w-jz1fGJd6g)，我看旷野之息里就做得挺好的

起步和停步怎么做，walk 或者 run 的动画的第一帧通常和的 Idle 态的位姿有差异

实现：**锥形视角可视化，双人约束铰链，地板破碎塌陷**，对话系统，攀爬，勾绳索，布娃娃，战争迷雾

看的类型：rogue like，3D 平台，独立游戏？
### RPG Notes
**目前整个实现假设了被打断的 montage 不会再触发新的 notify，unreal 也确实是这么实现的（即使此时 montage 已经处于 blend out 状态了，也可以把它打断掉**
* **例如在攻击时被 hit 了然后切换到 hit montage，我们不希望原来的 attack montage 再触发一个 end combo 把我们拉到 idle 状态**
* **但是 unreal 里 montage 被打断了可能不会马上触发 montage end delegate，这造成了一些问题：我希望带 root motion 的冲刺在结束后会恢复原来的速度，但由于存在打断机制，例如跳跃打断了冲刺，如果此时 montage end delegate 在跳跃修改了速度之后才触发，会导致跳跃动作施加的速度被原来的速度覆盖掉了**
* **现在的做法是在播放任何 montage 之前都要调用 BreakMontage 来手动打断其它 montage，手动触发这些回调，为了避免回调被调用多次，还加了版本检测**
* **冲刺可以在任何时候被打断，因此又进行了额外处理：打断时如果 end combo 未被触发，手动切换状态**

TODO：拔剑混合的时候不好处理跳跃的情形
TODO：处理 enemy 的转身滑步
TODO：enemy 在攻击时也会 focus player，跟着 player 一起转，关了是不是好些
TODO：修正 move to 即使没有靠近 player 也返回 true 的问题，见 [AI MoveTo always reports Success?](https://forums.unrealengine.com/t/ai-moveto-always-reports-success/478210)
TODO：近战攻击的命中判定
* 在命中帧给一个判定框：如果攻击动画比较慢的话容易给人一种延时感（就是击中了之后才触发受击动画）
* 给武器一个 trigger box，在 overlap 时触发命中逻辑（无法获得详细的 overlap 几何信息）
* 每一帧做 trace：开销大，但是能获得详细的几何信息
TODO：人鱼怪眼睛残留的问题，需要改下它的材质？
TODO：蓝图中获取重力方向，保证 soul 是反重力移动的
TODO：空中冲刺时停止下落
TODO：人物坠落死亡重生
TODO：验证冲刺约束是否生效，找明白为什么空中冲刺会跑很远：之前空中没有 braking，然后 root motion 后速度不会恢复到之前的状态，而是 root motion 最后的速度。另外，在空中时 root motion 仍然会下落，这些都改了
TODO：连按两次跳跃时混合得不好看
TODO：看起来在 begin play 的时候没有触发 initial overlap（勾索实现）

TODO：root motion 与打断：root motion 进入打断期间后，root motion 仍然正常播放，一旦用户输入打断 root motion...
* 如果 root  motion stop 的时间早于打断期：没问题
* 如果 root motion stop 的时间晚于打断期：需要让用户输入提前打断
#### Combo
巫师三里的 combo 触发判定比较松，核心是在角色挥击完上一剑后会有一段暂留时间，玩家可以选择要不要继续连击，**因此下一击衔接的时间是可变的，而不是一个固定的连击动画**

TODO：什么时候结束动画，开始混合比较合适？如何调整混合的时间？是否能播放一个 montage 时播放另一个 montage（打断？）
#### 面试问题
UE 的遮挡剔除：PVS，hierarchical z buffer
UE 的 LOD 优化：hierachical LOD
SAH 划分
probe DDGI
draw primitives 太多会怎样，什么情况下才能合批
OpenGL 里 glflush 和 glfinish 干嘛的
