// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : prbs16_stream_source.v
// Module  : prbs16_stream_source
// Created : 2026-08-25
// Revised : 2026-09-23
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module prbs16_stream_source #(
    parameter [15:0] PRBS_SEED = 16'hACE1
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        ready,
    output wire        valid,
    output wire [15:0] data,
    output reg  [63:0] total_words
);
    reg [15:0] lfsr;
    assign valid = enable;
    assign data  = lfsr;

    function [15:0] prbs_next;
        input [15:0] value;
        begin
            prbs_next = {value[14:0], value[15] ^ value[13] ^ value[12] ^ value[10]};
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            lfsr        <= PRBS_SEED;
            total_words <= 64'd0;
        end else if (valid && ready) begin
            lfsr        <= prbs_next(lfsr);
            total_words <= total_words + 1'b1;
        end
    end
endmodule
