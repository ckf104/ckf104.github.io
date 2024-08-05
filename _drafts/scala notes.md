# scala 随记

* this.getClass.getName -> java binary name
* private constructor

```scala
class AnnotationSeq private (underlying: Seq[Annotation]) {
  def toSeq: Seq[Annotation] = underlying
}
object AnnotationSeq {
  def apply(xs: Seq[Annotation]): AnnotationSeq = new AnnotationSeq(xs)
}
```

* covariance :`+T` , contravariance  `-T` , context bound: `A : B` view bound : `A <% B`, upper/lower bound `A <: B, A >: B`

* `A <:< B` : 要求`A`是`B`的子类, `A =:= B`: 要求`A`和`B`相同 -->  `op[T1, T2]` 可以写为`T1 op T2`

  

```scala
val qh = new (Int Function1 String){
   override def apply(v1: Int): String = s"${v1 + 1}"
}
```

* [alias this](http://enear.github.io/2018/10/08/self-arrow/)，并不局限于使用`self`，例如在`Enumeration.scala`中`thisenum =>`，虽然可以直接使用`outerclass.this`来引用就是了
* `extends (A => B)`等价于`extends Function1[A, B]`
* **java generics**: Type Erasure
* https://typelevel.org/blog/2015/07/13/type-members-parameters.html，我觉得`type member`和`type parameter`没什么本质区别吧，都是依赖于`Type Erasure`
* Existential types --> type abstract ? Java中一个类似的语法是question mark as type parameter

```scala
class TT[A](val a: A){
  def pri(t: TT[_]) ={
    println(t.a)
    t.a
  }
}

// pri 函数在实际上被翻译为java, 字节码中实际视为 TT<Object>
  public java.lang.Object pri(TT<?>);
    Code:
       0: getstatic     #28                 // Field scala/Predef$.MODULE$:Lscala/Predef$;
       3: aload_1
       4: invokevirtual #30                 // Method a:()Ljava/lang/Object;
       7: invokevirtual #34                 // Method scala/Predef$.println:(Ljava/lang/Object;)V
      10: aload_1
      11: invokevirtual #30                 // Method a:()Ljava/lang/Object;
      14: areturn

// 更抽象的是，还可以用到 self type 里面？
// 我想这表达的意思就是，任何一个都可以，比如这里的self type,就是mixin任何一个trans[A]就行了
trait trans[A] {
  def pri(a: A): A
}
// H with trans[_$1] forSome {type _$1}
trait H {
  self: trans[_ >: String] =>
  type F = trans[A] forSome {type A}
  def qq = pri("djsakl")
}
```

* Covariant = retrieves or produces T.    Contravariant = acts on, or consumes T.
* Singleton type: [SIP-23](https://docs.scala-lang.org/sips/42.type.html), [trait Singleton](https://www.scala-lang.org/api/2.13.x/scala/Singleton.html)
* @在pattern match中的作用：https://stackoverflow.com/questions/2359014/scala-operator/2359365#2359365
* scala reflect, mirror, macro: 
  * https://docs.scala-lang.org/overviews/macros/overview.html
  * https://docs.scala-lang.org/overviews/reflection/symbols-trees-types.html

* `func _` --> [partially applied function](https://stackoverflow.com/questions/39573823/underscore-after-function)





## Chisel and Firrtle

```scala
trait Phase extends TransformLike[AnnotationSeq] with DependencyAPI[Phase]
// AnnotationSeq -> AnnotationSeq


trait Transform extends TransformLike[CircuitState] with DependencyAPI[Transform]
// CircuitState -> CircuitState
// CircuitState中包含了AnnotationSeq以及Circuit
// 纯粹修改Circuit的是 `trait pass`
```



```
Shell Options
  <arg>...                 optional unbounded args
  -td, --target-dir <directory>
                           Work directory (default: '.')
  -faf, --annotation-file <file>
                           An input annotation file
  -foaf, --output-annotation-file <file>
                           An output annotation file
  --show-registrations     print discovered registered libraries and transforms
  --help                   prints this usage text
Logging Options
  -ll, --log-level {error|warn|info|debug|trace}
                           Set global logging verbosity (default: None
  -cll, --class-log-level <FullClassName:{error|warn|info|debug|trace}>...
                           Set per-class logging verbosity
  --log-file <file>        Log to a file instead of STDOUT
  -lcn, --log-class-names  Show class names and log level in logging output
Chisel Front End Options
  -chnrf, --no-run-firrtl  Do not run the FIRRTL compiler (generate FIRRTL IR from Chisel and exit)
  --full-stacktrace        Show full stack trace when an exception is thrown
  --throw-on-first-error   Throw an exception on the first error instead of continuing
  --warnings-as-errors     Treat warnings as errors
  --warn:reflective-naming
                           Warn when reflective naming changes the name of signals (3.6 migration)
  --chisel-output-file <file>
                           Write Chisel-generated FIRRTL to this file (default: <circuit-main>.fir)
  --module <package>.<module>
                           The name of a Chisel module to elaborate (module must be in the classpath)
FIRRTL Compiler Options
  -i, --input-file <file>  An input FIRRTL file
  -I, --input-directory <directory>
                           A directory of FIRRTL files
  -o, --output-file <file>
                           The output FIRRTL file
  --info-mode <ignore|use|gen|append>
                           Source file info handling mode (default: use)
  --firrtl-source <string>
                           An input FIRRTL circuit string
  -fct, --custom-transforms <package>.<class>
                           Run these transforms during compilation
  --change-name-case <lower|upper>
                           Convert all FIRRTL names to a specific case
  -X, --compiler <none|high|middle|low|verilog|mverilog|sverilog>
                           The FIRRTL compiler to use (default: verilog)
  -E, --emit-circuit <chirrtl|high|middle|low|verilog|mverilog|sverilog>
                           Run the specified circuit emitter (all modules in one file)
  -P, --emit-circuit-protobuf <chirrtl|mhigh|high|middle|low|low-opt>
                           Run the specified circuit emitter generating a Protocol Buffer format
  -e, --emit-modules <chirrtl|high|middle|low|verilog|mverilog|sverilog>
                           Run the specified module emitter (one file per module)
  -p, --emit-modules-protobuf <chirrtl|mhigh|high|middle|low|low-opt>
                           Run the specified module emitter (one protobuf per module)
  --emission-options <disableMemRandomization,disableRegisterRandomization>
                           Options to disable random initialization for memory and registers
  --no-dedup               Do NOT dedup modules
  --warn:no-scala-version-deprecation
                           (deprecated, this option does nothing)
  --pretty:no-expr-inlining
                           Disable expression inlining
  --dont-fold <primop>     Disable folding of specific primitive operations
  --target:fpga            Choose compilation strategies that generally favor FPGA targets
  --start-from <chirrtl|mhigh|high|middle|low|low-opt>
                           
  --no-cse                 Disable common subexpression elimination
  --allow-unrecognized-annotations
                           Allow annotation files to contain unrecognized annotations
  --wave-viewer-script <value>
                           <json>, you can combine them like 'json', pass empty string will generate json
FIRRTL Transform Options
  --no-dce                 Disable dead code elimination
  --no-check-comb-loops    Disable combinational loop checking
  -fil, --inline <circuit>[.<module>[.<instance>]][,...]
                           Inline selected modules
  -clks, --list-clocks -c:<circuit>:-m:<module>:-o:<filename>
                           List which signal drives each clock of every descendent of specified modules
  --no-asa                 Disable assert submodule assumptions
  --no-constant-propagation
                           Disable constant propagation elimination
AspectLibrary
  --with-aspect <package>.<aspect>
                           The name/class of an aspect to compile with (must be a class/object without arguments!)
MemLib Options
  -firw, --infer-rw        Enable read/write port inference for memories
  -frsq, --repl-seq-mem -c:<circuit>:-i:<file>:-o:<file>
                           Blackbox and emit a configuration file for each sequential memory
  -gmv, --gen-mem-verilog <blackbox|full>
                           Blackbox and emit a Verilog behavior model for each sequential memory
```

一些重要的`phase`:

* `Elaborate`，这个`phase`把`ChiselGeneratorAnnotation`转换为`ChiselCircuitAnnotation`和`DesignAnnotation`，分别包含了生成的`Circuit`电路和`RawModule`.  
* `Convert`，将`ChiselGeneratorAnnotation`中携带的`Circuit`转换成`firrtl.Circuit`，wrap到`FirrtlCircuitAnnotation`中。另外，这一步也将`ChiselAnnotation`转为`Annotation`（我并不清楚为什么要额外添加一个`ChiselAnnotation`，在代码中`BlackBox`的实现上，`addResource`函数会生成一个`ChiselAnnotation`包含源文件路径和模块等信息，最后在`Convert`中将其转换为`BlackBoxInlineAnno`这个`Annotation`）
* 接下来最重要的是`MaybeFirrtlStage`，将`FirrtlStage`作为一个`phase`加入进来
  * `FirrtlPhase`中跑的第一个重要的`Phase`是`AddCircuit`，把命令行中指定的`firrtl`文件和字符串加进来了（**因此现在有多个`FirrtlCircuitAnnotation`，这该如何处理？** --> 多个`Circuit`互不干扰，分别编译）

```
======== Starting chisel3.stage.phases.Checks ========
----------------------------------------------------------------

Time: 0.7 ms
======== Finished chisel3.stage.phases.Checks ========
======== Starting chisel3.stage.phases.Elaborate ========
Elaborating design...
Done elaborating.
-------------------------------------------------------------------

Time: 77.4 ms
======== Finished chisel3.stage.phases.Elaborate ========
======== Starting chisel3.stage.phases.AddImplicitOutputFile ========
-------------------------------------------------------------------------------

Time: 1.1 ms
======== Finished chisel3.stage.phases.AddImplicitOutputFile ========
======== Starting chisel3.stage.phases.AddImplicitOutputAnnotationFile ========
-----------------------------------------------------------------------------------------

Time: 1.1 ms
======== Finished chisel3.stage.phases.AddImplicitOutputAnnotationFile ========
======== Starting chisel3.stage.phases.MaybeAspectPhase ========
--------------------------------------------------------------------------

Time: 0.5 ms
======== Finished chisel3.stage.phases.MaybeAspectPhase ========
======== Starting chisel3.stage.phases.AddSerializationAnnotations ========
-------------------------------------------------------------------------------------

Time: 2.3 ms
======== Finished chisel3.stage.phases.AddSerializationAnnotations ========
======== Starting chisel3.stage.phases.Convert ========
-----------------------------------------------------------------

Time: 18.1 ms
======== Finished chisel3.stage.phases.Convert ========
======== Starting chisel3.stage.phases.MaybeFirrtlStage ========
======== Starting firrtl.stage.phases.ConvertCompilerAnnotations ========
-----------------------------------------------------------------------------------

Time: 0.8 ms
======== Finished firrtl.stage.phases.ConvertCompilerAnnotations ========
======== Starting firrtl.stage.phases.AddDefaults ========
--------------------------------------------------------------------

Time: 2.0 ms
======== Finished firrtl.stage.phases.AddDefaults ========
======== Starting firrtl.stage.phases.AddImplicitEmitter ========
---------------------------------------------------------------------------

Time: 1.4 ms
======== Finished firrtl.stage.phases.AddImplicitEmitter ========
======== Starting firrtl.stage.phases.Checks ========
---------------------------------------------------------------

Time: 2.0 ms
======== Finished firrtl.stage.phases.Checks ========
======== Starting firrtl.stage.phases.AddCircuit ========
-------------------------------------------------------------------

Time: 0.5 ms
======== Finished firrtl.stage.phases.AddCircuit ========
======== Starting firrtl.stage.phases.AddImplicitOutputFile ========
------------------------------------------------------------------------------

Time: 2.0 ms
======== Finished firrtl.stage.phases.AddImplicitOutputFile ========
======== Starting firrtl.stage.phases.Compiler ========
Computed transform order in: 309.3 ms
Determined Transform order that will be executed:
  firrtl.stage.transforms.Compiler
  ├── firrtl.transforms.formal.ConvertAsserts$
  ├── firrtl.transforms.formal.RemoveVerificationStatements
  ├── firrtl.stage.transforms.CheckScalaVersion
  ├── firrtl.passes.CheckChirrtl$
  ├── firrtl.passes.CInferTypes$
  ├── firrtl.passes.CInferMDir$
  ├── firrtl.passes.RemoveCHIRRTL$
  ├── firrtl.annotations.transforms.CleanupNamedTargets
  ├── firrtl.passes.CheckHighForm$
  ├── firrtl.passes.ResolveKinds$
  ├── firrtl.passes.InferTypes$
  ├── firrtl.passes.CheckTypes$
  ├── firrtl.passes.ResolveFlows$
  ├── firrtl.passes.CheckFlows$
  ├── firrtl.passes.InferBinaryPoints
  ├── firrtl.passes.TrimIntervals
  ├── firrtl.passes.InferWidths
  ├── firrtl.passes.CheckWidths$
  ├── firrtl.transforms.InferResets
  ├── firrtl.stage.TransformManager
  │   └── firrtl.passes.CheckTypes$
  ├── firrtl.transforms.DedupModules
  ├── firrtl.transforms.DedupAnnotationsTransform
  ├── firrtl.passes.PullMuxes$
  ├── firrtl.passes.ReplaceAccesses$
  ├── firrtl.passes.ExpandConnects$
  ├── firrtl.passes.ZeroLengthVecs$
  ├── firrtl.stage.TransformManager
  │   └── firrtl.passes.ResolveFlows$
  ├── firrtl.passes.RemoveAccesses$
  ├── firrtl.stage.TransformManager
  │   ├── firrtl.passes.ResolveKinds$
  │   └── firrtl.passes.ResolveFlows$
  ├── firrtl.passes.ExpandWhensAndCheck
  ├── firrtl.stage.TransformManager
  │   ├── firrtl.passes.ResolveKinds$
  │   ├── firrtl.passes.InferTypes$
  │   ├── firrtl.passes.ResolveFlows$
  │   └── firrtl.passes.InferWidths
  ├── firrtl.passes.RemoveIntervals
  ├── firrtl.stage.TransformManager
  │   ├── firrtl.passes.ResolveKinds$
  │   └── firrtl.passes.InferTypes$
  ├── firrtl.passes.ConvertFixedToSInt$
  ├── firrtl.passes.ZeroWidth$
  ├── firrtl.stage.TransformManager
  │   └── firrtl.passes.InferTypes$
  ├── firrtl.passes.LowerTypes$
  ├── firrtl.transforms.formal.AssertSubmoduleAssumptions
  ├── firrtl.stage.TransformManager
  │   └── firrtl.passes.ResolveFlows$
  ├── firrtl.transforms.RemoveReset$
  ├── firrtl.stage.TransformManager
  │   └── firrtl.passes.ResolveFlows$
  ├── firrtl.passes.LegalizeConnects$
  ├── firrtl.transforms.CheckCombLoops
  ├── firrtl.checks.CheckResets
  ├── firrtl.transforms.RemoveWires
  ├── firrtl.stage.TransformManager
  │   └── firrtl.passes.ResolveKinds$
  ├── firrtl.passes.PadWidths$
  ├── firrtl.passes.RemoveValidIf$
  ├── firrtl.transforms.ConstantPropagation
  ├── firrtl.passes.SplitExpressions$
  ├── firrtl.stage.TransformManager
  │   └── firrtl.passes.ResolveKinds$
  ├── firrtl.passes.CommonSubexpressionElimination$
  ├── firrtl.transforms.DeadCodeElimination
  └── firrtl.VerilogEmitter
      ├── firrtl.backends.verilog.LegalizeVerilog$
      ├── firrtl.passes.memlib.VerilogMemDelays$
      ├── firrtl.passes.ResolveFlows$
      ├── firrtl.passes.SplitExpressions$
      ├── firrtl.passes.ResolveKinds$
      ├── firrtl.transforms.CombineCats
      ├── firrtl.transforms.InlineBooleanExpressions
      ├── firrtl.transforms.LegalizeAndReductionsTransform
      ├── firrtl.transforms.DeadCodeElimination
      ├── firrtl.transforms.BlackBoxSourceHelper
      ├── firrtl.transforms.FixAddingNegativeLiterals
      ├── firrtl.transforms.ReplaceTruncatingArithmetic
      ├── firrtl.transforms.InlineBitExtractionsTransform
      ├── firrtl.transforms.PropagatePresetAnnotations
      ├── firrtl.transforms.InlineAcrossCastsTransform
      ├── firrtl.transforms.LegalizeClocksAndAsyncResetsTransform
      ├── firrtl.transforms.FlattenRegUpdate
      ├── firrtl.transforms.DeadCodeElimination
      ├── firrtl.passes.VerilogModulusCleanup$
      ├── firrtl.transforms.VerilogRename
      ├── firrtl.passes.InferTypes$
      ├── firrtl.passes.VerilogPrep$
      └── firrtl.AddDescriptionNodes
======== Starting firrtl.transforms.formal.ConvertAsserts$ ========
-----------------------------------------------------------------------------

Time: 4.4 ms
======== Finished firrtl.transforms.formal.ConvertAsserts$ ========
======== Starting firrtl.transforms.formal.RemoveVerificationStatements ========
------------------------------------------------------------------------------------------

Time: 1.1 ms
======== Finished firrtl.transforms.formal.RemoveVerificationStatements ========
======== Starting firrtl.stage.transforms.CheckScalaVersion ========
------------------------------------------------------------------------------

Time: 0.1 ms
======== Finished firrtl.stage.transforms.CheckScalaVersion ========
======== Starting firrtl.passes.CheckChirrtl$ ========
----------------------------------------------------------------

Time: 21.9 ms
======== Finished firrtl.passes.CheckChirrtl$ ========
======== Starting firrtl.passes.CInferTypes$ ========
---------------------------------------------------------------

Time: 11.0 ms
======== Finished firrtl.passes.CInferTypes$ ========
======== Starting firrtl.passes.CInferMDir$ ========
--------------------------------------------------------------

Time: 3.6 ms
======== Finished firrtl.passes.CInferMDir$ ========
======== Starting firrtl.passes.RemoveCHIRRTL$ ========
-----------------------------------------------------------------

Time: 6.2 ms
======== Finished firrtl.passes.RemoveCHIRRTL$ ========
======== Starting firrtl.annotations.transforms.CleanupNamedTargets ========
--------------------------------------------------------------------------------------

Time: 7.2 ms
======== Finished firrtl.annotations.transforms.CleanupNamedTargets ========
======== Starting firrtl.passes.CheckHighForm$ ========
-----------------------------------------------------------------

Time: 1.0 ms
======== Finished firrtl.passes.CheckHighForm$ ========
======== Starting firrtl.passes.ResolveKinds$ ========
----------------------------------------------------------------

Time: 4.3 ms
======== Finished firrtl.passes.ResolveKinds$ ========
======== Starting firrtl.passes.InferTypes$ ========
--------------------------------------------------------------

Time: 5.6 ms
======== Finished firrtl.passes.InferTypes$ ========
======== Starting firrtl.passes.CheckTypes$ ========
--------------------------------------------------------------

Time: 3.4 ms
======== Finished firrtl.passes.CheckTypes$ ========
======== Starting firrtl.passes.ResolveFlows$ ========
----------------------------------------------------------------

Time: 2.6 ms
======== Finished firrtl.passes.ResolveFlows$ ========
======== Starting firrtl.passes.CheckFlows$ ========
--------------------------------------------------------------

Time: 3.6 ms
======== Finished firrtl.passes.CheckFlows$ ========
======== Starting firrtl.passes.InferBinaryPoints ========
--------------------------------------------------------------------

Time: 10.8 ms
======== Finished firrtl.passes.InferBinaryPoints ========
======== Starting firrtl.passes.TrimIntervals ========
----------------------------------------------------------------

Time: 6.7 ms
======== Finished firrtl.passes.TrimIntervals ========
======== Starting firrtl.passes.InferWidths ========
--------------------------------------------------------------

Time: 7.8 ms
======== Finished firrtl.passes.InferWidths ========
======== Starting firrtl.passes.CheckWidths$ ========
---------------------------------------------------------------

Time: 3.3 ms
======== Finished firrtl.passes.CheckWidths$ ========
======== Starting firrtl.transforms.InferResets ========
------------------------------------------------------------------

Time: 6.1 ms
======== Finished firrtl.transforms.InferResets ========
======== Starting firrtl.passes.CheckTypes$ ========
--------------------------------------------------------------

Time: 0.1 ms
======== Finished firrtl.passes.CheckTypes$ ========
======== Starting firrtl.transforms.DedupModules ========
-------------------------------------------------------------------

Time: 28.9 ms
======== Finished firrtl.transforms.DedupModules ========
======== Starting firrtl.transforms.DedupAnnotationsTransform ========
--------------------------------------------------------------------------------

Time: 2.6 ms
======== Finished firrtl.transforms.DedupAnnotationsTransform ========
======== Starting firrtl.passes.PullMuxes$ ========
-------------------------------------------------------------

Time: 1.2 ms
======== Finished firrtl.passes.PullMuxes$ ========
======== Starting firrtl.passes.ReplaceAccesses$ ========
-------------------------------------------------------------------

Time: 1.5 ms
======== Finished firrtl.passes.ReplaceAccesses$ ========
======== Starting firrtl.passes.ExpandConnects$ ========
------------------------------------------------------------------

Time: 1.1 ms
======== Finished firrtl.passes.ExpandConnects$ ========
======== Starting firrtl.passes.ZeroLengthVecs$ ========
------------------------------------------------------------------

Time: 2.3 ms
======== Finished firrtl.passes.ZeroLengthVecs$ ========
======== Starting firrtl.passes.ResolveFlows$ ========
----------------------------------------------------------------

Time: 0.2 ms
======== Finished firrtl.passes.ResolveFlows$ ========
======== Starting firrtl.passes.RemoveAccesses$ ========
------------------------------------------------------------------

Time: 3.6 ms
======== Finished firrtl.passes.RemoveAccesses$ ========
======== Starting firrtl.passes.ResolveKinds$ ========
----------------------------------------------------------------

Time: 0.1 ms
======== Finished firrtl.passes.ResolveKinds$ ========
======== Starting firrtl.passes.ResolveFlows$ ========
----------------------------------------------------------------

Time: 0.1 ms
======== Finished firrtl.passes.ResolveFlows$ ========
======== Starting firrtl.passes.ExpandWhensAndCheck ========
----------------------------------------------------------------------

Time: 13.2 ms
======== Finished firrtl.passes.ExpandWhensAndCheck ========
======== Starting firrtl.passes.ResolveKinds$ ========
----------------------------------------------------------------

Time: 0.2 ms
======== Finished firrtl.passes.ResolveKinds$ ========
======== Starting firrtl.passes.InferTypes$ ========
--------------------------------------------------------------

Time: 0.4 ms
======== Finished firrtl.passes.InferTypes$ ========
======== Starting firrtl.passes.ResolveFlows$ ========
----------------------------------------------------------------

Time: 0.1 ms
======== Finished firrtl.passes.ResolveFlows$ ========
======== Starting firrtl.passes.InferWidths ========
--------------------------------------------------------------

Time: 1.5 ms
======== Finished firrtl.passes.InferWidths ========
======== Starting firrtl.passes.RemoveIntervals ========
------------------------------------------------------------------

Time: 4.5 ms
======== Finished firrtl.passes.RemoveIntervals ========
======== Starting firrtl.passes.ResolveKinds$ ========
----------------------------------------------------------------

Time: 0.1 ms
======== Finished firrtl.passes.ResolveKinds$ ========
======== Starting firrtl.passes.InferTypes$ ========
--------------------------------------------------------------

Time: 0.5 ms
======== Finished firrtl.passes.InferTypes$ ========
======== Starting firrtl.passes.ConvertFixedToSInt$ ========
----------------------------------------------------------------------

Time: 5.6 ms
======== Finished firrtl.passes.ConvertFixedToSInt$ ========
======== Starting firrtl.passes.ZeroWidth$ ========
-------------------------------------------------------------

Time: 4.9 ms
======== Finished firrtl.passes.ZeroWidth$ ========
======== Starting firrtl.passes.InferTypes$ ========
--------------------------------------------------------------

Time: 0.7 ms
======== Finished firrtl.passes.InferTypes$ ========
======== Starting firrtl.passes.LowerTypes$ ========
--------------------------------------------------------------

Time: 13.8 ms
======== Finished firrtl.passes.LowerTypes$ ========
======== Starting firrtl.transforms.formal.AssertSubmoduleAssumptions ========
----------------------------------------------------------------------------------------

Time: 0.9 ms
======== Finished firrtl.transforms.formal.AssertSubmoduleAssumptions ========
======== Starting firrtl.passes.ResolveFlows$ ========
----------------------------------------------------------------

Time: 0.2 ms
======== Finished firrtl.passes.ResolveFlows$ ========
======== Starting firrtl.transforms.RemoveReset$ ========
-------------------------------------------------------------------

Time: 5.5 ms
======== Finished firrtl.transforms.RemoveReset$ ========
======== Starting firrtl.passes.ResolveFlows$ ========
----------------------------------------------------------------

Time: 0.2 ms
======== Finished firrtl.passes.ResolveFlows$ ========
======== Starting firrtl.passes.LegalizeConnects$ ========
--------------------------------------------------------------------

Time: 0.9 ms
======== Finished firrtl.passes.LegalizeConnects$ ========
======== Starting firrtl.transforms.CheckCombLoops ========
---------------------------------------------------------------------

Time: 10.0 ms
======== Finished firrtl.transforms.CheckCombLoops ========
======== Starting firrtl.checks.CheckResets ========
--------------------------------------------------------------

Time: 2.2 ms
======== Finished firrtl.checks.CheckResets ========
======== Starting firrtl.transforms.RemoveWires ========
------------------------------------------------------------------

Time: 4.0 ms
======== Finished firrtl.transforms.RemoveWires ========
======== Starting firrtl.passes.ResolveKinds$ ========
----------------------------------------------------------------

Time: 0.1 ms
======== Finished firrtl.passes.ResolveKinds$ ========
======== Starting firrtl.passes.PadWidths$ ========
-------------------------------------------------------------

Time: 5.1 ms
======== Finished firrtl.passes.PadWidths$ ========
======== Starting firrtl.passes.RemoveValidIf$ ========
-----------------------------------------------------------------

Time: 2.0 ms
======== Finished firrtl.passes.RemoveValidIf$ ========
======== Starting firrtl.transforms.ConstantPropagation ========
--------------------------------------------------------------------------

Time: 18.6 ms
======== Finished firrtl.transforms.ConstantPropagation ========
======== Starting firrtl.passes.SplitExpressions$ ========
--------------------------------------------------------------------

Time: 2.4 ms
======== Finished firrtl.passes.SplitExpressions$ ========
======== Starting firrtl.passes.ResolveKinds$ ========
----------------------------------------------------------------

Time: 0.2 ms
======== Finished firrtl.passes.ResolveKinds$ ========
======== Starting firrtl.passes.CommonSubexpressionElimination$ ========
----------------------------------------------------------------------------------

Time: 2.4 ms
======== Finished firrtl.passes.CommonSubexpressionElimination$ ========
======== Starting firrtl.transforms.DeadCodeElimination ========
--------------------------------------------------------------------------

Time: 9.9 ms
======== Finished firrtl.transforms.DeadCodeElimination ========
======== Starting firrtl.VerilogEmitter ========
Main module will be renamed. Renaming circuit: '~HelloLED' -> ['~HelloLED']
----------------------------------------------------------

Time: 133.3 ms
======== Finished firrtl.VerilogEmitter ========
Total FIRRTL Compile Time: 426.4 ms
-----------------------------------------------------------------

Time: 786.9 ms
======== Finished firrtl.stage.phases.Compiler ========
--------------------------------------------------------------------------

Time: 920.0 ms
======== Finished chisel3.stage.phases.MaybeFirrtlStage ========

Process finished with exit code 0
```

