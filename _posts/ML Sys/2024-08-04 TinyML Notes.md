## Lec2 

模型的 Memory bandwidth 不仅需要考虑 weights，还需要考虑 activation，至少对于 GPU 这种结构来说，通常一个 layer 对应一个 kernel call，就对应一次的 weight read，activation read，activation write

## Lec3

Prune 基本想法：裁掉值接近 0 的 weight，在新模型上重新训练，然后接着裁，再训练。。。这样循环

granularity：指裁的时候是否需要遵循一定的 pattern，**例如 A100 上的 sparse tensor core，裁的时候保证 50% 的 sparsity，有时间看看它的实现**

* regular pruning 便于存储和计算，但 compression rate 可能不高，irregular pruning 则反之

关于 neuron pruning，PPT 中谈到了这个根据 ReLU 的输出使用 Percentage-of-Zero-Based Pruning，不理解：这个依赖于数据？不同的数据导致不同的 Pruning 结果？感觉和论文 A Data-Driven Neuron Pruning Approach towards Efficient Deep Architectures 有些关系

后面那个 Regression-based Pruning 也不是特别理解，不过它大概想法是说选择 prune 那些对 layer 函数影响最小的 channel（就是说在 prune 这一个 channel 之后，用更少地参数去重建之前的 layer 函数，使得误差最小），要搞明白需要读下 Channel Pruning for Accelerating Very Deep Neural Networks 