[Geometry Collection settings (part 1/2)](https://www.youtube.com/watch?v=zI9k6sbMi_M) 中讨论许多 Geometry Collection 的设置，解释了 particle-implicit vs implicit-implicit，我看起来要使用 non-uniform 的形变的话，最好在 Geometry Collection 的 geometry source 设置中修改形变，而不是 fracture 完了之后来设置形变，后者感觉破碎时效果挺奇怪的

另外，视频里还说到 geometry collection 有三个材质通道，但我这里如果不手动添加，只有一个来着d

[虚幻Chaos物理引擎剖析（GeometryCollection篇）](https://zhuanlan.zhihu.com/p/546918035) 中讨论了如何解决破碎透明材质带来的问题

[Chaos Debug Console Commands not working (5.3)](https://forums.unrealengine.com/t/chaos-debug-console-commands-not-working-5-3/1521172) 中 staff 给出了如何 debug 绘制 chaos 碎片的碰撞体的方法


[Chaos Destruction In Unreal Engine 5](https://www.youtube.com/watch?v=DbwCDz0zFBQ&list=PLPpgDoSBYYWgAsFdt3AsvyblUk04qkEob&index=3) 中讨论了如何使用更基本的 API 来构建 chaos field，而不是直接使用引擎提供的 FS master field 等蓝图

[Disabling Chaos Anchor Fields at runtime](https://forums.unrealengine.com/t/disabling-chaos-anchor-fields-at-runtime/496278) 讨论了如何在运行时关闭 anchor

[Unreal Engine 5 Tutorial - Chaos: Caching](https://www.youtube.com/watch?v=axoEwGjtg1s) 中讨论了 chaos 的 cache 回放