## 内建PASS

```cpp
class PassRegistry;

class PassInfo;

class PassBuilder;

class **PassManager;
// Module, CGSCC, Function, Loop
class **AnalysisManager;
```

为什么 `opt -tbaa`可行，但是`opt --passes=tbaa`报错呢

INITIALIZE_PASS