// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : project2_v3_calib_top.v
// Module  : project2_v3_calib_top
// Created : 2026-07-26
// Revised : 2026-09-19
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// Phase A: course-style MIG calibration baseline.  AXI is intentionally idle.
module project2_v3_calib_top (
    input  wire        sys_clk,
    inout  wire [15:0] ddr3_dq,
    inout  wire [1:0]  ddr3_dqs_n,
    inout  wire [1:0]  ddr3_dqs_p,
    output wire [13:0] ddr3_addr,
    output wire [2:0]  ddr3_ba,
    output wire        ddr3_ras_n,
    output wire        ddr3_cas_n,
    output wire        ddr3_we_n,
    output wire        ddr3_reset_n,
    output wire [0:0]  ddr3_ck_p,
    output wire [0:0]  ddr3_ck_n,
    output wire [0:0]  ddr3_cke,
    output wire [0:0]  ddr3_cs_n,
    output wire [1:0]  ddr3_dm,
    output wire [0:0]  ddr3_odt,
    output wire [1:0]  led
);
    wire clk_50m, clk_200m, board_reset_n;
    wire ui_clk, ui_clk_sync_rst, init_calib_complete;
    wire awready, wready, bvalid, arready, rlast, rvalid;
    wire [3:0] bid, rid;
    wire [1:0] bresp, rresp;
    wire [127:0] rdata;

    clock_reset_gen u_clock_reset (
        .clk_50m_in(sys_clk), .clk_50m(clk_50m),
        .clk_200m(clk_200m), .reset_n(board_reset_n)
    );

    ddr3_axi_mig_wrapper u_ddr3 (
        .sys_clk_200m(clk_200m), .sys_reset_n(board_reset_n),
        .ddr3_dq(ddr3_dq), .ddr3_dqs_n(ddr3_dqs_n), .ddr3_dqs_p(ddr3_dqs_p),
        .ddr3_addr(ddr3_addr), .ddr3_ba(ddr3_ba), .ddr3_ras_n(ddr3_ras_n),
        .ddr3_cas_n(ddr3_cas_n), .ddr3_we_n(ddr3_we_n),
        .ddr3_reset_n(ddr3_reset_n), .ddr3_ck_p(ddr3_ck_p), .ddr3_ck_n(ddr3_ck_n),
        .ddr3_cke(ddr3_cke), .ddr3_cs_n(ddr3_cs_n), .ddr3_dm(ddr3_dm),
        .ddr3_odt(ddr3_odt), .ui_clk(ui_clk), .ui_clk_sync_rst(ui_clk_sync_rst),
        .init_calib_complete(init_calib_complete),
        .s_axi_awid(4'd0), .s_axi_awaddr(28'd0), .s_axi_awlen(8'd0),
        .s_axi_awsize(3'd4), .s_axi_awburst(2'b01), .s_axi_awlock(1'b0),
        .s_axi_awcache(4'd0), .s_axi_awprot(3'd0), .s_axi_awqos(4'd0),
        .s_axi_awvalid(1'b0), .s_axi_awready(awready), .s_axi_wdata(128'd0),
        .s_axi_wstrb(16'd0), .s_axi_wlast(1'b1), .s_axi_wvalid(1'b0),
        .s_axi_wready(wready), .s_axi_bid(bid), .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid), .s_axi_bready(1'b0), .s_axi_arid(4'd0),
        .s_axi_araddr(28'd0), .s_axi_arlen(8'd0), .s_axi_arsize(3'd4),
        .s_axi_arburst(2'b01), .s_axi_arlock(1'b0), .s_axi_arcache(4'd0),
        .s_axi_arprot(3'd0), .s_axi_arqos(4'd0), .s_axi_arvalid(1'b0),
        .s_axi_arready(arready), .s_axi_rid(rid), .s_axi_rdata(rdata),
        .s_axi_rresp(rresp), .s_axi_rlast(rlast), .s_axi_rvalid(rvalid),
        .s_axi_rready(1'b0)
    );

    assign led[0] = init_calib_complete;
    assign led[1] = 1'b0;

    ila_calib u_ila_calib (
        .clk(ui_clk),
        .probe0(init_calib_complete),
        .probe1(ui_clk_sync_rst)
    );
endmodule
