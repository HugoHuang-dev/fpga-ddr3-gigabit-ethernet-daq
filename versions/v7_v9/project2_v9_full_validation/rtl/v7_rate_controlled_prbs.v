// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : v7_rate_controlled_prbs.v
// Module  : v7_rate_controlled_prbs
// Created : 2026-09-02
// Revised : 2026-09-23
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// V7 acquisition source. A rate of zero selects the V6-compatible maximum
// rate. Non-zero rates are expressed in accepted 16-bit words per second.
// A pending sample is held until ready, so throttling never skips PRBS words.
module v7_rate_controlled_prbs #(
    parameter integer CLK_HZ = 125000000,
    parameter [15:0] PRBS_SEED = 16'hACE1
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        clear_counters,
    input  wire        enable,
    input  wire        ready,
    input  wire [31:0] rate_words_per_sec,
    input  wire        finite_mode,
    input  wire [31:0] finite_words,
    output wire        valid,
    output wire [15:0] data,
    output wire        finite_done,
    output reg  [31:0] run_words,
    output reg  [63:0] total_words
);
    reg [15:0] lfsr;
    reg [32:0] phase_accumulator;
    reg token_pending;
    reg enable_d;

    wire unlimited = (rate_words_per_sec == 0) ||
                     (rate_words_per_sec >= CLK_HZ);
    assign finite_done = finite_mode && (finite_words != 0) &&
                         (run_words >= finite_words);
    assign valid = enable && !finite_done && (unlimited || token_pending);
    assign data = lfsr;

    function [15:0] prbs_next;
        input [15:0] value;
        begin
            prbs_next = {value[14:0], value[15] ^ value[13] ^
                         value[12] ^ value[10]};
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            lfsr              <= PRBS_SEED;
            phase_accumulator <= 0;
            token_pending     <= 0;
            enable_d          <= 0;
            run_words         <= 0;
            total_words       <= 0;
        end else begin
            enable_d <= enable;

            if (clear_counters) begin
                lfsr              <= PRBS_SEED;
                phase_accumulator <= 0;
                token_pending     <= 0;
                run_words         <= 0;
                total_words       <= 0;
            end else begin
                if (enable && !enable_d) begin
                    run_words         <= 0;
                    phase_accumulator <= 0;
                    token_pending     <= 0;
                end

                if (!enable || finite_done || unlimited) begin
                    token_pending <= 0;
                    if (!enable)
                        phase_accumulator <= 0;
                end else if (token_pending && ready) begin
                    // Consume the pending token and advance the phase in the
                    // same cycle.  Omitting this advance inserts one dead
                    // clock per word and makes SET_RATE systematically slow.
                    if (phase_accumulator + rate_words_per_sec >= CLK_HZ) begin
                        phase_accumulator <= phase_accumulator +
                                             rate_words_per_sec - CLK_HZ;
                        token_pending <= 1'b1;
                    end else begin
                        phase_accumulator <= phase_accumulator +
                                             rate_words_per_sec;
                        token_pending <= 1'b0;
                    end
                end else if (!token_pending) begin
                    if (phase_accumulator + rate_words_per_sec >= CLK_HZ) begin
                        phase_accumulator <= phase_accumulator +
                                             rate_words_per_sec - CLK_HZ;
                        token_pending <= 1'b1;
                    end else begin
                        phase_accumulator <= phase_accumulator +
                                             rate_words_per_sec;
                    end
                end

                if (valid && ready) begin
                    lfsr        <= prbs_next(lfsr);
                    run_words   <= run_words + 1'b1;
                    total_words <= total_words + 1'b1;
                end
            end
        end
    end
endmodule
