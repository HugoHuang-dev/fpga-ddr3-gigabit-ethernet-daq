# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : collect_reports.tcl
# Module  : Vivado build script
# Created : 2026-09-08
# Revised : 2026-09-22
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
file mkdir [file join $root_dir reports]
open_project [file join $root_dir build project2_v8_xadc_acquisition.xpr]
open_run impl_1
report_timing_summary -file [file join $root_dir reports timing_summary.rpt]
report_utilization -file [file join $root_dir reports utilization.rpt]
report_drc -file [file join $root_dir reports drc.rpt]
set impl_dir [get_property DIRECTORY [current_run]]
file copy -force [file join $impl_dir project2_v8_top.bit] [file join $root_dir project2_v8_top.bit]
write_debug_probes -force [file join $root_dir project2_v8_top.ltx]
puts "BITSTREAM_READY: [file join $root_dir project2_v8_top.bit]"
close_project
