// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : tb_v9_packetizer.v
// Module  : tb_v9_packetizer
// Created : 2026-09-14
// Revised : 2026-09-23
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// V9 self-checking regression for the real udp_v9_tx_fifo_packetizer RTL.
module tb_v9_packetizer;
    localparam integer BURST_BYTES = 1024;
    localparam integer HEADER_BYTES = 32;
    localparam integer PAYLOAD_BYTES = 256;
    reg clk = 0;
    always #5 clk = ~clk;

    reg reset = 1, clear_counters = 0;
    reg [15:0] configured_payload_bytes = PAYLOAD_BYTES;
    reg [7:0] source_id = 1;
    reg user_rd_valid = 0, user_rd_last = 0;
    reg [7:0] user_rd_data = 0;
    reg [31:0] committed_bytes_low = 32'h11223344;
    reg [31:0] occupancy_bytes = 32'h55667788;
    reg stream_expected = 0;
    wire burst_space_available, burst_committed, packet_done;
    wire [31:0] packet_sequence;
    wire [63:0] first_word_index;
    wire framing_error;
    wire [13:0] fifo_byte_count;
    wire [3:0] fifo_packet_count;
    wire [31:0] overflow_count, underflow_count;
    wire app_tx_data_vld, app_tx_data_last;
    wire [7:0] app_tx_data;
    wire [15:0] app_tx_length;
    reg app_tx_ready = 0;

    integer errors = 0;
    integer i;
    integer packets = 0;
    integer wire_index = 0;
    integer payload_index = 0;
    integer burst_commit_pulses = 0;
    reg [7:0] expected_header;
    reg [63:0] expected_word_index;

    udp_v9_tx_fifo_packetizer #(
        .BURST_BYTES(BURST_BYTES), .FIFO_BURSTS(2),
        .POST_READY_IDLE_CYCLES(2)
    ) dut (
        .clk(clk), .reset(reset), .clear_counters(clear_counters),
        .configured_payload_bytes(configured_payload_bytes), .source_id(source_id),
        .user_rd_valid(user_rd_valid), .user_rd_last(user_rd_last),
        .user_rd_data(user_rd_data), .committed_bytes_low(committed_bytes_low),
        .occupancy_bytes(occupancy_bytes), .stream_expected(stream_expected),
        .burst_space_available(burst_space_available), .burst_committed(burst_committed),
        .packet_done(packet_done), .packet_sequence(packet_sequence),
        .first_word_index(first_word_index), .framing_error(framing_error),
        .fifo_byte_count(fifo_byte_count), .fifo_packet_count(fifo_packet_count),
        .overflow_count(overflow_count), .underflow_count(underflow_count),
        .app_tx_data_vld(app_tx_data_vld), .app_tx_data_last(app_tx_data_last),
        .app_tx_data(app_tx_data), .app_tx_length(app_tx_length),
        .app_tx_ready(app_tx_ready)
    );

    task tick;
        begin @(posedge clk); #1; end
    endtask

    task check;
        input condition;
        input [8*100-1:0] what;
        begin
            if (!condition) begin
                $display("FAIL packetizer: %0s at %0t", what, $time);
                errors = errors + 1;
            end
        end
    endtask

    task pulse_clear;
        begin
            clear_counters = 1;
            tick;
            clear_counters = 0;
            tick;
        end
    endtask

    task drive_byte;
        input [7:0] value;
        input is_last;
        begin
            @(negedge clk);
            user_rd_valid = 1;
            user_rd_data = value;
            user_rd_last = is_last;
            tick;
            if (burst_committed)
                burst_commit_pulses = burst_commit_pulses + 1;
        end
    endtask

    function [7:0] header_expected;
        input integer index;
        input integer packet_no;
        reg [31:0] seq;
        reg [63:0] word_idx;
        begin
            seq = packet_no;
            word_idx = packet_no * (PAYLOAD_BYTES/2);
            case (index)
                0: header_expected = "P";
                1: header_expected = "2";
                2: header_expected = "V";
                3: header_expected = "9";
                4: header_expected = 8'h09;
                5: header_expected = 8'h01;
                6: header_expected = 8'h01;
                7: header_expected = 8'h20;
                8: header_expected = seq[31:24];
                9: header_expected = seq[23:16];
                10: header_expected = seq[15:8];
                11: header_expected = seq[7:0];
                12: header_expected = 8'h01;
                13: header_expected = 8'h00;
                14: header_expected = 8'h00;
                15: header_expected = 8'h20;
                16: header_expected = 8'h11;
                17: header_expected = 8'h22;
                18: header_expected = 8'h33;
                19: header_expected = 8'h44;
                20: header_expected = 8'h55;
                21: header_expected = 8'h66;
                22: header_expected = 8'h77;
                23: header_expected = 8'h88;
                24: header_expected = word_idx[63:56];
                25: header_expected = word_idx[55:48];
                26: header_expected = word_idx[47:40];
                27: header_expected = word_idx[39:32];
                28: header_expected = word_idx[31:24];
                29: header_expected = word_idx[23:16];
                30: header_expected = word_idx[15:8];
                default: header_expected = word_idx[7:0];
            endcase
        end
    endfunction

    task check_output_byte;
        begin
            check(app_tx_length == HEADER_BYTES + PAYLOAD_BYTES, "wire length/header size");
            if (wire_index < HEADER_BYTES) begin
                expected_header = header_expected(wire_index, packets);
                check(app_tx_data === expected_header, "32-byte P2V9 header field");
            end else begin
                check(app_tx_data === payload_index[7:0], "payload byte-for-byte comparison");
                payload_index = payload_index + 1;
            end
            check(app_tx_data_last == (wire_index == HEADER_BYTES + PAYLOAD_BYTES - 1),
                  "last only on exact packet boundary");
            if (app_tx_data_last) begin
                check(packet_done, "packet_done accompanies last byte");
                packets = packets + 1;
                wire_index = 0;
                check(packet_sequence == packets, "packet sequence increments exactly once");
                expected_word_index = packets * (PAYLOAD_BYTES/2);
                check(first_word_index == expected_word_index,
                      "64-bit first-sample/word index increments per payload");
            end else begin
                wire_index = wire_index + 1;
            end
        end
    endtask

    initial begin
        repeat (4) tick;
        reset = 0;
        tick;
        check(packet_sequence == 0 && first_word_index == 0, "reset sequence/index");
        check(fifo_byte_count == 0 && fifo_packet_count == 0, "reset FIFO accounting");

        // Queue one complete DDR burst while the downstream packet interface
        // is not ready. This is the packet-boundary backpressure contract used
        // by the real UDP stack: no byte may be emitted or consumed yet.
        for (i = 0; i < BURST_BYTES; i = i + 1)
            drive_byte(i[7:0], i == BURST_BYTES-1);
        @(negedge clk);
        user_rd_valid = 0;
        user_rd_last = 0;
        repeat (5) begin
            tick;
            check(!app_tx_data_vld, "ready-low holds packet launch");
            check(fifo_byte_count == BURST_BYTES && fifo_packet_count == 1,
                  "ready-low preserves queued burst");
            check(packet_sequence == 0 && first_word_index == 0,
                  "ready-low preserves sequence/index");
        end
        check(burst_commit_pulses == 1, "one burst_committed pulse per complete DDR burst");

        // Let each packet complete, then deliberately hold ready low between
        // packets. The state, payload pointer, and counters must stay stable.
        app_tx_ready = 1;
        while (packets < 4) begin
            tick;
            if (app_tx_data_vld) begin
                check_output_byte;
                if (app_tx_data_last) begin
                    app_tx_ready = 0;
                    repeat (3) begin
                        tick;
                        check(!app_tx_data_vld, "inter-packet ready-low suppresses output");
                        check(packet_sequence == packets, "inter-packet sequence stable");
                        check(first_word_index == packets*(PAYLOAD_BYTES/2),
                              "inter-packet word index stable");
                    end
                    app_tx_ready = 1;
                end
            end
        end
        repeat (8) tick;
        check(payload_index == BURST_BYTES, "all payload bytes consumed exactly once");
        check(fifo_byte_count == 0 && fifo_packet_count == 0, "FIFO empty after four packets");
        check(!framing_error && overflow_count == 0, "nominal framing/overflow clean");

        // With a stream expected and an empty queue, starvation increments
        // once for the whole idle interval rather than once per clock.
        stream_expected = 1;
        app_tx_ready = 1;
        repeat (8) tick;
        check(underflow_count == 1, "starvation underflow is interval-latched");
        repeat (5) tick;
        check(underflow_count == 1, "starvation does not chatter");
        stream_expected = 0;

        // Early user_rd_last must be rejected as a framing violation.
        pulse_clear;
        burst_commit_pulses = 0;
        for (i = 0; i < 17; i = i + 1)
            drive_byte(i[7:0], i == 16);
        @(negedge clk); user_rd_valid = 0; user_rd_last = 0;
        tick;
        check(framing_error, "early-last anomaly injection");
        check(burst_commit_pulses == 1, "early last still exposes bad-burst completion for diagnostics");

        // Missing the correct last followed by a late last is also detected.
        pulse_clear;
        for (i = 0; i < BURST_BYTES; i = i + 1)
            drive_byte(i[7:0], 1'b0);
        drive_byte(8'hAA, 1'b1);
        @(negedge clk); user_rd_valid = 0; user_rd_last = 0;
        tick;
        check(framing_error, "late-last anomaly injection");

        // Fill both FIFO bursts with output blocked, then violate
        // burst_space_available with one additional byte.
        pulse_clear;
        app_tx_ready = 0;
        for (i = 0; i < 2*BURST_BYTES; i = i + 1)
            drive_byte(i[7:0], (i == BURST_BYTES-1) || (i == 2*BURST_BYTES-1));
        check(!burst_space_available && fifo_byte_count == 2*BURST_BYTES,
              "FIFO full/backpressure assertion");
        drive_byte(8'hEE, 1'b0);
        @(negedge clk); user_rd_valid = 0; user_rd_last = 0;
        tick;
        check(overflow_count == 1 && framing_error, "full-FIFO overflow anomaly injection");
        check(fifo_byte_count == 2*BURST_BYTES, "overflow byte not accepted");

        pulse_clear;
        check(packet_sequence == 0 && first_word_index == 0 &&
              !framing_error && overflow_count == 0 && underflow_count == 0 &&
              fifo_byte_count == 0 && fifo_packet_count == 0,
              "clear restores packetizer diagnostics and FIFO state");

        if (errors == 0)
            $display("PASS tb_v9_packetizer: P2V9 header/payload/sequence/64-bit index/backpressure/anomalies");
        else
            $display("FAIL tb_v9_packetizer: %0d checks failed", errors);
        $finish;
    end
endmodule
