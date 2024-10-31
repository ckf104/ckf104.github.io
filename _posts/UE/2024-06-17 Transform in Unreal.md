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

但现在给定一个可逆方阵 $A_{ij}$，我们也可以认为它的两组基相同，都为 $e_i$，那么 $A_{ij}$ 不改变坐标的基，但是把一个坐标映射到另一个坐标上了。现在我们回头看 9.3 节的问题，给出一个在一个坐标系 $e_i$ 下的变换 $T$，问它在另一个坐标系 $h_i$ 描述下的相同变换。我们假设矩阵 $M$ 将以 $e_i$ 描述的坐标变换到以 $h_i$ 描述的坐标。而 $T$ 可以看作是 $e_i$ 到 $e_i$ 的变换，根据上面的讨论，我们容易知道在 $h_i$ 描述下的这个旋转矩阵应该是 $MTM^{-1}$。这也说明了相似矩阵的几何意义，即描述不同基下的相同变换

TODO：解释四元数的插值

## TTransform
`TTransform<T>` 包含 Scale -> Rotate -> Translate（变换顺序）的完整的变换，`TTransform` 重载了乘法操作，乘法是对 `TTransform` 的复合（A 乘 B 的结果是先应用 A 变换，再应用 B）。但正如实现中注释解释的那样，它这里假定了 scale 是一个标量（即不会进行不等比的缩放）
```c++
	//	When Q = quaternion, S = single scalar scale, and T = translation
	//	QST(A) = Q(A), S(A), T(A), and QST(B) = Q(B), S(B), T(B)

	//	QST (AxB) 

	// QST(A) = Q(A)*S(A)*P*-Q(A) + T(A)
	// QST(AxB) = Q(B)*S(B)*QST(A)*-Q(B) + T(B)
	// QST(AxB) = Q(B)*S(B)*[Q(A)*S(A)*P*-Q(A) + T(A)]*-Q(B) + T(B)
	// QST(AxB) = Q(B)*S(B)*Q(A)*S(A)*P*-Q(A)*-Q(B) + Q(B)*S(B)*T(A)*-Q(B) + T(B)
	// QST(AxB) = [Q(B)*Q(A)]*[S(B)*S(A)]*P*-[Q(B)*Q(A)] + Q(B)*S(B)*T(A)*-Q(B) + T(B)
```
但单论结果的表达式是很合理的，即复合后的 `TTransform` 的 缩放，旋转矩阵分别是原本两个缩放，旋转矩阵的叠加。而平移矩阵是第一个平移矩阵在经历第二个 `TTransform` 的缩放旋转后再叠加第二个平移矩阵

类似地，还有 `TTransform<T>::GetRelativeTransform(const TTransform<T>& Other)`,它返回的是 this 乘以 `Other` 的逆变换
## SceneComponent and Its Movement
与 scene component 最直接相关的字段是
```c++
/** Location of the component relative to its parent */
UPROPERTY(EditAnywhere, BlueprintReadOnly, ReplicatedUsing=OnRep_Transform, Category = Transform, meta=(AllowPrivateAccess="true", LinearDeltaSensitivity = "1", Delta = "1.0"))
FVector RelativeLocation;

/** Rotation of the component relative to its parent */
UPROPERTY(EditAnywhere, BlueprintReadOnly, ReplicatedUsing=OnRep_Transform, Category=Transform, meta=(AllowPrivateAccess="true", LinearDeltaSensitivity = "1", Delta = "1.0"))
FRotator RelativeRotation;

/**
*	Non-uniform scaling of the component relative to its parent.
*	Note that scaling is always applied in local space (no shearing etc)
*/
UPROPERTY(EditAnywhere, BlueprintReadOnly, ReplicatedUsing=OnRep_Transform, Category=Transform, meta=(AllowPrivateAccess="true", LinearDeltaSensitivity = "1", Delta = "0.0025"))
FVector RelativeScale3D;

/** Current transform of the component, relative to the world */
FTransform ComponentToWorld;
```
`RelativeLocation`，`RelativeRotation` 以及 `RelativeScale3D` 表示该 scene component 相对于 parent 的变换，即
```c++
this->ComponentToWorld = FTransform(RelativeScale3D, RelativeRotation, RelativeLocation) * parent->ComponentToWorld;
```
如果 `bAbsoluteLocation`，`bAbsoluteRotation`，`bAbsoluteScale` 中某个为 true 的话，上面相应的 RelativeXXX 变换也变成绝对含义（就直接是世界坐标的变换了），具体此时 `ComponentToWorld` 的计算参考 `CalcNewComponentToWorld_GeneralCase` 函数

在具体讨论 scene component 向上层提供的变换 API 之前，我们先讨论其内部的一些函数。其中两个重要的函数是 `UpdateComponentToWorld` 以及`UpdateComponentToWorldWithParent`，前者只是对后者的一个简单封装，提供了默认的参数

`UpdateComponentToWorldWithParent` 的用处是，在修改了前面的 RelativeXXX 变换后，更新 `ComponentToWorld` 成员变量。这个 component 的变换更新后，不改变它的 parent 的变换，但会改变其子节点的变换。因此该函数内部调用 `PropagateTransformUpdate` 函数，这个函数负责广播 component 的变换更新了，并且调用 `UpdateChildTransforms` 函数，这个函数又进一步调用每个 child 的 `UpdateComponentToWorld`，这样递归地对 child 的 `ComponentToWorld` 进行更新。请注意，父节点的变换改变后，子节点的 RelativeXXX 是不需要改的，不论 `bAbsoluteXXX` 是否为 true（因为 `bAbsoluteXXX` 除了表示相应的变换对应世界坐标外，也表示子节点的这个变换不再跟随着父节点了：在 `bAbsoluteXXX` 为 false 时，父节点的变换改变，子节点的 RelativeXXX 不改变就对应子节点在跟着父节点一起动）

然后我们说 `InternalSetWorldLocationAndRotation` 函数，这个函数会接收一个 world position 和一个 world rotation 参数，这是 component 在 world space 中的新位置。函数内部会根据这两个参数对 `RelativeLocation` 和 `RelativeRotation` 进行更新，然后调用 `UpdateComponentToWorldWithParent` 对它和子节点的 `ComponentToWorld` 进行更新

接下来两个重要的函数是 `MoveComponent` 以及 `MoveComponentImpl`，前者是直接调用后者。`MoveComponentImpl` 是一个虚函数，可以被子类重载，至少有以下三个实现
* scene component 有一个默认是实现（我猜测这个默认的实现是用来移动摄像机之类的物体的？）
* primitive component 中重载了该函数，因为它需要处理物理碰撞等额外信息
* skeletal mesh component 重载了该函数，因为它需要处理骨骼动画等额外信息
scene component 的 `MoveComponentImpl` 实现很简单，因为它处理的是在 scene 中不可见的 component，因此它的实现基本就是调用 `InternalSetWorldLocationAndRotation` 进行更新就可以了

primitive component 额外考虑了物理碰撞的因素，如果 `bsweep` 为 true，那么它会考虑沿途上所有可能的碰撞，最终的位置是停在第一个发生碰撞的位置处。然后调用 `InternalSetWorldLocationAndRotation` 设置更新 component 的位置和旋转

对比这几个 API 函数，`AddLocalOffset`, `AddRelativeLocation`, `AddWorldOffset`，它们的主要区别在于移动的坐标系参考不同，第一个是相对于物体自身的局部坐标系，第二个是相对于 parent component 的局部坐标系，第三个是相对于 world space 的坐标系。[Coordinate System and Spaces](https://dev.epicgames.com/documentation/en-us/unreal-engine/coordinate-system-and-spaces-in-unreal-engine) 告诉我们，在编辑器界面点击右上角的图标可以切换 local 和 world space 视图。

TODO：在实际测试 primitive component 时观察到的几个现象
* 如果 `bsweep` 为 false，在碰撞到物体后还发生了转动（这看起来更加真实），但我没理解这个转动是如何发生的，我猜测应该和 overlap 的检测有关，就是 UpdateOverlaps 相关的函数，但不太确定。而 `bsweep` 为 true 时则不会有转动（我猜测是因为它是缓缓扫过去的，因此不会像 `bsweep` 为 false 时穿到内部去然后再根据 overlap 机制弹出来了）
* 如果 `bsweep` 为 true，且有重力和物理碰撞，cude 移动时会直接与地板碰撞，导致 cude 没法移动，一个相同问题的帖子 [Moving objects with sweep enabled not working if they are touching the floor and gravity enabled](https://forums.unrealengine.com/t/moving-objects-with-sweep-enabled-not-working-if-they-are-touching-the-floor-and-gravity-enabled/1814530)，但没人回复。但我发现如果移动的方向稍微向上一点（z > 0），就能够动起来了，不知道 UE 里面是咋搞的
TODO：skeletal mesh component 的 `MoveComponentImpl` 实现
```c++
/** What we are currently attached to. If valid, RelativeLocation etc. are used relative to this object */
UPROPERTY(ReplicatedUsing = OnRep_AttachParent)
TObjectPtr<USceneComponent> AttachParent;

/** List of child SceneComponents that are attached to us. */
UPROPERTY(ReplicatedUsing = OnRep_AttachChildren, Transient)
TArray<TObjectPtr<USceneComponent>> AttachChildren;
```
`SceneComponent` 的结构：`SceneComponent` 可以通过父子节点关联，整个 Actor 的 `SceneComponent` 呈现树状结构。每个 `SceneComponent` 的 `RelativeLocation`，`RelativeRotation` 和 `RelativeScale3D` 默认情况下是相对父节点来说的（除非设置 `bAbsoluteLocation` 等为真），而 `ComponentToWorld` 参数则表示相对于世界的变换
#### GetSocketTransform
在 `InternalSetWorldLocationAndRotation`，`SetWorldLocation` 等函数中，都需要调用 parent component 的 `GetSocketTransform` 函数来获取 parent 的相对世界坐标的变换，从而将自己相对世界坐标的变换，转化为相对于 parent 的变换，从而设置自己的 `RelativeXXX` 节点。`GetSocketTransform` 是一个虚函数，接收一个 `FName InSocketName` 参数（其实还有一个枚举变量，但通常都使用默认值 `RTS_World`），默认实现就是返回自己的 `ComponentToWorld` 成员

`SceneComponent` 的子类有需求可以重载 `GetSocketTransform` 函数，根据不同的 `InSocketName` 返回不同的 `FTransform`。另外一个可重载的函数 `QuerySupportedSockets` 则返回自己可识别的所有 socket name 
## Rotation

`TRotator<T>` 中存储的是基本的欧拉角 Yaw，Pitch，Roll，并且是 intrinsic rotation（即旋转是相对物体自身的坐标系），**具体的角度正方向规定在 `Rotator.h` 中解释得很清楚：按照 Yaw，Pitch，Roll 的顺序，先沿着 z 轴按照左手定则规定的正方向旋转，再沿着 y 轴按照右手定则规定的正方向旋转，最后沿着 x 轴按照右手定则规定的正方向旋转**

四元数在 ue 中对应 `TQuat` 结构，注意 W 对应的是实数分量，而 X，Y，Z 分别对应 i，j，k 分量。由于 ue 使用的左手坐标系，因此一些公式会和网上看到的有些不太一样，例如四元数转旋转矩阵的函数 `TQuat<T>::ToMatrix`，左手坐标系得到的旋转矩阵是右手坐标系的旋转矩阵的转置。四元数的旋转总是使用左手定则规定的正方向

`TRotator<T>::Vector` 函数返回一个单位向量，它表示原来指向 x 轴的单位向量在经过这个 rotator 的旋转后的新坐标，如果我们记 yaw 上的旋转角度为 $\theta$，pitch 上的旋转角度为 $\phi$，那么这个结果的向量坐标为 $(cos\phi cos\theta,cos\phi sin\theta,sin\phi)$

## TMatrix
`TMaxtrix<T>` 是行主序的存储方式。构造函数中传入的 `TPlane<T>` 或者 `TVector<T>` 会初始化 `TMaxtrix<T>` 的一行。但实际上我们传入矩阵数据时，传入的是矩阵数据的转置（例如 PerspectiveMatrix.h 中的矩阵初始化），这样得到的 `TMaxtrix<T>` 也是一个转置。这样做是因为 UE 的矩阵向量乘实现中向量是左乘的（见 `VectorTransformVector` 函数的实现）。这意味着，矩阵 A 乘以矩阵 B，得到的新矩阵对应的变换应该是先应用 A 变换，再应用 B 变换。例如要得到一个变换矩阵，它将 world space 中的点变换到 clip space，那么这个矩阵应该是 view x project（而在向量右乘时应该是 project x view）。这个变换的复合顺序和 `TTransform<T>` 是一致的
## Transform Matrix

UE 中使用的投影矩阵是 Reversed Z Perspective Matrix，看下面函数的实现就知道了

```c++
FMinimalViewInfo::CalculateProjectionMatrix();
```
TODO：ue 的摄像机 lookat 的方向是哪个？+Z 轴，-Z 轴，还是表示 forward 的 X 轴？

ue 使用左手坐标系，X 轴对应 Forward Vector，Y 轴对应 Right Vector，Z 轴对应 Up Vector
## Camera and Transformation

* `SceneComponent` 的结构：
  * `SceneComponent` 可以通过父子节点关联，整个 Actor 的 `SceneComponent` 呈现树状结构。每个 `SceneComponent` 的 `RelativeLocation`，`RelativeRotation` 和 `RelativeScale3D` 默认情况下是相对父节点来说的（除非设置 `bAbsoluteLocation` 等为真），而 `ComponentToWorld` 参数则表示相对于世界的变换
  * 一个父节点的变换矩阵改变会带来子节点的相应改变，即父 `SceneComponent` 移动会带动子 `SceneComponent` 的移动（除非 `bAbsoluteLocation` 等参数全部设置为真，此时该子 `SceneComponent` 完全独立），典型的从 `SetActorRotation` 追溯可以看到。当父节点的  `ComponentToWorld` 变化后，虽然子节点的 Relative Transform 不会发生变化，但是需要递归地修改子节点的 `ComponentToWorld`
  * TODO：我看 Relative Transform 总是和 ComponentToWorld 同步更新？那这个 Relative Transform 有什么作用呢？什么时候单独的 Relative Transform 能拿出来有用？
* `ViewTarget` 中的 target 和 POV 的关系是什么
* 对 `SpringArmComponent` 的理解：在 [Player-Controlled Cameras](https://dev.epicgames.com/documentation/en-us/unreal-engine/quick-start-guide-to-player-controlled-cameras-in-unreal-engine-cpp) 教程中，对 SpringArm 调用了 `SetRelativeLocationAndRotation` 方法。这个方法其实来自于 `SceneComponent`，设置 `Component` 和父节点的相对位置。`SpringArmComponent` 则是 `SceneComponent` 的子类。我理解的 `Location` 和 `Rotation` 对于 `SpringArm` 的含义是看的对象的位置，以及看的角度。而配置参数 `socket offset`，`target offset` 则是对其的微调，见 [UE SpringArm TargetOffset 和 SocketOffset 区别](https://www.bilibili.com/read/cv14318016/)
  * 那将一个 `CameraComponent` attach 到 SpringArm 上又如何呢？[UE4 里的 Camera 系统](https://zhuanlan.zhihu.com/p/149176416) 中讨论说，`APlayerCameraManager` 里的 `ViewTarget` 中 Actor 作为观察的对象，`FMinimalViewInfo` 是根据 Actor 计算出的相机数据，其中调用了 Actor 的 `CalcCamera` 方法，在 `CalcCamera` 实现中，会检索 Actor 是否存在 `CameraComponent`，如果存在，那么将使用该 `CameraComponent`，调用它的 `GetCameraView` 方法。该方法将 `CameraComponent` 的位置和朝向作为摄像机的位置和朝向。而 `CameraComponent` 作为 `SceneComponent`，只存储相对的位置和朝向，会调用父节点 `SpringArmComponent` 的 `GetSocketTransform` 方法来计算自己在世界坐标中的位置和朝向。该方法默认情况下直接返回节点的 Transform，但 `SpringArmComponent` 重载了该函数，返回的 Transform 会额外乘 `RelativeSocketRotation` 和 `RelativeSocketLocation` 对应的变换。这俩参数的值是用 `TargetArmLength`，`TargetOffset`，`SocketOffset` 等 SpringArm 的参数进行控制
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