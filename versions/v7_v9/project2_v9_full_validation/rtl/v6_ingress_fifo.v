// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : v6_ingress_fifo.v
// Module  : v6_ingress_fifo
// Created : 2026-08-25
// Revised : 2026-09-23
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// Single-clock acquisition FIFO. The hysteretic run gate prevents full-boundary
// chatter and models a backpressure-capable acquisition front end.
module v6_ingress_fifo #(
    parameter integer DEPTH_WORDS = 2048,
    parameter integer HIGH_WATER_WORDS = 1536,
    parameter integer LOW_WATER_WORDS = 512,
    parameter integer BURST_WORDS = 512
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        clear_counters,
    input  wire        flush,
    input  wire        enable,
    input  wire        in_valid,
    input  wire [15:0] in_data,
    output wire        in_ready,
    input  wire        out_ready,
    output wire        out_valid,
    output wire [15:0] out_data,
    output reg  [$clog2(DEPTH_WORDS+1)-1:0] level_words,
    output wire        has_burst,
    output wire        high_water,
    output wire        low_water,
    output reg         source_run,
    output reg  [31:0] overflow_count,
    output reg  [31:0] underflow_count
);
    localparam integer PTR_BITS = $clog2(DEPTH_WORDS);
    reg [15:0] mem [0:DEPTH_WORDS-1];
    reg [PTR_BITS-1:0] wr_ptr;
    reg [PTR_BITS-1:0] rd_ptr;
    wire push = in_valid && in_ready;
    wire pop  = out_ready && out_valid;

    assign in_ready  = source_run && (level_words < DEPTH_WORDS);
    assign out_valid = (level_words != 0);
    assign out_data  = mem[rd_ptr];
    assign has_burst = (level_words >= BURST_WORDS);
    assign high_water = (level_words >= HIGH_WATER_WORDS);
    assign low_water  = (level_words <= LOW_WATER_WORDS);

    always @(posedge clk) begin
        if (reset) begin
            wr_ptr          <= 0;
            rd_ptr          <= 0;
            level_words     <= 0;
            source_run      <= 1'b0;
            overflow_count  <= 0;
            underflow_count <= 0;
        end else begin
            if (!enable)
                source_run <= 1'b0;
            else if (source_run && high_water)
                source_run <= 1'b0;
            else if (!source_run && low_water)
                source_run <= 1'b1;

            if (clear_counters) begin
                overflow_count  <= 0;
                underflow_count <= 0;
            end else begin
                if (in_valid && !in_ready)
                    overflow_count <= overflow_count + 1'b1;
                if (out_ready && !out_valid)
                    underflow_count <= underflow_count + 1'b1;
            end

            if (push) begin
                mem[wr_ptr] <= in_data;
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (pop)
                rd_ptr <= rd_ptr + 1'b1;

            if (flush) begin
                rd_ptr <= wr_ptr;
                level_words <= 0;
            end else begin
                case ({push,pop})
                    2'b10: level_words <= level_words + 1'b1;
                    2'b01: level_words <= level_words - 1'b1;
                    default: level_words <= level_words;
                endcase
            end
        end
    end
endmodule
