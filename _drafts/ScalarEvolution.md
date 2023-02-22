## Loop count相关的数据结构

```cpp
class ExitLimit;

class BackedgeTakenInfo;

SE.getSCEVAtScope(SCEV, nullptr);
// some problem if too big scope
// e.g, SCEV = {0,+,{1,+,1}<outer loop>}<inner loop>
// -> {0, + {1 smax %0}}<inner loop>, but iteration count is a SCEV 
// which is not refined by getSCEVAtScope
// so need to call getSCEVAtScope multiple times until return value don't change

SE.getSCEV(Value);
// From https://www.youtube.com/watch?v=y07BE1og4VI, around the 12th minute of the video
// If we create SCEV speculatively, because getSCEV function get SCEV from map and do not
// check flags, we may get a SCEV with wrong flags set!
// should we add SCEV flags into FoldingSetID?

SE.isKnownPredicate(Predicate, SCEV, SCVE);
// prove predicate with runtime check information(e.g., loop guard)

class SCEVPredicate;
// we can analyze SCEV better if we assume something may not true
// e.g., SE.getPredicatedBackedgeTakenCount(L, Preds);
class PredicatedScalarEvolution;
class SCEVExpander;
// structure that I don't know how to interact with it.
```

SCEV表达式，获取范围时选择unsigned, signed的区别？因为SCEV中并不区分unsigned, signed，所以最后实际的范围可以两个取交集？