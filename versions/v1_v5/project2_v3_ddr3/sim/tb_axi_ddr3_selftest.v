// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : tb_axi_ddr3_selftest.v
// Module  : tb_axi_ddr3_selftest
// Created : 2026-07-26
// Revised : 2026-09-19
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_axi_ddr3_selftest;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg init_calib_complete = 1'b0;
    always #5 clk = ~clk;

    wire [3:0] awid, arid;
    wire [27:0] awaddr, araddr;
    wire [7:0] awlen, arlen;
    wire [2:0] awsize, awprot, arsize, arprot;
    wire [1:0] awburst, arburst;
    wire awlock, arlock;
    wire [3:0] awcache, awqos, arcache, arqos;
    wire awvalid, wlast, wvalid, bready, arvalid, rready;
    wire [127:0] wdata;
    wire [15:0] wstrb;
    reg awready = 1'b1;
    reg wready = 1'b1;
    reg [3:0] bid = 4'd0;
    reg [1:0] bresp = 2'b00;
    reg bvalid = 1'b0;
    reg arready = 1'b1;
    reg [3:0] rid = 4'd0;
    reg [127:0] rdata = 128'd0;
    reg [1:0] rresp = 2'b00;
    reg rlast = 1'b0;
    reg rvalid = 1'b0;

    wire [3:0] state;
    wire [1:0] pattern_id;
    wire [27:0] current_addr, first_error_addr;
    wire [31:0] write_count, read_count, error_count;
    wire [127:0] expected_data, actual_data;
    wire compare_error, test_done, test_pass;

    reg [127:0] memory [0:31];
    reg [27:0] captured_awaddr;
    reg [127:0] captured_wdata;
    reg have_aw = 1'b0;
    reg have_w = 1'b0;
    integer i;

    axi_ddr3_selftest #(.TEST_BEATS(16)) dut (
        .clk(clk), .reset(reset), .init_calib_complete(init_calib_complete),
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

    always @(posedge clk) begin
        if (reset) begin
            have_aw <= 1'b0;
            have_w <= 1'b0;
            bvalid <= 1'b0;
            rvalid <= 1'b0;
            rlast <= 1'b0;
        end else begin
            if (awvalid && awready) begin
                captured_awaddr <= awaddr;
                have_aw <= 1'b1;
            end
            if (wvalid && wready) begin
                captured_wdata <= wdata;
                have_w <= 1'b1;
            end
            if (!bvalid && (have_aw || (awvalid && awready)) &&
                          (have_w || (wvalid && wready))) begin
                memory[(have_aw ? captured_awaddr : awaddr) >> 4] <=
                    have_w ? captured_wdata : wdata;
                bvalid <= 1'b1;
                have_aw <= 1'b0;
                have_w <= 1'b0;
            end else if (bvalid && bready) begin
                bvalid <= 1'b0;
            end

            if (arvalid && arready && !rvalid) begin
                rdata <= memory[araddr >> 4];
                rvalid <= 1'b1;
                rlast <= 1'b1;
            end else if (rvalid && rready) begin
                rvalid <= 1'b0;
                rlast <= 1'b0;
            end
        end
    end

    initial begin
        for (i = 0; i < 32; i = i + 1)
            memory[i] = 128'd0;
        repeat (8) @(posedge clk);
        reset <= 1'b0;
        repeat (8) @(posedge clk);
        init_calib_complete <= 1'b1;
        wait (test_done);
        repeat (4) @(posedge clk);
        if (test_pass && error_count == 0 && write_count == 48 && read_count == 48) begin
            $display("V3 AXI SELFTEST SIM PASSED: writes=%0d reads=%0d errors=%0d",
                     write_count, read_count, error_count);
            $finish;
        end else begin
            $display("V3 AXI SELFTEST SIM FAILED: pass=%0d writes=%0d reads=%0d errors=%0d first_addr=%h",
                     test_pass, write_count, read_count, error_count, first_error_addr);
            $fatal(1);
        end
    end

    initial begin
        #500000;
        $fatal(1, "V3 AXI SELFTEST SIM TIMEOUT");
    end
endmodule
