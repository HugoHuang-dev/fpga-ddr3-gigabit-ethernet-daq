# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : build_bitstream.tcl
# Module  : Vivado build script
# Created : 2026-07-26
# Revised : 2026-09-19
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set mode [expr {[llength $argv] > 0 ? [lindex $argv 0] : "axi"}]
if {$mode ne "calib" && $mode ne "axi"} { error "mode must be calib or axi" }

set project_name "project2_v3_${mode}"
set project_file [file join $root_dir build $mode ${project_name}.xpr]
if {![file exists $project_file]} {
    error "Project not found. Run create_project.tcl $mode first."
}

open_project $project_file
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Implementation failed"
}

set run_dir [get_property DIRECTORY [get_runs impl_1]]
set top_name [get_property top [get_filesets sources_1]]
file copy -force [file join $run_dir ${top_name}.bit] [file join $root_dir project2_v3_${mode}.bit]
set ltx_file [file join $run_dir ${top_name}.ltx]
if {[file exists $ltx_file]} {
    file copy -force $ltx_file [file join $root_dir project2_v3_${mode}.ltx]
}

open_run impl_1
report_timing_summary -file [file join $root_dir reports ${mode}_timing_summary.rpt]
report_utilization -file [file join $root_dir reports ${mode}_utilization.rpt]
puts "BITSTREAM_READY: [file join $root_dir project2_v3_${mode}.bit]"
close_project
