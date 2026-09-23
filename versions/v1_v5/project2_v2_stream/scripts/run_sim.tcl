# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : run_sim.tcl
# Module  : Vivado build script
# Created : 2026-07-22
# Revised : 2026-09-19
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
open_project [file join $root_dir build project2_v2_stream.xpr]
set_property top tb_udp_v2_stream_source [get_filesets sim_1]
launch_simulation
restart
run all
close_sim
close_project
