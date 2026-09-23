# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : program_v9_board.tcl
# Module  : Vivado build script
# Created : 2026-09-14
# Revised : 2026-09-23
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set bit_file [file join $root_dir project2_v9_top.bit]
set ltx_file [file join $root_dir project2_v9_top.ltx]
if {![file exists $bit_file] || ![file exists $ltx_file]} {
    error "V9 BIT or LTX missing"
}
load_features labtools
open_hw
connect_hw_server -url localhost:3121
set targets [get_hw_targets]
if {[llength $targets] != 1} {
    error "Expected exactly one connected JTAG target; found $targets"
}
current_hw_target [lindex $targets 0]
open_hw_target
set devices [get_hw_devices]
if {[llength $devices] != 1 || [get_property PART [lindex $devices 0]] ne "xc7a35t"} {
    error "Expected one xc7a35t device; found $devices"
}
set device [lindex $devices 0]
current_hw_device $device
set_property PROGRAM.FILE $bit_file $device
set_property PROBES.FILE $ltx_file $device
program_hw_devices $device
refresh_hw_device $device
puts "V9_PROGRAMMED: $device"
puts "V9_ILAS: [get_hw_ilas -of_objects $device]"
close_hw_target
disconnect_hw_server
close_hw
