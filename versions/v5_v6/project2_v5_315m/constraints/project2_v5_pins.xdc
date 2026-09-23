# -----------------------------------------------------------------------------
# Hugo's FPGA Project
# -----------------------------------------------------------------------------
# Author  : sunmingyin.huang@haw-hamburg.de
# Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
# File    : project2_v5_pins.xdc
# Module  : Vivado constraints
# Created : 2026-08-11
# Revised : 2026-09-21
# Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
# -----------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]

set_property -dict {PACKAGE_PIN R4 IOSTANDARD LVCMOS33} [get_ports sys_clk]
set_property -dict {PACKAGE_PIN U2 IOSTANDARD LVCMOS33 PULLUP true} [get_ports sys_rst_n]
set_property -dict {PACKAGE_PIN T1 IOSTANDARD LVCMOS33 PULLUP true} [get_ports start_n]

create_clock -period 8.000 -name eth_rxc [get_ports eth_rxc]
set_property -dict {PACKAGE_PIN T21 IOSTANDARD LVCMOS33} [get_ports eth_rst_n]
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33} [get_ports eth_rxc]
set_property -dict {PACKAGE_PIN Y21 IOSTANDARD LVCMOS33} [get_ports eth_rx_ctl]
set_property -dict {PACKAGE_PIN Y22 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[0]}]
set_property -dict {PACKAGE_PIN W21 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[1]}]
set_property -dict {PACKAGE_PIN W22 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[2]}]
set_property -dict {PACKAGE_PIN V22 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[3]}]
set_property -dict {PACKAGE_PIN AA21 IOSTANDARD LVCMOS33} [get_ports eth_txc]
set_property -dict {PACKAGE_PIN AB22 IOSTANDARD LVCMOS33} [get_ports eth_tx_ctl]
set_property -dict {PACKAGE_PIN AB21 IOSTANDARD LVCMOS33} [get_ports {eth_txd[0]}]
set_property -dict {PACKAGE_PIN AA20 IOSTANDARD LVCMOS33} [get_ports {eth_txd[1]}]
set_property -dict {PACKAGE_PIN AB20 IOSTANDARD LVCMOS33} [get_ports {eth_txd[2]}]
set_property -dict {PACKAGE_PIN AA19 IOSTANDARD LVCMOS33} [get_ports {eth_txd[3]}]

set_property -dict {PACKAGE_PIN R2 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN R3 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
