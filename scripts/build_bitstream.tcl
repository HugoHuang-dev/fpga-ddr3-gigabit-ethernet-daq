# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : build_bitstream.tcl
# Module  : Vivado build script
# Created : 2026-09-14
# Revised : 2026-09-23
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
file mkdir [file join $root_dir reports]
open_project [file join $root_dir build project2_v9_full_validation.xpr]
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "*write_bitstream Complete*" $impl_status]} {
    error "V9 implementation did not complete: $impl_status"
}
open_run impl_1
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 20 \
    -file [file join $root_dir reports timing_summary.rpt]
report_utilization -file [file join $root_dir reports utilization.rpt]
report_drc -file [file join $root_dir reports drc.rpt]
file copy -force [get_property DIRECTORY [current_run]]/project2_v9_top.bit \
    [file join $root_dir project2_v9_top.bit]
write_debug_probes -force [file join $root_dir project2_v9_top.ltx]
puts "BITSTREAM_READY: [file join $root_dir project2_v9_top.bit]"
close_project
