# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : build_bitstream.tcl
# Module  : Vivado build script
# Created : 2026-08-02
# Revised : 2026-09-20
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set project_file [file join $root_dir build project2_v4_ddr3_udp.xpr]
if {![file exists $project_file]} { error "Run create_project.tcl first" }

open_project $project_file
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "Implementation failed" }

set run_dir [get_property DIRECTORY [get_runs impl_1]]
file copy -force [file join $run_dir project2_v4_top.bit] [file join $root_dir project2_v4_top.bit]
if {[file exists [file join $run_dir project2_v4_top.ltx]]} {
    file copy -force [file join $run_dir project2_v4_top.ltx] [file join $root_dir project2_v4_top.ltx]
}

open_run impl_1
report_timing_summary -file [file join $root_dir reports timing_summary.rpt]
report_utilization -file [file join $root_dir reports utilization.rpt]
report_drc -file [file join $root_dir reports drc.rpt]
puts "BITSTREAM_READY: [file join $root_dir project2_v4_top.bit]"
close_project
