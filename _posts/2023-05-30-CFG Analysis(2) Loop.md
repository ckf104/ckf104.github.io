* If v and w are vertices of G such that v <_ w, then any path from v to w must contain a common ancestor of v and w in T.

上面这个关于 DFST 的性质出现在论文 [A fast algorithm for finding dominators in a flowgraph](https://dl.acm.org/doi/pdf/10.1145/357062.357071) 中，对下面所阐述的结论的证明也很有帮助。

考虑两种可能的循环定义：

* 按 [Nesting of reducible and irreducible loops ](https://dl.acm.org/doi/pdf/10.1145/262004.262005)中所述的，每次去掉 header
* 根据回边进行定义，每一条回边得到 header，如果一个节点编号大于 header，不经过 header 到达 bottom ，且 header 可在不经过比它更小的节点的前提下可达该节点（**等价于header是该节点的祖先**），将该节点加入循环（如果 header 有多个回边，则一起考虑）

两种定义是否等价？

对于第一种定义中，每个 loop 的 header 都一定有至少一条回边，且每个回边一定对应一个 loop header（结论的导出是因为可以证明第一种 loop 中每个 header 都是其余节点的祖先节点），对于 loop 中每个非 header 节点，它一定编号大于 header，且由于强连通，因此 header 可以在不经过比它更小的节点到达该节点，同时该节点显然可以不经过 header 到达 bottom，因此第一种 loop 是第二种 loop 的子集。

对于第二种定义，同样可以说明该 loop 的 header 是其余节点的祖先节点。显然该 loop 中的节点强连通。对于 loop 中每个非 header 的节点，如果有某一些节点没有在第一种 loop 里，那么可以把该 loop 的节点分为 A，B 两类，前者在第一种 loop 中，后者不在第一种 loop 中，现在考虑从第一种定义的根出发，在第一次划分强连通子图的时候，由其极大性，A，B应该分在同一个第一类 loop 中，由于 A 中节点都属于最终的子 loop，因此它们不会变成中间路径上的某一个 header，而路径上header编号递增，因此B中节点也不会变成中间路径上某一个header，而由于A,B的强连通性，每一次划分loop时时A,B应当被分在同一个loop中，这说明B为空集。因此第二种loop和第一种loop相同。**两种定义是等价的**

**总结上面两种定义，我们可以得到一个非常直观的第三种定义：任取一个节点作为header，该header对应的loop是一个最大的强连通子图，该子图上header是编号最小的节点。**

有了基本的定义，接下来问题是，reducible loop 和 irreducible loop 的区分和判定。定义上，如果有多个入口节点，则称为 irreducible loop。**基本判定：loop reducible 等价于该 loop 中指向 header 的回边都是 reducible backedge**

**reducible backedge 不依赖于 DFST 的选取，但这并不代表 reducible loop 不依赖于 DFST 的选取**。因为在某些 DFST 中 irreducible backedge 可能指向 header，而在另一些 DFST 中，这些 irreducible backedge 消失了。因此 [Nesting of reducible and irreducible loops](https://dl.acm.org/doi/pdf/10.1145/262004.262005) 中最大化 reducible loop 的方法是通过 split node，来保证没有 reducible backedge 和 irreducible backedge 指向同一个 header

对于 reducible loop，传统的 loop 优化与分析可以适用。当流图可规约时，所有的 loop 都是可规约的，且 loop 的层级结构不依赖于 DFST 的选取。

**另外一种常见的对于 natural loop 的定义，仍然根据回边定义，要求回边是 reducible backedge，如果有多个回边的话对应多个 loop，这些 loop 可以共用 header**

natural loop 的定义不能够自然形成层级结构，两个共用 header 的 loop 可能重叠若干节点，例如 a -> b, b -> c, b->d, c->a, d->a, a是两loop共同的头部节点，而b是两loop的共同节点。a -> b, b->a, a->c, c->a，loop 1 是{a,b}，loop 2 是{a,b,c}，共用header a，但第二个loop完全包含住了第一个loop。不过 natural loop 的一个重要性质在于如果两个loop有公共节点重叠，则要么这两个loop共header，要么其中一个loop完全包含另一个loop（父子关系）

不过直观上来讲，上层代码中的loop显然是具有层级结构且互不相交的。因此我倾向于认为最上面的定义更合理。另外，在natural loop 定义中，在可规约流图的背景下，将共header的natural loop合并，就会得到最上面的定义产生的loop层级结构。

待解决的一些重要问题：a+b,c-a,b*d

* **最上面loop的层级结构导致一些loop结构没了，LLVM 如何解决的？**（即两个共用 header 的 loop 其实是两重循环，但该定义使得这个两重循环被视为一个loop了）
* natural loop 定义中一些 loop 共用节点，是否会对优化产生影响？例如循环展开？（或者更加根本的问题是如何对多退出的loop 进行循环展开？） --> 查看 LLVM 源码
* 在 irreducible loop 中，不同的 DFST 选取产生不同的 loop，这对优化有哪些影响？(比如看看 LLVM 的 LICM)



## Refs

* [Nesting of reducible and irreducible loops](https://dl.acm.org/doi/pdf/10.1145/262004.262005)
* https://llvm.org/docs/LoopTerminology.html