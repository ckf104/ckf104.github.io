讨论模板中的天空光照是如何实现的

加入 `ADirectionalLight`，并设置其 `UDirectionalLightComponent` 的 `bAtmosphereSunLight` 为 true，这使得这个方向光会与 volumetric cloud 等天空中的物体相交互（不然整个天空是黑的，虽然其它物体仍被正常照亮）

我目前的理解是，`ADirectionalLight` 和 `ASkyAtmosphere` 与构成了天空的主要部分（光照来源和大气散射）。在材质编辑器中通过 `SkyAtmosphereViewLuminance` 和 `SkyAtmosphereLightDiskLuminance` 节点获取到由 `ASkyAtmosphere` 和 `ADirectionalLight` 组成的天空的颜色分布，作为材质的颜色输出。然后我们加入天空球，并将这个材质贴到天空球上，这就在屏幕上看到了天空的渲染结果。与 sky atmosphere 相关节点的文档可以在 [Sky Atmosphere Component Properties](https://dev.epicgames.com/documentation/en-us/unreal-engine/sky-atmosphere-component-properties-in-unreal-engine) 中找到

`ASkyLight` 的作用是捕获天空的环境光，然后用这个环境光渲染其它物体。如果不加入 `ASkyLight`，那么在渲染物体时不会考虑天空的环境光。这里天空的环境光不局限于 `ADirectionalLight` 和 `ASkyAtmosphere` 带来的环境光，例如我们可以只使用天空球，在材质中设置它的 emissive color 为红色。只有加入 `ASkyLight` 后，这个天空球的颜色才能转化为环境光照亮其它物体

`AVolumetricCloud` 在天空加入体积云，除了影响天空的渲染结果外，还会对 `ASkyLight` 捕获的环境光产生影响

`AExponentialHeightFog` 加入雾气，因为我是否关闭 `ASkyLight` 并不影响它的渲染结果。说明它的渲染不与环境光交互，根据 [Sky Atmosphere Component Properties](https://dev.epicgames.com/documentation/en-us/unreal-engine/sky-atmosphere-component-properties-in-unreal-engine) 中的描述，在项目设置中开启 _Support Sky Atmosphere Affecting Height Fog_ 后，它的渲染会与 `ADirectionalLight` 交互（关闭这个设置后，模板中的雾气就直接黑了）
`ADirectionalLight` 和 `ASkyAtmosphere` 的组合只会渲染天空（即上半球），如果没有 `AExponentialHeightFog`，模板场景的下半球就全黑了

TODO：进一步弄清楚这些元素在渲染时是如何交互的