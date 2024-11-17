### Lec1
最后那个机器学习的分类据说要考，注意有个额外的 weakly supervised learning

task , experience , performance(loss function) 三要素
task, algorithm, task 也看到这么说的

trainning data vs validation data vs test data，可以用 validation data 来测试超参数，以及避免 overfit 的 early stop

### Lec2
supervised learning（据说这俩分类要考）
 * continuous prediction  --> regression task
 * discrete prediction --> classification
最基础的预测模型 linear model
* linear regression 用于连续预测
* logistic regression 用于离散预测
最小二乘法的解要求 $A^TA$ 是可逆的，它的 rank 等于它的非零本征值等于 $A$ 的非零奇异值，设 $A$ 是 n 行 p 列，n 是样本数目，而 p 是线性模型的输入维数，那么 $NonZeroSingularValue(A) \lt min(n,p)$，这说明当样本点小于输入维数时，该矩阵不可逆，据说要考
大的学习率和小的学习率的优劣：前者收敛更快，但是具有更大的残留误差，并且容易在极值处震荡。后者则相反，据说要考

[maximum a posteriori](https://www.jiqizhixin.com/graph/technologies/496f2bac-fafd-4c1f-83cc-5776e04065d3) 估计，假设参数的 prior distribution，根据样本结果，计算参数的 posterior distribution，估计结果就是 posterior distribution 中概率最大的参数值

当参数的 prior distribution 设置为 laplace distribution 和 gaussian distribution 时，我们得到 [lasso and ridge regression](https://www.cnblogs.com/wuliytTaotao/p/10837533.html)，或者说是 L1, L2 的正则惩罚项。[lasso and ridge regression](https://www.cnblogs.com/wuliytTaotao/p/10837533.html) 中解释了为什么 lasso regression 更容易得到 sparse solution，即需要项为 0

logistic regression 进行分类预测
### lec7
object detection 中定义了 intersection over union(iou)，来评价 bounding box 的好坏，然后定义了 precision 和 recall 来评价分类的好坏。为什么会有 precision 和 recall 两个指标呢，在给定一个物体类别 C 时，我们想要区分将类别 C 的物体分类为别的物体，和将别的物体分类为类别 C 这两种错误。precision 对应查准率，表示我认为是类别 C 的物体中有多少确实是类别 C，rcall 是查全率，表示我认为是所有是类别 C 的物体中我识别出来了多少

[Recall, Precision, AP, mAP的计算方法](https://blog.csdn.net/weixin_43646592/article/details/113998328) 对 map 讲得挺好，关键在于每个 bounding box 有个 confidence，先将结果数据按照 confidence 从大到小排序，然后绘制 precision 和 recall 的曲线，然后 [浅析经典目标检测评价指标--mmAP（一）](https://zhuanlan.zhihu.com/p/55575423) 也讲得很好。额外提到了计算 ap 时使用 precision 和 recall 曲线围成的面积需要进行一些调整，然后由于 map 依赖于 iou，因此还有 mmap 等等（对 iou 进行平均）

目前看到的一些：
* lec7：video reasoning，objection detection
* lec6：ok-robot(pick-and-drop tasks)，large video language model
* lec5：learning transferable visual models from natural language supervision(什么玩意)，relation transformer for scene graph generation(什么玩意)
* lec4：llm related，large language model and vision assistant


可以考虑的论文和 project 方向
* object detection
* image segmentation
* depth estimation(depth anything)
* 3d reconstruction