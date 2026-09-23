// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : v6_ingress_drain.v
// Module  : v6_ingress_drain
// Created : 2026-08-25
// Revised : 2026-09-22
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// Converts one scheduler toggle into exactly one contiguous ADMA write burst.
module v6_ingress_drain #(
    parameter integer BURST_WORDS = 512
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        grant_toggle_async,
    input  wire        fifo_valid,
    input  wire [15:0] fifo_data,
    output wire        fifo_ready,
    output wire        user_wr_en,
    output wire [15:0] user_wr_data,
    output reg         busy,
    output reg  [31:0] completed_bursts,
    output reg  [31:0] starvation_count
);
    reg grant_meta, grant_sync, grant_seen;
    reg [$clog2(BURST_WORDS)-1:0] word_index;
    assign fifo_ready   = busy && fifo_valid;
    assign user_wr_en   = busy && fifo_valid;
    assign user_wr_data = fifo_data;

    always @(posedge clk) begin
        if (reset) begin
            grant_meta <= 0; grant_sync <= 0;
        end else begin
            grant_meta <= grant_toggle_async;
            grant_sync <= grant_meta;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            grant_seen <= 0; busy <= 0; word_index <= 0;
            completed_bursts <= 0; starvation_count <= 0;
        end else begin
            if (!busy && enable && grant_sync != grant_seen) begin
                grant_seen <= grant_sync;
                word_index <= 0;
                busy <= 1'b1;
            end else if (busy && !fifo_valid) begin
                starvation_count <= starvation_count + 1'b1;
            end else if (busy && fifo_valid) begin
                if (word_index == BURST_WORDS-1) begin
                    word_index <= 0;
                    busy <= 1'b0;
                    completed_bursts <= completed_bursts + 1'b1;
                end else begin
                    word_index <= word_index + 1'b1;
                end
            end
        end
    end
endmodule
