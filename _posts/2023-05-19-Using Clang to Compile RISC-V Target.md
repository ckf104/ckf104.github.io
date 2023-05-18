---
title: "Using Clang to Compile RISC-V Target"
date: 2023-05-19 05:21:43 +800
categories: [Architecture]
---

基于使用的需求，我希望能够用 clang 来编译 RISC-V 文件，但按照网上的教程编译后，clang 找不到 GNU 的 C 库文件，或者需要使用`--sysroot`手动指定路径以及`-I`来指定 C++ 头文件路径等。链接时`ld`也会报错说找不到`libgcc.a`或者`crtendS.o`文件这样。所以一直以来的解决方案都是使用 clang 将上层语言编译为 RISC-V 汇编，然后再用 GNU 的工具链将汇编翻译为二进制的 RISC-V 指令。

今天又重新捣腾了一下，总算能够直接使用 clang 编译了。使用的 LLVM 配置参数如下

```shell
cmake -S . -B build-riscv/ -DCMAKE_INSTALL_PREFIX=~/tmp/install/llvm-riscv/ \
-DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_PROJECTS=clang \
-DGCC_INSTALL_PREFIX=/home/ckf104/install/riscv/ \
-DLLVM_DEFAULT_TARGET_TRIPLE="riscv64-unknown-linux-gnu" \
-DLLVM_TARGETS_TO_BUILD="RISCV" -DDEFAULT_SYSROOT=/home/ckf104/install/riscv/sysroot/ \
-DLLVM_ENABLE_RUNTIMES="compiler-rt;libcxx;libcxxabi;libunwind" \
-DCLANG_DEFAULT_RTLIB=compiler-rt -DCLANG_DEFAULT_CXX_STDLIB=libc++  \
-DBUILD_SHARED_LIBS=ON -DLIBCXXABI_USE_LLVM_UNWINDER=ON
```

在交叉编译时，总是面临着编译器和 C 库相互依赖的问题。因为编译器编译 C/C++ 代码时，依赖于 compiler runtime（例如 `libgcc_s.so`），而 compiler runtime 又依赖于 C库。因此一个完整功能的编译器是依赖于 C 库的，但在交叉编译的初始阶段并没有一个目标平台的 C 库。因此 GCC 的编译分为两个阶段。第一个阶段编译时使用`--with-newlib`参数，表明编译`libgcc_s.so`时将其对 C 库的调用替换为 GCC 内部的实现。最终编译出一个支持 [freestanding envrionment](https://gcc.gnu.org/onlinedocs/gcc/Standards.html) 的 C 编译器。随后再用该编译器编译 C 库。得到目标平台的二进制 C 库。再基于此重新编译 GCC，得到功能完整的编译器。

现在我们说明上面配置中各参数的含义。由于 LLVM 目前貌似并不支持这样一种两阶段的配置。因此我们需要首先配置 RISC-V GNU TOOLCHAIN。来保证在安装 LLVM 工具链前有 RISC-V 平台的 C 库，这里我安装在了`/home/ckf104/install/riscv/`目录下。因此相应的 RISC-V 的`sysroot`目录就是`/home/ckf104/install/riscv/sysroot/`。

`-DLLVM_DEFAULT_TARGET_TRIPLE="riscv64-unknown-linux-gnu"`设置 clang 编译时默认的 triple，`-DLLVM_TARGETS_TO_BUILD="RISCV"`设置 clang 支持的目标平台，我们只启用了 RISC-V。

`-DLLVM_ENABLE_RUNTIMES`启动了四个库，`compiler-rt`用于摆脱 clang 对 `libgcc_s.so`的依赖。剩下的三个库用来编译`libc++.so`。摆脱 clang 对 GNU C++ 库的依赖。值得注意的是这里并没有加入`libc`。原因之一是`libc`的官网上说该项目功能尚不完善，另外一个原因是编译时`compiler-rt`已经依赖于 GNU 的 C 库了，再把 LLVM 的 C 库加进来也感觉怪怪的。`-DCLANG_DEFAULT_RTLIB`和`-DCLANG_DEFAULT_CXX_STDLIB`告诉 clang 在以后编译 C/C++ 时默认使用`compiler-rt`和`libc++.so`，而不是使用 GNU 的库。

在编译`compiler-rt`以及 C++ 库时需要用到 GNU C 库以及链接器，因此`-DGCC_INSTALL_PREFIX`以及`-DDEFAULT_SYSROOT=`指明相应的 GNU 工具链的位置。

`-DLIBCXXABI_USE_LLVM_UNWINDER=ON`指明依赖关系，先构建`libunwind`再构建`libc++`，然后链接`libc++.so`时使用刚刚构建的`libunwind.so`库。



**一些可能的报错：**

```shell
/home/ckf104/install/riscv/bin/riscv64-unknown-linux-gnu-ld: cannot find crtbeginS.o: No such file or directory
```

编译好的 clang 还是依赖于 GNU 的 `crtbeginS.o` 和 `crtendS.o` 两个启动文件。将安装的 GNU 工具链中的这俩文件复制到`riscv-sysroot-path/usr/lib/` 下就可以了。

```shell
undefined reference to `_Unwind_Resume`
```

编译时没有加入`-DLIBCXXABI_USE_LLVM_UNWINDER=ON`，导致编译好的`libc++.so`不依赖于`libunwind.so`



**Refs** :

* [Using Clang to compile for RISC-V](https://stackoverflow.com/questions/68580399/using-clang-to-compile-for-risc-v)

* [Cross compiling with Clang - crtbeginS.o: No such file or directory](https://stackoverflow.com/questions/73776689/cross-compiling-with-clang-crtbegins-o-no-such-file-or-directory)

* [Enable libc++/libcxx by default when using clang++](https://stackoverflow.com/questions/19901128/enable-libc-libcxx-by-default-when-using-clang)