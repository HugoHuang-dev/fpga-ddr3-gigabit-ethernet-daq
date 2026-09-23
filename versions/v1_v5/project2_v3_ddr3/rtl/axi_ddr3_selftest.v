// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : axi_ddr3_selftest.v
// Module  : axi_ddr3_selftest
// Created : 2026-07-26
// Revised : 2026-09-19
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// AXI4 DDR3 memory test.  One 128-bit transfer is kept outstanding at a time,
// which makes every AXI handshake visible and easy to follow in ILA.
module axi_ddr3_selftest #(
    parameter integer TEST_BEATS = 256,
    parameter [27:0] BASE_ADDR = 28'h0000000
) (
    input  wire         clk,
    input  wire         reset,
    input  wire         init_calib_complete,

    output wire [3:0]   m_axi_awid,
    output wire [27:0]  m_axi_awaddr,
    output wire [7:0]   m_axi_awlen,
    output wire [2:0]   m_axi_awsize,
    output wire [1:0]   m_axi_awburst,
    output wire         m_axi_awlock,
    output wire [3:0]   m_axi_awcache,
    output wire [2:0]   m_axi_awprot,
    output wire [3:0]   m_axi_awqos,
    output wire         m_axi_awvalid,
    input  wire         m_axi_awready,
    output wire [127:0] m_axi_wdata,
    output wire [15:0]  m_axi_wstrb,
    output wire         m_axi_wlast,
    output wire         m_axi_wvalid,
    input  wire         m_axi_wready,
    input  wire [3:0]   m_axi_bid,
    input  wire [1:0]   m_axi_bresp,
    input  wire         m_axi_bvalid,
    output wire         m_axi_bready,
    output wire [3:0]   m_axi_arid,
    output wire [27:0]  m_axi_araddr,
    output wire [7:0]   m_axi_arlen,
    output wire [2:0]   m_axi_arsize,
    output wire [1:0]   m_axi_arburst,
    output wire         m_axi_arlock,
    output wire [3:0]   m_axi_arcache,
    output wire [2:0]   m_axi_arprot,
    output wire [3:0]   m_axi_arqos,
    output wire         m_axi_arvalid,
    input  wire         m_axi_arready,
    input  wire [3:0]   m_axi_rid,
    input  wire [127:0] m_axi_rdata,
    input  wire [1:0]   m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid,
    output wire         m_axi_rready,

    output reg  [3:0]   state,
    output reg  [1:0]   pattern_id,
    output reg  [27:0]  current_addr,
    output reg  [31:0]  write_count,
    output reg  [31:0]  read_count,
    output reg  [31:0]  error_count,
    output reg  [27:0]  first_error_addr,
    output reg  [127:0] expected_data,
    output reg  [127:0] actual_data,
    output reg          compare_error,
    output reg          test_done,
    output reg          test_pass
);
    localparam [3:0] ST_WAIT_CALIB = 4'd0;
    localparam [3:0] ST_START      = 4'd1;
    localparam [3:0] ST_WRITE      = 4'd2;
    localparam [3:0] ST_WRITE_RESP = 4'd3;
    localparam [3:0] ST_READ_ADDR  = 4'd4;
    localparam [3:0] ST_READ_DATA  = 4'd5;
    localparam [3:0] ST_NEXT       = 4'd6;
    localparam [3:0] ST_DONE       = 4'd7;

    localparam [127:0] PRBS_SEED = 128'h1ACE_B00C_0123_4567_89AB_CDEF_1357_9BDF;

    reg [31:0] beat_index;
    reg [9:0]  start_delay;
    reg aw_sent;
    reg w_sent;
    reg fail_sticky;
    reg [127:0] write_prbs;
    reg [127:0] read_prbs;

    function [127:0] prbs_next;
        input [127:0] value;
        begin
            prbs_next = {value[126:0], value[127] ^ value[125] ^ value[100] ^ value[98]};
        end
    endfunction

    function [127:0] make_pattern;
        input [1:0] mode;
        input [27:0] address;
        input [31:0] index;
        input [127:0] prbs_value;
        reg [31:0] a;
        begin
            a = {4'b0, address};
            case (mode)
                2'd0: make_pattern = {a ^ 32'hC3C3_3C3C,
                                      a ^ 32'h5A5A_A5A5,
                                      a ^ 32'hFFFF_0000,
                                      a};
                2'd1: make_pattern = (128'b1 << index[6:0]);
                default: make_pattern = prbs_value;
            endcase
        end
    endfunction

    wire [127:0] selected_write_data = make_pattern(pattern_id, current_addr, beat_index, write_prbs);
    wire [127:0] selected_expected   = make_pattern(pattern_id, current_addr, beat_index, read_prbs);
    wire current_read_error = (m_axi_rdata != selected_expected) ||
                              (m_axi_rresp != 2'b00) || !m_axi_rlast;

    assign m_axi_awid    = 4'd0;
    assign m_axi_awaddr  = current_addr;
    assign m_axi_awlen   = 8'd0;
    assign m_axi_awsize  = 3'd4; // 16 bytes = 128 bits
    assign m_axi_awburst = 2'b01;
    assign m_axi_awlock  = 1'b0;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awqos   = 4'b0000;
    assign m_axi_awvalid = (state == ST_WRITE) && !aw_sent;

    assign m_axi_wdata   = selected_write_data;
    assign m_axi_wstrb   = 16'hFFFF;
    assign m_axi_wlast   = 1'b1;
    assign m_axi_wvalid  = (state == ST_WRITE) && !w_sent;
    assign m_axi_bready  = (state == ST_WRITE_RESP);

    assign m_axi_arid    = 4'd0;
    assign m_axi_araddr  = current_addr;
    assign m_axi_arlen   = 8'd0;
    assign m_axi_arsize  = 3'd4;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arqos   = 4'b0000;
    assign m_axi_arvalid = (state == ST_READ_ADDR);
    assign m_axi_rready  = (state == ST_READ_DATA);

    always @(posedge clk) begin
        if (reset) begin
            state            <= ST_WAIT_CALIB;
            pattern_id       <= 2'd0;
            current_addr     <= BASE_ADDR;
            beat_index       <= 32'd0;
            start_delay      <= 10'd0;
            aw_sent          <= 1'b0;
            w_sent           <= 1'b0;
            fail_sticky      <= 1'b0;
            write_prbs       <= PRBS_SEED;
            read_prbs        <= PRBS_SEED;
            write_count      <= 32'd0;
            read_count       <= 32'd0;
            error_count      <= 32'd0;
            first_error_addr <= 28'd0;
            expected_data    <= 128'd0;
            actual_data      <= 128'd0;
            compare_error    <= 1'b0;
            test_done        <= 1'b0;
            test_pass        <= 1'b0;
        end else begin
            compare_error <= 1'b0;
            case (state)
                ST_WAIT_CALIB: begin
                    if (init_calib_complete) begin
                        start_delay <= 10'd0;
                        state <= ST_START;
                    end
                end

                ST_START: begin
                    if (start_delay == 10'd1023) begin
                        current_addr <= BASE_ADDR;
                        beat_index <= 32'd0;
                        write_prbs <= PRBS_SEED;
                        aw_sent <= 1'b0;
                        w_sent <= 1'b0;
                        state <= ST_WRITE;
                    end else begin
                        start_delay <= start_delay + 1'b1;
                    end
                end

                ST_WRITE: begin
                    if (m_axi_awvalid && m_axi_awready)
                        aw_sent <= 1'b1;
                    if (m_axi_wvalid && m_axi_wready)
                        w_sent <= 1'b1;
                    if ((aw_sent || m_axi_awready) && (w_sent || m_axi_wready))
                        state <= ST_WRITE_RESP;
                end

                ST_WRITE_RESP: begin
                    if (m_axi_bvalid) begin
                        write_count <= write_count + 1'b1;
                        if (m_axi_bresp != 2'b00) begin
                            if (!fail_sticky)
                                first_error_addr <= current_addr;
                            fail_sticky <= 1'b1;
                            error_count <= error_count + 1'b1;
                        end
                        if (beat_index == TEST_BEATS-1) begin
                            current_addr <= BASE_ADDR;
                            beat_index <= 32'd0;
                            read_prbs <= PRBS_SEED;
                            state <= ST_READ_ADDR;
                        end else begin
                            current_addr <= current_addr + 28'd16;
                            beat_index <= beat_index + 1'b1;
                            write_prbs <= prbs_next(write_prbs);
                            aw_sent <= 1'b0;
                            w_sent <= 1'b0;
                            state <= ST_WRITE;
                        end
                    end
                end

                ST_READ_ADDR: begin
                    if (m_axi_arready)
                        state <= ST_READ_DATA;
                end

                ST_READ_DATA: begin
                    if (m_axi_rvalid) begin
                        expected_data <= selected_expected;
                        actual_data <= m_axi_rdata;
                        read_count <= read_count + 1'b1;
                        if (current_read_error) begin
                            compare_error <= 1'b1;
                            if (!fail_sticky)
                                first_error_addr <= current_addr;
                            fail_sticky <= 1'b1;
                            error_count <= error_count + 1'b1;
                        end
                        if (beat_index == TEST_BEATS-1) begin
                            state <= ST_NEXT;
                        end else begin
                            current_addr <= current_addr + 28'd16;
                            beat_index <= beat_index + 1'b1;
                            read_prbs <= prbs_next(read_prbs);
                            state <= ST_READ_ADDR;
                        end
                    end
                end

                ST_NEXT: begin
                    if (pattern_id == 2'd2) begin
                        test_done <= 1'b1;
                        test_pass <= !fail_sticky;
                        state <= ST_DONE;
                    end else begin
                        pattern_id <= pattern_id + 1'b1;
                        current_addr <= BASE_ADDR;
                        beat_index <= 32'd0;
                        write_prbs <= PRBS_SEED;
                        aw_sent <= 1'b0;
                        w_sent <= 1'b0;
                        state <= ST_WRITE;
                    end
                end

                default: state <= ST_DONE;
            endcase
        end
    end
endmodule
