主要参考了 [Code vs Data Driven Displacement](https://theorangeduck.com/page/code-vs-data-driven-displacement)
### Database
database 的输入
* 骨骼结构
* 每段动画的每个关键帧中的骨骼位置，旋转，以及骨骼的速度和角速度
* contact states

TODO：contact states 是什么，骨骼的速度和角速度的作用
### Character Controller
定义 backward, side, forward movement 的速度，根据用户输入和当前的 character 的姿势，以及摄像机的角度确定角色接下来的移动方向，根据移动方向得到 desired velocity，也同时得到 desired rotation

desired velocity 和 desired rotation 是根据用户输入会发生突变的。下一层是 simulation velocity 和 simulation rotation，它根据弹簧振子模型，对 desired velocity 和 desired rotation 进行了平滑处理

TODO：没看懂为啥弹簧振子模型可以应用于四元数的平滑过渡


Simulation Bones
bone_rotations(0), bone_positions(0)