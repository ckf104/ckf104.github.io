## Transform Matrix

UE 中使用的投影矩阵是 Reversed Z Perspective Matrix，看下面函数的实现就知道了

```c++
FMinimalViewInfo::CalculateProjectionMatrix();
```

另外，虽然 TMatrix 是声称行主序，但实际上变换矩阵初始化时总是把列放在行的位置（见 PerspectiveMatrix.h 中的矩阵初始化），因此实际上 TMatrix 是列主序的（这也解释了为什么 FViewMatrices::Init 函数中变换矩阵是右乘的，例如要得到 view_project 的综合变换矩阵，UE  中是 view x project 而不是通常的 project x view）

TODO：ue 的摄像机 lookat 的方向是哪个？+Z 轴，-Z 轴，还是表示 forward 的 X 轴？

ue 使用左手坐标系，X 轴对应 Forward Vector，Y 轴对应 Right Vector，Z 轴对应 Up Vector

## Rotation

`TRotator<T>` 中存储的是基本的欧拉角 Yaw，Pitch，Roll，并且是 intrinsic rotation（即旋转是相对物体自身的坐标系），**具体的角度正方向规定在 `Rotator.h` 中解释得很清楚：按照 Yaw，Pitch，Roll 的顺序，先顺时针沿着 -z 轴转（在 +z 轴的位置，看向 -z 轴），再逆时针沿着 -y 轴转，最后逆时针沿着 -x 轴转**

四元数在 ue 中对应 `TQuat` 结构，注意 W 对应的是实数分量，而 X，Y，Z 分别对应 i，j，k 分量。由于 ue 使用的左手坐标系，因此一些公式会和网上看到的有些不太一样，例如四元数转旋转矩阵的函数 `TQuat<T>::ToMatrix`，左手坐标系得到的旋转矩阵是右手坐标系的旋转矩阵的转置

## Camera and Transformation

* `SceneComponent` 的结构：
  * `SceneComponent` 可以通过父子节点关联，整个 Actor 的 `SceneComponent` 呈现树状结构。每个 `SceneComponent` 的 `RelativeLocation`，`RelativeRotation` 和 `RelativeScale3D` 默认情况下是相对父节点来说的（除非设置 `bAbsoluteLocation` 等为真），而 `ComponentToWorld` 参数则表示相对于世界的变换
  * 一个父节点的变换矩阵改变会带来子节点的相应改变，即父 `SceneComponent` 移动会带动子 `SceneComponent` 的移动（除非 `bAbsoluteLocation` 等参数全部设置为真，此时该子 `SceneComponent` 完全独立），典型的从 `SetActorRotation` 追溯可以看到。当父节点的  `ComponentToWorld` 变化后，虽然子节点的 Relative Transform 不会发生变化，但是需要递归地修改子节点的 `ComponentToWorld`
  * TODO：我看 Relative Transform 总是和 ComponentToWorld 同步更新？那这个 Relative Transform 有什么作用呢？什么时候单独的 Relative Transform 能拿出来有用？
* `ViewTarget` 中的 target 和 POV 的关系是什么
* 对 `SpringArmComponent` 的理解：在 [Player-Controlled Cameras](https://dev.epicgames.com/documentation/en-us/unreal-engine/quick-start-guide-to-player-controlled-cameras-in-unreal-engine-cpp) 教程中，对 SpringArm 调用了 `SetRelativeLocationAndRotation` 方法。这个方法其实来自于 `SceneComponent`，设置 `Component` 和父节点的相对位置。`SpringArmComponent` 则是 `SceneComponent` 的子类。我理解的 `Location` 和 `Rotation` 对于 `SpringArm` 的含义是看的对象的位置，以及看的角度。而配置参数 `socket offset`，`target offset` 则是对其的微调，见 [UE SpringArm TargetOffset 和 SocketOffset 区别](https://www.bilibili.com/read/cv14318016/)
  * 那将一个 `CameraComponent` attach 到 SpringArm 上又如何呢？[UE4 里的 Camera 系统](https://zhuanlan.zhihu.com/p/149176416) 中讨论说，`APlayerCameraManager` 里的 `ViewTarget` 中 Actor 作为观察的对象，`FMinimalViewInfo` 是根据 Actor 计算出的相机数据，其中调用了 Actor 的 `CalcCamera` 方法，在 `CalcCamera` 实现中，会检索 Actor 是否存在 `CameraComponent`，如果存在，那么将使用该 `CameraComponent`，调用它的 `GetCameraView` 方法。该方法将 `CameraComponent` 的位置和朝向作为摄像机的位置和朝向。而 `CameraComponent` 作为 `SceneComponent`，只存储相对的位置和朝向，会调用父节点 `SpringArmComponent` 的 `GetSocketTransform` 方法来计算自己在世界坐标中的位置和朝向。该方法默认情况下直接返回节点的 Transform，但 `SpringArmComponent` 重载了该函数，返回的 Transform 会额外乘 `RelativeSocketRotation` 和 `RelativeSocketLocation` 对应的变换。这俩参数的值是用 `TargetArmLength`，`TargetOffset`，`SocketOffset` 等 SpringArm 的参数进行控制