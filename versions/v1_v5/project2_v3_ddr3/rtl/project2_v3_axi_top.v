// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : project2_v3_axi_top.v
// Module  : project2_v3_axi_top
// Created : 2026-07-26
// Revised : 2026-09-19
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module project2_v3_axi_top (
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
    wire clk_50m;
    wire clk_200m;
    wire board_reset_n;
    wire ui_clk;
    wire ui_clk_sync_rst;
    wire init_calib_complete;

    wire [3:0] awid, bid, arid, rid;
    wire [27:0] awaddr, araddr;
    wire [7:0] awlen, arlen;
    wire [2:0] awsize, awprot, arsize, arprot;
    wire [1:0] awburst, bresp, arburst, rresp;
    wire awlock, awvalid, awready, wlast, wvalid, wready, bvalid, bready;
    wire arlock, arvalid, arready, rlast, rvalid, rready;
    wire [3:0] awcache, awqos, arcache, arqos;
    wire [127:0] wdata, rdata;
    wire [15:0] wstrb;

    wire [3:0] state;
    wire [1:0] pattern_id;
    wire [27:0] current_addr;
    wire [31:0] write_count, read_count, error_count;
    wire [27:0] first_error_addr;
    wire [127:0] expected_data, actual_data;
    wire compare_error, test_done, test_pass;

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
        .s_axi_awid(awid), .s_axi_awaddr(awaddr), .s_axi_awlen(awlen),
        .s_axi_awsize(awsize), .s_axi_awburst(awburst), .s_axi_awlock(awlock),
        .s_axi_awcache(awcache), .s_axi_awprot(awprot), .s_axi_awqos(awqos),
        .s_axi_awvalid(awvalid), .s_axi_awready(awready), .s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb), .s_axi_wlast(wlast), .s_axi_wvalid(wvalid),
        .s_axi_wready(wready), .s_axi_bid(bid), .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid), .s_axi_bready(bready), .s_axi_arid(arid),
        .s_axi_araddr(araddr), .s_axi_arlen(arlen), .s_axi_arsize(arsize),
        .s_axi_arburst(arburst), .s_axi_arlock(arlock), .s_axi_arcache(arcache),
        .s_axi_arprot(arprot), .s_axi_arqos(arqos), .s_axi_arvalid(arvalid),
        .s_axi_arready(arready), .s_axi_rid(rid), .s_axi_rdata(rdata),
        .s_axi_rresp(rresp), .s_axi_rlast(rlast), .s_axi_rvalid(rvalid),
        .s_axi_rready(rready)
    );

    axi_ddr3_selftest #(.TEST_BEATS(256)) u_selftest (
        .clk(ui_clk), .reset(ui_clk_sync_rst),
        .init_calib_complete(init_calib_complete),
        .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen),
        .m_axi_awsize(awsize), .m_axi_awburst(awburst), .m_axi_awlock(awlock),
        .m_axi_awcache(awcache), .m_axi_awprot(awprot), .m_axi_awqos(awqos),
        .m_axi_awvalid(awvalid), .m_axi_awready(awready), .m_axi_wdata(wdata),
        .m_axi_wstrb(wstrb), .m_axi_wlast(wlast), .m_axi_wvalid(wvalid),
        .m_axi_wready(wready), .m_axi_bid(bid), .m_axi_bresp(bresp),
        .m_axi_bvalid(bvalid), .m_axi_bready(bready), .m_axi_arid(arid),
        .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arlock(arlock), .m_axi_arcache(arcache),
        .m_axi_arprot(arprot), .m_axi_arqos(arqos), .m_axi_arvalid(arvalid),
        .m_axi_arready(arready), .m_axi_rid(rid), .m_axi_rdata(rdata),
        .m_axi_rresp(rresp), .m_axi_rlast(rlast), .m_axi_rvalid(rvalid),
        .m_axi_rready(rready), .state(state), .pattern_id(pattern_id),
        .current_addr(current_addr), .write_count(write_count), .read_count(read_count),
        .error_count(error_count), .first_error_addr(first_error_addr),
        .expected_data(expected_data), .actual_data(actual_data),
        .compare_error(compare_error), .test_done(test_done), .test_pass(test_pass)
    );

    // LED0: calibration completed. LED1: test completed and all comparisons passed.
    // Any read/write error leaves LED1 off and remains visible in ILA error_count.
    assign led[0] = init_calib_complete;
    assign led[1] = test_done && test_pass;

    ila_ddr3 u_ila (
        .clk(ui_clk),
        .probe0(init_calib_complete), .probe1(state), .probe2(pattern_id),
        .probe3(current_addr), .probe4(awvalid), .probe5(awready),
        .probe6(wvalid), .probe7(wready), .probe8(bvalid), .probe9(bready),
        .probe10(arvalid), .probe11(arready), .probe12(rvalid), .probe13(rready),
        .probe14(test_done), .probe15(test_pass), .probe16(error_count),
        .probe17(compare_error), .probe18(expected_data), .probe19(actual_data)
    );
endmodule
