**TODO：看 niagara 源码的时候注意看下为什么人家可以将 niagara 实现为一个插件，而不需要侵入式地修改 UE 的源码**

## Niagara

UNiagaraComponent -> FNiagaraSystemInstanceController -> FNiagaraSystemInstance -> FNiagaraSystemSimulation

FNiagaraWorldManager -> FNiagaraSystemSimulation

前者感觉像是后者的一层封装，UNiagaraComponent 中包含一个 Controller 指针，在该 component activate 时，会 new 一个 Controller，这个 Controller 内部再 new 一个 FNiagaraSystemInstance。不太理解为什么 Controller 中指向FNiagaraSystemInstance 时使用的共享指针

FNiagaraSystemInstance 初始化时从 FNiagaraWorldManager 中获取这个 UNiagaraSystem 对应的 asset 的 FNiagaraSystemSimulation（没有则创建一个新的），然后调用这个 Simulation 的 AddInstance 方法，把自己加到 Simulation 的 SystemInstancesPerState 字段中

另外，SysInstance 会根据 UNiagaraSystem 构建 FNiagaraEmitterInstance，它的 Emitter 字段存储了所有的 EmitInstance

### Tick

FNiagaraWorldManager 中包含了 FTickFunction 类字段，使得 FNiagaraWorldManager 支持 Tick 操作

FNiagaraWorldManager 内部有一个 TMap 数组，包含了所有的 FNiagaraSystemSimulation，在 Manager 的 Tick 函数中，会依次调用这些 Simulation 的 Tick_GameThread 函数。然后每个 Simulation 内部根据自己的 SystemInstancesPerState 字段：

* 调用处于 Running 状态的 SysInstance 的 Tick_GameThread 函数，这个函数内部感觉主要在更新一堆系统参数，像 FNiagaraSystemParameters 这些
* 调用处于 PendingSpawn 状态的 SysInstance 的 Tick_GameThread 函数，然后将其状态切换为 Running。**那其它例如 Spawn 状态呢**
* 创建 FNiagaraSystemSimulationTickConcurrentTask，这个 Task 负责在 worker thread 中调用 Simulation 的 Tick_Concurrent 函数

在 Simulation 的 Tick_Concurrent 函数中，大概做了这些事情

* 对每个 SysInstance，调用它的 TickInstanceParameters_Concurrent 函数，将一些需要计算的系统参数的更新延迟到这个阶段来避免阻塞 GameThread
* 调用 FNiagaraSystemSimulation::PrepareForSystemSimulate 函数，这个函数主要把一些参数例如 SysInstance 的 InstParameters（这个包含了 UserParameters），以及 GlobalParameters，SystemParameters，OwnerParameters 等复制到 SpawnInstanceParameterDataSet 和 UpdateInstanceParameterDataSet 中
* 调用 FNiagaraSystemSimulation::SpawnSystemInstances 函数，这个函数内部会调用 Spawn System 阶段的脚本，这里使用了两个 FNiagaraDataSet，一个是 Main DataSet，一个是 SpawnInstanceParameterDataSet
* 调用 FNiagaraSystemSimulation::UpdateSystemInstances 函数，这个函数内部会调用 Update System 阶段的脚本，这里使用了两个 FNiagaraDataSet，一个是 Main DataSet，一个是 UpdateInstanceParameterDataSet

设置 fx.DumpSystemData 为 1，从 dump 的文字来看，Main DataSet 对应 System Data，SpawnInstanceParameterDataSet 对应 Spawn Instance Parameter Data，UpdateInstanceParameterDataSet 对应 Update Instance Parameter Data。我猜测大概就是 Main DataSet 是表示 System 自己的参数数据，而剩下两个表示外部提供的参数数据

* 调用 FNiagaraSystemSimulation::TransferSystemSimResults 函数，这个函数会将 Main DataSet 中的一些数据复制到 Emitter 的 SpawnContext 和 UpdateContext 的 Parameters 中
* SysInstance 的 Tick_Concurrent



### Parameters and Data

```c++
USTRUCT()
struct FNiagaraDataSetCompiledData
{
    /** Variables in the data set. */
	UPROPERTY()
	TArray<FNiagaraVariableBase> Variables; // 有哪些变量

	/** Data describing the layout of variable data. */
	UPROPERTY()
	TArray<FNiagaraVariableLayoutInfo> VariableLayouts; // 变量的 layout
    
    /** Total number of components of each type in the data set. */
	UPROPERTY()
	uint32 TotalFloatComponents;

	UPROPERTY()
	uint32 TotalInt32Components;

	UPROPERTY()
	uint32 TotalHalfComponents;
    // Other Variables
};
```

FNiagaraDataSetCompiledData 是一个记录 NiagaraSystem 中用到的变量的元信息，从引用关系上来看，FNiagaraDataSet 中包含 FNiagaraDataSetCompiledData 和 FNiagaraDataBuffer，后者包含了实际的数据，前者描述了后者中有哪些变量，每个变量在 buffer 中的位置，以及在虚拟机的寄存器中的位置（见 FNiagaraDataBuffer::BuildRegisterTable 函数）

```c++
/** Base storage class for Niagara parameter values. */
USTRUCT()
struct FNiagaraParameterStore
{
    /** Storage for the set of variables that are represented by this ParameterStore.  Shouldn't be accessed directly, instead use
	ReadParameterVariables() */
	UPROPERTY()
	TArray<FNiagaraVariableWithOffset> SortedParameterOffsets;

	/** Buffer containing parameter data. Indexed using offsets in ParameterOffsets */
	UPROPERTY()
	TArray<uint8> ParameterData;
    
    /** Bindings between this parameter store and others we push data into when we tick. */
	typedef TPair<FNiagaraParameterStore*, FNiagaraParameterStoreBinding> BindingPair;
	TArray<BindingPair> Bindings;
    
    // Other Variables
};

/**
* Extension of the base parameter store to allow the user in the editor to use variable names without 
* the "User." namespace prefix. The names without the prefix just redirect to the original variables, it is just done
* for better usability.
*/
USTRUCT()
struct FNiagaraUserRedirectionParameterStore : public FNiagaraParameterStore
{
    /** Map from the variables with shortened display names to the original variables with the full namespace */
	UPROPERTY()
	TMap<FNiagaraVariable, FNiagaraVariable> UserParameterRedirects;
};
```

目前的理解是 FNiagaraParameterStore 用于储存 UserParameter。这个 Redirection 子类主要做一个重命名参数。这个 Bindings 字段用于变量值的传递。 UNiagaraComponent 中有一个 OverridingParameters 字段，我们修改的 UserParameter 的值会存储在这里，并且 SysInstance 的 InstanceParameters 字段会绑定到它上面，在 ParameterStore 的 Tick 函数中这些变量会传递到 SysInstance 的 InstanceParameters 上

FNiagaraParameterStore

​	-> FNiagaraUserRedirectionParameterStore

​	-> FNiagaraScriptInstanceParameterStore

​	-> FNiagaraScriptExecutionParameterStore

FNiagaraParameterStoreToDataSetBinding 结构体中记录了 FNiagaraParameterStore 和 FNiagaraDataSet 的映射关系，它的 ParameterStoreToDataSet 和 DataSetToParameterStore 函数负责将数据在这俩结构间搬运

**在 FNiagaraScriptExecutionContextBase 中的 Parameters 是什么玩意，它的数据被放到了虚拟机的 ConstantBufferTable 里，它的初始值应该来自它要执行的 UNiagaraScript 的  ScriptExecutionParamStore**



TODO: Simulation 中的 MainDataSet, SpawningDataSet, PausedDataSet, SpawnInstanceParameterDataSet, UpdateInstanceParameterDataSet 都是 FNiagaraDataSet，它们分别是干嘛的，为什么不是逐 SysInstance 一个 DataSet

SysInstance 中的一堆参数

* FNiagaraGlobalParameters
* FNiagaraSystemParameters
* FNiagaraOwnerParameters
* FNiagaraEmitterParameters

### ExecutionContext

FNiagaraScriptExecutionContextBase

​	-> FNiagaraScriptExecutionContext

​	-> FNiagaraSystemScriptExecutionContext

