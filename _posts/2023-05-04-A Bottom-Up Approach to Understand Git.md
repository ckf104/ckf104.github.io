---
title: "A Bottom-Up Approach to Understand Git"
date: 2023-05-04 15:44:45 +800
categories: [tools usage]
---

这篇文章受 Git Book 第十章[Git Internals](https://git-scm.com/book/en/v2/Git-Internals-Plumbing-and-Porcelain)的启发，总结一下自己目前对 git 的一些理解（好好好，我知道这个标题是在碰瓷Computer Networking: A Top-Down Approach）。

我们以一个实际的搭建 git 仓库的例子，从 git 底层的 key-value system 出发，讨论 git 如果实现上层 working tree, staging area, local repository 的三状态抽象，以及 branch, merge/rebase, submodule 特性。

## 1. Key-value System

第一个需要讨论的问题是 git 是如何管理我们的数据的。所有的数据都存放在`.git`目录中。`.git`目录的结构可以参考[gitrepository-layout](https://git-scm.com/docs/gitrepository-layout). 本文关心的有`config`, `HEAD`, `index`, `refs/tags/`, `refs/heads/`, `refs/remotes/`, `objects/`. 在本节我们讨论`objects`目录

### 1.1 Blob Objects

`objects`目录中以键值对的形式存放了所有的文件。其中键是文件的 SHA 哈希值，文件内容则使用 zlib 压缩存储。我们从头创建一个新的 git 仓库进行研究。

```shell
$ git init    # 此时 .git/objects 目录中没有文件（info, pack目录除外）
$ echo "first obj" | git hash-object -w --stdin  # 使用 git hash-object 命令向仓库中添加新文件
0504a209aeb067af4ad229d6a7ee2863a8ed74ff
```

此时我们查看`.git/objects`目录，会发现多出了`.git/objects/05/04a209aeb067af4ad229d6a7ee2863a8ed74ff`文件，该文件的路径正对应它的 SHA 哈希值。

```shell
$ file .git/objects/05/04a209aeb067af4ad229d6a7ee2863a8ed74ff 
.git/objects/05/04a209aeb067af4ad229d6a7ee2863a8ed74ff: zlib compressed data
```

使用`git cat-file`命令查看文件的具体内容和

```shell
$ git cat-file -p 0504a209aeb0
first obj
$ git cat-file -t 0504a209aeb0
blob
```

一个 key-value system 就展现出来了，我们可以向其中写入文件，返回文件的 SHA 哈希值，随后可以用返回的哈希值前缀获取该文件的内容。`git cat-file`命令的`-t`参数使 git 返回该文件的类型，blob 是 git 仓库中最基础的一种文件类型，接下来我们还会看到更多的文件类型。

## 1.2 Tree Objects

blob object 构成了 key-value system 的基石。但目前的 key-value system 没有保存文件名和文件属性，也没有保存目录结构。因此新的 Tree Objects 来解决这一问题。

不过在此之前，我们先讨论`.git/index`文件，来阐述 git 如何实现 staging area 的。`index`是一个二进制形式的文件，具体的格式可参考[index-format](https://git-scm.com/docs/index-format). 我们可以使用`git update-index`命令来修改`index`文件，`git ls-files -s`来查看`index`文件的具体内容。

我们将上一节中创建的 first obj 加入`index`文件。

```shell
$ git update-index --add --cache-info git update-index --add --cacheinfo 100644,0504a209aeb067af4ad229d6a7ee2863a8ed74ff,first-obj.txt
$ git ls-files -s
100644 0504a209aeb067af4ad229d6a7ee2863a8ed74ff 0       first-obj.txt
```

这下我们看到`index`中出现了我们新添加的 `first-obj.txt`文件。输出的内容依次为文件权限，文件哈希值，stage number（在下文讨论分支合并时会用到）以及文件名。`index`中的文件名可以包含目录，以此来体现目录结构。

```shell
$ echo "second obj in tmp dir" | git hash-object -w --stdin  # 向仓库写入第二个文件
160e90f4726294335ed5a1bc9a1df91adac181e4
$ git update-index --add --cacheinfo 100644,160e90f4726294335ed5a1bc9a1df91adac181e4,tmp/second-obj.txt
$ git ls-files -s
100644 0504a209aeb067af4ad229d6a7ee2863a8ed74ff 0       first-obj.txt
100644 160e90f4726294335ed5a1bc9a1df91adac181e4 0       tmp/second-obj.txt
$ git status
On branch master

No commits yet

Changes to be committed:
  (use "git rm --cached <file>..." to unstage)

        new file:   first-obj.txt
        new file:   tmp/second-obj.txt

Changes not staged for commit:
  (use "git add/rm <file>..." to update what will be committed)
  (use "git checkout -- <file>..." to discard changes in working directory)

        deleted:    first-obj.txt
        deleted:    tmp/second-obj.txt
```

当我们使用`git status`查看仓库状态时，有趣的事情发生了，即使我们没有使用任何的`git add/commit`命令，仓库状况仍发生了改变。事实上，`index`文件正对应着 git 的 staging area，之前的命令中我们将`first-obj.txt, tmp/second-obj.txt`加入了`index`文件，但工作区中并没有创建这两个文件，因此产生了上面的输出。

最后我们通过`index`文件来生成 tree object

```shell
$ git write-tree  # 读取index文件，并生成相应的tree object
9d30e6393627ed36849c38cd60c062fe9c78a151
$ file .git/objects/9d/30e6393627ed36849c38cd60c062fe9c78a151 
.git/objects/9d/30e6393627ed36849c38cd60c062fe9c78a151: zlib compressed data
$ git cat-file -t 9d30e6393627
tree
$ git cat-file -p 9d30e6393627
100644 blob 0504a209aeb067af4ad229d6a7ee2863a8ed74ff    first-obj.txt
040000 tree 8cecc3da5efdee47d6f270d5ec3990bba3899024    tmp
$ git cat-file -p  8cecc3da5efde
100644 blob 160e90f4726294335ed5a1bc9a1df91adac181e4    second-obj.txt
```

可以看到，tree object 中体现了文件名，文件属性，目录结构等信息，引入 tree object 后，key-value system 中的一个哈希键值可以对应整个目录下的所以信息，即可以包含一个 commit 中所有文件内容。

### 1.3 Commit Objects

但 tree object 和实际的 commit 还有些区别，因为 git commit 中还包含了 commit message, committer 等信息。因此一个 git commit 对应的是 一个 commit object

我们使用`git commit-tree`读取 tree object，然后生成相应的 commit object

```shell
$ git commit-tree 9d30e6393627ed36849c38cd60c062fe9c78a151 -m "first commit"
60d16c1fbf0573f8ad1c9cdae976d7d96eebeb44
$ git cat-file -t 60d16c1
commit
$ git cat-file -p 60d16c1
tree 9d30e6393627ed36849c38cd60c062fe9c78a151
author ckf104 <git-config-email> 1683125736 +0800
committer ckf104 <git-config-email> 1683125736 +0800

first commit
```

可以看到，commit object 中包含了一次 commit 的所有信息，指向的 tree object 则包含了该 commit 中所有的文件信息

通常的 commit object 还应该包含指向父节点的指针。我们再创建一个新的 commit object 来体现这一点，这一次使用`git commit-tree`时加上`-p`参数来指示其 parent commit object

```shell
$ echo "third obj" | git hash-object -w --stdin
8f92dd341b27373920b499000233ddc95817775c
$ git update-index --add --cacheinfo 100644,8f92dd341b27373920b499000233ddc95817775c,third-obj.txt
$ git write-tree
68eb629874fa8287044900cbdf46462a80fe3ffa
$ git commit-tree 68eb629874fa8287044900cbdf46462a80fe3ffa -p 60d16c1fbf -m "second commit"
cd6c4c853af37c334e49d27c6c67536d4a914ea2
$ git cat-file -p cd6c4
tree 68eb629874fa8287044900cbdf46462a80fe3ffa
parent 60d16c1fbf0573f8ad1c9cdae976d7d96eebeb44
author ckf104 <git-config-email> 1683126191 +0800
committer ckf104 <git-config-email> 1683126191 +0800

second commit
```

最后，我们更新`.git/refs`中的指针，来指向我们创建的 commit object（这一步的原理会在下文讨论分支时详细阐述）

```shell
$ git update-ref refs/heads/master cd6c4c853af37c3
$ git log
commit cd6c4c853af37c334e49d27c6c67536d4a914ea2 (HEAD -> master)
Author: ckf104 <git-config-email>
Date:   Wed May 3 23:03:11 2023 +0800

    second commit

commit 60d16c1fbf0573f8ad1c9cdae976d7d96eebeb44
Author: ckf104 <git-config-email>
Date:   Wed May 3 22:55:36 2023 +0800

    first commit
$ git status
On branch master
Changes not staged for commit:
  (use "git add/rm <file>..." to update what will be committed)
  (use "git checkout -- <file>..." to discard changes in working directory)

        deleted:    first-obj.txt
        deleted:    third-obj.txt
        deleted:    tmp/second-obj.txt

no changes added to commit (use "git add" and/or "git commit -a")
```

有趣的是，我们没有使用任何的`git add/commit`命令，仅仅是操纵底层的 key-value system，就创建出了新的 commit log。因为工作区没有任何的文件，所有`git status`会认为我们把所有文件都删除了。

### 1.4 Summary

我们总结一下到目前为止对 git 的理解，`.git/objects`目录中有三类重要的 object，分别是 blob, tree, commit. commit object 中包含了一个 tree object 的指针，tree object 中有若干 tree object, blob object 的指针，以此来形成目录结构。commit object 中还包含了其它 commit object 的指针，形成一个由 commit object 组成的有向无环图，进一步形成提交历史。`index`文件对应 git 的 staging area，包含了若干 blob 指针，因此可以与 working area, commit object 进行对比，由此比较出哪些文件被修改了，哪些文件尚未提交等等。 

## 2. Git Refs

在这一节我们将把目光放在`.git/refs`目录下，来理解 git 中的 branch 和 tag. 如果仅有1.4节中总结的上层抽象，我们还需要记住 commit object 的哈希值。因此 branch, tag 机制的本质也是一个 key-value system，将一个字符串映射为一个 commit object 的 哈希值。

`.git/refs`下通常有三个子目录，`.git/refs/heads/`, `.git/refs/tags`, `.git/refs/remotes`，分别对应 git 的 branch, tag, remote-tracking branch.

### 2.1 Branch

首先来看`.git/refs/heads`

```shell
$ cat .git/refs/heads/master 
cd6c4c853af37c334e49d27c6c67536d4a914ea2
```

对应 master 分支的文件中简单地存放了该分支对应的 commit object 的哈希值。现在我们可以理解1.3节中命令`git update-ref refs/heads/master cd6c4c853af37c3`的含义了。本质上相当于`echo cd6c4c853af37c334e49d27c6c67536d4a914ea2 > .git/refs/heads/master `。

我们可以再新建一个 test 分支

```shell
$ git branch test HEAD^
$ cat .git/refs/heads/test 
60d16c1fbf0573f8ad1c9cdae976d7d96eebeb44
```

`.git/refs/heads/test`中包含的正是我们所创建的第一个 commit object

### 2.2 Tag

接下来我们来看看 tag 的原理。git 中有 lightweight tag 和 annotated tag 之分。lightweight tag 和 branch 几乎一样。

```shell
$ git tag v1.0 HEAD  # create lightweight tag
$ cat .git/refs/tags/v1.0 
cd6c4c853af37c334e49d27c6c67536d4a914ea2
```

而 annotated tag 对应的文件中也包含一个哈希值，不过它不再指向一个 commit object，而是我们前文尚未提到的 tag object

```shell
$ git tag -a v0.5 HEAD^ -m "annotated tag"
$ cat .git/refs/tags/v0.5 
588418fb9a163cfbd6a62d89c34abf52a6870af8
$ git cat-file -t 588418fb
tag
$ git cat-file -p 588418fb
object 60d16c1fbf0573f8ad1c9cdae976d7d96eebeb44
type commit
tag v0.5
tagger ckf104 <git-config-email> 1683129702 +0800

annotated tag
```

可以看到，相比于 lightweight tag, annotated tag 包含了更多的信息。tag object 中包含了一个 object 指针，大部分情况下，但不局限于是一个 commit object。

### 2.3 Remote-tracking Branch  

最后我们讨论 git 远程分支的实现。为此，我们在 github 上新建一个仓库 git-remote，然后加入到 git config 中

```
$ git remote add origin https://github.com/ckf104/git-remote
$ git push -u origin master  # push local commit into remote empty repository
$ git push -u origin test
$ cat .git/refs/remotes/origin/master
cd6c4c853af37c334e49d27c6c67536d4a914ea2
$ cat .git/refs/remotes/origin/test 
60d16c1fbf0573f8ad1c9cdae976d7d96eebeb44
```

可以看到，`.git/refs/remotes/<remote-repo-name>/<branch>`表示一个 remote-tracking branch，与 local branch 一样，它也指向一个 commit object，表示上一次 fetch 所看到的远程仓库该分支对应的 commit object。现在我们直接在 github 上修改远程仓库

```shell
$ echo "remote edition" >> third-obj.txt # edit in github
```

然后在本地 fetch

```shell
$ cat .git/refs/remotes/origin/master
cd6c4c853af37c334e49d27c6c67536d4a914ea2
$ git fetch origin master:refs/remotes/origin/master
$ cat .git/refs/remotes/origin/master 
9658fd94729388354d42d370ab29d74463b02c7b
```

最后我们可以将该远程修改合并进本地分支

```shell
$ git merge origin/master 
Updating cd6c4c8..9658fd9
Fast-forward
 third-obj.txt | 1 +
 1 file changed, 1 insertion(+)
$ cat .git/refs/heads/master 
9658fd94729388354d42d370ab29d74463b02c7b
```

最后值得提的一点是 git 如何判断我们在哪个分支上。这是基于`.git/HEAD`文件，`HEAD`文件通常包含的是某个分支的引用，由此来表明我们所在的分支。有时候我们希望`git checkout`到某次具体的 commit，此时`HEAD`文件则包含该 commit object 的哈希值，称为`detached head`

```shell
$ cat .git/HEAD   # head points to master branch now
ref: refs/heads/master
```

### 2.4 Summary

现在我们来讨论现在所看到的上层抽象，在1.4节 commit object 形成的有向无环图的基础上，git 提供的一个新的 key-value 映射，将字符串名字映射到有向无环图的某一个节点上。字符串名字可以分为，branch, tag, remote-tracking branch

每次`git checkout`时修改`HEAD`文件的引用，修改`index`文件和工作区。每次`git commit`时会修改`refs/heads/<branch>`中的引用，使其指向最新的 commit object

## 3. Merge and Rebase

如果我们仅考虑 merge 和 rebase 成功的情况，那这个模型也是很简单的，merge 就是把两个 commit object 合并，生成新的 commit object，新的 commit object 以合并的那俩 commit object 为父节点。而 rebase 则修改分支的提交路径，A rebase B 表示将分支 A 在分支 B 中没有的提交迁移到分支 B 中，更加准确和图形化的描述可以参考文档[git-rebase](https://git-scm.com/docs/git-rebase) 

现在我们关心的问题是，当发生合并冲突了，此时的 git 仓库处于一个怎样的状态。

### 3.1 Merge Conflicts

现在的master分支应处于如下状态

```shell
$ git status
On branch master
Your branch is up to date with 'origin/master'.

Changes not staged for commit:
  (use "git add/rm <file>..." to update what will be committed)
  (use "git checkout -- <file>..." to discard changes in working directory)

        deleted:    first-obj.txt
        deleted:    tmp/second-obj.txt

no changes added to commit (use "git add" and/or "git commit -a")
$ git log --oneline
9658fd9 (HEAD -> master, origin/master) Update third-obj.txt
cd6c4c8 (tag: v1.0) second commit
60d16c1 (tag: v0.5, origin/test, test) first commit
```

我们先恢复 master 分支的工作区，然后对 test 分支进行修改

```shell
$ git checkout -- first-obj.txt tmp/second-obj.txt
$ git checkout test
$ echo "test edit" >> first-obj.txt
$ git commit -am "edit first-obj.txt"
[test be7bbfe] edit first-obj.txt
 1 file changed, 1 insertion(+)
$ echo "test edit" > third-obj.txt
$ git add third-obj.txt
$ git commit -m "edit third-obj.txt"
[test f167c80] edit third-obj.txt
 1 file changed, 1 insertion(+)
 create mode 100644 third-obj.txt

$ git diff test master 
diff --git a/first-obj.txt b/first-obj.txt
index db64dd4..0504a20 100644
--- a/first-obj.txt
+++ b/first-obj.txt
@@ -1,2 +1 @@
 first obj
-test edit
diff --git a/third-obj.txt b/third-obj.txt
index b0d7d2d..12a2b7a 100644
--- a/third-obj.txt
+++ b/third-obj.txt
@@ -1 +1,2 @@
-test edit
+third obj
+remote edition
```

我们为 test 分支新增了两个 commit ，第一个 commit 为`first-obj.txt`添加了一行，这与主分支不冲突。第二个 commit 新建了 third-obj.txt，这个改动与主分支冲突了。

现在我们切换回主分支，尝试合并 test 分支 

```shell
$ git checkout master
$ git merge test 
Auto-merging third-obj.txt
CONFLICT (add/add): Merge conflict in third-obj.txt
Automatic merge failed; fix conflicts and then commit the result.
$ git status
On branch master
Your branch is up to date with 'origin/master'.

You have unmerged paths.
  (fix conflicts and run "git commit")
  (use "git merge --abort" to abort the merge)

Changes to be committed:

        modified:   first-obj.txt

Unmerged paths:
  (use "git add <file>..." to mark resolution)

        both added:      third-obj.txt
$ git ls-files -s
100644 db64dd457525358ffc12b5c8b1ddbbe083348f81 0       first-obj.txt
100644 12a2b7ae95771fdf44d3d3541bf54dd4f2905c73 2       third-obj.txt
100644 b0d7d2dd8383faefadc0535eba47383adad021a4 3       third-obj.txt
100644 160e90f4726294335ed5a1bc9a1df91adac181e4 0       tmp/second-obj.txt
```

如我们所预期的，合并时发生了冲突，值得注意的是`index`文件的内容，`first-obj.txt`的修改已经被加入到`index`中，而`third-obj.txt`出现了两个版本，并有着不同的stage number

```shell
$ git log -n1 --oneline
9658fd9 (HEAD -> master, origin/master) Update third-obj.txt
$ git cat-file -p 12a2b7ae95771
third obj
remote edition
$ git cat-file -p b0d7d2dd8383f
test edit
```

注意，在发生合并冲突时，我们仍处于master分支上（即将 B 合并进 A 时，如果发生冲突，此时我们处于 A 分支上）。另外可以看到，B 合并到 A 中，stage number 2 对应的是 A 分支的文件，stage number 3 对应的是 B 分支的文件。通常还会有stage number 1，对应两个分支的共同祖先节点的该文件（这里由于共同祖先节点没有`third-obj.txt`，所以没有出现 stage number 1）。

我们尝试解决冲突

```shell
$ git add third-obj.txt 
$ git ls-files -s
100644 db64dd457525358ffc12b5c8b1ddbbe083348f81 0       first-obj.txt
100644 50f66c530744a1963fb4afce2d4f69ef164c70ca 0       third-obj.txt
100644 160e90f4726294335ed5a1bc9a1df91adac181e4 0       tmp/second-obj.txt
$ git status
On branch master
Your branch is up to date with 'origin/master'.

All conflicts fixed but you are still merging.
  (use "git commit" to conclude merge)

Changes to be committed:

        modified:   first-obj.txt
        modified:   third-obj.txt
$ cat .git/MERGE_HEAD 
f167c80386c257e5134e6505036080e8cd1e4b8d
$ cat .git/refs/heads/test 
f167c80386c257e5134e6505036080e8cd1e4b8d
```

可以看到，`git add`清理掉了 stage number 大于0的相应文件，冲突得到了解决。另外一个问题是 git 如何知道此时仓库处于 merge conflicts 状态，我猜想应该是 git 在 merge 冲突时产生了`.git/MERGE_HEAD`文件，指向了被合并的分支，由此来判断此时处于 merge 途中。当 merge 结束后，该文件被自动删除。

这下我们清楚 merge 冲突时 git 的仓库状态如何，以及如何表示冲突文件了。最后，我们终止 merge

```shell
$ git merge --abort
```

### 3.2 Rebase Conflicts

我们将上面的操作中的 merge 替换为 rebase

```shell
$ git rebase master test  # rebase test onto master
First, rewinding head to replay your work on top of it...
Applying: edit first-obj.txt
Applying: edit third-obj.txt
Using index info to reconstruct a base tree...
Falling back to patching base and 3-way merge...
Auto-merging third-obj.txt
CONFLICT (add/add): Merge conflict in third-obj.txt
error: Failed to merge in the changes.
Patch failed at 0002 edit third-obj.txt
hint: Use 'git am --show-current-patch' to see the failed patch

Resolve all conflicts manually, mark them as resolved with
"git add/rm <conflicted_files>", then run "git rebase --continue".
You can instead skip this commit: run "git rebase --skip".
To abort and get back to the state before "git rebase", run "git rebase --abort".

$ git status
rebase in progress; onto 9658fd9
You are currently rebasing branch 'test' on '9658fd9'.
  (fix conflicts and then run "git rebase --continue")
  (use "git rebase --skip" to skip this patch)
  (use "git rebase --abort" to check out the original branch)

Unmerged paths:
  (use "git reset HEAD <file>..." to unstage)
  (use "git add <file>..." to mark resolution)

        both added:      third-obj.txt

no changes added to commit (use "git add" and/or "git commit -a")

$ git log -n4 --oneline
3bf5463 (HEAD) edit first-obj.txt
9658fd9 (origin/master, master) Update third-obj.txt
cd6c4c8 (tag: v1.0) second commit
60d16c1 (tag: v0.5, origin/test) first commit

$ git ls-files -s 
100644 db64dd457525358ffc12b5c8b1ddbbe083348f81 0       first-obj.txt
100644 12a2b7ae95771fdf44d3d3541bf54dd4f2905c73 2       third-obj.txt
100644 b0d7d2dd8383faefadc0535eba47383adad021a4 3       third-obj.txt
100644 160e90f4726294335ed5a1bc9a1df91adac181e4 0       tmp/second-obj.txt

$ git log -n4 --oneline
3bf5463 (HEAD) edit first-obj.txt
9658fd9 (origin/master, master) Update third-obj.txt
cd6c4c8 (tag: v1.0) second commit
60d16c1 (tag: v0.5, origin/test) first commit

$ cat .git/refs/heads/test 
f167c80386c257e5134e6505036080e8cd1e4b8d
$ cat .git/REBASE_HEAD 
f167c80386c257e5134e6505036080e8cd1e4b8d
```

正如前面简述的 rebase 工作模型，commit 是一个一个依次 apply 到 master 分支上的，test 分支的第一个 commit 并不与 master 发生冲突，因此成功 apply 上去了。但是第二个 commit 冲突了，因此此时查看 log 发现目前恰好领先 master 一个 commit. 然后`third-obj.txt`如 merge 时一样在`index`中有多个版本。类比`MERGE_HEAD`，此时也有`REBASE_HEAD`文件。

这一次，我们解决冲突，并让 rebase 最终完成

```shell
$ git add third-obj.txt
$ git ls-files -s
100644 db64dd457525358ffc12b5c8b1ddbbe083348f81 0       first-obj.txt
100644 dba11baaee5f17c8e601948dcd01df0369591726 0       third-obj.txt
100644 160e90f4726294335ed5a1bc9a1df91adac181e4 0       tmp/second-obj.txt
$ git status
rebase in progress; onto 9658fd9
You are currently rebasing branch 'test' on '9658fd9'.
  (all conflicts fixed: run "git rebase --continue")

Changes to be committed:
  (use "git reset HEAD <file>..." to unstage)

        modified:   third-obj.txt
$ git rebase --continue   # continue rebase process after solving conflicts
Applying: edit third-obj.txt
$ git log --oneline
426f3da (HEAD -> test) edit third-obj.txt
3bf5463 edit first-obj.txt
9658fd9 (origin/master, master) Update third-obj.txt
cd6c4c8 (tag: v1.0) second commit
60d16c1 (tag: v0.5, origin/test) first commit
```

### 3.3 Summary

在 merge 冲突时，`HEAD`指针停留在主分支上，未发生冲突的修改加入`index`文件，stage number 为0，发生冲突的修改在`index`文件中有至多三个版本，stage number 为 1, 2, 3，解决冲突后将该文件加入`index`后，git 会删除 stage number 1, 2, 3的文件，当`index`中仅有 stage number 为0的文件时冲突修改完成。

在 rebase 冲突时，若发生冲突前有 k 个 commit 成功 apply，则`HEAD`指针领先主分支 k 个 commit，此时 index 文件记录了发生冲突的 commit 对应的修改信息，这些与 merge 基本一致。

## 4. Git Misc

接下来我们讨论三个杂项，延续上面的仓库状态，在刚刚 rebase 完成后，我们应处于 test 分支。

### 4.1 Git Rename

本节我们讨论 git 底层如何看待文件重命名。我们尝试修改`first-obj.txt`文件

```shell
$ git ls-files -s
100644 db64dd457525358ffc12b5c8b1ddbbe083348f81 0       first-obj.txt
100644 dba11baaee5f17c8e601948dcd01df0369591726 0       third-obj.txt
100644 160e90f4726294335ed5a1bc9a1df91adac181e4 0       tmp/second-obj.txt
$ git mv first-obj.txt first-obj-name.txt
$ git status
On branch test
Your branch is ahead of 'origin/test' by 4 commits.
  (use "git push" to publish your local commits)

Changes to be committed:
  (use "git reset HEAD <file>..." to unstage)

        renamed:    first-obj.txt -> first-obj-name.txt
$ git ls-files -s
100644 db64dd457525358ffc12b5c8b1ddbbe083348f81 0       first-obj-name.txt
100644 dba11baaee5f17c8e601948dcd01df0369591726 0       third-obj.txt
100644 160e90f4726294335ed5a1bc9a1df91adac181e4 0       tmp/second-obj.txt
```

可以看到，`git mv`干的事情本质上是`git rm first-obj.txt; git add first-obj-rename.txt`. 我们关心的是，git 是如何识别文件名被修改了。上面的例子很简单，因为 git 发现对应的 commit object 中哈希值以 db64dd457 开头的文件名为`first-obj.txt`。那如果我们在一次 commit 中又修改文件名，又修改文件内容呢？

```shell
$ echo "new line" >> first-obj-name.txt
$ git add first-obj-name.txt
$ git status
On branch test
Your branch is ahead of 'origin/test' by 4 commits.
  (use "git push" to publish your local commits)

Changes to be committed:
  (use "git reset HEAD <file>..." to unstage)

        renamed:    first-obj.txt -> first-obj-name.txt
$ git ls-files -s
100644 3bf6a18b405a4902f47210d4f957ab2de338a2a6 0       first-obj-name.txt
100644 dba11baaee5f17c8e601948dcd01df0369591726 0       third-obj.txt
100644 160e90f4726294335ed5a1bc9a1df91adac181e4 0       tmp/second-obj.txt
```

有趣的是，即使文件的哈希值变了，git 仍识别出了重命名操作，而不是认为我们删除了`first-obj.txt`后添加了`first-obj-name.txt`。那我们再增大修改幅度？

```shell
$ echo "random txt" > first-obj-name.txt
$ git add first-obj-name.txt
$ git status
On branch test
Your branch is ahead of 'origin/test' by 4 commits.
  (use "git push" to publish your local commits)

Changes to be committed:
  (use "git reset HEAD <file>..." to unstage)

        new file:   first-obj-name.txt
        deleted:    first-obj.txt
$ git reset --hard HEAD  # reset
```

在给`first-obj-name.txt`大变样后，git 就不再识别出重命名操作了。这说明，git 并不会记住操作序列（即`git mv`与`git rm; git add`没有区别），而是基于一种 implicit auto-detection 来识别重命名操作。正如[mailing list](https://sourceware.org/legacy-ml/frysk/2008-q1/msg00004.html)中所谈到的。

### 4.2 Tracking Branch

我们区分 remote-tracking branch 和 tracking branch，前者指的是`refs/remotes/`中的分支，后者指的是`refs/heads/`中的本地分支。如果我们查看`.git/config`会看到

```shell
[branch "test"]
        remote = origin
        merge = refs/heads/test
```

这表明我们的 test 分支是一个 tracking branch，追踪 origin/test 分支。我们也可以稍作修改`git branch -u origin/master test`

```shell
[branch "test"]
        remote = origin
        merge = refs/heads/master
```

这样我们的 test 分支就会追踪 origin/master 分支了，测试完后，使用`git branch -u origin/test test`改回来。

tracking branch 主要帮助我们缩减命令行参数，主要体现在`git push, git pull`上，如果当前所在分支不是 tracking branch，我们需要使用`git push/pull <remote> <branch>`命令，这等价于`git push/pull <remote> <branch>:<remote>/<branch>`。而若当前分支是 tracking branch，我们可以直接使用`git push/pull`，这等价于`git push/pull <tracked-remote> HEAD:<tracked-remote-branch>`

不过`git fetch`指令则总是可以直接使用，如果当前分支不是 tracking branch，`git fetch`等价于`git fetch origin remote.origin.fetch`，其中`remote.origin.fetch`来自于`.git/config`文件，当设置一个远程仓库时，默认`remote.<repo-name>.fetch`为`+refs/heads/*:refs/remotes/origin/*`，这表示 fetch 所有的远程分支

### 4.3 Git Checkout

通常我们在做`git checkout`时，默认认为此时`git status`应该是 clean 状态，但 git 并不要求这一点。有时我们会看到如下报错

```shell
error: Your local changes to the following files would be overwritten by checkout:
      
Please commit your changes or stash them before you switch branches.
Aborting
```

但有时我们又能成功切换，并得到一个 dirty 的工作区

```shell
M       <some-file-name>
M       <some-file-name>
Switched to branch 'master'
Your branch is up to date with 'origin/master'.
```

当我们工作区或暂存区 dirty 的时候进行 checkout ，通常是希望将原分支的修改直接迁移到新分支上，这有点类似于`git stash`，因此我们可以类比`git stash`来理解这一点，当我们 checkout 时，git 会将工作区和暂存区的修改挪到一个临时区域，然后再在新分支上 apply 这些修改，如果 apply 失败，那么 git 就会报错`Your local changes to the following files would be overwritten`。因此如果在 A 分支上的 K 文件和 B 分支上的 K 文件相同，然后在 A 分支上对 K 文件修改后，马上 checkout 到 B分支，这些修改就会被 apply 到 B 分支上。

## 5. Git Submodule

懒得写了。提几点核心的吧

* `.gitmodules`中记录了所有的子模块，每个子模块有两个关键属性，子模块 url，子模块在父模块中的路径（名字）
* 子模块中不再有`.git`目录，取而代之的是`.git`文件，`.git`文件中记录了该子模块的`.git`在哪，通常位于父模块的`.git/modules/<submodule-path>/`中。因此父模块的`.git`目录包含了所有数据信息
* 在子模块路径中所有 git 指令正常使用，并不意识到父模块的存在。
* 在父模块中只记录子模块的 commit object 哈希值。如果使用`git cat-file`逐级追查，会发现父模块的 commit object 对应的 tree object 将子模块所在的目录整体记为一个 commit object，而这个 commit object 的 哈希值表示父模块追踪的子模块的版本，而在父模块的`.git/objects/`目录中并不存在对应哈希值的文件。
* `git submodule init`的作用在于将需要的子模块注册进`.git/config`文件，以后的`git submodule update/foreach`都只作用在`.git/config`中的子模块
* `git submodule update`的作用在于根据指定的动作更新子模块，默认的动作是 checkout，即将子模块切换到父模块追踪的版本上。也可以使用`--merge / --rebase`选项，将远程仓库最新的修改合并到本地
* 许多 git 指令有`--recurse-submodules`选项，例如`git push/pull/checkout`，表明相应的指令也在子模块中执行。**最重要的是`git checkout`，因为如果不加`--recurse-submodules`选项，切换到新分支后不会自动将子模块 checkout 到新分支追踪的子模块版本 ，导致得到一个 dirty 的工作区**。

## 6. Others

一些其它还没说到的 git 特性

* **git garbage collection**
* **git packfiles**
* ....

## 7. Refs

* [git rename](https://sourceware.org/legacy-ml/frysk/2008-q1/msg00004.html)
* [What is the point of 'git submodule init'?](https://stackoverflow.com/questions/44366417/what-is-the-point-of-git-submodule-init)
* [git-index-format](https://git-scm.com/docs/index-format)
* [gitreopsitory-layout](https://git-scm.com/docs/gitrepository-layout)
* [Git Internals](https://git-scm.com/book/en/v2/Git-Internals-Plumbing-and-Porcelain)
* [git-rebase](https://git-scm.com/docs/git-rebase)

