**一些电平规范 LVDS，CMOS，LVCMOS，LVTTL，TTL等等，如果理解？**

什么是 差分时钟，什么是 PLL

reset信号 active low, active high 对输入端的影响？

```
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0
INFO: [Ipptcl 7-1463] No Compatible Board Interface found. Board Tab not created in customize GUI
set_property -dict [list \
  CONFIG.CLKIN1_JITTER_PS {50.0} \
  CONFIG.CLKOUT1_DRIVES {Buffer} \
  CONFIG.CLKOUT1_JITTER {114.523} \
  CONFIG.CLKOUT1_PHASE_ERROR {97.786} \
  CONFIG.CLKOUT1_USED {true} \
  CONFIG.CLKOUT2_DRIVES {Buffer} \
  CONFIG.CLKOUT3_DRIVES {Buffer} \
  CONFIG.CLKOUT4_DRIVES {Buffer} \
  CONFIG.CLKOUT5_DRIVES {Buffer} \
  CONFIG.CLKOUT6_DRIVES {Buffer} \
  CONFIG.CLKOUT7_DRIVES {Buffer} \
  CONFIG.CLK_OUT1_PORT {clk_out} \
  CONFIG.MMCM_BANDWIDTH {OPTIMIZED} \
  CONFIG.MMCM_CLKFBOUT_MULT_F {4} \
  CONFIG.MMCM_CLKIN1_PERIOD {5.000} \
  CONFIG.MMCM_CLKIN2_PERIOD {10.0} \
  CONFIG.MMCM_CLKOUT0_DIVIDE_F {8} \
  CONFIG.MMCM_COMPENSATION {AUTO} \
  CONFIG.PLL_CLKIN_PERIOD {5.000} \
  CONFIG.PRIMITIVE {PLL} \
  CONFIG.PRIM_IN_FREQ {200.000} \
  CONFIG.PRIM_SOURCE {Differential_clock_capable_pin} \
  CONFIG.RESET_PORT {resetn} \
  CONFIG.RESET_TYPE {ACTIVE_LOW} \
  CONFIG.USE_LOCKED {true} \
] [get_ips clk_wiz_0]
generate_target {instantiation_template} [get_files /home/ckf104/tmp/vivado-poj/project_1/project_1.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci]
INFO: [IP_Flow 19-1686] Generating 'Instantiation Template' target for IP 'clk_wiz_0'...
generate_target all [get_files  /home/ckf104/tmp/vivado-poj/project_1/project_1.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci]
INFO: [IP_Flow 19-1686] Generating 'Synthesis' target for IP 'clk_wiz_0'...
INFO: [IP_Flow 19-1686] Generating 'Simulation' target for IP 'clk_wiz_0'...
INFO: [IP_Flow 19-1686] Generating 'Implementation' target for IP 'clk_wiz_0'...
INFO: [IP_Flow 19-1686] Generating 'Change Log' target for IP 'clk_wiz_0'...
catch { config_ip_cache -export [get_ips -all clk_wiz_0] }
INFO: [IP_Flow 19-6924] IPCACHE: Running cache check for IP inst: clk_wiz_0
export_ip_user_files -of_objects [get_files /home/ckf104/tmp/vivado-poj/project_1/project_1.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] /home/ckf104/tmp/vivado-poj/project_1/project_1.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci]
launch_runs clk_wiz_0_synth_1 -jobs 6
```

