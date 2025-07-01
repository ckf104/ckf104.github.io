TODO：AI Perception Component 中的三个 update 回调有啥区别？

TODO：sense 中的 age 是什么意思

UAIPerceptionSystem

[UE4 关于AIPerception（二）](https://zhuanlan.zhihu.com/p/463525577) 中谈到 pawn 会直接被注册为 sense source，UAIPerceptionStimuliSourceComponent 帮助注册 sense source

[Should I use “Pawn Sensing or “Ai Perception” for Unreal Engine 5.1.1?](https://forums.unrealengine.com/t/should-i-use-pawn-sensing-or-ai-perception-for-unreal-engine-5-1-1/791984) 中谈到 `UPawnSensingComponent` 被 AI Perception 取代了

[Unreal Engine AI with Behavior Trees](https://www.youtube.com/watch?v=iY1jnFvHgbE) 中讨论了 EQS 如何让 AI 变得更智能一些
### Sense, Stimuli and Listener
stimuli 是 sense 观测的对象，AI Perception System 的 `RegisteredStimuliSources` 字段记录了哪些 actor 是 stimuli，并且这个 stimuli 能被哪些 sense 观测到

接收 sense 得到的 stimuli 更新数据的 AI Perception Component 又被称为 listener，场景中的 listener 都存放在 AI Perception System 的 `ListenerContainer` 中

具体负责观测 stimuli 并通知 listener 的对象被称为 sense，这些 sense 都继承自 `UAISense` 类。例如通过视觉观察 stimuli 的 `UAISense_Sight`，激活的 sense（至少存在一个 listener 对该 sense 感兴趣）都保存在 AI Perception System 的 `Senses` 中

在每一帧 tick 中，sense 根据的注册到自己这边的 listener 和 stimuli，依次判断每个 listener 能否观测到每个 stimuli。如果可以，发送新的 stimuli 信息给 listener，这些待 listener 处理的 stimuli 存放在 AI Perception Component 的 `StimulusToProcess` 字段中

在 listener 的每一帧 tick 中，对新来的 stimuli 进行处理。stimuli 包含了 actor 和具体的 stimuli 信息，listener 的 `PerceptualData` 中存储了 actor 与具体的 stimuli 信息的对应，然后根据新来的 stimuli 对 actor 对应的 stimuli 信息进行更新

当一个 actor 从可以被 listener 观测到变为不可被 listener 观测到，或者说 actor 从不可被观测到变为可观测到，那么会触发回调 `OnTargetPerceptionUpdated`，`OnTargetPerceptionInfoUpdated`，`OnPerceptionUpdated`。如果 `FAIStimulus` 的 `bSuccessfullySensed` 字段为 false，则说明 actor 从可观测到变为了不可观测，stimulus 包含的信息是最后一次观测到 actor 的信息
### Stimuli Age
在 sense config 中可以配置 listener 能保持对该类 sense 的记忆多久，如果全局设置 forget stale actors 为 true 并且超过 age 的时间 stimuli 没有被更新，那么 listener 会将 stimuli 信息从 `PerceptualData` 中删除，表现得好像从来没有 sense 到过该 actor 一样，并触发 `OnTargetPerceptionForgotten` 回调
### Team
可以通过 team 对 sense 这边需要检查的 listener - stimuli 对进行过滤。每个 listener 和 stimuli 对应的 actor 都实现 `IGenericTeamAgentInterface` 接口，实现自己的 attribute solver 并通过 `FGenericTeamId::SetAttitudeSolver` 进行注册。这样 sense 就会知道 listener 和 stimuli 的关系是 Friendly，Neutral，Hostile 中的哪一个。然后配置 sense config 中的 Detection by Affiliation 就能实现过滤了

因为通常 AI Perception Component 都是挂在 `AIController` 上，而 `AIController` 已经继承 `IGenericTeamAgentInterface` 了，所以 listener 这边的实现对 `AIController` 中的相应函数进行重载即可

默认情况下，所有的 listener 和 stimuli 的关系都是 `Neutral`