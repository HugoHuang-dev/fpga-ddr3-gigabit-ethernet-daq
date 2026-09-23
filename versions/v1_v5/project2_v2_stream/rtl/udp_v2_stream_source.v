// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : udp_v2_stream_source.v
// Module  : udp_v2_stream_source
// Created : 2026-07-22
// Revised : 2026-09-19
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// Project2 v2 continuous UDP test source.
//
// Packet payload layout (all multi-byte fields are big-endian):
//   0..3   "P2V2"
//   4      protocol version (2)
//   5      flags (0)
//   6..7   total UDP payload length
//   8..11  32-bit packet sequence
//   12..13 incrementing-data length
//   14     first incrementing-data byte in this packet
//   15     reserved (0)
//   16..   byte-by-byte incrementing test data
module udp_v2_stream_source #(
    parameter integer PACKET_BYTES = 1024,
    parameter integer INTER_PACKET_GAP_CYCLES = 125_000
)(
    input  wire        clk,
    input  wire        reset,
    output reg         app_tx_data_vld,
    output reg         app_tx_data_last,
    output reg  [7:0]  app_tx_data,
    output reg  [15:0] app_tx_length,
    input  wire        app_tx_ready,
    output reg  [31:0] packet_sequence,
    output reg  [31:0] packet_count
);

localparam integer HEADER_BYTES = 16;
localparam integer DATA_BYTES = PACKET_BYTES - HEADER_BYTES;
localparam [1:0] TX_IDLE = 2'd0;
localparam [1:0] TX_SEND = 2'd1;
localparam [1:0] TX_GAP  = 2'd2;

reg [1:0]  tx_state;
reg [15:0] byte_index;
reg [31:0] gap_counter;
reg [7:0]  payload_start;

function [7:0] stream_byte;
    input [15:0] index;
    input [31:0] sequence;
    input [7:0] start_value;
    begin
        case (index)
            16'd0:  stream_byte = "P";
            16'd1:  stream_byte = "2";
            16'd2:  stream_byte = "V";
            16'd3:  stream_byte = "2";
            16'd4:  stream_byte = 8'h02;
            16'd5:  stream_byte = 8'h00;
            16'd6:  stream_byte = PACKET_BYTES[15:8];
            16'd7:  stream_byte = PACKET_BYTES[7:0];
            16'd8:  stream_byte = sequence[31:24];
            16'd9:  stream_byte = sequence[23:16];
            16'd10: stream_byte = sequence[15:8];
            16'd11: stream_byte = sequence[7:0];
            16'd12: stream_byte = DATA_BYTES[15:8];
            16'd13: stream_byte = DATA_BYTES[7:0];
            16'd14: stream_byte = start_value;
            16'd15: stream_byte = 8'h00;
            default: stream_byte = start_value + (index - HEADER_BYTES);
        endcase
    end
endfunction

always @(posedge clk) begin
    if (reset) begin
        tx_state          <= TX_IDLE;
        byte_index        <= 16'd0;
        gap_counter       <= 32'd0;
        payload_start     <= 8'd0;
        packet_sequence   <= 32'd0;
        packet_count      <= 32'd0;
        app_tx_data_vld   <= 1'b0;
        app_tx_data_last  <= 1'b0;
        app_tx_data       <= 8'd0;
        app_tx_length     <= PACKET_BYTES;
    end else begin
        app_tx_data_vld  <= 1'b0;
        app_tx_data_last <= 1'b0;

        case (tx_state)
            TX_IDLE: begin
                if (app_tx_ready) begin
                    byte_index      <= 16'd0;
                    app_tx_length   <= PACKET_BYTES;
                    tx_state        <= TX_SEND;
                end
            end

            TX_SEND: begin
                app_tx_data_vld  <= 1'b1;
                app_tx_data      <= stream_byte(byte_index, packet_sequence, payload_start);
                app_tx_data_last <= (byte_index == PACKET_BYTES - 1);

                if (byte_index == PACKET_BYTES - 1) begin
                    packet_sequence <= packet_sequence + 1'b1;
                    packet_count    <= packet_count + 1'b1;
                    payload_start   <= payload_start + DATA_BYTES;
                    gap_counter     <= 32'd0;
                    tx_state        <= TX_GAP;
                end else begin
                    byte_index <= byte_index + 1'b1;
                end
            end

            TX_GAP: begin
                if (gap_counter >= INTER_PACKET_GAP_CYCLES - 1) begin
                    tx_state <= TX_IDLE;
                end else begin
                    gap_counter <= gap_counter + 1'b1;
                end
            end

            default: tx_state <= TX_IDLE;
        endcase
    end
end

endmodule
