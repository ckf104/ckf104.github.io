---
title: "CFG Analysis(1): Reducibility"
date: 2023-05-30 10:45:31 +800
categories: [Compiler]
---

这一个系列是记录流图分析相关的笔记。第一篇我们讨论 **Reducibility**

## 1. 定义

我们沿用 [Characterizations of Reducible Flow Graphs](https://dl.acm.org/doi/pdf/10.1145/321832.321835) 中对可规约流图的定义。

* 定义流图：有向图，且存在入口节点，该节点可达所有其他节点

* 定义图节点合并操作： 合并节点 $n_1, n_2 $ 为 $n_1$，将指向 $n_2$ 的边改为指向 $n_1$ ，删除重复边。

* 定义变换 $T_1$：如果流图中存在节点，该节点有边指向自己，则可使用 $T_1$ 消除该边
* 定义变换 $T_2$：如果流图中存在节点 $n_1，n_2$，使得 $n_2$ 的入边仅有边 $(n_1，n2)$，则将节点 $n_1，n_2$ 合并。

* 定义流图的可规约性：流图 $G$ 可规约，当且仅当可通过一系列的 $T_1，T_2$ 变换，使得 $G$ 仅有单个节点。

该定义不方便直接揭示可规约流图的性质，接下来将给出若干等价定义及其证明。

## 2. 流图可规约性的等价定义

![](/res/base-cfg.png "不可规约流图的基本结构")



## Refs

主要参考了以下的一些论文

* [Flow Graph Reducibility](https://www.cs.tufts.edu/~nr/cs257/archive/jeff-ullman/reducibility.pdf)
* [Characterizations of Reducible Flow Graphs](https://dl.acm.org/doi/pdf/10.1145/321832.321835)
* [Testing Flow Graph Reducibility](https://core.ac.uk/download/pdf/82032035.pdf)



