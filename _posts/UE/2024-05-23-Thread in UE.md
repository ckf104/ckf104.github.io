## TLS（Thread Local Storage）

ue 在 unix 平台上的实现就是基于 pthread_key_create，pthread_getspecific，pthread_setspecific 这几个函数。FUnixTLS::AllocTlsSlot 封装 pthread_key_create，它的返回值就是 pthread_key_t。一些全局的 pthread key 包括

```c++
// UnixPlatformProcess.cpp
uint32 FUnixTLS::ThreadIdTLSKey = FUnixTLS::AllocTlsSlot(); // 这个 key 用于存储 thread id
// ThreadingBase.cpp
uint32 FRunnableThread::RunnableTlsSlot = FRunnableThread::GetTlsSlot(); // 这个 key 用于存储当前线程的 FRunnableThread 指针
```

除了 AllocTlsSlot，另外的两个接口函数为 FUnixTLS::SetTlsValue，FUnixTLS::GetTlsValue，分别是 pthread_getspecific 和 pthread_setspecific 的封装

### FTaskTagScope



## Thread Context

FRunnableThread    -- contain pointer -->  Runnable

​	->  FRunnableThreadPThread  ( pthread )

​			-> FRunnableThreadUnix ( unix pthread )

这个类表示一个 thread object，通常由父线程持有，来对子线程进行一些控制，典型的例如 Stop, Kill, WaitForCompletion 等函数，ThreadID 字段记录了这个 thread 的 thread id

FRunnableThread 的 Runnable 字段是 FRunnable 类，表示实际运行的线程，它的 Run 函数是实际的子线程运行的函数

每个创建的线程会被加入到 FThreadManager 中，它是一个全局静态单例。它的 Threads 字段是一个 map，记录了 thread id 到 FRunnableThread 指针的映射

### FEvent

FEvent 是 ue 里封装的同步源语，提供了 trigger，wait 等同步函数。在 unix 系统上其实是对 pthread 中的 conditional variable 的封装，如果是 ManualReset 类型的 FEvent 的话，每次 trigger 会把所有线程唤醒，而 AutoReset 类型则每次只唤醒一个线程（所谓 ManualReset 的含义就是如果要阻塞调用 Wait 的线程的话，得手动将 Triggered 这个字段从 TRIGGERED_ALL 状态设置回 TRIGGERED_NONE）

## Lock-Free Structure in UE

### Hazard Pointer

与 lock free 紧密相关的是 Hazard Pointer，FAAArrayQueue::DequeueHazard 继承自 THazardPointer， [introduction to hazard pointers](https://melodiessim.netlify.app/intro-hazard-ptrs/) 中介绍得特别好。我觉得大体思想和 RCU 特别类似，延迟释放内存。当我要释放一个内存节点时，如果不确定其它线程是否正在使用，就先把这个内存节点保存起来，过一段时间再释放。那过多久才安全呢，RCU 中是在所有进程都上下文切换过之后，而 hazard pointer 中则使用一个 HP 数组，给出了一个显式地判断是否能安全释放的方法

UE 中的 THazardPointer 中的 Hazard 字段就对应可能被多个线程使用的 node，而 Record 字段就是线程局部的 HP，调用 THazardPointer::Get 时获取 node 指针，同时将 node 指针记录到 Record 上，调用 THazardPointer::Retire 则会把 Record 清除

[实现无锁的栈与队列(5)：Hazard Pointer](https://www.cnblogs.com/catch/p/5129586.html) 中谈到一个优化是，没必要给每个线程分配一个 Hazard Record，只需要一个全局的 Hazard Record List，每个线程需要 Record 时从 List 上拿一个过来就行了（当然，这个 List 也是 lock free 的）。UE 中也使用了这个优化。FHazardPointerCollection 就充当这个 Hazard Record List。使用 FHazardPointerCollection::Acquire 函数获取一个 Record 表项。它的 CollectablesTlsSlot 字段利用 TLS，为每个线程分配了一个数组，这是 Hazard Pointer 算法中用到的每个线程的待删除节点数组。每个线程想要删除一个节点时，就调用 FHazardPointerCollection::Delete 函数，将这个节点加入线程局部的待删除节点数组。每隔一段时间，会调用 FHazardPointerCollection::Collect 函数，这个函数会实际地扫描待删除节点数组，并与所有的 Hazard Record 进行对比，如果没有在 Hazard Record 上找到想要删除的节点，就说明该节点安全可以删除，否则将节点重新加入到线程局部的待删除节点数组中

### Fetch-And-Add Array Queue

现在我们来讨论 UE 中的 FAAArrayQueue\<T\> 类，它存储 T* 类型的指针，对外提供了 queue 形式的接口，并且是 mpmc （multi producer multi consumer）安全的

FAAArrayQueue 的内部定义了一个 node 类，每个 node 内部有一个长为 1024 的存储 T* 的数组，不同的 node 实例间串联成一个单链表。FAAArrayQueue 总共只有三个成员，两个 node 指针，分别指向 node 链表的头和尾，还有一个 FHazardPointerCollection，利用 Hazard Pointer 来释放 node。在 FAAArrayQueue 的构造函数中，它会 new 一个 node 节点，然后让自己的两个 node 指针指向这个刚创建的 node 指针

node 类内部还有 deqidx 和 enqidx。这对应了实际的 enqueue 和 dequeue 的位置。当我们调用 FAAArrayQueue::enqueue 时，这个 T* 指针会被压入 tail 指针指向的 node 的存储 T* 的数组的 enqidx 位置。而 FAAArrayQueue::dequeue 则会弹出 head 指针指向的 node 的存储 T* 的数组的 deqidx 处的 T* 指针。那是如何保证 mpmc 安全呢，我们只需要在获取 enqidx 和 deqidx 时使用 Fetch-And-Add 这个原子操作就可以了，这样保证不同的线程不会将 T* 指针压入到同一个位置，也不会弹出时弹出同一个 T* 指针

在 enqueue 函数中，如果使用 Fetch-And-Add 操作获取到的 enqidx 的值大于等于 1024，则说明这个 tail node 已经被装满了，就 new 一个新的 node，将这个新的 node 加入链表，作为新的 tail。类似地在 dequeue 函数中，如果获取到的 deqidx 大于等于 1024，说明这个 head node 已经空了，就应该删除它。这里就是 Hazard Pointer 的用武之地了，用它来保证我们删除 head node 时不会有其它线程正在使用

### Work Stealing Queue

Work Stealing Queue 是另一种支持并发的无锁双端队列结构，它允许同一个线程以 LIFO 的形式向队列头部中压入或者弹出元素，同时允许其它线程从队列尾部 steal 元素（显然，这种数据结构来源于多线程负载均衡的背景）

UE 中它的实现是 TWorkStealingQueue2\<T, uint32 NumItems\>，它内部有三个字段，长为 NumItems 的元素为 T* 的数组，以及 head，tail 指针。这个 T* 数组的元素值除了可能代表一个真实指针，还可以是 Free，Taken 这两种值

TWorkStealingQueue2 对外提供三个方法，Put，Get，Steal。拥有这个队列的线程可以调用 Put 和 Get 方法，其他线程可以调用 Steal 方法来获取队尾的元素。Put 和 Get 方法的实现非常简单，如果当前 Head 指针 + 1 的 slot 为 Free，则 Put 可以压入，并前移 Head 指针。而当前 Head 指针指向的 slot 不为 Free 和 Taken，则可以使用 compare and exchange 原子操作将这个 slot 置换为 Free，后移 Head 指针，然后返回被置换的元素

有一点复杂的是 Steal 函数的实现，它获取 Tail 指针，然后判断 Tail 指针对应的 slot 是否为一个合法的指针，如果是的话使用 compare and exchange 原子操作将这个 slot 置换为 Taken，然后将 Tail 指针前移，最后再将 slot 置换为 Free，返回 slot 中原本的合法指针

```c++
	inline bool Steal(uintptr_t& Item)
	{
		do
		{
			uint32 IdxVer = Tail.load(std::memory_order_acquire);
			uint32 Idx = IdxVer % NumItems;
			uintptr_t Slot = ItemSlots[Idx].Value.load(std::memory_order_acquire);

			if (Slot == uintptr_t(ESlotState::Free))
			{
				return false;
			}
			else if (Slot != uintptr_t(ESlotState::Taken) && ItemSlots[Idx].Value.compare_exchange_weak(Slot, uintptr_t(ESlotState::Taken), std::memory_order_acq_rel))
			{
				if(IdxVer == Tail.load(std::memory_order_acquire))
				{
					uint32 Prev = Tail.fetch_add(1, std::memory_order_release);
					checkSlow(Prev % NumItems == Idx);
					ItemSlots[Idx].Value.store(uintptr_t(ESlotState::Free), std::memory_order_release);
					Item = Slot;
					return true;
				}
				ItemSlots[Idx].Value.store(Slot, std::memory_order_release);
			}
		} while(true);
	}
```

上面的代码引入额外的 Taken 状态，以及在置换为 Taken 状态后还需要检查 Tail 指针是否发生变化，这是必需的。假设没有额外的 Taken 状态，并且此时 queue 已经满了，另外两个线程 B，C 想从线程 A 中偷取一个 item，如果没有 Taken 态，线程 B 和 C 同时获取到了 Tail 指针，然后 B 首先用 compare and exchange 获取到了 Tail 指针指向的 slot 的 item 指针。由于 queue 之前是满的，如果现在 A 线程调用 Put 函数就会发现 Head 指针 + 1 的 slot 空出来了，又在这个 slot 中填充了合法的指针。此时 C 线程使用 compare and exchange 也会成功，导致 B，C 线程都会前移 tail 指针，导致下一个 slot 被跳过去了。现在引入 Taken 态后，A 线程此时不能够压入新的 item，直到 B 线程前移 Tail 指针，将 slot 的状态设置 Free。如果此时 C 线程 compare and exchange 通过，此时比较 Tail 值的判断一定不能通过（因为 B 线程已经前移 Tail 了），从而杜绝了这种 hazard

注：[compare_exchange_weak vs. compare_exchange_strong](https://stackoverflow.com/questions/4944771/stdatomic-compare-exchange-weak-vs-compare-exchange-strong) 中讨论了 weak 和 strong 的区别，主要在于用 LL / SC 实现原子操作的平台上可能产生一些性能差异，**但我其实不能够理解当 LL / SC 失败时如何判断这是否是一个 spurious failure**

### Treiber Stack

[Treiber Stack](https://en.wikipedia.org/wiki/Treiber_stack) 是一个支持并发 pop 和 push 操作的 stack。它基本的实现想法是，内部数据结构使用一个链表而不是数组来实现对外的 LIFO 抽象。使用数组的问题在于 head 指针和数组元素都是 concurrent access，不是很好处理，而使用链表只需要修改 head 指针，而修改 push 进来的新元素或者 pop 出去的元素的 next 指针是 local access

UE 中的 TEventStack\<NodeType\> 实现了这个 Treiber Stack。但有一些额外的 trick

```c++
template<typename NodeType>
class TEventStack {
	struct FTopNode
	{
		uint32 EventIndex;		// All events are stored in an array, so this allows us to pack node info into 32 bit as array index
		uint32 Revision;		// Tagging is used to avoid ABA (https://en.wikipedia.org/wiki/ABA_problem#Tagged_state_reference)
	};
	std::atomic<FTopNode> Top { FTopNode{EVENT_INDEX_NONE, 0} };
	TAlignedArray<NodeType>& NodesArray;
}
```

从上面的 TEventStack 模板类的声明可以看到，Head 指针实际上有两部分组成，EventIndex 充当了实际的 Head 指针，而 Revision 则作为一个单调递增的 ID 来避免 ABA 问题（为什么这里会产生 ABA 问题在 Revision 字段的注释的 wiki 链接中解释得非常清楚了）。EventIndex 的值就是栈顶元素在 NodesArray 中的索引，因此 32bits 就能够作为指针了，保证 FTopNode 的大小只有 64bits，使其能够执行原子操作

### Lock-Free Pointer List

TODO：FLockFreePointerListLIFOBase, FLockFreePointerFIFOBase

## Scheduler Backend

FTaskBase   -- contain --> TTaskDelegate\<FTask*(bool), LOWLEVEL_TASK_SIZE - sizeof(FPackedData) - sizeof(void\*)\>

​	-> FTask （no data member）

### TTaskDelegate

TTaskDelegate 模板类的声明为 TTaskDelegate\<ReturnType(ParamTypes...), TotalSize\> ，它包含两个成员 InlineStorage 和 TTaskDelegateBase，因此 TotalSize 参数实际指明了 TTaskDelegate 的大小

```c++
template<uint32 TotalSize , typename ReturnType, typename... ParamTypes>
class alignas(8) TTaskDelegate<ReturnType(ParamTypes...), TotalSize> {
private:
	static constexpr uint32 InlineStorageSize = TotalSize - sizeof(TTaskDelegateBase);
	mutable char InlineStorage[InlineStorageSize];
	TTaskDelegateBase CallableWrapper;
}

```

而 FTaskBase 总共三个成员，除了 TTaskDelegate 外，还有一个 FPackedData 以及 void* 指针，因此可以看出 FTask 类的大小为 LOWLEVEL_TASK_SIZE

TTaskDelegate 类似于 std::function，可以存储任意的 Callable Object，然后重载了 operator() 对存储的 Callable Object 进行调用。具体实现上运用了 type erasure 的技巧，InlineStorage 字段存储这个 Callable Object，根据 Callable Object 的大小决定在它存储在 InlineStorage 中还是存储在堆上（InlineStorage 只存储一个指针）。TTaskDelegateBase 和它的两个子类 TTaskDelegateDummy，TTaskDelegateImpl 都不包含任何数据成员，但由于有虚函数，所以它们的大小都是 8 字节。TTaskDelegateBase 主要的目的是基于虚函数做转发

```c++
template<typename TCallableType>
struct TTaskDelegateImpl<TCallableType, false> final : TTaskDelegateBase
    
template<typename TCallableType>
struct TTaskDelegateImpl<TCallableType, true> final : TTaskDelegateBase
```

从上面的 TTaskDelegateImpl 模板类的声明可以看出来，它在模板参数中有 Callable Object 的类型，因此它只要重载 TTaskDelegateBase 的 Call 方法，内部将 InlineStorage 强转为 TCallableType 类型就可以了。当 TTaskDelegate 中没有存储 Callable Object 时，CallableWrapper 字段实际上是一个 TTaskDelegateDummy 子类，表示空的情况

### FTaskBase, FTask

FTaskBase 除了包含一个 TTaskDelegate 外，还有一个 userData 指针和 8 字节的 PackedData，userData 指针是可以在 FTask 中自定义数据，没有什么特别的作用。而 PackedData 主要是包含 priority 和 task state

值得注意的是，FTaskBase 中包含的 TTaskDelegate 的模板参数为 FTask*(bool)，而实际传给 TTaskDelegate 的 Callable Object 为

```c++
// version 1
if (bNotCanceled)
{
	FTask* Task = LocalRunnable();
	return Task;
}
return nullptr;

// version 2
if (bNotCanceled)
{
	LocalRunnable();
}
return nullptr;
```

其中 bNotCanceled 是 Callable Object 的 bool 参数，表示这个 task 是否被取消。而选择 version 1 还是 version 2 依赖于传给 FTask 的 Callable Object 的返回值类型是否为 FTask*。这说明 FTask 仅接受不带参数的 Callable Object（见 FTask::Init 函数）

### TLocalQueue, TLocalQueueRegistry

TLocalQueue 类就是每个线程的工作队列，它存放了分配给每个线程的 work。TLocalQueue 的 QueueType 字段标识这个线程是 foreground worker 还是 background worker。每个 task 有优先级，优先级为 High 和 Normal 的为 foreground task，其余为 background task。foreground worker 只会处理 foreground task。每个优先级的 task 在 TLocalQueue 中都有一个 Local Queue，这个 Local Queue 就是前面提到的 Work Stealing Queue。这保证了其它 worker 能够窃取这个线程的 task。TLocalQueue 中还有一个 AffinityQueue 成员，AffinityQueue 的类型为前面讨论过的 Fetch-And-Add Array Queue，它用来存放要求必须在线程上运行的 task

TLocalQueueRegistry 类中为每个优先级的 task 设置了 OverflowQueues

在 worker thread 的主函数 FScheduler::WorkerMain 中，每个 worker 循环遍历这些 queue。如果 worker thread 的 local queue 满了之后，task 就会被压入对应优先级的 OverflowQueue 中。worker thread 选择 task 时，优先会在 local queue 中寻找需要执行的 task，然后在 OverflowQueues 中寻找 task，再考虑从其它 thread 的 local queue 中窃取 task 过来，最后考虑执行 AffinityQueue 中的 task

这里所有的 queue 中保存的 task，就是保存的 FTask*

### FScheduler

FSchedulerTls

​	-> FReserveScheduler

​	-> FScheduler

整个 Scheduler Backend 最上层的对象就是 FScheduler 了。它是一个全局静态单例，负责创建和管理所有的 worker thread

```c++
class FScheduler final : public FSchedulerTls {
    // Other fields are ignored
    TEventStack<FSleepEvent>       SleepEventStack[2] = { WorkerEvents , WorkerEvents };
    TLocalQueueRegistry 		   QueueRegistry;
    TArray<TUniquePtr<FThread>>	   WorkerThreads;
	TAlignedArray<TLocalQueue>	   WorkerLocalQueues;
	TAlignedArray<FSleepEvent>	   WorkerEvents;
}
```

其中 FThread 类的作用类似于 FrunnableThread，就是对一个 worker thread 的句柄。我不是很理解为什么这里需要用 FThread 类。而 FSleepEvent 是对 FEvent 的简单封装，它主要用来控制 worker 的睡眠与唤醒

worker thread 的状态共有四个：Running，Drowsing，Affinity，Sleeping。基本的想法是，如果 worker thread 找不到 task，就进入 Sleeping 状态让出 cpu。Drowsing 状态则是 Running 和 Sleeping 间的过渡态，worker thread 处于 Drowsing 态时会调用 arch-specific 的指令来 spin 一些 cycle 来减少功耗。Affinity 这个态我不知道有啥用。涉及状态切换的地方包括 FScheduler::WorkerMain（Running -> Drowsing -> Sleeping 等），FScheduler::WakeUpWorker（Sleeping -> Running 等），FScheduler::TryLaunchAffinity（Sleeping -> Affinity 等）

要启动 FScheduler，需要调用 FScheduler::StartWorkers 函数，指明需要的 foreground worker 和 background worker 数目

```c++
FScheduler::StartWorkers(uint32 NumForegroundWorkers = 0, uint32 NumBackgroundWorkers = 0);
```

在 StartWorkers 函数中，会为每个 worker thread 创建 TlocalQueue，FSleepEvent，然后创建 FThread 句柄，实际地启动每个 worker thread。每个 worker thread 的主函数为 FScheduler::WorkerMain

FScheduler 对外提供的最重要的两个接口函数是 TryLaunch，TryLaunchAffinity 

```c++
bool FScheduler::TryLaunch(FTask& Task, EQueuePreference QueuePreference, bool bWakeUpWorker);
bool TryLaunchAffinity(FTask& Task, uint32 AffinityIndex)
```

TryLaunch 将 FTask 压入 local queue 或者全局的 OverflowQueue，而 TryLaunchAffinity 则将 FTask 压入 AffinityQueue 中

**TODO: local queue 是否有意义，仅有在 worker thread 自己调用 TryLaunch 时才能压入 local queue 中，但这怎么可能呢**

####  TODO: game thread 和 render thread 这些 nameThread 是怎么处理 task 的

### FReserveScheduler

FReserveScheduler 也是一个全局静态单例，它的 StartWorkers 函数会启动若干 Reserve Workers，顾名思义，这些 workers 平时是都是不干事的，它提供了 DoReserveWorkUntil 函数，这个函数接收一个不带参数，且返回值为 bool 的 Callable Object。调用一次该函数，就会唤醒一个 Reserve Worker，这个 Reserve Worker 会调用 FScheduler::BusyWaitUntil 函数，化身为一个 worker thread，它没有 local queue，因此只能从 OverflowQueue 或者其它 worker thread 的 local queue 中窃取 task。每完成一个 task，它就会调用 Callable Object，检查是否返回值为 true 了。如果是，那么又变为 Reserve Worker，重新睡眠

## Task Graph

FTaskGraphInterface

​	-> FTaskGraphImplementation

​	-> FTaskGraphCompatibilityImplementation

FRunnable, FSingleThreadRunnable

​	-> FTaskThreadBase

​		-> FNamedTaskThread

​		-> FTaskThreadAnyThread

UE 将 Thread 总体分为两类，一类是 NamedThread，包括 RHIThread，GameThread，RenderingThread，另一类是 AnyThread，这对应在 Scheduler Backend 中的众多 worker

FTaskGraphImplementation 类是 UE4 的 task graph 实现，此时还没有 Scheduler Backend，在这个类的构造函数中显式地创建了众多作为 worker 的 AnyThread

UE5 中引入了单独的 Scheduler Backend 后，新的 task graph 实现 FTaskGraphCompatibilityImplementation 的构造函数中不再单独创建 AnyThread，而是直接调用 FScheduler::StartWorkers 函数，让 Scheduler Backend 来创建 worker。原来的 WorkerThreads 字段变为 NamedThreads 字段，表明这个字段现在只包含 NamedThreads

```c++
struct FWorkerThread
{
	/** The actual FTaskThread that manager this task **/
	FTaskThreadBase*	TaskGraphWorker;
	/** For internal threads, the is non-NULL and holds the information about the runable thread that was created. **/
	FRunnableThread*	RunnableThread;
	/** For external threads, this determines if they have been "attached" yet. Attachment is mostly setting up TLS for this individual thread. **/
	bool				bAttached;
};
class FTaskGraphCompatibilityImplementation final : public FTaskGraphInterface
{
   TArray<FWorkerThread> NamedThreads;
}
```

仍然使用 FWorkerThread 也只+

 是为了保证和 UE4 中的 task graph 实现相兼容。实际上现在的 RunnableThread 字段将总是为 nullptr，而 TaskGraphWorker 总是指向 FNamedTaskThread，bAttached 总是为 false





FBaseGraphTask

​	-> TGraphTask\<TTask\>

FGraphEvent

一些对 TTask 类的要求，静态函数 GetSubsequentsMode

```c++
static ESubsequentsMode::Type GetSubsequentsMode();
DoTask
```

TGraphTask 的结构

```c++
class FBaseGraphTask {
    /** FTask in scheduler backend **/
    LowLevelTasks::FTask TaskHandle;
    /**	Thread to execute on, can be ENamedThreads::AnyThread to execute on any unnamed thread **/
	ENamedThreads::Type			ThreadToExecuteOn;
	/**	Number of prerequisites outstanding. When this drops to zero, the thread is queued for execution.  **/
	FThreadSafeCounter			NumberOfPrerequistitesOutstanding; 
}

class TGraphTask : public FBaseGraphTask{
	/** An aligned bit of storage to hold the embedded task **/
	TAlignedBytes<sizeof(TTask),alignof(TTask)> TaskStorage;
	/** Used to sanity check the state of the object **/
	bool						TaskConstructed;
	/** A reference counted pointer to the completion event which lists the tasks that have me as a prerequisite. **/
	FGraphEventRef				Subsequents; 
};

class FGraphEvent {
	/** Threadsafe list of subsequents for the event **/
	TClosableLockFreePointerListUnorderedSingleConsumer<FBaseGraphTask, 0>	SubsequentList;
	/** List of events to wait for until firing. This is not thread safe as it is only legal to fill it in within the context of an executing task. **/
	FGraphEventArray														EventsToWaitFor;
	/** Number of outstanding references to this graph event **/
	FThreadSafeCounter														ReferenceCount;
	ENamedThreads::Type														ThreadToDoGatherOn;  
};

class FConstructor {
		/** The task that created me to assist with embeded task construction and preparation. **/
		TGraphTask*						Owner;
		/** The list of prerequisites. **/
		const FGraphEventArray*			Prerequisites;
		/** If known, the current thread.  ENamedThreads::AnyThread is also fine, and if that is the value, we will determine the current thread, as needed, via TLS. **/
		ENamedThreads::Type				CurrentThreadIfKnown;  
};
```

该 GraphTask 不能先于它的 EventsToWaitFor 字段中包含的 GraphEvent 完成。在 UE 实际的实现中，当该 FGraphEvent 完成后，UE 会启动一个 NullTask，这个 NullTask 复用该 GraphTask 的 GraphEvent，并且将  EventsToWaitFor 字段作为它的 Preqs

每一个 Task 执行完毕后，如果 EventsToWaitFor 字段为空，会检查它的 SubsequentList，将这里面的 Task 的 NumberOfPrerequistitesOutstanding 值减一，减到 0 之后就会调用 FTaskGraphInterface::QueueTask 将 Task 压入调度队列中

FTaskGraphInterface::QueueTask 是对外提供的重要接口。它根据 FBaseGraphTask::ThreadToExecuteOn 来决定将 task 压入到哪个调度队列中。如果是 ThreadToExecuteOn 是 AnyThread，那么会将 Task 压入到 Scheduler Backend 中，由 backend 中的 worker 进行执行。如果 ThreadToExecuteOn 是 Named Thread，那么会将 Task 压入到它的 FThreadTaskQueue 中

FNamedTaskThread 中包含两个 FThreadTaskQueue，一个称为 Main Queue，一个称为 Local Queue，每个 FThreadTaskQueue 中又包含两个 Queue，分别对应高优先级和低优先级的 FBaseGraphTask。具体 Task 被压入到哪个 queue 中取决于 ENamedThreads::Type 的高位 bit 的置位。下面这两个函数是将 Task 压入 Named Thread 中的接口

```c++
void FNamedTaskThread::EnqueueFromThisThread(int32 QueueIndex, FBaseGraphTask* Task);
bool FNamedTaskThread::EnqueueFromOtherThread(int32 QueueIndex, FBaseGraphTask* Task)
```

TODO：NamedThread 中 Local Queue 和 Main Queue 有什么区别，例如 Render Thread 的主函数就是一直处理 MainQueue 上的 Task，那压入 Local Queue 的 Task 怎么办呢？[UE4之TaskGraph系统](https://www.cnblogs.com/kekec/p/13915313.html) 中提到了这俩 queue 的区别



FReturnGraphTask

FAsyncGraphTaskBase

​	-> FAsyncGraphTask

## User API in Task Graph

### AsyncTask



## Task System

FTaskHandle      -- only contain a pointer -->  UE::Tasks::Private::FTaskBase

​	-> TTask\<ResultType\>    (no data member)

UE::Tasks::Private::FTaskBase   --> contain --> FTask, Subsequents, Prerequisites, pipe pointer...

​	-> TTaskWithResult\<ResultType\>    （additional result storage）

​		-> TExecutableTaskBase\<TaskBodyType, ResultType\>   (additional taskbody storage)

​			-> TExecutableTask\<TaskBodyType\>     (no data member)

### FTaskBase

FTaskBase 有一个 RefCount 字段，初始值为 2

## Console Variable

FAutoConsoleObject

​	-> TAutoConsoleVariable\<T\> （用于静态注册 IConsoleVariable）

​	-> FAutoConsoleVariableRef  （用于静态注册 IConsoleVariable，修改它时会修改它引用的外部变量）

​	-> FAutoConsoleCommand      （用于静态注册 IConsoleCommand）

TConsoleVariableData\<T\> （用于保存实际的变量值）

IConsoleManager

​	-> FConsoleManager

IConsoleObject

​	-> IConsoleVariable

​		-> FConsoleVariableBase

​			-> FOtherPlatformValueHelper\<T\>  （可以忽略这一块）

​				-> FConsoleVariable\<T\>

​				-> FConsoleVariableRef\<T\>

​	-> IConsoleCommand

FConsoleManager 的 ConsoleObjects 字段是一个 map，存储了 console object 名称到 IConsoleObject 的映射。ConsoleVariableUnregisteredDelegate 字段，ThreadPropagationCallback 字段

TConsoleVariableData\<T\> 中包含两个 T 类型的值，一个表示 GameThread 上的值，一个表示 RenderThread 上的值

FConsoleVariable\<T\> 的 Data 字段是一个 TConsoleVariableData\<T\> 类型，它包含实际的 console variable 的值，而 FConsoleVariableVariableBase 中包含 Help 字符串等。而 IConsoleVariable 和 IConsoleObject 中仅包含一些接口，不包含实际的数据

FConsoleVariableVariableBase 中包含 Help 字符串等，还包含一个 OnChangedCallback 字段，它是一个多播代理。console variable 的修改发生在 GameThread，如果这个 variable 有 RenderThreadSafe flag，那会调用 ThreadPropagationCallback  来负责完成 TConsoleVariableData\<T\> 中表示 RenderThread 上的值的修改（在 StartRenderingThread 函数中，创建 RenderThread 时会设置 ThreadPropagationCallback 字段，实际的效果就是将这个 copy 操作使用 ENQUEUE_RENDER_COMMAND 宏来在 RenderThread 中异步执行）。最后会调用 OnChangedCallback 进行广播（此时 RenderThread 的 copy 操作可能还未执行）

## Sync Between GameThread and RenderThread

Render Thread 的主函数就是调用 Task Graph 的 ProcessThreadUntilRequestReturn 函数，反复地处理 task 即可。之前提到每个 NamedThread 有 Local Queue 和 Main Queue，**而 ProcessThreadUntilRequestReturn 函数只会从一个 Queue 中取 Task。这里 Render Thread 调用时是从 Main Queue 中取 task，所以我不太清楚这里 Local Queue 有啥作用**

[UE4之TaskGraph系统](https://www.cnblogs.com/kekec/p/13915313.html) 谈到了在哪些地方 GameThread 会调用 task

[UE 多线程渲染](https://www.cnblogs.com/timlly/p/14327537.html) 这篇也很值得一看

ENQUEUE_UNIQUE_RENDER_COMMAND_XXXPARAMETER

### FRenderCommandFence

大致来讲，它的 BeginFence 函数就是塞一个空的 Task 到 Render Thread 中，然后 Wait 函数就是等这个 Task 完成。由于 Named Thread 的 Task Queue 是 FIFO 的，如果我们将 BeginFence 塞的空 Task 和希望同步的 Task 塞到同一个 Queue 中，就可以保证 fence 执行完时其它 task 也都执行完了

**FlushRenderingCommands**





TODO：[threaded-rendering-in-unreal-engine](https://dev.epicgames.com/documentation/en-us/unreal-engine/threaded-rendering-in-unreal-engine) 文档讲得很好，但我现在还没怎么读懂