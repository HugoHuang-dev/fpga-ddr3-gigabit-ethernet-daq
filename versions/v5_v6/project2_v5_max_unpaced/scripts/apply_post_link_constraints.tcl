# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : apply_post_link_constraints.tcl
# Module  : Vivado build script
# Created : 2026-08-11
# Revised : 2026-09-22
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
# Runs after link_design, when generated MIG and Clocking Wizard clock objects
# exist.  The domains exchange payload only through asynchronous FIFOs.
set acquisition_clocks [get_clocks -quiet clk_out2_clk_wiz_0]
set ddr_ui_clocks [get_clocks -quiet clk_pll_i]
if {[llength $acquisition_clocks] != 1 || [llength $ddr_ui_clocks] != 1} {
    error "Expected acquisition and DDR UI generated clocks were not found"
}
set_clock_groups -asynchronous \
    -group $acquisition_clocks \
    -group $ddr_ui_clocks
puts "POST_LINK_CDC_CONSTRAINT_APPLIED"
