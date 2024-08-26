这是 pbrt4 第二章的阅读笔记

## Basic Idea

为了计算积分 $\int_\Omega f(\boldsymbol{x})d\boldsymbol{x}$，我们可以基于区域 $\Omega$ 上的概率分布 $p$ 对区域 $\Omega$ 进行 $n$ 采样，采样均值 $F_n$ 是积分结果的无偏估计
$$
E[F_n] = E[\frac{1}{n}\sum_{j=1}^{n}\frac{f(\boldsymbol{x_i})}{p(\boldsymbol{x_i})}] = \int_\Omega f(\boldsymbol{x})d\boldsymbol{x}
\\
\sigma^2 = var(\frac{f(\boldsymbol{x_i})}{p(\boldsymbol{x_i})})
\\
var(F_n) = \frac{\sigma^2}{n}
$$
可以看到，估计的方差随着 $n$ 的增大线性减小，$p(\boldsymbol{x})$ 的选择决定了常系数 $\sigma^2$ 的大小，$p(\boldsymbol{x})$ 和 $f(\boldsymbol{x})$ 变化越一致，$\sigma^2$ 越小

## Stratified Sampling

首先看 [probability-cheat-sheet-24](https://blog.nex3z.com/2019/01/26/probability-cheat-sheet-24/) 了解条件期望和条件方差，**关键是理解这俩也是随机变量**

上一节的基本符号和假设不变，现在我们将区域 $\Omega$ 划分为 $\Omega_1\dots \Omega_J$，并记 $w_j=p(\boldsymbol{x} \in \Omega_j)$，在区域 $\Omega_j$ 上以概率分布 $p_j$ 采样 $n_j$ 个点，那么 新的采样均值 $F_{n,strat}$ 是对积分结果的无偏估计
$$
p_j(\boldsymbol{x}) = \frac{p(\boldsymbol{x})}{w_j}, x \in \Omega_j
\\
E[F_{n,strat}] = E[\sum_{j=1}^{J}\frac{w_j}{n_j}\sum_{i=1}^{n_j}\frac{f(\boldsymbol{x_{ij}})}{p(\boldsymbol{x_{ij}})}] = \int_\Omega f(\boldsymbol{x})d\boldsymbol{x}
\\
\sigma_j^2 = var(\frac{f(\boldsymbol{x_j})}{p({\boldsymbol{x_j})}})
\\
var(F_{n,strat})=\sum_{j=1}^J w_j^2\frac{\sigma^2_j}{n_j}
$$
现在我们尝试比较 $var(F_{n,strat})$ 和 $var(F_n)$，根据条件方差公式
$$
var(f(X)) = E(var(f(X |Z))) + var(E(f(X |Z)))
$$
若记 $\mu_j$ 是在区域 $\Omega_j$ 上的条件期望，$\mu$ 为区域 $\Omega$ 上的期望，我们有
$$
var(F_n) = \frac{\sigma^2}{n} = \frac{\sum_{j=1}^J w_j\sigma_j^2 + \sum_{j=1}^J w_j(\mu_j - \mu)^2}{n}
$$
如果我们取 $n_j = nw_j$，此时显然有 $var(F_n) \ge var(F_{n,strat})$​

由柯西不等式可知，当 $n_j = \frac{w_j\sigma_j}{\sum_{j=1}^J w_j\sigma_j}n$ 时，$var(F_{n,strat})$ 取到最小值 $\frac{(\sum_{j=1}^Jw_j\sigma_j)^2}{n}$

这个结果的直观含义是，应当多采样概率大和方差大的位置

pdf [Further Variance Reduction Methods](https://www.columbia.edu/~mh2078/MonteCarlo/MCS_AdvVarRed_MasterSlides.pdf) 也讲得不错，以及 [Monte Carlo theory, methods and examples](https://artowen.su.domains/mc/)

## Multiple Importance Sampling

MIS 考虑的问题是当我们有多个概率密度函数时，如何结合它们的采样结果取得更小的方差，即考虑
$$
\sum_{i=1}^n\omega_i(\boldsymbol{x}) = 1 
\\
F = \sum_{i=1}^n \frac{1}{n_i}\sum_{j=1}^{n_i}w_i(\boldsymbol{x_{ij}})\frac{f(\boldsymbol{x_{ij}})}{p_i(\boldsymbol{x_{ij}})}
$$
容易知道，$F$ 是一个无偏估计。那如何选取合适的 $\omega_i(\boldsymbol{x})$ 呢？

在 Optimally Combining Sampling Techniques for Monte Carlo Rendering 这篇论文中（这篇论文对比各种采样方法在求渲染方程的积分中的应用，挺有意思的）证明了 balance heuristic 是一个值得考虑的选择
$$
\hat\omega_i(\boldsymbol{x}) = \frac{n_ip_i(\boldsymbol{x})}{\sum_{j=1}^n n_jp_j(\boldsymbol{x})}
$$
对于**任意非负**的 $\omega$ 选择（即 $\omega_i(\boldsymbol x) \ge 0$），我们有
$$
var(\hat{F}) \le var(F) + (\frac{1}{min(n_i)} - \frac{1}{\sum n_i})\mu^2
$$
其中 $\mu$​ 是待估计的积分值。除此外，还有 *power heuristic*, *cutoff heuristic* 等

## Russian Roulette

暂时还不太清楚这个咋用，它的基本想法是以一定概率 $q$ 放弃计算，并保持无偏估计。即给定一个随机变量 $X$，它的俄罗斯轮盘赌对应的随机变量 $X_{rr}$ 为
$$
X_{rr}=\begin{equation}
\left\{
             \begin{array}{lr}
             \frac{X - qc}{1-q}, & \xi > q \\
             c, & otherwise
             \end{array}
\right.
\end{equation}
$$
可见
$$
E[X_{rr}]=E[X]
\\
var(X_{rr}) = var(X) + \frac{q}{1-q}E[(X-c)^2]
$$
因此 Russian Roulette 总是会增大方差

**TODO: 2.2节的 MIS Compensation 和 one sample model**

## Sampling by Transformation

这节是讨论如何在有了采样 $p_x(\boldsymbol{x})$ 的方法后，如何对 $p_y(\boldsymbol{y})$  进行采样。从实际应用的角度来说，我们希望在有了基本的 uniform distribution sample 后，获得一般的其它分布函数对应的采样

对于一维的情况
$$
若 \quad Y = f(X),
\\
则 \quad p_y(y) = \frac{p_x(x)}{|f'(x)|}
$$
反过来说，在给定需要采样的 $p_y(y)$ 时，假设 $P_x(x)$ 和 $P_y(y)$ 是其累积分布函数，那么取 $f(x) = P^{-1}_y(P_x(x))$ 时，通过 $f$ 变换得到的随机变量 $Y$ 满足分布函数 $p_y(y)$，当 $X$ 是区间 0，1 上的均匀分布，$f(x)=P_y^{-1}(x)$，这被称为 *Inversion Method*

利用变换的雅克比行列式的大小对应空间的体积缩放这一观点，对应 n 维的变换我们有
$$
p_y(\boldsymbol{y}) = \frac{p_x(\boldsymbol{x})}{|J_T(\boldsymbol{x})|}
$$
其中 $|J_T(\boldsymbol{x})|$ 表示 $\boldsymbol{f}(\boldsymbol{x})$​ 的雅克比矩阵的行列式的绝对值

但是在给定 $p_y(\boldsymbol{y})$ 时，要反过来给出合适的 $\boldsymbol{f}(\boldsymbol{x})$ 的显式表达式就不容易了。pbrt4 的 2.2.4 节给出了一种利用边缘分布化归为一维情况的隐式做法

以二维的情况为例，我们可以先求出 $x$ 的边缘分布，然后可以对这个一维的边缘分布进行采样，得到一个 $x_0$，那么可以求出 $p(y|x_0)$ 这个 $y$ 关于 $x_0$ 的条件分布，然后对这个一维的条件分布再进行采样，得到一个 $y_0$，这个 $(x_0,y_0)$ 就是对这个二维分布一次采样的结果

