// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : prbs16_burst_source.v
// Module  : prbs16_burst_source
// Created : 2026-08-11
// Revised : 2026-09-22
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// Continuous acquisition model with burst-level backpressure.  A toggle from
// the DDR/UI domain authorizes exactly one BURST_BYTES block.  PRBS state is
// continuous across blocks, so stalls never create gaps or duplicate samples.
module prbs16_burst_source #(
    parameter integer BURST_BYTES = 1024,
    parameter [15:0] PRBS_SEED = 16'hACE1
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        grant_toggle_async,
    output reg         user_wr_en,
    output reg  [15:0] user_wr_data,
    output reg         busy,
    output reg  [63:0] total_words,
    output reg  [31:0] completed_bursts
);
    localparam integer WORDS_PER_BURST = BURST_BYTES / 2;

    reg grant_meta;
    reg grant_sync;
    reg grant_seen;
    reg [15:0] lfsr;
    reg [15:0] word_index;

    function [15:0] prbs_next;
        input [15:0] value;
        begin
            prbs_next = {value[14:0], value[15] ^ value[13] ^ value[12] ^ value[10]};
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            grant_meta <= 1'b0;
            grant_sync <= 1'b0;
        end else begin
            grant_meta <= grant_toggle_async;
            grant_sync <= grant_meta;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            grant_seen       <= 1'b0;
            user_wr_en       <= 1'b0;
            user_wr_data     <= 16'd0;
            busy             <= 1'b0;
            lfsr             <= PRBS_SEED;
            word_index       <= 16'd0;
            total_words      <= 64'd0;
            completed_bursts <= 32'd0;
        end else begin
            user_wr_en <= 1'b0;

            if (!busy && enable && (grant_sync != grant_seen)) begin
                grant_seen <= grant_sync;
                word_index <= 16'd0;
                busy       <= 1'b1;
            end else if (busy) begin
                user_wr_en   <= 1'b1;
                user_wr_data <= lfsr;
                lfsr         <= prbs_next(lfsr);
                total_words  <= total_words + 1'b1;

                if (word_index == WORDS_PER_BURST-1) begin
                    word_index       <= 16'd0;
                    busy             <= 1'b0;
                    completed_bursts <= completed_bursts + 1'b1;
                end else begin
                    word_index <= word_index + 1'b1;
                end
            end
        end
    end
endmodule

