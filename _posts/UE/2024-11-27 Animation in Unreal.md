TODO：理解第一人称模板中的 Animation Blueprint
TODO：理解第三人称模板中的骨骼动画
### Vertex Animation Basics
参考了视频 [VAT 1 | What are Vertex Animation Textures](https://www.youtube.com/watch?v=3ep9mkwiOjU) 和文章 [Texture Animation: Applying Morphing and Vertex Animation Techniques](https://medium.com/tech-at-wildlife-studios/texture-animation-techniques-1daecb316657) 这篇文章中还额外谈到了 animation blending 的问题

vertex animation 可以理解为二维的纹理动画在三维中的自然推广。它通过 vertex animation texture 存储了物体在每一个关键帧中的顶点坐标位置
### Skeletal Animation Basics
主要参考了一下 [learn opengl 骨骼动画](https://learnopengl-cn.github.io/08%20Guest%20Articles/2020/01%20Skeletal%20Animation/) 的实现，以及 [Thread: [Assimp-discussions] Nodes and Bones](https://sourceforge.net/p/assimp/mailman/assimp-discussions/thread/op.vmrwicttou3nzj%40flachzange/#msg26657996) 和 [can't get bones/skinning to work](https://sourceforge.net/p/assimp/discussion/817654/thread/5462cbf5/)

第一个需要理解清楚的事情是如何根据 bone matrix 和 node matrix 得到当前动画的顶点的坐标。当我们不使用 bone matrix 和 node matrix，直接使用原始的模型坐标时，渲染出来的图像是默认的模型位姿

node，也称为 joint，表示了树状的骨骼层级结构。每个 node matrix 是子关节相对于父关节需要做的变换。而 bone matrix 将模型顶点从 model space 变换到 bone space。每个 bone 有唯一的一个 node 与之对应。因此属于某个 bone 的顶点在动画播放时的变换矩阵为
```
final_matrix = root_node_matrix * child1_node_matrix * child2_node_matrix * ... * childN_node_matrix * bone_matrix
```
第二个需要理解清楚的事情是一个顶点可能属于多个 bone。我的理解是，对于人和动物的骨骼而言，joint 处的顶点归属不可能分得特别清楚。例如手腕旋转时手臂上靠近手腕的顶点多多少少会受到一些影响，而不可能保持完全的静止。因此让关节附近的顶点属于多个 bone 来创造渐变的过渡（不过对于机器人之类的建模可能就不需要这种过渡了）。一个顶点属于若干个 bone，然后我们为这个顶点属于的每个 bone 分配一个权重，这些权重的和为 1。例如随着手臂上的顶点离手腕越来越远，手腕骨骼的权重就越来越小

最后我们顶点的计算公式为
```
final_vertex = final_maxtrix1 * w1 + final_maxtrix2 * w2 + ... + final_maxtrixN * wN
```
我们考虑一个手臂上的三角形，它们都被手臂骨骼和手腕骨骼影响，但各自的权重分配并不相同。请注意，当手臂关节或者手臂关节更上层的关节运动时，这个三角形顶点之间的相对位置不会发生变化，因为手臂关节或者手臂关节更上层的关节运动会对 `final_matrix1` 和 `final_matrix2` 产生同样的影响。但是如果手腕关节运动了，此时 `final_matrix1` 不变，而 `final_matrix2` 变化，由于它们在手腕骨骼上的权重不相同，这个三角形不可避免地会发生形变。但这种形变是可以接受的，因为人和动物在关节运动处的皮肤也会有形变
### Animation Blending
TODO：当游戏中播放人物移动的动画时，假设此时人物又需要跳起来，如何平稳地从一个动画切换到另一个动画。通常制作的动画会使得开始和结束的位姿相同，这样所有的动画公用一个初始位姿的话，就可以在一个动画播放完成后流畅地切换到另一个动画上去，但如何从一个动画的中间切过去呢？