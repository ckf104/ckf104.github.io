一些奇奇怪怪的名词解释

* BSP：build server protocol，只是一个协议
* bloop：build server，负责实际的构建工作
* ant, maven, gradle, sbt，mill：构建的前端，用户可以使用sbt或者Mill来定义如何进行编译
* couriser，ivy：都属于 package resolver，ivy 还包括一个符合 ivy 标准的仓库（类似地，也有 maven 仓库），但是 couriser 可以识别 ivy 和 maven 仓库
* 