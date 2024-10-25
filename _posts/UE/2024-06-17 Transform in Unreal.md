TODO：弄清楚 transformation，四元数的乘法

三维坐标系中叉乘的定义依赖于坐标系的手系，如果是右手坐标系用右手定则确定叉乘向量的方向，而如果是左手坐标系则用左手定则。这样叉乘的计算公式不依赖于手系选择。

[Krasjet：四元数与三维旋转](https://krasjet.github.io/quaternion/quaternion.pdf) 有详细的关于四元数旋转的推导。我这里仅列出一些核心的结论

Theorem 10: 向量 $\boldsymbol{v}$ 沿着以单位向量定义的旋转轴 $\boldsymbol{u}$ 旋转 $\theta$ 度之后的 $\boldsymbol{v}^\prime$ 可以用四元数乘法获得。令 $v = [0, \boldsymbol{v}]$，$q=[cos\frac{\theta}{2},sin\frac{\theta}{2}\boldsymbol{u}]$，有 $$
\boldsymbol{v}^\prime = qvq^* = qvq^{-1}
$$注意，这是在右手坐标系下，以右手定则定义旋转正方向（即从向量指着的方向，往回看，逆时针旋转为正）得到的结果。我们可以进一步得到两个推论
* 单位四元数和 3D 旋转是一个双倍覆盖（因为 $q$ 和 $-q$ 对应同一个旋转）
* 将四元数旋转 $q1$ 和 $q2$ 进行复合，先进行 $q1$ 旋转，再进行 $q2$ 旋转。这个复合的旋转可以用 $q2*q1$ 来表示（直接验算可知，$|q2*q1| = |q2|*|q1|$，因此 $q2*q1$ 仍然是单位四元数
那我们可以进一步问，右手坐标系下，使用左手定则定义旋转正方向（即从向量指着的方向，往回看，顺时针旋转为正）的结果呢？这个比较简单，这只是旋转的正方向改了，现在应该用 $-\theta$ 代替 $\theta$，在 $q$ 的定义不变的情况下，此时有 $v^\prime = q^*vq$
更进一步的是左手坐标系下，左手定则定义旋转正方向呢，它的公式与右手坐标系，右手定则定义正方向的结果一致。那显然左手坐标系下，右手定则定义旋转正方向的结果与右手坐标系下，使用左手定则定义旋转正方向的结果也是一样的

我感觉一般情况下都是，右手坐标系下，右手定则定义旋转正方向。而左手坐标系下，左手定则定义旋转正方向

[Krasjet：四元数与三维旋转](https://krasjet.github.io/quaternion/quaternion.pdf) 的 9.3 节讨论坐标系转换的问题，这也有一些启发。我们写一个 $n$ 维空间坐标时，这个坐标都应该有组对应的基，表示它的坐标值是以哪组基来衡量的。当我们考虑一个矩阵 $m$ 行 $n$ 列的矩阵 $A_{ij}$时，矩阵向量乘法是一个线性映射，把一组基和坐标映射为另一组基和坐标。不妨设第一组基为 $e_i$，第二组基是 $h_i$，那么有 $Ae_i=\sum_k a_{ki}h_k$，即 $A_{ij}$ 的第 $i$ 列表示的是将 $e_i$ 映射为这个 m 维向量后，这个向量用基 $h_i$ 表示的系数
一种特殊的情况是 $m=n$，我们取两组基 $e_i,h_i$，并且假设 $e_j=\sum_i a_{ij}h_i$，此时 $a_{ij}$ 组成的矩阵 $A_{ij}$ 从某种意义上讲是一个恒等映射（因为它只是把向量的基给替换了而已）。为了更直观地理解我这里想表达的含义，我们考虑如下的一个旋转矩阵，它在右手坐标系下，将坐标的 x,y 轴逆时针旋转 90 度 $$
\left(
\begin{array}{ccc} 0 & -1 & 0
\\ 1 & 0 & 0
\\ 0 & 0 & 1
\end{array} 
\right)
$$我们这里认为基 $e_i$ 就是标准的 x,y,z 轴，现在考虑求出 $h_i$ 的坐标。因为矩阵的每一列的含义是 $e_i$ 如何用 $h_i$ 表示，我们可以求这个矩阵的逆矩阵，这样就拿到了 $h_i$ 是如何用 $e_i$ 表示，它的逆矩阵是 $$
\left(
\begin{array}{ccc} 0 & 1 & 0
\\ -1 & 0 & 0
\\ 0 & 0 & 1
\end{array} 
\right)
$$因此我们知道有 $h_1=(0,-1,0),h_2=(1,0,0),h_3=(0,0,1)$，这是 $h_i$ 用 $e_i$ 表示的系数。然后我们考虑向量 $(1,1,1)$，这是它在标准的 x,y,z 轴下的坐标，我们有 $$
\left(
\begin{array}{ccc} 0 & -1 & 0
\\ 1 & 0 & 0
\\ 0 & 0 & 1
\end{array} 
\right)
\left(
\begin{array}{ccc} 1 \\ 1 \\ 1
\end{array}
\right) =
\left( \begin{array}{ccc} -1 \\ 1 \\ 1
\end{array} \right)
$$$(-1,1,1)$ 也就是原向量 $(1,1,1)$ 用 $h1,h2,h3$ 表示下的坐标（或者我们可以把 $h1,h2,h3$ 视为新的 x,y,z 轴）。这是说可逆方阵就是把一个向量从一组基的表示变换到另一组基下的表示

TODO：解释四元数的插值

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
## SceneComponent and Its Movement
`TTransform<T>` 包含 Scale -> Rotate -> Translate（变换顺序）的完整的变换
`TTransform ComponentToWorld` 记录了

## ActorComponent

* AActor 中重要的一些字段

```c++
	UPROPERTY(DuplicateTransient)
	TObjectPtr<class UInputComponent> InputComponent;

	/** Pawn responsible for damage and other gameplay events caused by this actor. */
	UPROPERTY(BlueprintReadWrite, ReplicatedUsing=OnRep_Instigator, meta=(ExposeOnSpawn=true, AllowPrivateAccess=true), Category=Actor)
	TObjectPtr<class APawn> Instigator;

	/** Array of all Actors whose Owner is this actor, these are not necessarily spawned by UChildActorComponent */
	UPROPERTY(Transient)
	TArray<TObjectPtr<AActor>> Children;

	UPROPERTY(BlueprintGetter=K2_GetRootComponent, Category="Transformation")
	TObjectPtr<USceneComponent> RootComponent;

	/** The UChildActorComponent that owns this Actor. */
	UPROPERTY()
	TWeakObjectPtr<UChildActorComponent> ParentComponent;	

	/**
	 * All ActorComponents owned by this Actor. Stored as a Set as actors may have a large number of components
	 * @see GetComponents()
	 */
	TSet<TObjectPtr<UActorComponent>> OwnedComponents;
```

* `Pawn` 相比于 `Actor`，增加了处理输入的能力，例如 `SetupPlayerInputComponent` 虚函数，使得能够使用


### Offset

AddLocalOffset
AddRelativeLocation
AddActorLocalOffset