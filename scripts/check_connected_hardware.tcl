# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : check_connected_hardware.tcl
# Module  : Vivado build script
# Created : 2026-09-14
# Revised : 2026-09-23
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
load_features labtools
open_hw
connect_hw_server -url localhost:3121
set targets [get_hw_targets]
puts "HW_TARGETS: $targets"
foreach target $targets {
    current_hw_target $target
    if {[catch {open_hw_target} result]} {
        puts "HW_TARGET_OPEN_FAILED: $target : $result"
        continue
    }
    puts "HW_DEVICES: [get_hw_devices]"
    foreach device [get_hw_devices] {
        puts "HW_DEVICE: $device PART=[get_property PART $device]"
    }
    close_hw_target
}
disconnect_hw_server
close_hw
