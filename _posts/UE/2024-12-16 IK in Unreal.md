### Blending
时长对齐：ozz animation 中选择的时长是加权混合的时长

blending 的输入：每个需要混合的 pose，pose 每根骨骼的混合权重。对于普通的 blending，同一个 pose 每根骨骼的混合权重是相同的，但 partial blending 中不同骨骼可能采取不同的混合权重。ozz animation 中 rotation 的 blending 是直接使用线性插值实现的
additive blending 的输入和通常的 blending 类似，只是它有一个基础的 ref pose，然后是其余的 additive pose，每个 additive pose 也可以逐骨骼都有不同的权重，也可以整个 pose 使用一个统一的权重，另外就是这里的权重可以为负数，对应的就是 negative blending。additive / negative blending 只是在混合公式上和普通的 blending 不一样。以线性插值 rotation 的混合为例
```c++
out_r = ref_r * w + add_r * (1-w)  // 通常的 blending
additive_out_r = ref_r * add_r * w + ref_r * (1-w) = ref_r * (add_r * w + (1 - w)) // additive blending
negative_out_r = ref_r / (neg_r * w + (1 - w))   // negative blending
// 不太清楚为啥 ozz animation 中 negative blending 是这样混合的，我会预期下面的结果
// negative_out_r = ref_r * (w / neg_r + (1 - w))
```
### User Channel
[user channel example](https://guillaumeblanc.github.io/ozz-animation/samples/user_channel/) 就是 keyframe 中保存数据的一个推广吧，之前 keyframe 中保存各个 joint 的 transform，那我也可以保存一些其它的东西，然后通过插值来获得额外的一些连续的信息。有意思的是，对于 triggering 类型的信息，例如例子中的 attach，如果为了避免误差，需要计算出 triggering 发生的准确的时间点，而不是直接使用当前的时间。比如这里的 attach，如果我们在每一帧当前的时间进行采样，判断当前的值是否发生了 trigger，由于实际的 trigger 时间可能发生在前一帧和当前帧之间的时间里，用当前时间的 joint transform 去计算木板的 local transform 就会引入误差
### Phyiscal Baked Animation
[Baked physic simulation](https://guillaumeblanc.github.io/ozz-animation/samples/baked/) 和前面的 user channel 的例子很类似，这里是将每个刚体物体的移动都作为一根骨骼嵌进去了，然后骨骼在每个关键帧的 transform 作为该刚体物体的 transform
### Root Motion
第一个事情是 root motion 存储在 root transform 中，第二个事情是在 blending 时 root motion 也需要混合
### Two Bone IK
参与 two bone ik 的共有三根骨骼，start, middle，end，它的目标是旋转 start 和 middle 这两根骨骼，使得 end 骨骼达到要求的位置。如果不加约束的话，这里有 6 个自由度，但只有三个方程约束。通常我们会对 middle 骨骼进行限制，它只能绕着一个固定的轴旋转，这个轴是垂直于默认位姿中 start - middle 向量（表示起始点为 start，终点为 middle 向量）和 middle - end 向量构成的平面的向量（我们称这个轴为 middle axis），因此 middle 骨骼只有一个自由度。这样只剩下四个自由度了。对于人体的手臂和腿来说，这样的约束是非常合理的

我们记两根骨骼长度为 lsm, lme，可以想象一下，如果这四个自由度没有任何范围约束的话，那么这两根骨骼的末端点能够取遍所有的，到 start 关节的距离在范围 `[|lsm-lme|, lsm + lme]` 中的点，并且对于任意一个解，我们可以绕着 start joint 到 target 这根轴旋转，生成其它所有的解，start, middle, target 三个点的两两距离都是知道的，然后运用余弦定理就可以解出它们的角度关系。而绕着 start joint 到 target 这根轴旋转时不改变它们相对的角度关系

那么应该取这个圆盘上的哪一个解呢？首先不是所有的解都是好的，我们应该取使得关节朝向最自然的点，不过这没有一个明确的标准，因此我们要求在求解时提供一个 pole vector，最终解出的 start, middle, end 三点构成的平面需要平行于 pole vector。这样满足要求的解就只剩下两个了，又因为平行这个平面的 pole vector 还有正负两个，因此根据 pole vector 的取值又排除了一个，就得到最后满足要求的解了。从几何意义上来说，用腿部的 two bone 来举例的话，pole vector 指定了解对应的骨骼位姿的膝盖的朝向

但仔细一想会解其实还没有完全确定下来，因为如果 middle 骨骼可以绕着 middle axis 360 度旋转的话，那么与 start 骨骼满足夹角约束的 middle 骨骼是有两处的。因此我们将 middle 骨骼的旋转范围限制为 +0 到 +180 度。对于人体的手臂和腿来说，这样的约束是同样是非常合理的，并且在有这个约束时，解同样能够取遍距离 start 关节在的距离在 `[|lsm-lme|, lsm + lme]` 中的点。那如何规定 start 骨骼的哪一侧的夹角为正，哪一侧为负呢？同样地，由于 middle axis 有正负两个，因此我们可以根据 middle axis 的朝向约定正负即可

#### 具体实现
我们用 [ozz::animation::IKTwoBoneJob](https://guillaumeblanc.github.io/ozz-animation/documentation/ik/) 的实现来做一个说明的例子。它的 IK Two Bone Job 除了接收我们上面提到的 target，mid axis，pole vector 外，还接收 `weight` 和 `soften` 这两个额外的参数
```c++
  // Soften ratio allows the chain to gradually fall behind the target
  // position. This prevents the joint chain from snapping into the final
  // position, softening the final degrees before the joint chain becomes flat.
  // This ratio represents the distance to the end, from which softening is
  // starting.
  float soften;

  // Weight given to the IK correction clamped in range [0,1]. This allows to
  // blend / interpolate from no IK applied (0 weight) to full IK (1).
  float weight;
```
IK Two Bone Job 返回的是在 local space 下对 start 和 middle 关节进行修正的一个四元数旋转。这里的 `weight` 就是用来将这个修正位姿的四元数旋转和 identity 进行插值，以此实现一个渐变的效果。`soften` 也是用来做一个渐变，如果 `soften` 值如果小于 1，那么 target 比较靠近 `lsm + lme` 这个边界距离时就会让解出的骨骼位姿稍微弯一点，这样 end 点会处于 start 和 target 直线上靠近 target 的一个位置，这样随着 target 越来越远，解出来的 start，middle 骨骼逐渐打直，这样展现出的动画效果更加柔和。`soften` 等于 1 的时解出来的位姿就是 end 能和 target 重合就重合，如果 target 太远或者太近，那么解出的 start 和 middle 骨骼就在一条直线上

middle correction 是很容易确定的，根据余弦定理解出的夹角，可以算出 middle 关节需要旋转多少度（如果 target 取不到，那么将得到的余弦值截断在 0，1 范围即可），由此得到一个绕着 middle axis 旋转的四元数就是我们要的 middle correction。在 ozz animation 的实现中，start - middle 向量叉乘 middle axis 得到的向量的方向为 +90 度夹角的方向

代码中确定 start correction 的方法我觉得挺巧妙的。它将这个 correction 拆分为两步旋转，第一个四元数旋转将当前的 start - end 向量旋转至与 start - target 向量平行。这样做的效果是，如果这个 target 是能够取到的，那么这个旋转叠加上 middle correction，我们就保证了 end joint 已经与 target 重合了，而如果 target 取不到，也保证了 start，end，target 三点共线，这也是一个视觉上看着还行的结果。第二个四元数旋转是将当前 start, middle, end 三点构成的平面旋转为 pole vector 与 start - end 向量构成的平面。这个旋转的轴就是 start - end 向量。旋转的度数由两个平面的法线夹角决定

其中一个 corner case 是 start, middle，end 三点共线，看起来就没办法确定平面了。但由于我们天然地有这个平面的法线 middle axis，所以这不是什么问题。另一个 corner case 是 start 和 target 重合，此时我们解出的 middle correction 会将 middle 关节的夹角修正为 0 度。这时 start - target 向量为零向量，可以直接取 start correction 为 identity（因为确实也不用再做其它的修正了）
### Foot IK
记录一下 ozz animation 的 [fook ik sample](https://guillaumeblanc.github.io/ozz-animation/samples/foot_ik/) 是如何实现的。foot ik 是 two bone ik 的直接应用，不过有额外的一些处理细节
* 动态调整人物高度：比如上台阶或者斜坡，需要将 root 的位置动态调整到台阶上的位置，来实时匹配人物的真实所在高度。如何知道该提高多少高度呢？[fook ik sample](https://guillaumeblanc.github.io/ozz-animation/samples/foot_ik/) 里的做法是先将 root 的高度提高 character ray height 这个预设的高度值，然后再向下做 ray cast，求出 ray 与台阶的交点，然后将 root 下移动至这个交点即可。这个方法感觉有点 hacking，我估计 ue 里应该不会这么做
* 计算 ankle target 的坐标。[fook ik sample](https://guillaumeblanc.github.io/ozz-animation/samples/foot_ik/) 里同样是将当前的 ankle 往上抬 foot ray height 这个预设的高度值，然后向下做一个 ray cast，求出与台阶的交点。这个我倒觉得没有那么 hacking，因为此时已经将人物的高度动态调整到台阶上了，此时 angle 即使陷入台阶里，也不会陷入太多，因此 foot ray height 取一个较小的值就行了。但需要额外注意的是，ankle 是有实际大小的，我们不会将 ankle target 直接设置为 ray cast 得到的交点坐标，否则渲染出来，脚有一部分就陷到台阶里面了。我们可以把 ankle 看作一个长方体，长方体的长宽构成的面就对应脚板的平面，而长方体的高就对应足部的高度。然后我们设置的 ankle target 会从交点处往上抬一些，使得它与交点的距离在交点处法线方向的投影长度等于足部高度。这样后续调整 ankle 的 rotation 使得脚板平面与交点法线垂直后，整个足部就紧贴地面了
* 下放人物高度。一只脚可能踩着低一级的台阶，如果 root 的高度比 ankle target 还高了，那么这只脚就没办法踩到台阶上了。因此这里会将人物的高度下放至最低的 ankle target 处（不过下放的是渲染的位置，碰撞检测的 root 位置还是在台阶上的，至少 ue 里面表现是这样）
* 接下来就是做 two bone ik，将两只脚的位置分别调整至 ankle target 处
* 最后是做 ankle rotation，将 ankle 的脚板与交点平面对齐。具体脚板平面在哪依赖于 skeleton 的设置。通常是 ankle 的 local space 的 x 轴为脚板平面的法线（感觉就跟 middle bone 的 z 轴是 middle bone 的旋转轴一样可能是默认的习惯吧）

做 ankle rotation 时 ozz animation 用了一个 look at 的概念。我觉得这是更宽泛的东西，在这个 job 中，指定关节当前的 forward（look at）方向，以及需要看向的 target 位置，这个 job 返回一个 rotation correction，它会将当前的 look at 方向旋转至与 joint - target 向量平行（joint 看向 target）。为了保证结果唯一，还需要指定当前的 up 方向以及希望的 up 方向，rotation correction 会保证旋转后的 up 方向与希望的 up 方向，以及 joint - target 向量三线共面。job 还可以指定一个 offset 参数，这样最终旋转的结果不再是 joint 看向 target，而是 offset 指定的位置看向 target。对于 ankle rotation 这个任务来说，ankle 关节当前的 forward 方向就是脚板的法线，然后它需要看向的方向就是交点的法线方向

TODO：ue 里是如何动态调整人物所在的高度的？如何设置人物能跨过的最大台阶高度？看起来 ue 在动态调整高度时还做了插值的，就是 root 的高度看起来可以介于地板和台阶之间（把碰撞检测的胶囊体显示出来就看得清楚了）来实现一个平滑的过渡，这里的实现细节是怎样的？
TODO：如何处理台阶点太高的情况？就是说人物向前检测到一个碰撞，首先需要判断这个障碍能不能跨越过去（如何获取障碍的高度？对于一次性的刚体障碍，它的高度可以预先计算？但对于斜坡应该如何处理，如何知道该跨多高的距离），如果不能跨过去，那就UE 里台阶过高时还能播放原地走的动画，这是如何做到的？
TODO：第三人称模板中，人物能直接跨过的台阶和能够弯腿的台阶高度是不一样的，为什么？感觉这中间存在一个过渡态，就人物在高台阶的位置弯腿时，甚至人物都已经判定从高台阶处落下来了，但还是能马上转身返回高台阶处，而正常走的话是没办法直接跨过这个高台阶的（把用于碰撞检测的胶囊体显示出来就清楚了，此时这个胶囊体还在台阶上）。而且这个过渡态有时还会把人物的部分卡在墙里，这又是为什么（看起来问题好像是模板中的人物只有右脚做了 IK，左脚没有做 IK）
### Look At IK
TODO
### Skinning
[skinning sample](https://guillaumeblanc.github.io/ozz-animation/samples/skinning/) 的启发在两个地方。一个是人物布料和脸部的动画，照样可以在布料和脸部布置骨骼，然后生成动画，虽然模拟起来需要的骨骼数可能会比较多。第二个是 skeleton sharing，在加载这个人物 mesh 时，这个人物实际上是由许多 mesh 共同组成的，例如头发是一个 mesh，披风是一个 mesh，人物是一个 mesh，武器是一个 mesh，这些 mesh 依附的骨骼实际上是整个 skeleton 的骨骼的一个子集，并且结构与 skeleton 的骨骼保持一致。因此这些 mesh 就共享一个 skeleton。结构一致的判定标准可以参考 ue 的 [sharing skeleton](https://dev.epicgames.com/documentation/en-us/unreal-engine/skeletons-in-unreal-engine#sharingskeletons) 文档