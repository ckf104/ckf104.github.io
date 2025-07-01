https://www.gamedeveloper.com/programming/behavior-trees-for-ai-how-they-work

[浅析UE4-BehaviorTree的特性](https://zhuanlan.zhihu.com/p/139514376) 中对打断行为的分析很到位

[UE5 行为树（1）：运行逻辑](https://zhuanlan.zhihu.com/p/667581758)：感觉它对 Notify Observer 的讨论有待商榷

TODO：[AI行为树系统 目录](https://zhuanlan.zhihu.com/p/368889019) 讲得很好，再看看

TODO：为什么只有上层是 selector 时 decorator 才能打断低优先级的节点？

TODO：为什么 service 的 on search start 被调用了两次，在一开始的时候

行为树的节点执行是可以跨多个 tick 的，首次执行是 `ExecuteTask`，后面是 `TickTask`。**abort 也是可以跨多个周期的，类似的，首次执行是 `AbortTask`，后面是 `TickTask`**

service 节点的几个回调
* `OnBecomeRelevant`，对应到蓝图里是 `ReceiveActivation`
* `OnCeaseRelevant`，对应到蓝图里是 `ReceiveDeactivation`
* `OnSearchStart`，对应到蓝图里是 `ReceiveSearchStart`
* `TickNode`，对应到蓝图里是 `ReceiveTick`

Relevant 这个概念比较好理解，就是当 service 被激活，开始执行的时候触发的回调。Search Start 是在 service 所在的节点的下层节点执行完一轮之后，又重新开始执行时触发（一开始执行的时候也会触发，search start 直译就是开始搜索了新的执行节点了嘛），可能 service 所在的节点的下层节点执行一轮又一轮，Search Start 会反复触发，而 service 节点由于始终是激活的，因此 Relevant 只触发了一次

decorator 节点的几个回调
* `CalculateRawConditionValue`，对应到蓝图里是 `PerformConditionCheck`，它会在一开始调用，判断 decorator 返回 true 或者 false 表示下面的节点能否执行
* `OnNodeActivation`：对应到蓝图是里是 `ReceiveExecutionStart`，如果 `CalculateRawConditionValue` 返回 true，下面的节点实际开始执行之前，会调用该函数
* `OnNodeDeactivation`：对应到蓝图里是 `ReceiveExecutionFinish`，下面的节点执行完毕后，会调用该函数
* TODO：`OnBecomeRelevant` 和 `OnCeaseRelevant` 什么时候调用的？

### 单例
[AI行为树系统 其一 行为树节点的单例设计](https://zhuanlan.zhihu.com/p/369100301) 讲得挺好的。额外需要注意的是，这个单例的意思是，多个对应同一行为树资产的行为树实例，它们共享行为树上的节点。假设行为树资产 U，它的实例 A，B。该行为树有三个节点 a，b，c。那么
* 实例 A 的节点 a 和实例 B 的节点 a 是同一个，除非该节点类的 `bCreateNodeInstance` 为 true（例如蓝图 task）
* 实例 A 的节点 a，b，c 不是相同的，即使它们是同一类的 task（例如都是 `MoveTo`）
* 假设有新的行为树资产 U2，则 U2 的实例不与 U 的实例共享节点，即使这些节点可能是同一类的 task
### 内存
TODO：解释 special memory 和 instance memory 的区别
### 组件
AI Controller 首次运行行为树时，会创建 `UBlackboardComponent` 和 `UBehaviorTreeComponent`

`UBehaviorTreeComponent` 里可能运行的不止一个行为树，因为可以通过 run behavior tree 这个 task 节点嵌套新的行为树进来运行，因此 `UBehaviorTreeComponent` 中维护了一个 `InstanceStack` 来表示当前活跃的行为树实例

