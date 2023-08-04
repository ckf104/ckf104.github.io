---
title: Understanding Fusesoc
date: 2023-08-04 21:54:39 +0800
categories: [IC]
---

最近在尝试将 Ara 跑在 FPGA 上，一个第三方的 [PR](https://github.com/pulp-platform/ara/pull/146) 使用 Fusesoc 工具来引导 Vivado 的综合和实现。因此大概翻了一下 Fusesoc 的文档。简要记录一下目前对 Fusesoc 的理解（文档的简化+自己的理解，不太确定的地方请翻阅文档）。

Fusesoc 主要在两个层面辅助 IC 设计：IP 管理，脚本自动化。

## 1. IP 管理

在 IP 管理上，Fusesoc 起到一个包管理工具的作用。这里设计到 Fusesoc 中两个重要的概念

* core library
* core file

core library 是一个目录，这个目录可以指定为本地目录，也可以是一个远程的 git 仓库。目录中（以及相应的次级目录）通常包含了若干 core file（后缀名为 .core 的文件）。每个 core file 是一个 yaml 文件，文件中描述了该 IP 的名字，组成该 IP 的各类文件以及该 IP 依赖于其它哪些 core。下一节会展开讨论 core file 中包含的内容。

在本地运行 Fusesoc 对某 IP 进行操作时，例如`fusesoc run --build --target synth-genesys2 ara` 指定对 ara IP 进行综合实现。Fusesoc 首先需要定位 IP 名称为 ara 的 core 文件，以及该 IP 依赖的其它 core，并根据这些 core 文件中的描述找到这些 IP 包含的源文件，然后进行命令行指定的综合，模拟等操作。

那具体Fusesoc怎么定位 core 文件呢，它依赖于一个配置文件 fusesoc.conf，在 Fusesoc 对 IP 进行操作前，会在以下目录依次寻找 fusesoc.conf

* Fusesoc 当前工作目录
* $XDG_CONFIG_HOME/fusesoc 目录
* /etc/fusesoc 目录

fusesoc.conf 文件中指定了若干的 core library 的位置（本地目录或者远程的 git 仓库）。然后 Fusesoc 会在这些指定的目录，以及它们的次级目录中寻找后缀名为 core 的文件。记录这些文件对应 IP 的名字（在前面的例子中就需要在这些 core 文件中找到 IP 名称为 ara 的文件，并一步定位它的依赖对应的 core 文件位置）。

## 2. core 文件内容与脚本自动化

core file 是一个 yaml 文件，首先它包含了它对应 IP 的名称，该名称用于指定依赖。通常该名称由三部分组成 `A::B:C`，A 通常用于指定组织名，B 用于指定该 IP 具体的名称，C 用于指定该 IP 的版本。然后是指定各种 fileset，每一类 fileset 通常有各种的用途（类似于 vivado 中的 sources_1, constraints_1 等等）。第一个 fileset 通常名称为 rtl，是组成该 IP 的所有文件。然后通常会有一个名称为 tb 的 fileset，包含用于 IP 测试验证相关的文件，还可以有一些 constraints fileset，用来包含一些 xdc 文件。或者用一个 fileset 来指定一些 tcl 脚本（例如在 target 选择的工具为 vivado 时，指定的 tcl 脚本将会在项目创建后运行）。

指定完 fileset 后，接下来是指定若干 target，一般会有一个 default target，这个 target 下面的参数指定了该 IP 作为 dependence 的时候，应该加入哪些文件（一般就是 rtl fileset）。接下来其他的 target 通常由两部分组成，一部分是该 target 需要用到哪些文件（用前面定义的 fileset 指定），另一部分就是该 target 用到的工具，以及相应的运行参数。比如我们可以指定一个 sim target，该 target 包含的 fileset 为 rtl 和 tb，指定工具为 icarus，再配置一些 icarus 的运行参数，使用命令`fusesoc run --run --target sim ip-name` 便可以运行 IP 的模拟仿真。

因此 core file 的 每个 target 指定了一种对该 IP 的操作，运行 Fusesoc 时指定相应的 target，fusesoc 就会启动相应的工具完成指定的操作，实现自动化。

最后值得一提的是，Fusesoc 对每个 target 的执行分为了三个阶段：setup，build，run。可以在命令行指定对该 target 执行到哪个阶段为止。每个阶段的具体含义可以查看文档中的 [Build stages](https://fusesoc.readthedocs.io/en/stable/user/overview.html#build-stages)。

OK，暂时想到的就这么多了

