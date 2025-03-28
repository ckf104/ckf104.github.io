主要参考了 [Code vs Data Driven Displacement](https://theorangeduck.com/page/code-vs-data-driven-displacement) 以及它的代码
### Database
database 的输入
* 骨骼结构
* 每段动画的每个关键帧中的骨骼位置，旋转

计算产生的额外信息
* 骨骼的速度和角速度
* contact states

TODO：contact states 是什么，骨骼的速度和角速度这些是怎么算出来的，看看 generate_database.py, 以及根骨骼以外的骨骼的速度和角速度有什么用

feature 的选择
* 左脚和右脚的位置
* 左脚，右脚的速度，hip 的速度
* 未来的 root position 偏移轨迹和 root rotation 偏移轨迹，这里取的是这个动画 20 帧，40 帧，60 帧以后相对于当前的 position，rotation 的变化值
### Character Controller
定义 backward, side, forward movement 的速度，根据用户输入和当前的 character 的姿势，以及摄像机的角度确定角色接下来的移动方向，根据移动方向得到 desired velocity，也同时得到 desired rotation

desired velocity 和 desired rotation 是根据用户输入会发生突变的。下一层是 simulation velocity 和 simulation rotation，它根据弹簧振子模型，对 desired velocity 和 desired rotation 进行了平滑处理

TODO：没看懂为啥弹簧振子模型可以应用于四元数的平滑过渡

simulation position / velocity / rotation 这些都是表征 simulation object 的信息。如果我们假定未来用户的输入不变，那么可以根据我们的 simulation bone 进一步地预测接下来一段时间 simulation object 的轨迹，这称为 simulation trajectory

动画这一侧则有 Simulation Bone，相应的 bone position / velocity / rotation 则表征了屏幕上渲染的动画角色当前的移动和朝向等信息。我的理解是根据动画中 root motion 的信息来进行 Simulation Bone 的模拟，然后我们知道接下来顺序播放的动画 pose 是什么，根据接下来的动画 pose 的 root motion 信息，我们也可以得到相应的 bone trajectory

关于初始的 desired velocity 和 desired rotation 等变量的确定。文中是根据数据库中 Simulation Bone 中前向，侧向，倒退的运动速度分布以及转向的角速度分布，来确定各个方向的 desired velocity 的值以及转向的角速度，然后我们可以根据用户输入模拟 simulation object 的运动，收集 simulation object 运动时的速度和角速度信息，并与数据库中的数据分布进行对比，如果重合度比较高那么这个配置就是合理的
### Synchronization
每次我们在 database 选择出的 bone position / rotation 可能不会完美地匹配到 simulation position / rotation。因此 bone position / rotation 与 simulation position / rotation 总会存在一定的偏差。如果偏差过大，我们可能会希望做一些同步，把 bone 的位置拉到 simulation 的位置或者把 simulation 的位置拉到 bone 的位置

假设我们选取好了同步位置 synchronized position 和 同步朝向 synchronized rotation，simulation object 同步到这里很简单，直接赋值即可
```c++
    simulation_position = synchronized_position;
    simulation_rotation = synchronized_rotation;
```
但 bone 的同步稍微有些复杂。这里涉及到下面的六个变量
* `transition_src_position` 和 `transition_src_rotation`：这是上一次发生 transition 时从 database 中取出的 pose 的 bone position / rotation，后续的 pose 提取的 root motion 信息都要转化为相对于 `transition_src_position` 和 `transition_src_rotation` 的位置偏移和旋转
* `transition_dst_position` 和 `transition_dst_rotation`：这是上一次发生 transition 时的 bone position / rotation，提取出的相对于 `transition_src_position` 和 `transition_src_rotation` 的位置偏移再通过 `transition_dst_rotation` 转化到世界坐标，然后位置和旋转再分别叠加上 `transition_dst_position` 和 `transition_dst_rotation`
* `bone_positions` 和 `bone_rotations`，当前 bone 的位置和朝向

现在我们希望将 `bone_positions` 和 `bone_rotations` 设置为 `synchronized_position` 和 `synchronized_rotation`，那其余四个变量应该如何处理呢？

直接的想法可能是，`transition_src_position` 和 `transition_src_rotation` 不变，我们将 `transition_dst_position` 和 `transition_dst_rotation` 同步地增加上这个变换值。即
```c++
void inertialize_root_adjust(
    vec3& offset_position,
    vec3& transition_src_position,
    quat& transition_src_rotation,
    vec3& transition_dst_position,
    quat& transition_dst_rotation,
    vec3& position,
    quat& rotation,
    const vec3 input_position,
    const quat input_rotation)
{
    // Find the position difference and add it to the state and transition location
    vec3 position_difference = input_position - position;
    position = position_difference + position;
    transition_dst_position = position_difference + transition_dst_position;
    
    // Find the rotation difference. We need to normalize here or some error can accumulate 
    // over time during adjustment.
    quat rotation_difference = quat_normalize(quat_mul_inv(input_rotation, rotation));
    
    // Apply the rotation difference to the current rotation and transition location
    rotation = quat_mul(rotation_difference, rotation);
    transition_dst_rotation = quat_mul(rotation_difference, transition_dst_rotation);
}
```
但仔细一下这有问题，回顾一下 bone 的位置是如何更新的
```c++
    vec3 world_space_position = quat_mul_vec3(transition_dst_rotation, 
        quat_inv_mul_vec3(transition_src_rotation, 
            bone_input_positions(0) - transition_src_position)) + transition_dst_position;
```
这里的逻辑是将 `transition_src_rotation` 朝向的 root motion 更新到 `transition_dst_rotation` 朝向的 bone 中。但现在
`transition_dst_rotation` 发生了突变，这导致我们最终计算出的 bone position 不是预期的 `synchronized_position`（计算一下会发现，rotation 不会受到影响，它会被更新到预期的 `synchronized_rotation`

一个可能的解决办法是，我们对 `transition_src_position` 的值进行调整，来抵消掉 `transition_dst_rotation` 的值变化带来的影响。Holden 的代码中的做法是根据突变后的 bone 位置计算新的 `transition_src_position` 和 `transition_src_rotation`
```c++
void inertialize_root_adjust(
    vec3& offset_position,
    vec3& transition_src_position,
    quat& transition_src_rotation,
    vec3& transition_dst_position,
    quat& transition_dst_rotation,
    vec3& position,
    quat& rotation,
    const vec3 input_position,
    const quat input_rotation)
{
    // Find the position difference and add it to the state and transition location
    vec3 position_difference = input_position - position;
    position = position_difference + position;
    transition_dst_position = position_difference + transition_dst_position;
    
    // Find the point at which we want to now transition from in the src data
    transition_src_position = transition_src_position + quat_mul_vec3(transition_src_rotation,
        quat_inv_mul_vec3(transition_dst_rotation, position - offset_position - transition_dst_position));
    transition_dst_position = position;
    offset_position = vec3();
    
    // Find the rotation difference. We need to normalize here or some error can accumulate 
    // over time during adjustment.
    quat rotation_difference = quat_normalize(quat_mul_inv(input_rotation, rotation));
    
    // Apply the rotation difference to the current rotation and transition location
    rotation = quat_mul(rotation_difference, rotation);
    transition_dst_rotation = quat_mul(rotation_difference, transition_dst_rotation);
}
```
新的 `transition_dst_position` 就是 `synchronized_position`，而新的 `transition_src_position` 则是当前帧动画的本来 pose（计算新的 `transition_src_position` 的逻辑与计算 `world_space_position` 的逻辑正好相反）。虽然我觉得因为 `bone_offset_rotations` 的存在，为了保证准确的话，rotation 应该做同样的处理，然后将 `bone_offset_rotations` 置为单位旋转

