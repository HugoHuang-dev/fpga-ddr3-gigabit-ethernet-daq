# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : create_project.tcl
# Module  : Vivado build script
# Created : 2026-08-11
# Revised : 2026-09-20
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set build_dir [file join $root_dir build]

create_project project2_v5_ring_buffer $build_dir -part xc7a35tfgg484-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

add_files -norecurse [glob [file join $root_dir rtl vendor net21 *.v]]
add_files -norecurse [glob [file join $root_dir rtl vendor adma_v1 *.v]]
add_files -norecurse [glob [file join $root_dir rtl *.v]]
set bundled_ip_files [glob [file join $root_dir ip *.xci]]
set used_ip_files {}
foreach ip_file $bundled_ip_files {
    set ip_name [file tail $ip_file]
    if {$ip_name ne "fifo_w72xd512.xci" && $ip_name ne "fifo_w288xd512.xci"} {
        lappend used_ip_files $ip_file
    }
}
add_files -norecurse $used_ip_files
add_files -norecurse [file join $root_dir ip mig_7series_0 mig_7series_0.xci]

set_property -dict [list CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200.000} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125.000} \
    CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {150.000}] [get_ips clk_wiz_0]

add_files -fileset constrs_1 -norecurse [file join $root_dir constraints project2_v5_pins.xdc]
add_files -fileset constrs_1 -norecurse [file join $root_dir constraints project2_v5_timing.xdc]
set_property PROCESSING_ORDER LATE [get_files *project2_v5_timing.xdc]
set_property STEPS.OPT_DESIGN.TCL.PRE [file join $root_dir scripts apply_post_link_constraints.tcl] [get_runs impl_1]
add_files -fileset sim_1 -norecurse [file join $root_dir sim tb_v5_units.v]
set_property top project2_v5_top [get_filesets sources_1]
set_property top tb_v5_units [get_filesets sim_1]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_v5
set_property -dict [list CONFIG.C_NUM_OF_PROBES {39} CONFIG.C_DATA_DEPTH {2048} \
    CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_PROBE1_WIDTH {1} \
    CONFIG.C_PROBE2_WIDTH {32} CONFIG.C_PROBE3_WIDTH {32} \
    CONFIG.C_PROBE4_WIDTH {32} CONFIG.C_PROBE5_WIDTH {32} \
    CONFIG.C_PROBE6_WIDTH {32} CONFIG.C_PROBE7_WIDTH {1} \
    CONFIG.C_PROBE8_WIDTH {1} CONFIG.C_PROBE9_WIDTH {1} \
    CONFIG.C_PROBE10_WIDTH {1} CONFIG.C_PROBE11_WIDTH {1} \
    CONFIG.C_PROBE12_WIDTH {1} CONFIG.C_PROBE13_WIDTH {2} \
    CONFIG.C_PROBE14_WIDTH {1} CONFIG.C_PROBE15_WIDTH {1} \
    CONFIG.C_PROBE16_WIDTH {1} CONFIG.C_PROBE17_WIDTH {12} \
    CONFIG.C_PROBE18_WIDTH {2} CONFIG.C_PROBE19_WIDTH {1} \
    CONFIG.C_PROBE20_WIDTH {1} CONFIG.C_PROBE21_WIDTH {32} \
    CONFIG.C_PROBE22_WIDTH {1} CONFIG.C_PROBE23_WIDTH {1} \
    CONFIG.C_PROBE24_WIDTH {1} CONFIG.C_PROBE25_WIDTH {1} \
    CONFIG.C_PROBE26_WIDTH {1} CONFIG.C_PROBE27_WIDTH {1} \
    CONFIG.C_PROBE28_WIDTH {1} CONFIG.C_PROBE29_WIDTH {32} \
    CONFIG.C_PROBE30_WIDTH {1} CONFIG.C_PROBE31_WIDTH {1} \
    CONFIG.C_PROBE32_WIDTH {1} CONFIG.C_PROBE33_WIDTH {1} \
    CONFIG.C_PROBE34_WIDTH {1} CONFIG.C_PROBE35_WIDTH {1} \
    CONFIG.C_PROBE36_WIDTH {1} CONFIG.C_PROBE37_WIDTH {1} CONFIG.C_PROBE38_WIDTH {1}] [get_ips ila_v5]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
generate_target all [get_ips]
export_ip_user_files -of_objects [get_ips] -no_script -sync -force -quiet
puts "PROJECT_CREATED: [file join $build_dir project2_v5_ring_buffer.xpr]"
