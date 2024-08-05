一种loop的定义（这种loop即一般的cycle）

* 回边：
* 可达:       

自然loop定义：

* 唯一的entry，这样的话loop自然形成层级结构（要么完全包含，要么不想交），不依赖于流图的reducibility。

两种Loop的定义不一样，这会产生什么影响？LoopSimplify的实现（如何判断两个loop是不是共用了header导致判定为只有一个loop）？

irreducible control 

reducible control：wiki定义为可将流图的边分为back edge, forward edge. 所有back edge的目标节点支配源节点  --> 所有的loop都是 forward loop

loop vs cycle

dominator tree vs loop

reversed post order traversal   --> 深度优先搜索，忽略回边（略过之前已经访问过的节点），所以最后得到的图的遍历等价于忽略回边的树的遍历

可规约流图 等价于 边分类方法唯一  等价于 不存在cycle（应该说，**定义cycle的层级的方法等于loop的自然层级结构，这件事是否等价于可规约流图**） 等价于  规约变换（tarjan）？

​       1                                        2                                             3

1 <-> 2是因为。   1 -> 3 ：  1-> 不存在强连通子图存在两个entry ---> reducibility  由此知道 1 <-> 3

~~当给定一个先序遍历 ，就已经把流图的边分为了两类，forward edge,   back edge ，reducible graph只是说 back edge 有dominate性质~~。 这是不对的，给定先序遍历，相当于给定一个子树，但是剩余的edge谁是forward，谁是back可能依赖与顺序

一般的流图边分类：边分为forward, back edge，要求forward edge组成的流图无环，且入口点可达所有节点。任意加入一条back edge，流图有环。

可规约流图的定义：存在一种边分类，back edge的目标dominate源，dominate是在全是forward的子图上定义的吗？还是在原图上定义的？或者两者等价？ ---> 两者等价。 可直接推出，可规约流图上的边分类是唯一的。

反过来的问题是，对于不可规约流图，边分类是否一定有多种？正确的。对于一种分类S1, S2，存在$(n1, n2) \in S2$，且$n2$不dominate $n1$，现在把这条边加入S1，可以证明对新形成的每一个环，都可以找到一条边安全删除。

规约变换的性质：规约变换的最终结果不依赖于变换的顺序，规约变换内新节点对应原图的一个region，~~反过来说，一个region是否一定能通过规约变换得到？~~



这是一条引用<sup><a href="#ref1">1</a></sup>

1. <p name = "ref1">https://lolitasian.blog.csdn.net/article/details/121656279</p>

调整文献引用上标，表改为三线表，英文字体改为TIMES new man, 逗号改为顿号。图重新画一下，大小一致，行距1.5倍。英文首次出现用中文。