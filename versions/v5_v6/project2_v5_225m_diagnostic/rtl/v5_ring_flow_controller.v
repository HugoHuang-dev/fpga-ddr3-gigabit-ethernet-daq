// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : v5_ring_flow_controller.v
// Module  : v5_ring_flow_controller
// Created : 2026-08-11
// Revised : 2026-09-21
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// Burst-level ownership and flow control for the DDR3 circular buffer.
//
// Invariants:
//   * A write slot becomes occupied only after an AXI OKAY write response.
//   * A read slot is released only when the final byte has entered the TX FIFO.
//   * At most one write and one read burst are outstanding in v5.
module v5_ring_flow_controller #(
    parameter integer BASE_ADDR   = 0,
    parameter integer RING_BYTES  = 262144,
    parameter integer BURST_BYTES = 1024
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        start_async,
    input  wire        init_calib_complete,

    input  wire        axi_bvalid,
    input  wire        axi_bready,
    input  wire [1:0]  axi_bresp,

    input  wire        user_rd_req_busy,
    input  wire        tx_burst_committed,
    input  wire        tx_burst_space_available,

    input  wire        packetizer_error,
    input  wire        wr_cmd_fifo_err,
    input  wire        wr_data_fifo_err,
    input  wire        rd_cmd_fifo_err,
    input  wire        rd_data_fifo_err,

    output reg         write_grant_toggle,
    output reg         user_rd_req,
    output reg         started,
    output reg         write_inflight,
    output reg         read_inflight,
    output reg  [31:0] write_pointer,
    output reg  [31:0] read_pointer,
    output reg  [63:0] committed_bytes,
    output reg  [63:0] released_bytes,
    output reg  [31:0] occupancy_bytes,
    output wire        ring_full,
    output wire        ring_empty,
    output reg  [31:0] write_stall_cycles,
    output reg  [31:0] read_stall_cycles,
    output reg         fatal_error
);
    localparam integer RING_SLOTS = RING_BYTES / BURST_BYTES;
    localparam integer SLOT_BITS = $clog2(RING_SLOTS + 1);
    localparam [31:0] END_ADDR = BASE_ADDR + RING_BYTES;

    reg start_meta;
    reg start_sync;
    reg [SLOT_BITS-1:0] occupied_slots;

    wire write_commit = axi_bvalid && axi_bready && write_inflight;
    wire write_commit_ok = write_commit && (axi_bresp == 2'b00);
    wire read_release = tx_burst_committed && read_inflight;

    assign ring_full  = (occupied_slots == RING_SLOTS);
    assign ring_empty = (occupied_slots == 0);

    always @(*) begin
        occupancy_bytes = occupied_slots * BURST_BYTES;
    end

    always @(posedge clk) begin
        if (reset) begin
            start_meta <= 1'b0;
            start_sync <= 1'b0;
        end else begin
            start_meta <= start_async;
            start_sync <= start_meta;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            write_grant_toggle <= 1'b0;
            user_rd_req        <= 1'b0;
            started            <= 1'b0;
            write_inflight     <= 1'b0;
            read_inflight      <= 1'b0;
            write_pointer      <= BASE_ADDR;
            read_pointer       <= BASE_ADDR;
            committed_bytes    <= 64'd0;
            released_bytes     <= 64'd0;
            occupied_slots     <= {SLOT_BITS{1'b0}};
            write_stall_cycles <= 32'd0;
            read_stall_cycles  <= 32'd0;
            fatal_error        <= 1'b0;
        end else begin
            user_rd_req <= 1'b0;

            if (start_sync && init_calib_complete)
                started <= 1'b1;

            if (packetizer_error || wr_cmd_fifo_err || wr_data_fifo_err ||
                rd_cmd_fifo_err || rd_data_fifo_err)
                fatal_error <= 1'b1;

            if (write_commit) begin
                write_inflight <= 1'b0;
                if (axi_bresp != 2'b00) begin
                    fatal_error <= 1'b1;
                end else begin
                    committed_bytes <= committed_bytes + BURST_BYTES;
                    if (write_pointer >= END_ADDR-BURST_BYTES)
                        write_pointer <= BASE_ADDR;
                    else
                        write_pointer <= write_pointer + BURST_BYTES;
                end
            end

            if (read_release) begin
                read_inflight  <= 1'b0;
                released_bytes <= released_bytes + BURST_BYTES;
                if (read_pointer >= END_ADDR-BURST_BYTES)
                    read_pointer <= BASE_ADDR;
                else
                    read_pointer <= read_pointer + BURST_BYTES;
            end

            case ({write_commit_ok, read_release})
                2'b10: begin
                    if (!ring_full)
                        occupied_slots <= occupied_slots + 1'b1;
                    else
                        fatal_error <= 1'b1;
                end
                2'b01: begin
                    if (!ring_empty)
                        occupied_slots <= occupied_slots - 1'b1;
                    else
                        fatal_error <= 1'b1;
                end
                default: occupied_slots <= occupied_slots;
            endcase

            if (started && !fatal_error) begin
                if (!write_inflight && !ring_full) begin
                    write_grant_toggle <= ~write_grant_toggle;
                    write_inflight <= 1'b1;
                end else if (ring_full && !read_release) begin
                    write_stall_cycles <= write_stall_cycles + 1'b1;
                end

                if (!read_inflight && !ring_empty && tx_burst_space_available &&
                    !user_rd_req_busy) begin
                    user_rd_req   <= 1'b1;
                    read_inflight <= 1'b1;
                end else if (!ring_empty && !tx_burst_space_available) begin
                    read_stall_cycles <= read_stall_cycles + 1'b1;
                end
            end
        end
    end
endmodule
