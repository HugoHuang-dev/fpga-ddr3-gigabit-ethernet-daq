# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : project2_v5_timing.xdc
# Module  : Vivado constraints
# Created : 2026-08-11
# Revised : 2026-09-21
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
# Clock definitions and CDC exceptions are supplied by the Clocking Wizard,
# MIG, FIFO Generator, and Ethernet IP constraints used by this project.

# The 125 MHz acquisition/Ethernet clock and MIG UI clock are generated through
# separate clock-management trees. All payload transfers between them use the
# asynchronous FIFO blocks; sticky status indications are synchronized
# explicitly. They therefore form asynchronous clock domains for STA.
set acquisition_clocks [get_clocks -quiet clk_out2_clk_wiz_0]
set ddr_ui_clocks [get_clocks -quiet clk_pll_i]

# During out-of-context/top-level synthesis the generated clock objects may not
# exist yet.  Vivado rereads this XDC during implementation after the IP clock
# constraints have created them, so apply the exception only when both objects
# are available instead of producing a misleading critical warning.
if {[llength $acquisition_clocks] > 0 && [llength $ddr_ui_clocks] > 0} {
    set_clock_groups -asynchronous \
        -group $acquisition_clocks \
        -group $ddr_ui_clocks
}
