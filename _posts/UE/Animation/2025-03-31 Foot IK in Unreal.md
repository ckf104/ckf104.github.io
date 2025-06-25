参考了第三人称模板以及 [玩转UE4/UE5动画系统 之 Control Rig + Fullbody IK版的足部IK实现](https://zhuanlan.zhihu.com/p/412251528) 中的实现

基本的 Foot IK 思路是这样：
* 两只脚各自向下做 line trace 或者 sphere trace，找到脚应该落在的平面的位置（注意，输入输出都应该转换到 model space 下）
* Pelvis 向下移动，使得 root 抵达较低的平面
* 脚的 target z 设置为脚做 IK 前的 z 值加上脚应该落在的平面的 z 值
* 以两只脚的 target position 作为 IK 的 end effector 进行 IK 解算

注意如果脚的 target z 直接设置为平面的 z 值，会导致平面移动时脚锁在地上。将脚的 target z 设置为脚做 IK 前的 z 值加上脚应该落在的平面的 z 值，就是说做 IK 前后，脚相对于地面的高度保持不变：原来在平地上这个 pose 左脚离地 20 厘米，那么在台阶上左脚的 target z 也设置为比它所在的台阶高 20 厘米

具体在实现上可能有一堆的 trick
* pelvis 向下移动的距离以及实际选取的脚做 IK 的 end effector，可以通过插值实现平滑过渡
* 保证 IK 前后脚相对地面的高度不变这个属性也不见得总是好的，比如我们上楼梯的时候，如果动画的步子迈得比较大，可能导致前后两个脚的 target z 差值很大，显示的姿势就很不协调。所以这里 trace 的时候需要一个 clamping，例如后脚当前的 z 值距离平面的 z 值太大了，就不要把后脚往下拉了（而这又可能导致抖动，前一帧的 target z 可能在下方，后一帧由于超过了阈值导致 target z 一下就跃变上去了，因此也需要插值来平滑过渡），总之需要限制前后脚的高度差不能太大，例如也可以说前脚的平面越高，脚的 target z 相对于平面的高度就设置得越小等等
* 基本的 Foot IK 思路是保证角色在平面移动时 root 的位置锁在地上，因此这个 IK 适用于角色在平面上移动的情况，不会导致脚锁在地上。但是不适用于角色跳跃的情况（因为跳跃时 root 是需要离地的），因此跳跃时需要关闭 IK。从做 IK 的 pose 过渡到不做 IK 的 pose 也有一个插值。在 [玩转UE4/UE5动画系统 之 Control Rig + Fullbody IK版的足部IK实现](https://zhuanlan.zhihu.com/p/412251528) 中是通过 animation curve 来实现的，这个 curve 表示 IK pose 和非 IK pose 混合的 alpha 权重。平面移动的 curve 值恒为 1，而跳跃动作的 curve 值恒为 0。UE 在混合 pose 时会自动地混合对应的 curve 值
* 另外还有 foot rotation，我们希望脚板的法线和平面的法线平行，但显然我们也不希望移动时每时每刻脚的朝向和平面一致。在 [玩转UE4/UE5动画系统 之 Control Rig + Fullbody IK版的足部IK实现](https://zhuanlan.zhihu.com/p/412251528) 中是当速度大于 1 时就不调整 foot rotation。这个感觉过于粗暴了。一个可能的想法是说也根据脚离平面的高度来调整，离平面越近调整 foot rotation 的幅度就越大之类的