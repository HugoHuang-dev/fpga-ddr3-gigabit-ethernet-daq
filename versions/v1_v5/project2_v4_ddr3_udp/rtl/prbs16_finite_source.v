// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : prbs16_finite_source.v
// Module  : prbs16_finite_source
// Created : 2026-08-02
// Revised : 2026-09-20
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// Finite acquisition model for v4.  The source emits exactly TOTAL_WORDS
// 16-bit PRBS words after MIG calibration. The ADMA write channel
// supplies the asynchronous FIFO between this clock and the MIG AXI clock.
module prbs16_finite_source #(
    parameter integer TOTAL_WORDS = 32768,
    parameter integer START_DELAY_CYCLES = 1024,
    parameter [15:0] PRBS_SEED = 16'hACE1
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        init_calib_complete,
    input  wire        start,
    output reg         user_wr_en,
    output reg  [15:0] user_wr_data,
    output reg  [31:0] word_count,
    output reg         source_done
);
    localparam [1:0] ST_WAIT = 2'd0;
    localparam [1:0] ST_SEND = 2'd1;
    localparam [1:0] ST_DONE = 2'd2;

    reg [1:0] state;
    reg [31:0] delay_count;
    reg [15:0] lfsr;
    reg calib_meta, calib_sync;

    function [15:0] prbs_next;
        input [15:0] value;
        begin
            prbs_next = {value[14:0], value[15] ^ value[13] ^ value[12] ^ value[10]};
        end
    endfunction

    always @(posedge clk) begin
        calib_meta <= init_calib_complete;
        calib_sync <= calib_meta;
    end

    always @(posedge clk) begin
        if (reset) begin
            state        <= ST_WAIT;
            delay_count  <= 32'd0;
            lfsr         <= PRBS_SEED;
            user_wr_en   <= 1'b0;
            user_wr_data <= 16'd0;
            word_count   <= 32'd0;
            source_done  <= 1'b0;
        end else begin
            user_wr_en <= 1'b0;
            case (state)
                ST_WAIT: begin
                    if (!calib_sync)
                        delay_count <= 32'd0;
                    else if (!start)
                        delay_count <= 32'd0;
                    else if (delay_count == START_DELAY_CYCLES-1)
                        state <= ST_SEND;
                    else
                        delay_count <= delay_count + 1'b1;
                end

                ST_SEND: begin
                    user_wr_en   <= 1'b1;
                    user_wr_data <= lfsr;
                    lfsr         <= prbs_next(lfsr);
                    word_count   <= word_count + 1'b1;
                    if (word_count == TOTAL_WORDS-1)
                        state <= ST_DONE;
                end

                default: begin
                    source_done <= 1'b1;
                    state <= ST_DONE;
                end
            endcase
        end
    end
endmodule
