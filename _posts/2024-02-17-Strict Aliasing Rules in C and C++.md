* gcc 提供了 [may_alias](https://gcc.gnu.org/onlinedocs/gcc-4.1.2/gcc/Type-Attributes.html) attribute
* memset 的实现，例如 [musl memset](https://github.com/kraj/musl/blob/kraj/master/src/string/memset.c)
* [void* 指针不影响 strict aliasing rules 分析](https://stackoverflow.com/questions/15745030/type-punning-with-void-without-breaking-the-strict-aliasing-rule-in-c99)
* [llvm tbaa](https://llvm.org/doxygen/TypeBasedAliasAnalysis_8cpp_source.html)

