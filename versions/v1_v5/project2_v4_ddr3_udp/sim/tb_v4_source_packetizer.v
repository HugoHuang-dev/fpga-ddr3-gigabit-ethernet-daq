// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : tb_v4_source_packetizer.v
// Module  : tb_v4_source_packetizer
// Created : 2026-08-02
// Revised : 2026-09-20
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_v4_source_packetizer;
    localparam DATA_BYTES = 16;
    localparam TOTAL_PACKETS = 2;
    reg clk = 0;
    reg reset = 1;
    reg calib = 0;
    reg start = 0;
    always #5 clk = ~clk;

    wire wr_en;
    wire [15:0] wr_data;
    wire [31:0] word_count;
    wire source_done;
    reg rd_valid = 0;
    reg rd_last = 0;
    reg [7:0] rd_data = 0;
    wire buffer_available;
    wire packet_done;
    wire [15:0] packet_sequence;
    wire framing_error;
    wire tx_valid, tx_last;
    wire [7:0] tx_data;
    wire [15:0] tx_length;
    reg [15:0] source_words [0:15];
    reg [7:0] expected_stream [0:31];
    integer source_index = 0;
    integer feed_index = 0;
    integer tx_byte_index = 0;
    integer packet_index = 0;
    integer errors = 0;
    integer i;

    function [15:0] prbs_next;
        input [15:0] value;
        begin
            prbs_next = {value[14:0], value[15] ^ value[13] ^ value[12] ^ value[10]};
        end
    endfunction

    prbs16_finite_source #(
        .TOTAL_WORDS(16), .START_DELAY_CYCLES(4), .PRBS_SEED(16'hACE1)
    ) source (
        .clk(clk), .reset(reset), .init_calib_complete(calib), .start(start),
        .user_wr_en(wr_en), .user_wr_data(wr_data),
        .word_count(word_count), .source_done(source_done)
    );

    udp_v4_packetizer #(.DATA_BYTES(DATA_BYTES), .TOTAL_PACKETS(TOTAL_PACKETS)) packetizer (
        .clk(clk), .reset(reset), .user_rd_valid(rd_valid), .user_rd_last(rd_last),
        .user_rd_data(rd_data), .buffer_available(buffer_available),
        .packet_done(packet_done), .packet_sequence(packet_sequence),
        .framing_error(framing_error), .app_tx_data_vld(tx_valid),
        .app_tx_data_last(tx_last), .app_tx_data(tx_data),
        .app_tx_length(tx_length), .app_tx_ready(1'b1)
    );

    always @(posedge clk) begin
        if (wr_en) begin
            source_words[source_index] <= wr_data;
            expected_stream[source_index*2] <= wr_data[7:0];
            expected_stream[source_index*2+1] <= wr_data[15:8];
            source_index <= source_index + 1;
        end
    end

    task feed_packet;
        input integer packet_number;
        integer k;
        begin
            wait(buffer_available);
            for (k = 0; k < DATA_BYTES; k = k + 1) begin
                @(negedge clk);
                rd_valid = 1;
                rd_data = expected_stream[packet_number*DATA_BYTES+k];
                rd_last = (k == DATA_BYTES-1);
                @(negedge clk);
                rd_valid = 0;
                rd_last = 0;
            end
            wait(packet_done);
        end
    endtask

    always @(posedge clk) begin
        if (tx_valid) begin
            if (tx_length != DATA_BYTES + 16)
                errors <= errors + 1;
            if (tx_byte_index < 16) begin
                case (tx_byte_index)
                    0: if (tx_data != "P") errors <= errors + 1;
                    1: if (tx_data != "2") errors <= errors + 1;
                    2: if (tx_data != "V") errors <= errors + 1;
                    3: if (tx_data != "4") errors <= errors + 1;
                    4: if (tx_data != 8'h04) errors <= errors + 1;
                    11: if (tx_data != packet_index) errors <= errors + 1;
                    13: if (tx_data != DATA_BYTES) errors <= errors + 1;
                    15: if (tx_data != TOTAL_PACKETS) errors <= errors + 1;
                endcase
            end else if (tx_data != expected_stream[packet_index*DATA_BYTES+tx_byte_index-16]) begin
                errors <= errors + 1;
            end

            if (tx_last) begin
                if (tx_byte_index != DATA_BYTES+15)
                    errors <= errors + 1;
                tx_byte_index <= 0;
                packet_index <= packet_index + 1;
            end else begin
                tx_byte_index <= tx_byte_index + 1;
            end
        end
    end

    initial begin
        repeat(5) @(posedge clk);
        reset <= 0;
        repeat(3) @(posedge clk);
        calib <= 1;
        repeat(3) @(posedge clk);
        if (wr_en) $fatal(1, "source started before explicit start");
        start <= 1;
        wait(source_done);
        repeat(2) @(posedge clk);
        if (source_index != 16 || word_count != 16) $fatal(1, "source count mismatch");
        feed_packet(0);
        feed_packet(1);
        repeat(5) @(posedge clk);
        if (framing_error || errors != 0 || packet_index != 2)
            $fatal(1, "V4 custom logic failed errors=%0d packets=%0d framing=%0d", errors, packet_index, framing_error);
        $display("V4 SOURCE/PACKETIZER SIM PASSED: words=%0d packets=%0d errors=%0d", source_index, packet_index, errors);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "V4 simulation timeout");
    end
endmodule
