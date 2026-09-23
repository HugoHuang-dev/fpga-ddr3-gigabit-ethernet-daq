# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : create_project.tcl
# Module  : Vivado build script
# Created : 2026-07-22
# Revised : 2026-09-19
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set build_dir  [file join $root_dir build]

create_project project2_v2_stream $build_dir -part xc7a35tfgg484-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

add_files -norecurse [glob [file join $root_dir rtl vendor xiaobai_net21 *.v]]
add_files -norecurse [file join $root_dir rtl udp_v2_stream_source.v]
add_files -norecurse [file join $root_dir rtl project2_v2_top.v]
add_files -norecurse [glob [file join $root_dir ip *.xci]]

# CLKOUT0 supports a fractional divider; assigning 200 MHz to output 1 lets
# one MMCM generate exact 200/125/150 MHz clocks from the 50 MHz board clock.
set_property -dict [list \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200.000} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125.000} \
    CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {150.000}] [get_ips clk_wiz_0]

add_files -fileset constrs_1 -norecurse [file join $root_dir constraints project2_v1_pins.xdc]
add_files -fileset constrs_1 -norecurse [file join $root_dir constraints project2_v1_timing.xdc]
add_files -fileset sim_1 -norecurse [file join $root_dir sim tb_udp_v2_stream_source.v]

set_property top project2_v2_top [get_filesets sources_1]
set_property top tb_udp_v2_stream_source [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

generate_target all [get_ips]
export_ip_user_files -of_objects [get_ips] -no_script -sync -force -quiet
puts "PROJECT_CREATED: [file join $build_dir project2_v2_stream.xpr]"
