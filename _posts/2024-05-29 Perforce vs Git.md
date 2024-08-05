Perforce 的一些基本概念

* workspace，类似于 git 的 local repo
* depot，类似于 git 的 remote repo

不同于 git 中本地仓库和远程仓库各自独立，perforce 中每次创建一个新的 workspace 都会在 depot 中存储相应的 metadata。因此 perforce 是一个中心化的版本管理工具，每个 workspace 都仅会连接一个 depot，是根据 depot 上存储的 metadata 来确定 workspace 的文件状态（例如每个文件处于哪个版本等等），切换文件版本时也需要从 depot 上获取。而在 git 中则是完全本地化的结构，本地的 .git 目录包含了完整的版本历史

这样相比于 Git，Perforce 的 workspace 能够小很多，因此将 Content 的管理迁移到 Perforce 上的话可以大幅减小 Content 目录的大小

另外 Perforce 其它的一些 feature

* Perforce 对于不同类型的文件采取了不同的保存方式，例如文本文件采用 reverse delta format，binary 文件采用 full version + compressed 等等（见 [Perforce file types for common file extensions](https://www.perforce.com/manuals/cmdref/Content/CmdRef/file.types.synopsis.common.html)）
* Perforce 在建立 workspace 时可以选择一部分文件和路径，在同步和修改时只会考虑这一部分的路径（类似 git 的 sparse checkout）
* Perforce 默认文件都是只读的，要修改一个文件时需要先 checkout 该文件，表明即将修改该文件。其它 workspace 会同步地收到这个消息，在 Perforce GUI 中，这个文件会被打上蓝色的勾，表明其它 workspace 正在改这个文件。同时，Perforce 也支持 lock 文件或者目录（git 中要做到这一点需要用 git lfs 拓展，例如 [File Locking](https://docs.gitlab.com/ee/user/project/file_lock.html)）

几种 Perforce 提供的购买方案 [helix-core-pricing](https://www.perforce.com/resources/vcs/helix-core-pricing)

* Free：至多 5 个 user，至多 20 个 workspace
* cloud：至多 50 个 user，workspace 数量没有限制，**不支持 LDAP integration**，提供云上的虚拟机。每人每月 39 刀
* 完整版：没有限制，没有公开定价，需要咨询协商 [How to buy](https://www.perforce.com/how-buy)

Continuous Integration：Perforce 可以与 jenkins 集成来实现 CI，其中 [jenkins][https://github.com/jenkinsci/jenkins] 是一个开源的 CI server。[jenkins-and-perforce-integrations](https://www.perforce.com/integrations/jenkins-and-perforce-integrations)