// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : udp_v6_tx_fifo_packetizer.v
// Module  : udp_v6_tx_fifo_packetizer
// Created : 2026-08-25
// Revised : 2026-09-22
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// Multi-packet TX FIFO plus UDP packetizer. A DDR slot is eligible for release
// only when user_rd_last is accepted into this memory.
module udp_v6_tx_fifo_packetizer #(
    parameter integer DATA_BYTES = 1024,
    parameter integer FIFO_PACKETS = 8,
    parameter integer POST_READY_IDLE_CYCLES = 0
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        user_rd_valid,
    input  wire        user_rd_last,
    input  wire [7:0]  user_rd_data,
    input  wire [31:0] committed_bytes_low,
    input  wire [31:0] occupancy_bytes,
    input  wire        stream_expected,
    output wire        burst_space_available,
    output wire        burst_committed,
    output reg         packet_done,
    output reg  [31:0] packet_sequence,
    output reg         framing_error,
    output reg  [13:0] fifo_byte_count,
    output reg  [3:0]  fifo_packet_count,
    output reg  [31:0] overflow_count,
    output reg  [31:0] underflow_count,
    output reg         app_tx_data_vld,
    output reg         app_tx_data_last,
    output reg  [7:0]  app_tx_data,
    output wire [15:0] app_tx_length,
    input  wire        app_tx_ready
);
    localparam integer HEADER_BYTES = 24;
    localparam integer PACKET_BYTES = HEADER_BYTES + DATA_BYTES;
    localparam integer FIFO_BYTES = DATA_BYTES * FIFO_PACKETS;
    localparam integer PTR_BITS = $clog2(FIFO_BYTES);
    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_SEND = 3'd1;
    localparam [2:0] ST_WAIT_READY_LOW  = 3'd2;
    localparam [2:0] ST_WAIT_READY_HIGH = 3'd3;
    localparam [2:0] ST_PACE = 3'd4;

    reg [7:0] data_mem [0:FIFO_BYTES-1];
    reg [31:0] meta_committed [0:FIFO_PACKETS-1];
    reg [31:0] meta_occupancy [0:FIFO_PACKETS-1];
    reg [PTR_BITS-1:0] write_ptr;
    reg [PTR_BITS-1:0] read_ptr;
    reg [$clog2(DATA_BYTES)-1:0] burst_write_index;
    reg [$clog2(FIFO_PACKETS)-1:0] meta_write_ptr;
    reg [$clog2(FIFO_PACKETS)-1:0] meta_read_ptr;
    reg [10:0] tx_index;
    reg [2:0] state;
    reg [15:0] pace_count;
    reg starvation_latched;

    wire push = user_rd_valid && (fifo_byte_count < FIFO_BYTES);
    wire push_last = push && user_rd_last;
    wire pop = (state == ST_SEND) && (tx_index >= HEADER_BYTES);
    wire pop_last = pop && (tx_index == PACKET_BYTES-1);

    assign burst_space_available = (fifo_byte_count <= FIFO_BYTES-DATA_BYTES);
    assign burst_committed = push_last;
    assign app_tx_length = PACKET_BYTES;

    function [7:0] header_byte;
        input [4:0] index;
        input [31:0] sequence;
        input [31:0] committed;
        input [31:0] occupancy;
        begin
            case (index)
                5'd0:  header_byte = "P";
                5'd1:  header_byte = "2";
                5'd2:  header_byte = "V";
                // V6 changes the internal pipeline while deliberately retaining
                // the proven V5 wire format and Windows receiver compatibility.
                5'd3:  header_byte = "5";
                5'd4:  header_byte = 8'h05;
                5'd5:  header_byte = 8'h00;
                5'd6:  header_byte = PACKET_BYTES[15:8];
                5'd7:  header_byte = PACKET_BYTES[7:0];
                5'd8:  header_byte = sequence[31:24];
                5'd9:  header_byte = sequence[23:16];
                5'd10: header_byte = sequence[15:8];
                5'd11: header_byte = sequence[7:0];
                5'd12: header_byte = DATA_BYTES[15:8];
                5'd13: header_byte = DATA_BYTES[7:0];
                5'd14: header_byte = HEADER_BYTES[15:8];
                5'd15: header_byte = HEADER_BYTES[7:0];
                5'd16: header_byte = committed[31:24];
                5'd17: header_byte = committed[23:16];
                5'd18: header_byte = committed[15:8];
                5'd19: header_byte = committed[7:0];
                5'd20: header_byte = occupancy[31:24];
                5'd21: header_byte = occupancy[23:16];
                5'd22: header_byte = occupancy[15:8];
                default: header_byte = occupancy[7:0];
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            write_ptr          <= 0;
            read_ptr           <= 0;
            burst_write_index  <= 0;
            meta_write_ptr     <= 0;
            meta_read_ptr      <= 0;
            fifo_byte_count    <= 0;
            fifo_packet_count  <= 0;
            tx_index           <= 0;
            state              <= ST_IDLE;
            pace_count         <= 0;
            packet_done        <= 1'b0;
            packet_sequence    <= 32'd0;
            framing_error      <= 1'b0;
            overflow_count     <= 32'd0;
            underflow_count    <= 32'd0;
            starvation_latched <= 1'b0;
            app_tx_data_vld    <= 1'b0;
            app_tx_data_last   <= 1'b0;
            app_tx_data        <= 8'd0;
        end else begin
            packet_done      <= 1'b0;
            app_tx_data_vld  <= 1'b0;
            app_tx_data_last <= 1'b0;

            if (user_rd_valid && fifo_byte_count == FIFO_BYTES) begin
                framing_error <= 1'b1;
                overflow_count <= overflow_count + 1'b1;
            end

            if (stream_expected && packet_sequence != 0 && state == ST_IDLE && fifo_packet_count == 0) begin
                if (!starvation_latched)
                    underflow_count <= underflow_count + 1'b1;
                starvation_latched <= 1'b1;
            end else if (fifo_packet_count != 0) begin
                starvation_latched <= 1'b0;
            end

            if (push) begin
                data_mem[write_ptr] <= user_rd_data;
                write_ptr <= write_ptr + 1'b1;
                if (user_rd_last != (burst_write_index == DATA_BYTES-1))
                    framing_error <= 1'b1;
                if (user_rd_last) begin
                    burst_write_index <= 0;
                    meta_committed[meta_write_ptr] <= committed_bytes_low;
                    meta_occupancy[meta_write_ptr] <= occupancy_bytes;
                    meta_write_ptr <= meta_write_ptr + 1'b1;
                end else begin
                    burst_write_index <= burst_write_index + 1'b1;
                end
            end

            case ({push, pop})
                2'b10: fifo_byte_count <= fifo_byte_count + 1'b1;
                2'b01: fifo_byte_count <= fifo_byte_count - 1'b1;
                default: fifo_byte_count <= fifo_byte_count;
            endcase

            case ({push_last, pop_last})
                2'b10: fifo_packet_count <= fifo_packet_count + 1'b1;
                2'b01: fifo_packet_count <= fifo_packet_count - 1'b1;
                default: fifo_packet_count <= fifo_packet_count;
            endcase

            case (state)
                ST_IDLE: begin
                    if (fifo_packet_count != 0 && app_tx_ready) begin
                        tx_index <= 0;
                        state <= ST_SEND;
                    end
                end

                ST_SEND: begin
                    app_tx_data_vld  <= 1'b1;
                    app_tx_data_last <= (tx_index == PACKET_BYTES-1);
                    if (tx_index < HEADER_BYTES)
                        app_tx_data <= header_byte(tx_index[4:0], packet_sequence,
                            meta_committed[meta_read_ptr], meta_occupancy[meta_read_ptr]);
                    else begin
                        app_tx_data <= data_mem[read_ptr];
                        read_ptr <= read_ptr + 1'b1;
                    end

                    if (tx_index == PACKET_BYTES-1) begin
                        packet_done <= 1'b1;
                        packet_sequence <= packet_sequence + 1'b1;
                        meta_read_ptr <= meta_read_ptr + 1'b1;
                        // net21/udp_send keeps ready high on the same edge that
                        // accepts last, then lowers it while the frame drains.
                        // Do not mistake that stale high level for permission to
                        // launch the next packet.
                        state <= ST_WAIT_READY_LOW;
                    end else begin
                        tx_index <= tx_index + 1'b1;
                    end
                end

                ST_WAIT_READY_LOW: begin
                    if (!app_tx_ready)
                        state <= ST_WAIT_READY_HIGH;
                end

                ST_WAIT_READY_HIGH: begin
                    if (app_tx_ready) begin
                        if (POST_READY_IDLE_CYCLES == 0) begin
                            state <= ST_IDLE;
                        end else begin
                            pace_count <= POST_READY_IDLE_CYCLES;
                            state <= ST_PACE;
                        end
                    end
                end

                ST_PACE: begin
                    if (pace_count > 1'b1)
                        pace_count <= pace_count - 1'b1;
                    else begin
                        pace_count <= 0;
                        state <= ST_IDLE;
                    end
                end
            endcase
        end
    end
endmodule
