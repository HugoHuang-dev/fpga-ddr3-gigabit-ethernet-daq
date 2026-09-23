# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : create_project.tcl
# Module  : Vivado build script
# Created : 2026-08-02
# Revised : 2026-09-20
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set build_dir [file join $root_dir build]

create_project project2_v4_ddr3_udp $build_dir -part xc7a35tfgg484-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

add_files -norecurse [glob [file join $root_dir rtl vendor net21 *.v]]
add_files -norecurse [glob [file join $root_dir rtl vendor adma_v1 *.v]]
add_files -norecurse [glob [file join $root_dir rtl *.v]]
add_files -norecurse [glob [file join $root_dir ip *.xci]]
add_files -norecurse [file join $root_dir ip mig_7series_0 mig_7series_0.xci]

set_property -dict [list \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200.000} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125.000} \
    CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {150.000}] [get_ips clk_wiz_0]

add_files -fileset constrs_1 -norecurse [file join $root_dir constraints project2_v4_pins.xdc]
add_files -fileset constrs_1 -norecurse [file join $root_dir constraints project2_v4_timing.xdc]
add_files -fileset sim_1 -norecurse [file join $root_dir sim tb_v4_source_packetizer.v]

set_property top project2_v4_top [get_filesets sources_1]
set_property top tb_v4_source_packetizer [get_filesets sim_1]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_v4
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {30} CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_PROBE1_WIDTH {3} \
    CONFIG.C_PROBE2_WIDTH {1} CONFIG.C_PROBE3_WIDTH {32} \
    CONFIG.C_PROBE4_WIDTH {8} CONFIG.C_PROBE5_WIDTH {8} \
    CONFIG.C_PROBE6_WIDTH {8} CONFIG.C_PROBE7_WIDTH {1} \
    CONFIG.C_PROBE8_WIDTH {1} CONFIG.C_PROBE9_WIDTH {1} \
    CONFIG.C_PROBE10_WIDTH {1} CONFIG.C_PROBE11_WIDTH {8} \
    CONFIG.C_PROBE12_WIDTH {1} CONFIG.C_PROBE13_WIDTH {1} \
    CONFIG.C_PROBE14_WIDTH {1} CONFIG.C_PROBE15_WIDTH {1} \
    CONFIG.C_PROBE16_WIDTH {1} CONFIG.C_PROBE17_WIDTH {1} \
    CONFIG.C_PROBE18_WIDTH {1} CONFIG.C_PROBE19_WIDTH {1} \
    CONFIG.C_PROBE20_WIDTH {1} CONFIG.C_PROBE21_WIDTH {1} \
    CONFIG.C_PROBE22_WIDTH {1} CONFIG.C_PROBE23_WIDTH {1} \
    CONFIG.C_PROBE24_WIDTH {1} CONFIG.C_PROBE25_WIDTH {1} \
    CONFIG.C_PROBE26_WIDTH {1} CONFIG.C_PROBE27_WIDTH {1} \
    CONFIG.C_PROBE28_WIDTH {16} CONFIG.C_PROBE29_WIDTH {1}] [get_ips ila_v4]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
generate_target all [get_ips]
export_ip_user_files -of_objects [get_ips] -no_script -sync -force -quiet
puts "PROJECT_CREATED: [file join $build_dir project2_v4_ddr3_udp.xpr]"
