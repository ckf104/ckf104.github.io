与 qemu plugin 相关的一些处理
### Init Stage
```c
static void __attribute__((__constructor__)) plugin_init(void);
```
初始化全局的 `struct qemu_plugin_state plugin`

qemu plugin state 这个数据结构中包含了所有的 plugin 相关的信息。其中的一些字段包括
```c
struct qemu_plugin_state {
	// 每个 qemu_plugin_ctx 是逐 plugin 的信息，例如这个 plugin 的 id，动态库的 handle 等等
    QTAILQ_HEAD(, qemu_plugin_ctx) ctxs;
    // 以链表方式记录所有 plugin 注册的 callback，有 QEMU_PLUGIN_EV_MAX 个调用这个 callback 的时机
    QLIST_HEAD(, qemu_plugin_cb) cb_lists[QEMU_PLUGIN_EV_MAX];
    /*
     * Use the HT as a hash map by inserting k == v, which saves memory as
     * documented by GLib. The parent struct is obtained with container_of().
     */
    GHashTable *id_ht;  // 通过 plugin id 找到 qemu_plugin_ctx
    /*
     * Use the HT as a hash map. Note that we could use a list here,
     * but with the HT we avoid adding a field to CPUState.
     */
    GHashTable *cpu_ht;  // vCPU index 到 CPUState* 的映射
    QLIST_HEAD(, qemu_plugin_scoreboard) scoreboards;
    size_t scoreboard_alloc_size;
    DECLARE_BITMAP(mask, QEMU_PLUGIN_EV_MAX);
    /*
     * @lock protects the struct as well as ctx->uninstalling.
     * The lock must be acquired by all API ops.
     * The lock is recursive, which greatly simplifies things, e.g.
     * callback registration from qemu_plugin_vcpu_for_each().
     */
    QemuRecMutex lock;
    /*
     * HT of callbacks invoked from helpers. All entries are freed when
     * the code cache is flushed.
     */
    struct qht dyn_cb_arr_ht;
    /* How many vcpus were started */
    int num_vcpus;
};
```
通常每个 plugin 会通过 `qemu_plugin_scoreboard_new` 函数申请一个 `qemu_plugin_scoreboard`，所有的 `qemu_plugin_scoreboard` 就通过链表挂在 `qemu_plugin_state.scoreboards` 上。`qemu_plugin_scoreboard` 本质上是一个动态数组，它的元素类型由 plugin 自行指定，plugin 用来记录逐 vCPU 的数据，动态数组的元素分配由 qemu 这边负责。具体的元素个数记录 `scoreboard_alloc_size` 字段中

在 `qemu_plugin_scoreboard_new` 函数，会默认分配 `scoreboard_alloc_size` 个元素给 scoreboard 中的动态数组，`scoreboard_alloc_size` 在 `plugin_init` 函数中被初始化为 16。每当运行一个新的 vCPU，`qemu_plugin_vcpu_init__async` 函数会调用 `plugin_grow_scoreboards__locked` 函数检查是否需要扩容 scoreboard 的动态数组，来保证 `scoreboard_alloc_size` 始终大于 vCPU 的个数

### Command Line Parser
在全局的 `static const struct qemu_argument arg_table[]` 中注册 `--plugin` 参数，设置回调函数 `handle_arg_plugin`，这个函数负责根据命令行参数，初始化全局变量 `static QemuPluginList plugins`。`plugins` 主要记录了每个需要加载的插件的位置以及每个插件的命令行参数
### Plugin Loading
然后是插件加载阶段，在这个阶段加载动态库
```c
static int plugin_load(struct qemu_plugin_desc *desc, const qemu_info_t *info, Error **errp);
```
要求每个 plugin 定义 `qemu_plugin_install` 这个回调函数，以及 `qemu_plugin_version` 符号指定该 plugin 使用的 API 版本
### vCPU Initialization
在 `CPUState` 的初始化函数 `cpu_common_initfn` 中，会将 `qemu_plugin_vcpu_init__async` 函数放到这个 vCPU 的工作队列中（后续在 `cpu_loop` 函数中进行处理）。`qemu_plugin_vcpu_init__async` 函数负责更新 `qemu_plugin_state.num_vcpus` 字段，视情况增长 scoreboard，以及回调所有注册在 `QEMU_PLUGIN_EV_VCPU_INIT` 阶段的函数等等
### TCG Code Injection
在若干回调注册函数的 `qemu_plugin_event` 中，最重要的是 `QEMU_PLUGIN_EV_VCPU_TB_TRANS`，注册到这个阶段的回调函数会在翻译完成一个 translation block 时被调用
```c
struct qemu_plugin_tb {
    GPtrArray *insns;
    size_t n; // 这个 Translation Block 中包含的指令数

    /* if set, the TB calls helpers that might access guest memory */
    bool mem_helper;

    GArray *cbs;
};
/**
 * typedef qemu_plugin_vcpu_tb_trans_cb_t - translation callback
 * @id: unique plugin id
 * @tb: opaque handle used for querying and instrumenting a block.
 */
typedef void (*qemu_plugin_vcpu_tb_trans_cb_t)(qemu_plugin_id_t id,
                                               struct qemu_plugin_tb *tb);
```
这个 callback 类型为 `qemu_plugin_vcpu_tb_trans_cb_t`，除了 id 之外，接受一个 `qemu_plugin_tb` 参数，所有需要注入的代码都会存储在这个 `qemu_plugin_tb` 中

`cbs` 字段是类型为 `qemu_plugin_dyn_cb` 的动态数组，调用 `qemu_plugin_register_vcpu_tb_exec_inline_per_vcpu` 等 api 进行代码注入时都会记录一个 `qemu_plugin_dyn_cb` 表项到 `cbs` 中。这些代码会在 translation block 执行前被执行

`qemu_plugin_tb` 的 `insns` 字段是一个类型为 `qemu_plugin_insn` 的动态数组
```c
/* Internal context for instrumenting an instruction */
struct qemu_plugin_insn {
    uint64_t vaddr;  // 这个指令的 pc 地址
    GArray *insn_cbs;
    GArray *mem_cbs;
    uint8_t len;    // 指令的编码长度
    bool calls_helpers;

    /* if set, the instruction calls helpers that might access guest memory */
    bool mem_helper;
};
```
它的 `insn_cbs` 和 `mem_cbs` 字段记录与这条指令相关的代码注入，这些代码会在这条指令执行前被执行

然后我们大概说说这些注入是如何实现的。tcg 将每条 guest 指令翻译到 tcg ir 时会进行打桩，例如生成 `INDEX_op_insn_start`，`INDEX_op_plugin_cb from PLUGIN_GEN_FROM_TB`，`INDEX_op_plugin_cb from PLUGIN_GEN_FROM_INSN` 等伪 tcg ir。然后在 `plugin_gen_inject` 函数中，将 `qemu_plugin_tb` 中注册的所有的需要注入的指令，翻译为对应的 tcg ir，插入到对应的桩的位置，然后将这些桩删除掉

TODO：tcg 中的 basic block 是啥样的，翻译跳转指令时一定会退出 tcg 吗
