[Multi-stage builds](https://docs.docker.com/build/building/multi-stage/)

dockerfile 的 ARG 变量是有[作用域](https://docs.docker.com/reference/dockerfile/#scope)的，一个 build stage 结束，这个 build stage 中声明的所有 ARG 都没了，要在新的 build stage 中使用需要重新声明

