### Skeletal Animation Basics
[learn opengl 骨骼动画](https://learnopengl-cn.github.io/08%20Guest%20Articles/2020/01%20Skeletal%20Animation/)
assimp 的 `aiMesh` 中包含的 `aiBone` 是什么
`aiBone` 的 offset matrix 表达了从 model space 到 bone space 的变换矩阵，这等价于从 node 的层次关系的变换矩阵的复合的逆矩阵（需要验证一下 assimp 输出的结果是否满足这个关系）