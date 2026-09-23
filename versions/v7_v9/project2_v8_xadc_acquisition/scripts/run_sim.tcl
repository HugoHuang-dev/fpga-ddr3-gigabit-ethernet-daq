# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : run_sim.tcl
# Module  : Vivado build script
# Created : 2026-09-08
# Revised : 2026-09-22
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set project_file [file join $root_dir build project2_v8_xadc_acquisition.xpr]
if {![file exists $project_file]} { error "Run create_project.tcl first" }
open_project $project_file
set_property top tb_v8_uart_control [get_filesets sim_1]
set_property xsim.simulate.runtime {all} [get_filesets sim_1]
launch_simulation
close_sim
close_project
