// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : v7_ui_status_snapshot.v
// Module  : v7_ui_status_snapshot
// Created : 2026-09-02
// Revised : 2026-09-23
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// Atomic UI-clock status snapshot. The request and acknowledge are toggles;
// snapshot_data remains stable until the next request and is double-sampled
// by the 125 MHz control domain.
module v7_ui_status_snapshot (
    input  wire         ui_clk,
    input  wire         reset,
    input  wire         request_toggle_async,
    input  wire         init_calib_complete,
    input  wire         ring_started,
    input  wire         drain_active,
    input  wire         write_inflight,
    input  wire         read_inflight,
    input  wire         ring_full,
    input  wire         fatal_error,
    input  wire [31:0]  occupancy_bytes,
    input  wire [31:0]  packet_sequence,
    input  wire [31:0]  ring_overflow_count,
    input  wire [31:0]  ring_underflow_count,
    input  wire [31:0]  tx_overflow_count,
    input  wire [31:0]  tx_underflow_count,
    input  wire [31:0]  write_stall_cycles,
    input  wire [31:0]  read_stall_cycles,
    input  wire [31:0]  committed_bytes_low,
    input  wire [31:0]  released_bytes_low,
    output reg          acknowledge_toggle,
    output reg  [326:0] snapshot_data
);
    reg request_meta, request_sync, request_seen;

    always @(posedge ui_clk) begin
        if (reset) begin
            request_meta       <= 0;
            request_sync       <= 0;
            request_seen       <= 0;
            acknowledge_toggle <= 0;
            snapshot_data      <= 0;
        end else begin
            request_meta <= request_toggle_async;
            request_sync <= request_meta;
            if (request_sync != request_seen) begin
                request_seen <= request_sync;
                snapshot_data <= {
                    released_bytes_low,
                    committed_bytes_low,
                    read_stall_cycles,
                    write_stall_cycles,
                    tx_underflow_count,
                    tx_overflow_count,
                    ring_underflow_count,
                    ring_overflow_count,
                    packet_sequence,
                    occupancy_bytes,
                    fatal_error, ring_full, read_inflight, write_inflight,
                    drain_active, ring_started, init_calib_complete
                };
                acknowledge_toggle <= request_sync;
            end
        end
    end
endmodule
