# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : report_bus_skew.tcl
# Module  : Vivado build script
# Created : 2026-09-14
# Revised : 2026-09-23
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
open_project [file join $root_dir build project2_v9_full_validation.xpr]
open_run impl_1
report_bus_skew -file [file join $root_dir reports bus_skew.rpt]
close_project
