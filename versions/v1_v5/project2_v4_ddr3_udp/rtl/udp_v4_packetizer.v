// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : udp_v4_packetizer.v
// Module  : udp_v4_packetizer
// Created : 2026-08-02
// Revised : 2026-09-20
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// Buffers one 1024-byte ADMA read burst, prepends a 16-byte v4 header, and
// presents one 1040-byte UDP payload to the UDP stack.
module udp_v4_packetizer #(
    parameter integer DATA_BYTES = 1024,
    parameter integer TOTAL_PACKETS = 64
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        user_rd_valid,
    input  wire        user_rd_last,
    input  wire [7:0]  user_rd_data,
    output wire        buffer_available,
    output reg         packet_done,
    output reg  [15:0] packet_sequence,
    output reg         framing_error,
    output reg         app_tx_data_vld,
    output reg         app_tx_data_last,
    output reg  [7:0]  app_tx_data,
    output wire [15:0] app_tx_length,
    input  wire        app_tx_ready
);
    localparam integer HEADER_BYTES = 16;
    localparam integer PACKET_BYTES = HEADER_BYTES + DATA_BYTES;
    localparam [1:0] ST_COLLECT = 2'd0;
    localparam [1:0] ST_WAIT_TX = 2'd1;
    localparam [1:0] ST_SEND    = 2'd2;

    reg [1:0] state;
    reg [10:0] write_index;
    reg [10:0] tx_index;
    reg [7:0] data_mem [0:DATA_BYTES-1];

    assign app_tx_length = PACKET_BYTES;
    assign buffer_available = (state == ST_COLLECT) && (write_index == 0);

    function [7:0] header_byte;
        input [3:0] index;
        input [15:0] sequence;
        begin
            case (index)
                4'd0:  header_byte = "P";
                4'd1:  header_byte = "2";
                4'd2:  header_byte = "V";
                4'd3:  header_byte = "4";
                4'd4:  header_byte = 8'h04;
                4'd5:  header_byte = (sequence == TOTAL_PACKETS-1) ? 8'h01 : 8'h00;
                4'd6:  header_byte = PACKET_BYTES[15:8];
                4'd7:  header_byte = PACKET_BYTES[7:0];
                4'd8:  header_byte = 8'h00;
                4'd9:  header_byte = 8'h00;
                4'd10: header_byte = sequence[15:8];
                4'd11: header_byte = sequence[7:0];
                4'd12: header_byte = DATA_BYTES[15:8];
                4'd13: header_byte = DATA_BYTES[7:0];
                4'd14: header_byte = TOTAL_PACKETS[15:8];
                default: header_byte = TOTAL_PACKETS[7:0];
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            state            <= ST_COLLECT;
            write_index      <= 11'd0;
            tx_index         <= 11'd0;
            packet_done      <= 1'b0;
            packet_sequence  <= 16'd0;
            framing_error    <= 1'b0;
            app_tx_data_vld  <= 1'b0;
            app_tx_data_last <= 1'b0;
            app_tx_data      <= 8'd0;
        end else begin
            packet_done      <= 1'b0;
            app_tx_data_vld  <= 1'b0;
            app_tx_data_last <= 1'b0;

            case (state)
                ST_COLLECT: begin
                    if (user_rd_valid) begin
                        data_mem[write_index] <= user_rd_data;
                        if (user_rd_last != (write_index == DATA_BYTES-1))
                            framing_error <= 1'b1;
                        if (write_index == DATA_BYTES-1) begin
                            write_index <= 11'd0;
                            state <= ST_WAIT_TX;
                        end else begin
                            write_index <= write_index + 1'b1;
                        end
                    end
                end

                ST_WAIT_TX: begin
                    if (app_tx_ready) begin
                        tx_index <= 11'd0;
                        state <= ST_SEND;
                    end
                end

                ST_SEND: begin
                    app_tx_data_vld  <= 1'b1;
                    app_tx_data_last <= (tx_index == PACKET_BYTES-1);
                    if (tx_index < HEADER_BYTES)
                        app_tx_data <= header_byte(tx_index[3:0], packet_sequence);
                    else
                        app_tx_data <= data_mem[tx_index-HEADER_BYTES];

                    if (tx_index == PACKET_BYTES-1) begin
                        packet_done <= 1'b1;
                        packet_sequence <= packet_sequence + 1'b1;
                        state <= ST_COLLECT;
                    end else begin
                        tx_index <= tx_index + 1'b1;
                    end
                end

                default: state <= ST_COLLECT;
            endcase
        end
    end
endmodule
