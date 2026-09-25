# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : project2_v4_timing.xdc
# Module  : Vivado constraints
# Created : 2026-08-02
# Revised : 2026-09-20
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
# Clock definitions and CDC exceptions are supplied by the Clocking Wizard,
# MIG, FIFO Generator, and Ethernet IP constraints used by this project.

# The 125 MHz acquisition/Ethernet clock and MIG UI clock are generated through
# separate clock-management trees. All payload transfers between them use the
# asynchronous FIFO blocks; sticky status indications are synchronized
# explicitly. They therefore form asynchronous clock domains for STA.
set_clock_groups -asynchronous \
    -group [get_clocks clk_out2_clk_wiz_0] \
    -group [get_clocks clk_pll_i]
