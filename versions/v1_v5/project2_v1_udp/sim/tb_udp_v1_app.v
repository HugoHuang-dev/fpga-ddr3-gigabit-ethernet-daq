// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : tb_udp_v1_app.v
// Module  : tb_udp_v1_app
// Created : 2026-07-19
// Revised : 2026-09-19
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_udp_v1_app;

reg clk = 1'b0;
reg reset = 1'b1;
reg rx_vld = 1'b0;
reg rx_last = 1'b0;
reg [7:0] rx_data = 8'd0;
reg [15:0] rx_length = 16'd0;
wire tx_vld;
wire tx_last;
wire [7:0] tx_data;
wire [15:0] tx_length;
reg tx_ready = 1'b1;
wire [31:0] echo_count;
wire [31:0] beacon_count;
wire [31:0] drop_count;

integer echo_index = 0;
integer beacon_index = 0;
reg echo_done = 1'b0;
reg beacon_done = 1'b0;

always #5 clk = ~clk;

udp_v1_app #(
    .BEACON_INTERVAL_CYCLES(64)
) dut (
    .clk(clk),
    .reset(reset),
    .app_rx_data_vld(rx_vld),
    .app_rx_data_last(rx_last),
    .app_rx_data(rx_data),
    .app_rx_length(rx_length),
    .app_tx_data_vld(tx_vld),
    .app_tx_data_last(tx_last),
    .app_tx_data(tx_data),
    .app_tx_length(tx_length),
    .app_tx_ready(tx_ready),
    .echo_packet_count(echo_count),
    .beacon_packet_count(beacon_count),
    .rx_drop_count(drop_count)
);

function [7:0] expected_echo;
    input integer index;
    begin
        case (index)
            0: expected_echo = 8'hde;
            1: expected_echo = 8'had;
            2: expected_echo = 8'hbe;
            3: expected_echo = 8'hef;
            default: expected_echo = 8'h00;
        endcase
    end
endfunction

initial begin
    repeat (8) @(posedge clk);
    reset <= 1'b0;
    repeat (20) @(posedge clk);

    rx_length <= 16'd4;
    send_rx_byte(8'hde, 1'b0);
    send_rx_byte(8'had, 1'b0);
    send_rx_byte(8'hbe, 1'b0);
    send_rx_byte(8'hef, 1'b1);

    wait(echo_done);
    wait(beacon_done);
    repeat (5) @(posedge clk);

    if (echo_count !== 32'd1 || beacon_count < 32'd1 || drop_count !== 32'd0)
        $fatal(1, "counter mismatch: echo=%0d beacon=%0d drop=%0d", echo_count, beacon_count, drop_count);

    $display("PASS: UDP v1 app echo and fixed beacon verified");
    $finish;
end

task send_rx_byte;
    input [7:0] value;
    input last;
    begin
        @(posedge clk);
        rx_vld  <= 1'b1;
        rx_data <= value;
        rx_last <= last;
        @(posedge clk);
        rx_vld  <= 1'b0;
        rx_last <= 1'b0;
    end
endtask

always @(posedge clk) begin
    if (!reset && tx_vld && !echo_done) begin
        if (tx_length !== 16'd4)
            $fatal(1, "echo length mismatch: %0d", tx_length);
        if (tx_data !== expected_echo(echo_index))
            $fatal(1, "echo byte %0d mismatch: %02x", echo_index, tx_data);
        if (tx_last !== (echo_index == 3))
            $fatal(1, "echo last mismatch at byte %0d", echo_index);
        if (echo_index == 3)
            echo_done <= 1'b1;
        else
            echo_index <= echo_index + 1;
    end else if (!reset && tx_vld && echo_done && !beacon_done) begin
        if (tx_length !== 16'd32)
            $fatal(1, "beacon length mismatch: %0d", tx_length);
        if (tx_last !== (beacon_index == 31))
            $fatal(1, "beacon last mismatch at byte %0d", beacon_index);
        if (beacon_index == 31)
            beacon_done <= 1'b1;
        else
            beacon_index <= beacon_index + 1;
    end
end

initial begin
    #100000;
    $fatal(1, "simulation timeout");
end

endmodule
