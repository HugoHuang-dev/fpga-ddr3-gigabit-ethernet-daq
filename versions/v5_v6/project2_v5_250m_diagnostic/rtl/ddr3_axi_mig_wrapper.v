// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : ddr3_axi_mig_wrapper.v
// Module  : ddr3_axi_mig_wrapper
// Created : 2026-07-26
// Revised : 2026-09-21
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module ddr3_axi_mig_wrapper (
    input  wire         sys_clk_200m,
    input  wire         sys_reset_n,

    inout  wire [15:0]  ddr3_dq,
    inout  wire [1:0]   ddr3_dqs_n,
    inout  wire [1:0]   ddr3_dqs_p,
    output wire [13:0]  ddr3_addr,
    output wire [2:0]   ddr3_ba,
    output wire         ddr3_ras_n,
    output wire         ddr3_cas_n,
    output wire         ddr3_we_n,
    output wire         ddr3_reset_n,
    output wire [0:0]   ddr3_ck_p,
    output wire [0:0]   ddr3_ck_n,
    output wire [0:0]   ddr3_cke,
    output wire [0:0]   ddr3_cs_n,
    output wire [1:0]   ddr3_dm,
    output wire [0:0]   ddr3_odt,

    output wire         ui_clk,
    output wire         ui_clk_sync_rst,
    output wire         init_calib_complete,

    input  wire [3:0]   s_axi_awid,
    input  wire [27:0]  s_axi_awaddr,
    input  wire [7:0]   s_axi_awlen,
    input  wire [2:0]   s_axi_awsize,
    input  wire [1:0]   s_axi_awburst,
    input  wire         s_axi_awlock,
    input  wire [3:0]   s_axi_awcache,
    input  wire [2:0]   s_axi_awprot,
    input  wire [3:0]   s_axi_awqos,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    input  wire [127:0] s_axi_wdata,
    input  wire [15:0]  s_axi_wstrb,
    input  wire         s_axi_wlast,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    output wire [3:0]   s_axi_bid,
    output wire [1:0]   s_axi_bresp,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,
    input  wire [3:0]   s_axi_arid,
    input  wire [27:0]  s_axi_araddr,
    input  wire [7:0]   s_axi_arlen,
    input  wire [2:0]   s_axi_arsize,
    input  wire [1:0]   s_axi_arburst,
    input  wire         s_axi_arlock,
    input  wire [3:0]   s_axi_arcache,
    input  wire [2:0]   s_axi_arprot,
    input  wire [3:0]   s_axi_arqos,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    output wire [3:0]   s_axi_rid,
    output wire [127:0] s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    output wire         s_axi_rlast,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready
);
    mig_7series_0 u_mig (
        .ddr3_addr(ddr3_addr), .ddr3_ba(ddr3_ba),
        .ddr3_cas_n(ddr3_cas_n), .ddr3_ck_n(ddr3_ck_n),
        .ddr3_ck_p(ddr3_ck_p), .ddr3_cke(ddr3_cke),
        .ddr3_ras_n(ddr3_ras_n), .ddr3_reset_n(ddr3_reset_n),
        .ddr3_we_n(ddr3_we_n), .ddr3_dq(ddr3_dq),
        .ddr3_dqs_n(ddr3_dqs_n), .ddr3_dqs_p(ddr3_dqs_p),
        .ddr3_cs_n(ddr3_cs_n), .ddr3_dm(ddr3_dm), .ddr3_odt(ddr3_odt),
        .init_calib_complete(init_calib_complete),
        .ui_clk(ui_clk), .ui_clk_sync_rst(ui_clk_sync_rst), .mmcm_locked(),
        .app_sr_req(1'b0), .app_ref_req(1'b0), .app_zq_req(1'b0),
        .app_sr_active(), .app_ref_ack(), .app_zq_ack(),
        .aresetn(~ui_clk_sync_rst),
        .s_axi_awid(s_axi_awid), .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awlen(s_axi_awlen), .s_axi_awsize(s_axi_awsize),
        .s_axi_awburst(s_axi_awburst), .s_axi_awlock(s_axi_awlock),
        .s_axi_awcache(s_axi_awcache), .s_axi_awprot(s_axi_awprot),
        .s_axi_awqos(s_axi_awqos), .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb), .s_axi_wlast(s_axi_wlast),
        .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bid(s_axi_bid), .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_arid(s_axi_arid), .s_axi_araddr(s_axi_araddr),
        .s_axi_arlen(s_axi_arlen), .s_axi_arsize(s_axi_arsize),
        .s_axi_arburst(s_axi_arburst), .s_axi_arlock(s_axi_arlock),
        .s_axi_arcache(s_axi_arcache), .s_axi_arprot(s_axi_arprot),
        .s_axi_arqos(s_axi_arqos), .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready), .s_axi_rid(s_axi_rid),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
        .s_axi_rlast(s_axi_rlast), .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .sys_clk_i(sys_clk_200m), .sys_rst(sys_reset_n)
    );
endmodule
