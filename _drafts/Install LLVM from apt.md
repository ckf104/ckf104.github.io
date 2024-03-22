Following tutorial https://mirrors.tuna.tsinghua.edu.cn/help/llvm-apt/, we use the second method. 

* Execute `wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -` in cmdline. 
* Add a new file `/etc/apt/sources.list.d/llvm-apt.list` with following contents
```
# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
deb [arch=amd64] https://mirrors.tuna.tsinghua.edu.cn/llvm-apt/focal/ llvm-toolchain-focal main
# deb-src https://mirrors.tuna.tsinghua.edu.cn/llvm-apt/focal/ llvm-toolchain-focal main
```

Pay attention to additional `arch=amd64` in brackets! Since no i386 package in tsinghua mirror(at least for llvm-apt), we restrict apt only to search amd64 package, or it will complain `Failed to fetch xxxx 404 not found`.

## Some Trouble Shooting
* `Error: can't connect ppa.launchpad.net`. It seems that ISP or router don't enable IPv6, which causes this problem by [this thread](https://askubuntu.com/questions/1199285/apt-update-failing-because-it-cant-connect-to-ppa-launchpad-net). We can download deb package(error messages tell us where it can be downlaoded) and install it manually to solve this problem.