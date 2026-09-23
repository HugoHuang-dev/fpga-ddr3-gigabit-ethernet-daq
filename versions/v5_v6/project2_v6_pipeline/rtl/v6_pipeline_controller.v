// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : v6_pipeline_controller.v
// Module  : v6_pipeline_controller
// Created : 2026-08-25
// Revised : 2026-09-22
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module v6_pipeline_controller #(
    parameter integer BASE_ADDR = 0,
    parameter integer RING_BYTES = 262144,
    parameter integer BURST_BYTES = 1024,
    parameter integer DDR_HIGH_WATER_BYTES = 65536,
    parameter integer DDR_LOW_WATER_BYTES = 16384
) (
    input wire clk, input wire reset, input wire start_async,
    input wire init_calib_complete, input wire ingress_has_burst_async,
    input wire axi_bvalid, input wire axi_bready, input wire [1:0] axi_bresp,
    input wire user_rd_req_busy, input wire tx_burst_committed,
    input wire tx_burst_space_available, input wire packetizer_error,
    input wire wr_cmd_fifo_err, input wire wr_data_fifo_err,
    input wire rd_cmd_fifo_err, input wire rd_data_fifo_err,
    output reg write_grant_toggle, output reg user_rd_req, output reg started,
    output reg write_inflight, output reg read_inflight, output reg drain_active,
    output reg [31:0] write_pointer, output reg [31:0] read_pointer,
    output reg [63:0] committed_bytes, output reg [63:0] released_bytes,
    output reg [31:0] occupancy_bytes, output wire ring_full, output wire ring_empty,
    output reg [31:0] write_stall_cycles, output reg [31:0] read_stall_cycles,
    output reg [31:0] ring_overflow_count, output reg [31:0] ring_underflow_count,
    output reg fatal_error
);
    localparam integer RING_SLOTS=RING_BYTES/BURST_BYTES;
    localparam integer SLOT_BITS=$clog2(RING_SLOTS+1);
    localparam integer HIGH_SLOTS=DDR_HIGH_WATER_BYTES/BURST_BYTES;
    localparam integer LOW_SLOTS=DDR_LOW_WATER_BYTES/BURST_BYTES;
    localparam [31:0] END_ADDR=BASE_ADDR+RING_BYTES;
    reg start_meta,start_sync,ingress_meta,ingress_sync;
    reg [SLOT_BITS-1:0] occupied_slots;
    wire write_commit=axi_bvalid && axi_bready && write_inflight;
    wire write_commit_ok=write_commit && axi_bresp==2'b00;
    wire read_release=tx_burst_committed && read_inflight;
    assign ring_full=(occupied_slots==RING_SLOTS);
    assign ring_empty=(occupied_slots==0);

    always @(*) occupancy_bytes=occupied_slots*BURST_BYTES;
    always @(posedge clk) begin
        if(reset) begin start_meta<=0;start_sync<=0;ingress_meta<=0;ingress_sync<=0; end
        else begin start_meta<=start_async;start_sync<=start_meta;
            ingress_meta<=ingress_has_burst_async;ingress_sync<=ingress_meta; end
    end

    always @(posedge clk) begin
        if(reset) begin
            write_grant_toggle<=0; user_rd_req<=0; started<=0;
            write_inflight<=0; read_inflight<=0; drain_active<=0;
            write_pointer<=BASE_ADDR; read_pointer<=BASE_ADDR;
            committed_bytes<=0; released_bytes<=0; occupied_slots<=0;
            write_stall_cycles<=0; read_stall_cycles<=0;
            ring_overflow_count<=0; ring_underflow_count<=0; fatal_error<=0;
        end else begin
            user_rd_req<=0;
            if(start_sync && init_calib_complete) started<=1;
            if(packetizer_error||wr_cmd_fifo_err||wr_data_fifo_err||rd_cmd_fifo_err||rd_data_fifo_err)
                fatal_error<=1;

            if(occupied_slots>=HIGH_SLOTS) drain_active<=1;
            else if(occupied_slots<=LOW_SLOTS) drain_active<=0;

            if(write_commit) begin
                write_inflight<=0;
                if(axi_bresp!=0) fatal_error<=1;
                else begin
                    committed_bytes<=committed_bytes+BURST_BYTES;
                    write_pointer <= (write_pointer>=END_ADDR-BURST_BYTES) ? BASE_ADDR : write_pointer+BURST_BYTES;
                end
            end
            if(read_release) begin
                read_inflight<=0; released_bytes<=released_bytes+BURST_BYTES;
                read_pointer <= (read_pointer>=END_ADDR-BURST_BYTES) ? BASE_ADDR : read_pointer+BURST_BYTES;
            end

            case({write_commit_ok,read_release})
                2'b10: if(!ring_full) occupied_slots<=occupied_slots+1'b1;
                       else ring_overflow_count<=ring_overflow_count+1'b1;
                2'b01: if(!ring_empty) occupied_slots<=occupied_slots-1'b1;
                       else ring_underflow_count<=ring_underflow_count+1'b1;
                default: occupied_slots<=occupied_slots;
            endcase

            if(started && !fatal_error) begin
                if(!write_inflight && !ring_full && ingress_sync) begin
                    write_grant_toggle<=~write_grant_toggle; write_inflight<=1;
                end else if(ingress_sync && ring_full && !read_release)
                    write_stall_cycles<=write_stall_cycles+1'b1;

                if(!read_inflight && drain_active && !ring_empty && tx_burst_space_available && !user_rd_req_busy) begin
                    user_rd_req<=1; read_inflight<=1;
                end else if(drain_active && !ring_empty && !tx_burst_space_available)
                    read_stall_cycles<=read_stall_cycles+1'b1;
            end
        end
    end
endmodule
