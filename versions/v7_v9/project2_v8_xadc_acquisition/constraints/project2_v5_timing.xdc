# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : project2_v5_timing.xdc
# Module  : Vivado constraints
# Created : 2026-08-11
# Revised : 2026-09-22
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
# Clock definitions and CDC exceptions are supplied by the Clocking Wizard,
# MIG, FIFO Generator, and Ethernet IP constraints used by this project.

# The 125 MHz acquisition/Ethernet clock and MIG UI clock are generated through
# separate clock-management trees. All payload transfers between them use the
# asynchronous FIFO blocks; sticky status indications are synchronized
# explicitly. They therefore form asynchronous clock domains for STA.
#
# Vivado 2018.3 does not support Tcl `if` commands inside an XDC file. The
# generated clocks also do not exist during every XDC read. The asynchronous
# clock grouping is consequently applied, with an explicit one-clock check,
# by scripts/apply_post_link_constraints.tcl at implementation opt-design PRE.
