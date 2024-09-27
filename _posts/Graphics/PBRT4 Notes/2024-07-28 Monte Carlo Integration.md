这是 pbrt4 第二章的阅读笔记

## Basic Idea

为了计算积分 $\int_\Omega f(\boldsymbol{x})d\boldsymbol{x}$，我们可以基于区域 $\Omega$ 上的概率分布 $p$ 对区域 $\Omega$ 进行 $n$ 采样，采样均值 $F_n$ 是积分结果的无偏估计
$$
\displaylines{
E[F_n] = E[\frac{1}{n}\sum_{j=1}^{n}\frac{f(\boldsymbol{x_i})}{p(\boldsymbol{x_i})}] = \int_\Omega f(\boldsymbol{x})d\boldsymbol{x}
\\
\sigma^2 = var(\frac{f(\boldsymbol{x_i})}{p(\boldsymbol{x_i})})
\\
var(F_n) = \frac{\sigma^2}{n}
}
$$
可以看到，估计的方差随着 $n$ 的增大线性减小，$p(\boldsymbol{x})$ 的选择决定了常系数 $\sigma^2$ 的大小，$p(\boldsymbol{x})$ 和 $f(\boldsymbol{x})$ 变化越一致，$\sigma^2$ 越小

## Stratified Sampling

首先看 [probability-cheat-sheet-24](https://blog.nex3z.com/2019/01/26/probability-cheat-sheet-24/) 了解条件期望和条件方差，**关键是理解这俩也是随机变量**

上一节的基本符号和假设不变，现在我们将区域 $\Omega$ 划分为 $\Omega_1\dots \Omega_J$，并记 $w_j=p(\boldsymbol{x} \in \Omega_j)$，在区域 $\Omega_j$ 上以概率分布 $p_j$ 采样 $n_j$ 个点，那么 新的采样均值 $F_{n,strat}$ 是对积分结果的无偏估计
$$
\displaylines{
p_j(\boldsymbol{x}) = \frac{p(\boldsymbol{x})}{w_j}, x \in \Omega_j
\\
E[F_{n,strat}] = E[\sum_{j=1}^{J}\frac{w_j}{n_j}\sum_{i=1}^{n_j}\frac{f(\boldsymbol{x_{ij}})}{p(\boldsymbol{x_{ij}})}] = \int_\Omega f(\boldsymbol{x})d\boldsymbol{x}
\\
\sigma_j^2 = var(\frac{f(\boldsymbol{x_j})}{p({\boldsymbol{x_j})}})
\\
var(F_{n,strat})=\sum_{j=1}^J w_j^2\frac{\sigma^2_j}{n_j}
}
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

很多时候，待积函数比较复杂，我们没办法直接针对待积函数进行重要性采样，但可能能够分别对它的一部分结构进行重要性采样。例如在渲染方程中 $L(x, w_i)f(x, w_i, w_o)$ 这个乘积不太好进行重要性采样，但单独针对 $L$ 和 $f$ 进行重要性采样会比较方便。MIS 考虑的问题是当我们有多个概率密度函数时，如何结合它们的采样结果取得更小的方差，即考虑
$$
\displaylines{
\sum_{i=1}^n\omega_i(\boldsymbol{x}) = 1 
\\
F = \sum_{i=1}^n \frac{1}{n_i}\sum_{j=1}^{n_i}w_i(\boldsymbol{x_{ij}})\frac{f(\boldsymbol{x_{ij}})}{p_i(\boldsymbol{x_{ij}})}
}
$$
容易知道，$F$ 是一个无偏估计。那如何选取合适的 $\omega_i(\boldsymbol{x})$ 呢？

在 Optimally Combining Sampling Techniques for Monte Carlo Rendering 这篇论文中，证明了 balance heuristic 是一个值得考虑的选择
$$
\hat\omega_i(\boldsymbol{x}) = \frac{n_ip_i(\boldsymbol{x})}{\sum_{j=1}^n n_jp_j(\boldsymbol{x})}
$$
对于**任意非负**的 $\omega$ 选择（即 $\omega_i(\boldsymbol x) \ge 0$），我们有
$$
\displaylines{
var(\hat{F}) = \int \frac{f^2(\boldsymbol{x})}{\sum_{j=1}^n n_j p_j(\boldsymbol{x})}dx
\\
var(\hat{F}) \le var(F) + (\frac{1}{min(n_i)} - \frac{1}{\sum n_i})\mu^2
}
$$
其中 $\mu$​ 是待估计的积分值。除此外，还有 *power heuristic*, *cutoff heuristic* 等

另外，我们也可以考虑 _one sample model_，它首先以 $q_i$ 的概率选择分布 $p_i$，当某个分布 $p_i$ 被选中时，再以分布 $p_i$ 来采样 $X$
$$
F = \frac{w_i(X)f(X)}{q_ip_i(X)}
$$
容易证明此时 $F$ 是结果的无偏估计。在 Optimally Combining Sampling Techniques for Monte Carlo Rendering 中证明了此时 balance heuristic 是最优的 $w_i(X)$ 选择。取 $n$ 个采样点，此时有
$$
\displaylines{
F = \frac{f(X)}{\sum q_ip_i(X)}
\\
Var(F_n) = \frac{1}{n}\int \frac{f^2(x)}{\sum q_ip_i(x)}dx 
}
$$
请注意，这个方差的结果和上面 multiple sample 使用 _balance heuristic_ 的结果是一致的。而使用单个采样函数得到的方差为
$$
Var(F_{i,n}) = \frac{1}{n}\int \frac{f^2(x)}{p_i(x)}dx 
$$
倒是直观上看不出来孰优孰劣，pbrt4 中的论述是说，MIS 能够减小 $p(x)$ 和 $f(x)$ 不匹配造成的 spike，即一个采样点的 $p(x)$ 很小，但如果 $f(x)$ 很大的话，会产生一个很大的估计，这是大方差的来源，如果我们这样混合 $\sum q_ip_i(x)$，只要有一个 $p_i(x)$的大小与  $f(x)$ 相匹配，那就会得到一个合理的估计结果，从而减少方差
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
## Sampling Possibility Mass Function

给定一个 PMF，[Alias Method](https://www.pbr-book.org/4ed/Sampling_Algorithms/The_Alias_Method) 展示了通过 O(n) 的预处理后，每次可以在 O(1) 的时间内采样这个 PMF 的方法

如果 PMF 是均匀分布，那给定一个 0 到 1 浮点数 $x$，那么 $\lfloor nx \rfloor$ 就是我们要的采样结果。现在对于不均匀的情况，划分 n 个桶，每个桶有额外的 0 到 1 浮点数 $q$ 并存储表示另一个桶的别名。现在给定 $x$，对于 $\lfloor nx \rfloor$ 指定的桶，如果 $nx - \lfloor nx \rfloor < q$ 那么返回该桶的编号，否则返回该桶存储的别名对应的桶

这里的想法就是说，每个桶对应了 $\frac{1}{n}$ 的概率，浮点数 $q$ 的存在使得这个桶能够对应更小的概率 $\frac{q}{n}$，而别名的存在其它没有装满的桶能够分担一些大于 $\frac{1}{n}$ 的概率（因为这个概率一个桶装不下）
## MIS Compensation

pbrt4 在 2.2 节额外谈到了 [MIS Compensation: Optimizing Sampling Techniques in Multiple Importance Sampling](https://dl.acm.org/doi/pdf/10.1145/3355089.3356565) 这篇论文。它的想法大概是，通常我们在做 MIS 时已经选定了一组由各种 sampling technique 决定好的采样概率函数 $p_i$，然后选择合适的 weight function $w_i$，例如最常用的 balance heuristic。那我们能不能在选择好 $w_i$ 后，放松 $p_i$ 已经固定这一条件，对某个 $p_i$ 进行一些调整，来进一步降低方差

我们考虑权重选择 balance heuristic，$p(x) = \sum c_ip_i(x)$，在最优的情况下，记 $F = \int f(x)dx$，应该有
$$
p(x) = \frac{f(x)}{F}
$$
此时方差为 0。实际情况下 $p(x) \neq \frac{f(x)}{F}$，那么如果我们希望调整其中的一个概率估计函数 $q$，来最小化方差，则有
$$
q(x) = \frac{f(x)}{c_qF} - \frac{\sum c_ip_i(x)}{c_q}
$$
但此时 $q(x) \ge 0$ 并不总是成立。因此我们稍微调整一下 $$
q(x) = \frac{1}{b}max\{0, \frac{f(x)}{c_qF} - \frac{\sum c_ip_i(x)}{c_q}\}
$$这里 $b$ 是归一化因子，使得 $q(x)$ 的积分为 0。这个新的 $q(x)$ 虽然不是使得方差为 0 的最优结果，不过也很接近了，论文中有讨论它和最优的 $q(x)$ 的差多少，这里就略过了

我们进一步看看 Image Based Lighting 中是如何应用上面的式子的
$$
\displaylines{
L_d(x,w_o) = \int_{H(n)} L_i(w_i)f(x,w_o,w_i)|w_i\cdot n|_+ dw_i
\\
|w_i \cdot n|_+ = max\{0,w_i \cdot n\}
}
$$
其中 $L_i(w_i)$ 是环境光，这里没有考虑遮挡因素（即对应 pbrt4 中的 ImageInfiniteLight）。在采样环境光时，我们有一个针对打表获得的（或者说储存在纹理中的）$L_i(w_i)$ 的重要性采样 $q(w_i)$，以及针对 brdf 项 $f(x,w_o,w_i)|w_i\cdot n|$ 的重要性采样 $p(w_i)$，前者由于是通过打表直接记录的，更容易调整。所以我们选择修改 $q(w_i)$，根据前面的推导，新的 $q(w_i)$ 为
$$
q(w_i|w_o,x) = \frac{1}{b}max\{0, \frac{L_i(w_i)f(x,w_o,w_i)|w_i\cdot n|_+}{cF} - \frac{(1-c)p(w_i)}{c}\}
$$
这个式子也不好处理，论文中采取了大胆的化简，取 $$
f(x,w_o,w_i) = \frac{1}{\pi}
$$ 此时有 $$
\displaylines{
p(w_i) = \frac{|w_i \cdot n|_+}{\pi}
\\
q(w_i|n) = \frac{1}{b(n)}max\{0, \frac{L_i(w_i)|w_i\cdot n|_+}{c\pi F} - \frac{(1-c)|w_i \cdot n|_+}{c\pi}\}
\\
F = \frac{1}{\pi}\int_{H(n)} L_i(w_i)|w_i\cdot n|_+dw_i
}$$此时 $q(w_i)$ 的分布还额外依赖于法线 $n$，一种做法可以是我们再对法线 $n$ 打表，为每个法线存储一个对应的 $q(w_i)$. 另外可以采取更激进的做法，我们对给定的 $w_i$，取 $\frac{1}{2\pi}\int_{H(w_i)} q(w_i, n)dn$ 这个平均值作为 $q(w_i)$ 的估计。另外的一系列近似包括
$$
\displaylines{
b(n) \approx b
\\
F \approx \frac{1}{\pi}\int_{H(n)} L_i(w_i)dw_i = 2 \overline L_i(w_i)
}
$$
因此有 $$
\displaylines{
q(w_i) = \frac{1}{2\pi}\int_{H(w_i)} q(w_i, n)dn \\
\approx \frac{1}{b}max\{0, \int_{H(w_i)} (\frac{L_i(w_i)|w_i\cdot n|_+}{c\pi F} - \frac{(1-c)|w_i \cdot n|_+}{c\pi})dn\}
\\
=  \frac{1}{b}max\{0, \frac{L_i(w_i)}{2c \overline L_i(w_i)} - \frac{1-c}{c}\}
}
$$ 再乘以一个常数因子，就得到了我们在 pbrt4 中看到的结果（取 $c = \frac{1}{2}$）
$$
q(w_i) = \frac{1}{b}max\{0, L_i(w_i) - 2(1-c)\overline L_i(w_i)\}
$$
从形式上来说，这个结果是把原来的概率函数给削尖了，以前 $q(w_i)$ 值大的地方变得更大，以此来补偿 MIS 混合时乘以的小于 1 的常数因子 $c$，MIS Compensation 就是这么个意思吧

Note
* 论文中还有个额外的近似 $\overline L = \overline L_i(w_i)$，即取整个环境光的平均作为 $\overline L_i(w_i)$ 的估计
* 因为 $q(w_i)$ 是定义在整个球面上的，因此我们写的是 $|w_i \cdot n|_+$ 而不是 $|w_i \cdot n|$，最终平均化消除 $n$ 时使得采样时 $w_i \cdot n \le 0$ 时 $q(w_i)$ 依然有非零的概率。因此最终结果中的归一化因子 $b$ 应该是 $q(w_i)$ 在整个球面上的积分，而不是半球
* 论文中的推导是基于 balance heuristic，不知道为啥 pbrt4 中直接对 power heuristic 也用上了