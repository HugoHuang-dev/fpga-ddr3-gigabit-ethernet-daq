// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : tb_udp_v2_stream_source.v
// Module  : tb_udp_v2_stream_source
// Created : 2026-07-22
// Revised : 2026-09-19
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_udp_v2_stream_source;

reg clk = 1'b0;
reg reset = 1'b1;
reg tx_ready = 1'b1;
wire tx_vld;
wire tx_last;
wire [7:0] tx_data;
wire [15:0] tx_length;
wire [31:0] sequence;
wire [31:0] packet_count;

integer byte_index = 0;
integer received_packets = 0;

always #4 clk = ~clk;

udp_v2_stream_source #(
    .PACKET_BYTES(32),
    .INTER_PACKET_GAP_CYCLES(4)
) dut (
    .clk(clk),
    .reset(reset),
    .app_tx_data_vld(tx_vld),
    .app_tx_data_last(tx_last),
    .app_tx_data(tx_data),
    .app_tx_length(tx_length),
    .app_tx_ready(tx_ready),
    .packet_sequence(sequence),
    .packet_count(packet_count)
);

function [7:0] expected_byte;
    input integer packet_number;
    input integer index;
    integer start_value;
    begin
        start_value = packet_number * 16;
        case (index)
            0: expected_byte = "P";
            1: expected_byte = "2";
            2: expected_byte = "V";
            3: expected_byte = "2";
            4: expected_byte = 8'h02;
            5: expected_byte = 8'h00;
            6: expected_byte = 8'h00;
            7: expected_byte = 8'h20;
            8: expected_byte = 8'h00;
            9: expected_byte = 8'h00;
            10: expected_byte = 8'h00;
            11: expected_byte = packet_number[7:0];
            12: expected_byte = 8'h00;
            13: expected_byte = 8'h10;
            14: expected_byte = start_value[7:0];
            15: expected_byte = 8'h00;
            default: expected_byte = start_value + index - 16;
        endcase
    end
endfunction

initial begin
    // Keep the test in reset beyond Vivado's automatic 1000 ns preview run;
    // run_sim.tcl then restarts and executes one complete self-check.
    repeat (160) @(posedge clk);
    reset <= 1'b0;
    wait (received_packets == 3);
    repeat (5) @(posedge clk);

    if (packet_count !== 32'd3 || sequence !== 32'd3)
        $fatal(1, "counter mismatch: count=%0d sequence=%0d", packet_count, sequence);

    $display("PASS: UDP v2 sequence and continuous incrementing payload verified");
    $finish;
end

always @(posedge clk) begin
    if (!reset && tx_vld) begin
        if (tx_length !== 16'd32)
            $fatal(1, "packet length mismatch: %0d", tx_length);
        if (tx_data !== expected_byte(received_packets, byte_index))
            $fatal(1, "packet %0d byte %0d mismatch: got=%02x expected=%02x",
                received_packets, byte_index, tx_data,
                expected_byte(received_packets, byte_index));
        if (tx_last !== (byte_index == 31))
            $fatal(1, "last mismatch: packet=%0d byte=%0d", received_packets, byte_index);

        if (byte_index == 31) begin
            byte_index = 0;
            received_packets = received_packets + 1;
        end else begin
            byte_index = byte_index + 1;
        end
    end
end

initial begin
    #100000;
    $fatal(1, "simulation timeout");
end

endmodule
