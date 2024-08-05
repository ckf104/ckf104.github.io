记录一下用到的llvm接口，有空分析一下

- [ ] `PreservedAnalyses`
- [ ] `PassInfoMixin`
- [ ] `FunctionAnalysisManager`
- [ ] `PassBuilder`
- [ ] `createModuleToFunctionPassAdaptor`
- [ ] **DenseMap实现**

* 各种各样的value类型如何理解？basicblock as value, metadata as value...

* replaceAllUsesWith函数，为什么要对Constant和Phi 进行特殊操作
* value中的stripPointerCasts函数是干嘛的，为什么对函数进行cast的时候需要调用stripPointerCasts([c++ - How can I get the name of function from StoreInst's Value In LLVM - Stack Overflow](https://stackoverflow.com/questions/28706263/how-can-i-get-the-name-of-function-from-storeinsts-value-in-llvm))

* ~~valueName类？~~value类中value name的作用？LLVMContext ?  **相应的，value与metadata的关系？**

* GlobalValue中的intrinsic::ID ？为什么在Value setName后需要重新计算function的intrinsic::ID

* IR中的blockaddress是什么，相应的indirectBr语义？（查看相应源码）
* Constant Expression内部结构如何组织？如何保证Constant实例只有一份（最麻烦的是PointerTy ?），类似的，StructType也只有一份？
* PHINode从定义上看，操作数除了基本的Value，还包括BasicBlock？不过代码中如果PHI添加了一个BasicBlock, 没有增加它的Use, PHINode为什么必须出现在基本块的开头？
* instruction的isEHPad函数是干嘛的，Exception Handle在IR中扮演了怎样的作用

* BasicBlock中迭代instructionsWithoutDebug，什么是debug inst ?
* GlobalValue中的Partition属性是干嘛的
* IR库中的全局参数要怎么传递，clang的`-mllvm`参数吗
* trailingobject的totalSizeToAlloc方法，这样写是否会因对齐导致问题？ValueHandle.h AssertVH的GetAsValue参数是不是不太对（应该是ValueTy？）
* SCEV论文中谈到的一些问题：Wraparound Variable Analysis, Cyclic Recurrence, 这些问题在LLVM中如何解决的？
* 在scalarEvolution类中，一个SCEV如何对应到多个value上去（例如：标识ADDREC SCEV的REFID包含信息：SCEV TYPE，SCEV OPS，LOOP，取俩变量步长和初始值都相同，他们就对应到同一个SCEV上去了，这个可以用来消除冗余变量？），SCEVTraversal怎么说？



* llvm::operator类是干嘛的，Instruction中有一大堆的`setHasNoUnsignedWrap`与Operator相关联的函数是干嘛的

目前可以做的一些事情：

* 看看IR中的intrinsics，关注如何手动添加，看看llvm-epi是怎么做的
* 回头看vegen的代码
* llvm中各种数据结构的实现方式，例如StringMap, Constants(vector), zip, scalar evolution(isconsecutive), pattern match,Alias Analysis，vegen loop unroll, loop peel, assumption cache，LazyValueInfo，BlockFrequencyInfo，TargetTransformInfo, DependenceInfo, TargetLibraryInfo
* 查ARM, X86加一些非SIMD指令的原因, 考虑一些相关的benchmark，ARM scalable vector extension



LLVM-EPI中对llvm源码做的一些变动:

* structlayout的构造函数

数据结构记录：

* ValueSymbolTable，对StringMap<Value*>做了两点封装
  * 限制了String作为key的最大长度：超过最大长度的输入会被截断
  * 自动重命名：如果插入时已有重名，会对插入的Value进行自动重命名
* GlobalObject，继承自GlobalValue，额外的属性包括
  * Alignment相关
  * Comdat与section相关
  * VcallVisibility相关？（不清楚这是干嘛的）
* GlobalVariable, 继承自GlobalObject，额外的属性包括
  * Constant，标志该全局变量是否为常量
  * ExternallyInitialized, 标志该全局变量的值在初始值到在全局变量初始化函数运行前是否会发生变化
  * AttributeSet，与该全局变量绑定的Attr（看看实现！）
* APInt，表达任意长度的整数，数据结构包括
  * 一个`uint64_t`的指针，指向堆上分配的`uint64_t`数组
  * `bitWidth`，表示该Int的宽度
* Type, llvm表达Type的基本类，相关的类成员
  * LLVMContext，该类所绑定的context
  * typeID, subclassData
  * ContainedTypes + NumContainedTys 该类型包含的其它类型（例如结构体，数组等），注意这个ContainedTypes是一个`Type**`类型，通常指向的是其子类内部的`Type*`（所以包含其它类型的子类需要额外的`Type*`数组）





已经解决的疑问：

* ~~replaceAllUsesWith函数，为什么要对Constant进行特殊操作~~（因为Constant是不可变对象，对于正常的Value，这里只需要改变该Value的操作数，让它指向新的操作数就可了，但是Constant不可变，因此将Constant整个替换，新的Constant使用新的操作数）
* static_assert in (template class) member function: 只要不使用该函数就不会触发`static_assert`，在`iterator_facade_base`类中llvm使用了该技巧
* ~~BasicBlock中的BlockAddressRefCount作用~~？修改的接口函数为`AdjustBlockAddressRefCount`，例如每生成一个BlockAddress引用该BasicBlock，该`RefCount+=1`
* ~~GlobalValue中的LinkageType, VisibilityType, DLLStorageClass, DSOLocal 语义上是否有重复？~~(是的，主要还是看assembler会如何使用这些属性)



TODO

* RISCV Intrinsic Wrapper ?  LLVM提供了fixed vector 来生成riscv的lowering
* LLVM如何估计vscale Intrinsic返回值的长度呢

