// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : project2_v2_top.v
// Module  : project2_v2_top
// Created : 2026-07-22
// Revised : 2026-09-19
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module project2_v2_top (
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    input  wire       eth_rxc,
    input  wire       eth_rx_ctl,
    input  wire [3:0] eth_rxd,
    output wire       eth_txc,
    output wire       eth_tx_ctl,
    output wire [3:0] eth_txd,
    output wire       eth_rst_n
);

parameter LOCAL_MAC_ADDR  = 48'h02_00_00_00_00_11;
parameter TARGET_MAC_ADDR = 48'hff_ff_ff_ff_ff_ff;
parameter LOCAL_IP_ADDR   = {8'd192, 8'd168, 8'd1, 8'd11};
parameter TARGET_IP_ADDR  = {8'd192, 8'd168, 8'd1, 8'd100};
parameter LOCAL_PORT      = 16'd8888;
parameter TARGET_PORT     = 16'd6666;

wire clk_125m;
wire clk_150m;
wire clk_200m;
wire clock_reset;
wire reset = clock_reset | ~sys_rst_n;

wire phy_rx_clk;
wire gmii_rx_data_error;
wire gmii_rx_data_vld;
wire [7:0] gmii_rx_data;
wire gmii_tx_data_vld;
wire [7:0] gmii_tx_data;
wire app_tx_data_vld;
wire app_tx_data_last;
wire [7:0] app_tx_data;
wire [15:0] app_tx_length;
wire app_tx_ready;

(* mark_debug = "true" *) wire [31:0] packet_sequence;
(* mark_debug = "true" *) wire [31:0] packet_count;

reg [21:0] phy_reset_counter;
reg        phy_reset_released;

assign eth_rst_n = phy_reset_released;

always @(posedge clk_125m or posedge reset) begin
    if (reset) begin
        phy_reset_counter  <= 22'd0;
        phy_reset_released <= 1'b0;
    end else if (phy_reset_counter < 22'd2_500_000) begin
        phy_reset_counter <= phy_reset_counter + 1'b1;
    end else begin
        phy_reset_released <= 1'b1;
    end
end

clock_and_reset u_clock_and_reset (
    .clkin_50m   (sys_clk),
    .clkout_125m (clk_125m),
    .clkout_150m (clk_150m),
    .clkout_200m (clk_200m),
    .reset       (clock_reset)
);

rgmii_interface u_rgmii_interface (
    .reset              (reset),
    .idelay_refclk      (clk_200m),
    .phy_rgmii_rx_clk   (eth_rxc),
    .phy_rgmii_rx_ctl   (eth_rx_ctl),
    .phy_rgmii_rx_data  (eth_rxd),
    .phy_rgmii_tx_clk   (eth_txc),
    .phy_rgmii_tx_ctl   (eth_tx_ctl),
    .phy_rgmii_tx_data  (eth_txd),
    .phy_rx_clk         (phy_rx_clk),
    .gmii_rx_data_vld   (gmii_rx_data_vld),
    .gmii_rx_data_error (gmii_rx_data_error),
    .gmii_rx_data       (gmii_rx_data),
    .phy_tx_clk         (clk_125m),
    .gmii_tx_data_vld   (gmii_tx_data_vld),
    .gmii_tx_data       (gmii_tx_data)
);

udp_protocol_stack #(
    .LOCAL_MAC_ADDR  (LOCAL_MAC_ADDR),
    .TARGET_MAC_ADDR (TARGET_MAC_ADDR),
    .LOCAL_IP_ADDR   (LOCAL_IP_ADDR),
    .TARGET_IP_ADDR  (TARGET_IP_ADDR),
    .LOCAL_PORT      (LOCAL_PORT),
    .TARGET_PORT     (TARGET_PORT)
) u_udp_protocol_stack (
    .phy_tx_clk       (clk_125m),
    .phy_rx_clk       (phy_rx_clk),
    .reset            (reset),
    .gmii_rx_data_vld (gmii_rx_data_vld),
    .gmii_rx_data     (gmii_rx_data),
    .gmii_tx_data_vld (gmii_tx_data_vld),
    .gmii_tx_data     (gmii_tx_data),
    .app_rx_clk       (clk_125m),
    .app_rx_data_vld  (),
    .app_rx_data_last (),
    .app_rx_data      (),
    .app_rx_length    (),
    .app_tx_clk       (clk_125m),
    .app_tx_data_vld  (app_tx_data_vld),
    .app_tx_data_last (app_tx_data_last),
    .app_tx_data      (app_tx_data),
    .app_tx_length    (app_tx_length),
    .app_tx_ready     (app_tx_ready)
);

udp_v2_stream_source #(
    .PACKET_BYTES            (1024),
    .INTER_PACKET_GAP_CYCLES (125_000)
) u_udp_v2_stream_source (
    .clk              (clk_125m),
    .reset            (reset),
    .app_tx_data_vld  (app_tx_data_vld),
    .app_tx_data_last (app_tx_data_last),
    .app_tx_data      (app_tx_data),
    .app_tx_length    (app_tx_length),
    .app_tx_ready     (app_tx_ready),
    .packet_sequence  (packet_sequence),
    .packet_count     (packet_count)
);

endmodule
