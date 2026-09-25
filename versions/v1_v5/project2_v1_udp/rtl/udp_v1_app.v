// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : udp_v1_app.v
// Module  : udp_v1_app
// Created : 2026-07-19
// Revised : 2026-09-19
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// Project2 v1 application layer.
//
// 1. Buffers one received UDP payload and sends it back unchanged.
// 2. When idle, sends a fixed 32-byte beacon once per second.
//
// The Ethernet stack supplies the UDP/IP/MAC/ARP/ICMP logic.
module udp_v1_app #(
    parameter integer BEACON_INTERVAL_CYCLES = 125_000_000
)(
    input  wire        clk,
    input  wire        reset,

    input  wire        app_rx_data_vld,
    input  wire        app_rx_data_last,
    input  wire [7:0]  app_rx_data,
    input  wire [15:0] app_rx_length,

    output reg         app_tx_data_vld,
    output reg         app_tx_data_last,
    output reg  [7:0]  app_tx_data,
    output reg  [15:0] app_tx_length,
    input  wire        app_tx_ready,

    output reg  [31:0] echo_packet_count,
    output reg  [31:0] beacon_packet_count,
    output reg  [31:0] rx_drop_count
);

localparam [1:0] TX_IDLE   = 2'd0;
localparam [1:0] TX_ECHO   = 2'd1;
localparam [1:0] TX_BEACON = 2'd2;
localparam integer BEACON_LENGTH = 32;

reg [1:0]  tx_state;
reg [15:0] echo_length;
reg        echo_pending;
reg [5:0]  beacon_index;
reg [27:0] beacon_timer;

wire [8:0] echo_fifo_dout;
wire       echo_fifo_full;
wire       echo_fifo_empty;
wire [11:0] echo_fifo_count;

wire echo_fifo_wr_en = app_rx_data_vld && !echo_fifo_full && !echo_pending;
wire echo_fifo_rd_en = (tx_state == TX_ECHO) && !echo_fifo_empty;

fifo_w9xd2048 u_echo_fifo (
    .clk        (clk),
    .srst       (reset),
    .din        ({app_rx_data_last, app_rx_data}),
    .wr_en      (echo_fifo_wr_en),
    .rd_en      (echo_fifo_rd_en),
    .dout       (echo_fifo_dout),
    .full       (echo_fifo_full),
    .empty      (echo_fifo_empty),
    .data_count (echo_fifo_count)
);

function [7:0] beacon_byte;
    input [5:0] index;
    begin
        case (index)
            6'd0:  beacon_byte = "F";
            6'd1:  beacon_byte = "P";
            6'd2:  beacon_byte = "G";
            6'd3:  beacon_byte = "A";
            6'd4:  beacon_byte = "-";
            6'd5:  beacon_byte = "U";
            6'd6:  beacon_byte = "D";
            6'd7:  beacon_byte = "P";
            6'd8:  beacon_byte = "-";
            6'd9:  beacon_byte = "V";
            6'd10: beacon_byte = "1";
            6'd11: beacon_byte = "-";
            6'd12: beacon_byte = "B";
            6'd13: beacon_byte = "E";
            6'd14: beacon_byte = "A";
            6'd15: beacon_byte = "C";
            6'd16: beacon_byte = "O";
            6'd17: beacon_byte = "N";
            6'd18: beacon_byte = "-";
            6'd19: beacon_byte = "0";
            6'd20: beacon_byte = "1";
            6'd21: beacon_byte = "2";
            6'd22: beacon_byte = "3";
            6'd23: beacon_byte = "4";
            6'd24: beacon_byte = "5";
            6'd25: beacon_byte = "6";
            6'd26: beacon_byte = "7";
            6'd27: beacon_byte = "8";
            6'd28: beacon_byte = "9";
            6'd29: beacon_byte = "A";
            6'd30: beacon_byte = "B";
            6'd31: beacon_byte = "C";
            default: beacon_byte = 8'h00;
        endcase
    end
endfunction

always @(posedge clk) begin
    if (reset) begin
        echo_pending <= 1'b0;
        echo_length  <= 16'd0;
        rx_drop_count <= 32'd0;
    end else begin
        if (app_rx_data_vld && (echo_fifo_full || echo_pending))
            rx_drop_count <= rx_drop_count + 1'b1;

        if (app_rx_data_vld && app_rx_data_last && !echo_fifo_full && !echo_pending) begin
            echo_pending <= 1'b1;
            echo_length  <= app_rx_length;
        end else if ((tx_state == TX_ECHO) && !echo_fifo_empty && echo_fifo_dout[8]) begin
            echo_pending <= 1'b0;
        end
    end
end

always @(posedge clk) begin
    if (reset) begin
        beacon_timer <= 28'd0;
    end else if (tx_state == TX_BEACON) begin
        beacon_timer <= 28'd0;
    end else if (beacon_timer < BEACON_INTERVAL_CYCLES - 1) begin
        beacon_timer <= beacon_timer + 1'b1;
    end
end

always @(posedge clk) begin
    if (reset) begin
        tx_state            <= TX_IDLE;
        beacon_index        <= 6'd0;
        app_tx_data_vld     <= 1'b0;
        app_tx_data_last    <= 1'b0;
        app_tx_data         <= 8'd0;
        app_tx_length       <= 16'd0;
        echo_packet_count   <= 32'd0;
        beacon_packet_count <= 32'd0;
    end else begin
        app_tx_data_vld  <= 1'b0;
        app_tx_data_last <= 1'b0;

        case (tx_state)
            TX_IDLE: begin
                if (echo_pending && !echo_fifo_empty && app_tx_ready) begin
                    app_tx_length <= echo_length;
                    tx_state      <= TX_ECHO;
                end else if ((beacon_timer == BEACON_INTERVAL_CYCLES - 1) && app_tx_ready) begin
                    app_tx_length <= BEACON_LENGTH;
                    beacon_index  <= 6'd0;
                    tx_state      <= TX_BEACON;
                end
            end

            TX_ECHO: begin
                if (!echo_fifo_empty) begin
                    app_tx_data_vld  <= 1'b1;
                    app_tx_data      <= echo_fifo_dout[7:0];
                    app_tx_data_last <= echo_fifo_dout[8];
                    if (echo_fifo_dout[8]) begin
                        echo_packet_count <= echo_packet_count + 1'b1;
                        tx_state          <= TX_IDLE;
                    end
                end
            end

            TX_BEACON: begin
                app_tx_data_vld  <= 1'b1;
                app_tx_data      <= beacon_byte(beacon_index);
                app_tx_data_last <= (beacon_index == BEACON_LENGTH - 1);
                if (beacon_index == BEACON_LENGTH - 1) begin
                    beacon_packet_count <= beacon_packet_count + 1'b1;
                    tx_state            <= TX_IDLE;
                end else begin
                    beacon_index <= beacon_index + 1'b1;
                end
            end

            default: tx_state <= TX_IDLE;
        endcase
    end
end

endmodule
