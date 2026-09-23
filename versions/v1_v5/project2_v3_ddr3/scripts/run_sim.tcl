# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : run_sim.tcl
# Module  : Vivado build script
# Created : 2026-07-26
# Revised : 2026-09-19
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set project_file [file join $root_dir build axi project2_v3_axi.xpr]
if {![file exists $project_file]} {
    error "AXI project not found. Run: source scripts/create_project.tcl axi"
}
open_project $project_file
set_property top tb_axi_ddr3_selftest [get_filesets sim_1]
set_property xsim.simulate.runtime {all} [get_filesets sim_1]
launch_simulation
close_sim
close_project
