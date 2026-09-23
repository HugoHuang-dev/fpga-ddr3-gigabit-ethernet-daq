# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : create_project.tcl
# Module  : Vivado build script
# Created : 2026-07-26
# Revised : 2026-09-19
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set mode       [expr {[llength $argv] > 0 ? [lindex $argv 0] : "axi"}]

if {$mode ne "calib" && $mode ne "axi"} {
    error "mode must be calib or axi"
}

set project_name "project2_v3_${mode}"
set build_dir [file join $root_dir build $mode]
create_project $project_name $build_dir -part xc7a35tfgg484-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

add_files -norecurse [file join $root_dir rtl clock_reset_gen.v]
add_files -norecurse [file join $root_dir rtl ddr3_axi_mig_wrapper.v]
add_files -norecurse [file join $root_dir ip clk_wiz_0 clk_wiz_0.xci]
add_files -norecurse [file join $root_dir ip mig_7series_0 mig_7series_0.xci]
add_files -fileset constrs_1 -norecurse [file join $root_dir constraints project2_v3_pins.xdc]

if {$mode eq "calib"} {
    add_files -norecurse [file join $root_dir rtl project2_v3_calib_top.v]
    set_property top project2_v3_calib_top [get_filesets sources_1]
    create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_calib
    set_property -dict [list \
        CONFIG.C_NUM_OF_PROBES {2} \
        CONFIG.C_DATA_DEPTH {1024} \
        CONFIG.C_PROBE0_WIDTH {1} \
        CONFIG.C_PROBE1_WIDTH {1}] [get_ips ila_calib]
} else {
    add_files -norecurse [file join $root_dir rtl axi_ddr3_selftest.v]
    add_files -norecurse [file join $root_dir rtl project2_v3_axi_top.v]
    add_files -fileset sim_1 -norecurse [file join $root_dir sim tb_axi_ddr3_selftest.v]
    set_property top project2_v3_axi_top [get_filesets sources_1]
    set_property top tb_axi_ddr3_selftest [get_filesets sim_1]
    create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_ddr3
    set_property -dict [list \
        CONFIG.C_NUM_OF_PROBES {20} CONFIG.C_DATA_DEPTH {1024} \
        CONFIG.C_PROBE0_WIDTH {1}   CONFIG.C_PROBE1_WIDTH {4} \
        CONFIG.C_PROBE2_WIDTH {2}   CONFIG.C_PROBE3_WIDTH {28} \
        CONFIG.C_PROBE4_WIDTH {1}   CONFIG.C_PROBE5_WIDTH {1} \
        CONFIG.C_PROBE6_WIDTH {1}   CONFIG.C_PROBE7_WIDTH {1} \
        CONFIG.C_PROBE8_WIDTH {1}   CONFIG.C_PROBE9_WIDTH {1} \
        CONFIG.C_PROBE10_WIDTH {1}  CONFIG.C_PROBE11_WIDTH {1} \
        CONFIG.C_PROBE12_WIDTH {1}  CONFIG.C_PROBE13_WIDTH {1} \
        CONFIG.C_PROBE14_WIDTH {1}  CONFIG.C_PROBE15_WIDTH {1} \
        CONFIG.C_PROBE16_WIDTH {32} CONFIG.C_PROBE17_WIDTH {1} \
        CONFIG.C_PROBE18_WIDTH {128} CONFIG.C_PROBE19_WIDTH {128}] [get_ips ila_ddr3]
}

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
generate_target all [get_ips]
export_ip_user_files -of_objects [get_ips] -no_script -sync -force -quiet
puts "PROJECT_CREATED: [file join $build_dir ${project_name}.xpr]"
