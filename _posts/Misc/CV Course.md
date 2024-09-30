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