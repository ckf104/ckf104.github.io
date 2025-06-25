可以直接打开 uasset 文件查看内容

可以在 C++ 文件中看到
* 对于一个 C++ 类，是否有，有哪些继承该类的蓝图类
* 对于一个 C++ 类的成员函数，是否有，有哪些蓝图类重载了它

unreal usf 语法提示，尤其是 ue 里自定义的全局变量，以及提供相应的文档

提供快捷的方法创建 module，c++ class 以及 plugin 等

找出为什么 windows 下能够正常编译，但是 clangd 会报错只有声明，没有定义等等
找出为什么不能直接从编辑器中跳到 vscode c++ 代码里，但 visual studio 可以

针对 inl 文件或者不自洽的 header，header context

针对 forward declared incomplete type，当要使用完整类型时自动补全头文件
