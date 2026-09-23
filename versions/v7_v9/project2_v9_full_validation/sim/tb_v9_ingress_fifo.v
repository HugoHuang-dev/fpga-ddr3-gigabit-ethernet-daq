// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : tb_v9_ingress_fifo.v
// Module  : tb_v9_ingress_fifo
// Created : 2026-09-14
// Revised : 2026-09-23
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// V9 self-checking regression for the real v6_ingress_fifo RTL.
module tb_v9_ingress_fifo;
    localparam integer DEPTH = 8;
    reg clk = 0;
    always #5 clk = ~clk;

    reg reset = 1;
    reg clear_counters = 0;
    reg flush = 0;
    reg enable = 0;
    reg in_valid = 0;
    reg [15:0] in_data = 0;
    wire in_ready;
    reg out_ready = 0;
    wire out_valid;
    wire [15:0] out_data;
    wire [$clog2(DEPTH+1)-1:0] level_words;
    wire has_burst, high_water, low_water, source_run;
    wire [31:0] overflow_count, underflow_count;

    integer errors = 0;
    integer i;

    v6_ingress_fifo #(
        .DEPTH_WORDS(DEPTH),
        .HIGH_WATER_WORDS(DEPTH),
        .LOW_WATER_WORDS(2),
        .BURST_WORDS(4)
    ) dut (
        .clk(clk), .reset(reset), .clear_counters(clear_counters),
        .flush(flush), .enable(enable), .in_valid(in_valid), .in_data(in_data),
        .in_ready(in_ready), .out_ready(out_ready), .out_valid(out_valid),
        .out_data(out_data), .level_words(level_words), .has_burst(has_burst),
        .high_water(high_water), .low_water(low_water), .source_run(source_run),
        .overflow_count(overflow_count), .underflow_count(underflow_count)
    );

    task check;
        input condition;
        input [8*80-1:0] what;
        begin
            if (!condition) begin
                $display("FAIL fifo: %0s at %0t", what, $time);
                errors = errors + 1;
            end
        end
    endtask

    task tick;
        begin @(posedge clk); #1; end
    endtask

    task push_word;
        input [15:0] value;
        begin
            in_data = value;
            in_valid = 1;
            tick;
            in_valid = 0;
        end
    endtask

    task pop_expect;
        input [15:0] value;
        begin
            check(out_valid, "out_valid before pop");
            check(out_data === value, "FIFO ordering/data");
            out_ready = 1;
            tick;
            out_ready = 0;
        end
    endtask

    initial begin
        repeat (3) tick;
        reset = 0;
        tick;
        check(level_words == 0 && !out_valid && low_water, "reset/empty/low-water state");
        check(!source_run && !in_ready, "disabled source is backpressured");

        enable = 1;
        tick;
        check(source_run && in_ready, "enable starts source below low-water");

        // Fill to the exact full boundary and verify water marks.
        for (i = 0; i < DEPTH; i = i + 1) begin
            push_word(16'h1000 + i);
            check(level_words == i + 1, "level increments on accepted push");
            if (i == 3) check(has_burst, "burst threshold asserts");
        end
        check(high_water && level_words == DEPTH && !in_ready, "full/high-water backpressure");
        tick;
        check(!source_run, "hysteretic source gate stops at high-water");

        // A producer violating in_ready is counted exactly once per cycle.
        in_valid = 1;
        in_data = 16'hDEAD;
        repeat (3) tick;
        in_valid = 0;
        check(overflow_count == 3, "backpressure violation/overflow counter");
        check(level_words == DEPTH, "rejected writes do not alter occupancy");

        // Drain in order to the low-water threshold. The source restarts only
        // after the registered hysteresis decision.
        for (i = 0; i < 6; i = i + 1)
            pop_expect(16'h1000 + i);
        check(level_words == 2 && low_water && !source_run, "low-water boundary reached");
        tick;
        check(source_run && in_ready, "source restarts below low-water");

        // Simultaneous push/pop preserves the level and ordering.
        check(out_data == 16'h1006, "pre simultaneous-transfer head");
        in_valid = 1;
        in_data = 16'h2000;
        out_ready = 1;
        tick;
        in_valid = 0;
        out_ready = 0;
        check(level_words == 2, "simultaneous push/pop keeps level stable");
        pop_expect(16'h1007);
        pop_expect(16'h2000);
        check(level_words == 0 && !out_valid, "drain reaches empty");

        // Empty read attempts are counted, then clear_counters resets only the
        // diagnostics without disturbing the FIFO state.
        out_ready = 1;
        repeat (2) tick;
        out_ready = 0;
        check(underflow_count == 2, "empty-read underflow counter");
        clear_counters = 1;
        tick;
        clear_counters = 0;
        check(overflow_count == 0 && underflow_count == 0, "diagnostic clear");

        // Flush discards queued words and realigns the read pointer to the
        // write pointer; the next accepted word must be the next output.
        push_word(16'h3000);
        push_word(16'h3001);
        push_word(16'h3002);
        check(level_words == 3, "pre-flush occupancy");
        flush = 1;
        tick;
        flush = 0;
        check(level_words == 0 && !out_valid, "flush empties FIFO");
        push_word(16'h4000);
        pop_expect(16'h4000);
        check(level_words == 0, "post-flush pointer alignment");

        enable = 0;
        tick;
        check(!source_run && !in_ready, "disable applies backpressure");

        if (errors == 0)
            $display("PASS tb_v9_ingress_fifo: full/empty/watermarks/backpressure/flush/order/counters");
        else
            $display("FAIL tb_v9_ingress_fifo: %0d checks failed", errors);
        $finish;
    end
endmodule
