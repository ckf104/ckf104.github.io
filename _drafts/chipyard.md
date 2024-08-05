```makefile
sim_files=sim_files.f
sim_common_files=sim_files.common.f
ALL_MODS_FILELIST=chipyard.TestHarness.RocketConfig.all.f
TOP_MODS_FILELIST=chipyard.TestHarness.RocketConfig.top.f
MODEL_MODS_FILELIST=chipyard.TestHarness.RocketConfig.model.f

MFC_SMEMS_CONF=chipyard.TestHarness.RocketConfig.mems.conf
MFC_TOP_SMEMS_JSON=gen-collateral/metadata/seq_mems.json
MFC_TOP_HRCHY_JSON=top_module_hierarchy.json
MFC_MODEL_HRCHY_JSON=model_module_hierarchy.json
MFC_MODEL_SMEMS_JSON=gen-collateral/metadata/tb_seq_mems.json
MFC_FILELIST=gen-collateral/filelist.f
MFC_BB_MODS_FILELIST=gen-collateral/firrtl_black_box_resource_files.f
FIRRTL_FILE=chipyard.TestHarness.RocketConfig.fir
ANNO_FILE=chipyard.TestHarness.RocketConfig.anno.json
CHISEL_LOG_FILE=chipyard.TestHarness.RocketConfig.chisel.log
```



```
Usage: chipyard [options] [<arg>...]

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
Chipyard Generator Options
  -LC, --legacy-configs <value>
                           A string of underscore-delimited configs (configs have decreasing precendence from left to right).
Rocket Chip Compiler Options
  -T, --top-module <value>
                           <top module>
  -C, --configs <value>    <comma-delimited configs>
  -n, --name <value>       <base name of output files>
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

freechips.rocketchip.linting.LintReporter
  --lint [*]|[<lintRule>,<lintRule>,...]
                           Enable linting for specified rules, where * is all rules. Available rules: anon-regs,trunc-widths,conflicting-module-names.
  --lint-options (strict|warn)[,displayTotal=<numError>][,display:<lintName>=<numError>]
                           Customize linting options, including strict/warn or number of violations displayed.
freechips.rocketchip.linting.rule.LintAnonymousRegisters
  --lint-whitelist:anon-regs <filename1>.scala[,<filename2>.scala]*
                           Enable linting anonymous registers for all files except provided files.
freechips.rocketchip.linting.rule.LintTruncatingWidths
  --lint-whitelist:trunc-widths <filename1>.scala[,<filename2>.scala]*
                           Enable linting anonymous registers for all files except provided files.
freechips.rocketchip.linting.rule.LintConflictingModuleNames
  --lint-whitelist:conflicting-module-names <filename1>.scala[,<filename2>.scala]*
                           Enable linting anonymous registers for all files except provided files.
AspectLibrary
  --with-aspect <package>.<aspect>
                           The name/class of an aspect to compile with (must be a class/object without arguments!)
MemLib Options
  -firw, --infer-rw        Enable read/write port inference for memories
  -frsq, --repl-seq-mem -c:<circuit>:-i:<file>:-o:<file>
                           Blackbox and emit a configuration file for each sequential memory
  -gmv, --gen-mem-verilog <blackbox|full>
                           Blackbox and emit a Verilog behavior model for each sequential memory
treadle
  --tr-write-vcd           writes vcd execution log, filename will be based on top-name
  --tr-vcd-show-underscored-vars
                           vcd output by default does not show var that start with underscore, this overrides that
  --tr-verbose             makes the treadle very verbose
  --tr-allow-cycle         will try to run when firrtl contains combinational loops
  --tr-random-seed <value>
                           sets the seed for Treadle's random number generator
  --tr-show-firrtl-at-load
                           show the low firrtl source treadle is using to build simulator
  --tr-save-firrtl-at-load
                           save the low firrtl source treadle is using to build simulator
  --tr-dont-run-lower-compiler-on-load
                           Deprecated: This option has no effect and will be removed in treadle 1.4
  --tr-validif-random      validIf returns random value when condition is false
  --tr-rollback-buffers <value>
                           number of rollback buffers, 0 is no buffers, default is 0
  --tr-mem-to-vcd <value>  log specified memory/indices to vcd, format "all" or "memoryName:1,2,5-10" 
  --tr-clock-info <value>  comma separated list of clock-name[:period[:initial-offset]]
  --tr-symbols-to-watch <value>
                           symbol[,symbol[...]
  --tr-reset-name <value>  name of the default reset signal
  --tr-randomize-at-startup
                           makes treadle do it's own randomization of circuit at startup
  --tr-call-reset-at-startup
                           makes treadle do it's own reset at startup, usually for internal use only
  --tr-add-rocket-black-boxes
                           add in the black boxes needed to simulate rocket
  --tr-prefix-printf-with-walltime
                           Adds a string "[<wall-time>]" to the front of printf lines, helps match to vcd
  --tr-firrtl-source-string <value>
                           a serialized firrtl circuit, mostly used internally
  -tfsf, --tr-firrtl-source-file <value>
                           specify treadle repl source file
  --tr-ignore-formal-assumes
                           Will ignore Forma Assume statements
  --tr-enable-coverage <value>
                           Enables automatic line coverage on tests

Process finished with exit code 0
```

从`Makefile`中来看，

* `ConfigsAnnotation` -->   `chipyard.RocketConfig`
* `TopModuleAnnotation` --> `chipyard.TestHarness`

## TileLink

* request message 发送后，在完全收到所有回复之前，可以接着发下一条 request吗（同一个channel中），结合下面的话

>This means that on the same cycle for the first beat of both the request message and the response message, ready high on the response channel implies ready high on the request channel. In particular, valid high and ready low on the request channel and valid high and ready low on the response channel are legal. However, valid high and ready low on the request channel is illegal if valid high and ready high are on the response channel.

