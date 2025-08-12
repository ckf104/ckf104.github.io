section size，component，overal resolution，这些参数是干嘛的

[Landscape Blueprint Brushes](https://dev.epicgames.com/documentation/en-us/unreal-engine/landscape-blueprint-brushes-in-unreal-engine) 是什么，允许用户自定义 brush 吗

landscape coords 感觉和普通的 tex coords 没啥区别

landscape layer blend 的三种混合方式：height / alpha / weight blend：[Landscape Materials](https://dev.epicgames.com/documentation/en-us/unreal-engine/landscape-materials-in-unreal-engine) 中已经讲得很清楚了，以及 [Intro to Unreal Landscapes - Alpha, Weight and Height Blend Modes](https://www.youtube.com/watch?v=KCVyf6LrFFk) 也讲得不错。但我不太清楚这些不同种类的 layer 放在一起的混合顺序是怎样的

[Landscape Technical Guide](https://dev.epicgames.com/documentation/en-us/unreal-engine/landscape-technical-guide-in-unreal-engine) 基本把 landscape 的原理讲清楚了

### Grass
这个 grass system 与 landscape 耦合在一起的，定义 landscape grass type 资产，然后在 landscape material 中定义 grass output 来在指定的地块上随机生成 grass type。主要它这性能真挺好，TODO：研究这个 grass 是怎么生成的