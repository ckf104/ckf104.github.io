### Separating Axis Theorem
Notes:
* 原本的数学定理并不局限于凸多边形，只要是凸的有界紧集就行了
* 3D 的情况除了检查两个凸多面体的面法线，还需要检查两个凸多面体的边的叉积（如果 A，B 两个凸多面体分别有 m，n 条边，那么需要额外检查 mn 根分离轴）
* 使用分离轴上的投影而不要去判断两个凸多面体是否在平面两侧，后者在处理边叉积确定的平面时不是很好弄，因为只知道平面方向，而不知道具体的位置
* 在计算分离轴上的投影时保留一些额外的信息可以确定 contact point，penetration depth 和 contact normal
	* contact point 是凸多面体上陷得最深的点，也可以近似理解为是碰撞开始发生时的碰撞点
	* contact normal 是要分离两个凸多面体时移动距离最短的方向，也可以近似理解为是碰撞发生其中一个凸多面体的法线方向
	* penetration depth 是要分离两个凸多面体时沿着 contact normal 移动的距离，可以近似理解为陷入的深度
	* 在测试分离轴时，如果两个凸多面体在上面的投影有重合，记录重合范围的大小。最小重合范围的分离轴的方向就是 contact normal，在该轴上投影的端点就是 contact point，而重合范围的大小就是 penetration depth（虽然我不太确定这样计算出来的 contact normal 是否是数学上最佳的 contact normal）

TODO：看看 [Physics Tutorial](https://research.ncl.ac.uk/game/mastersdegree/gametechnologies/previousinformation/) 系统，它在第 4 讲的碰撞检测中提到了怎么做粗筛以及如何用分离轴处理曲线物体
### Gilbert–Johnson–Keerthi Algorithm
