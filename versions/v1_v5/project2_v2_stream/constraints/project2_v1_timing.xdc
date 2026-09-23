# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : project2_v1_timing.xdc
# Module  : Vivado constraints
# Created : 2026-07-19
# Revised : 2026-09-19
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
# v1 runs the UDP application and GMII transmit path from the same 125 MHz
# clock.  The received RGMII clock-domain crossings are constrained by the
# FIFO/IP XDC files supplied with the course stack.
