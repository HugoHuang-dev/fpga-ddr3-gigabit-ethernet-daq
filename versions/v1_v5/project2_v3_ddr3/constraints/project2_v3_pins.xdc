# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : project2_v3_pins.xdc
# Module  : Vivado constraints
# Created : 2026-07-26
# Revised : 2026-09-19
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]

set_property PACKAGE_PIN R4 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]

set_property PACKAGE_PIN R2 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]
set_property PACKAGE_PIN R3 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]
