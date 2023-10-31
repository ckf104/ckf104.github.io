---
title: Writing SystemVerilog in vscode
date: 2023-10-31 19:11:25 +0800
categories: [tools usage]
---

本文记录如何在 vscode 中搭建一个简单的 systemverilog 的开发环境。首先下载安装 [verible](https://github.com/chipsalliance/verible)，verible 是一套 systemverilog 的辅助开发工具，提供了 systemverilog 的 parser, formatter, lintter, language server 等等。

我尝试了两个 vscode 的插件，一个是 verible 官方提供的 [Verible](https://marketplace.visualstudio.com/items?itemName=CHIPSAlliance.verible)，该插件提供了 linting，formatting，goto definition 以及 [verilog mode](https://www.veripool.org/verilog-mode/) 的部分支持。但我最终没有选择这个插件，原因如下

* 没有语法高亮支持
* 说明文档较少，比如文档中并没有解释如何使用它的 verilog mode，以及 goto definition 是如何寻找源文件的等等
* linting 能提供的报错较少

但该插件有一点好处是它的 goto definition 能够快速跳转到模块本地变量的定义上。我最终使用的[Verilog-HDL/SystemVerilog/Bluespec SystemVerilog](https://marketplace.visualstudio.com/items?itemName=mshr-h.VerilogHDL) 插件的跳转定义基于 ctags，ctags 的跳转让我不满意的地方有两点，一个是 ctags 生成的 tags 文件仅包含行号，因此跳转后光标总是位于行首，而不是定义的 token 名。另外就是对重名的支持很不友好。verilog 中各个模块的本地信号重名是很常见的，但 ctags 会机械地列出所有的重名信号，而不能通过上下文分析出真正引用的信号。

根据文档的说明，我额外下载了 [ctags-companion](https://github.com/gediminasz/ctags-companion) 插件，便于进行跳转。lint 额外的配置文件如下

```json
  "ctags-companion.command": "ctags -R --fields=+nKz --langmap=SystemVerilog:+.v -R .",
  "ctags-companion.readtagsGoToDefinitionCommand": "readtags -en",
  "verilog.formatting.verilogHDL.formatter": "verible-verilog-format",
  "verilog.linting.linter": "verilator",
  "verilog.linting.path": "/home/ckf104/tmp/install/verilator/bin/",
  "verilog.formatting.veribleVerilogFormatter.path": "/home/ckf104/install/verible-v0.0-3428-gcfcbb82b/bin/verible-verilog-format",
```

使用 `verible-verilog-format` 作为格式化工具，`verilator` 作为 linting 工具。然后下面的 `verilator.arguments` 是一个逐项目的配置，比较重要的是它的 `-I` 参数，用来设置寻找子模块的路径，不然 `verilator` 在 linting 的时候会报找不到子模块的错误。

```json
"verilog.linting.verilator.arguments": "-Wall -Ilib"
```

最后一点是关于插件的启用，因为 [ctags-companion](https://github.com/gediminasz/ctags-companion) 全局启用的话会对所有语言的项目的 goto definition 产生影响。我们只希望在 systemverilog 开发的时候启用就行了。这时候我们可以使用 vscode 提供的 [profile](https://code.visualstudio.com/docs/editor/profiles) 功能，把上面的额外配置和插件的启用打包了一个新的 profile，在需要写 systemverilog 代码时使用这个 profile 就好了。

总的来说，这样的配置能做到

* 语法高亮
* 错误检查
* 定义跳转
* 格式化

目前并没有找到如何在 systemverilog 中做自动补全的方法。