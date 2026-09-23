// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : tb_v9_pipeline_controller.v
// Module  : tb_v9_pipeline_controller
// Created : 2026-09-14
// Revised : 2026-09-23
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// V9 self-checking regression for the real v6_pipeline_controller RTL.
module tb_v9_pipeline_controller;
    localparam [31:0] BASE = 32'h00001000;
    localparam integer BURST = 1024;
    reg clk = 0;
    always #5 clk = ~clk;

    reg reset = 1, start_async = 0, clear_counters = 0;
    reg init_calib_complete = 0, ingress_has_burst_async = 0;
    reg axi_bvalid = 0, axi_bready = 0;
    reg [1:0] axi_bresp = 0;
    reg user_rd_req_busy = 0, tx_burst_committed = 0;
    reg tx_burst_space_available = 0, packetizer_error = 0;
    reg wr_cmd_fifo_err = 0, wr_data_fifo_err = 0;
    reg rd_cmd_fifo_err = 0, rd_data_fifo_err = 0;
    wire write_grant_toggle, user_rd_req, started;
    wire write_inflight, read_inflight, drain_active;
    wire [31:0] write_pointer, read_pointer;
    wire [63:0] committed_bytes, released_bytes;
    wire [31:0] occupancy_bytes;
    wire ring_full, ring_empty;
    wire [31:0] write_stall_cycles, read_stall_cycles;
    wire [31:0] ring_overflow_count, ring_underflow_count;
    wire fatal_error;

    integer errors = 0;
    integer i;
    reg old_toggle;

    v6_pipeline_controller #(
        .BASE_ADDR(BASE), .RING_BYTES(4096), .BURST_BYTES(BURST),
        .DDR_HIGH_WATER_BYTES(3072), .DDR_LOW_WATER_BYTES(1024)
    ) dut (
        .clk(clk), .reset(reset), .start_async(start_async),
        .clear_counters(clear_counters), .init_calib_complete(init_calib_complete),
        .ingress_has_burst_async(ingress_has_burst_async),
        .axi_bvalid(axi_bvalid), .axi_bready(axi_bready), .axi_bresp(axi_bresp),
        .user_rd_req_busy(user_rd_req_busy), .tx_burst_committed(tx_burst_committed),
        .tx_burst_space_available(tx_burst_space_available),
        .packetizer_error(packetizer_error), .wr_cmd_fifo_err(wr_cmd_fifo_err),
        .wr_data_fifo_err(wr_data_fifo_err), .rd_cmd_fifo_err(rd_cmd_fifo_err),
        .rd_data_fifo_err(rd_data_fifo_err), .write_grant_toggle(write_grant_toggle),
        .user_rd_req(user_rd_req), .started(started), .write_inflight(write_inflight),
        .read_inflight(read_inflight), .drain_active(drain_active),
        .write_pointer(write_pointer), .read_pointer(read_pointer),
        .committed_bytes(committed_bytes), .released_bytes(released_bytes),
        .occupancy_bytes(occupancy_bytes), .ring_full(ring_full), .ring_empty(ring_empty),
        .write_stall_cycles(write_stall_cycles), .read_stall_cycles(read_stall_cycles),
        .ring_overflow_count(ring_overflow_count),
        .ring_underflow_count(ring_underflow_count), .fatal_error(fatal_error)
    );

    task tick;
        begin @(posedge clk); #1; end
    endtask

    task check;
        input condition;
        input [8*96-1:0] what;
        begin
            if (!condition) begin
                $display("FAIL pipeline: %0s at %0t", what, $time);
                errors = errors + 1;
            end
        end
    endtask

    task wait_write_grant;
        integer timeout;
        begin
            timeout = 0;
            while (!write_inflight && timeout < 20) begin tick; timeout = timeout + 1; end
            check(write_inflight, "write grant/inflight timeout");
        end
    endtask

    task commit_write_ok;
        begin
            wait_write_grant;
            axi_bresp = 0;
            axi_bvalid = 1;
            axi_bready = 1;
            tick;
            axi_bvalid = 0;
            axi_bready = 0;
        end
    endtask

    task wait_read_grant;
        integer timeout;
        begin
            timeout = 0;
            while (!read_inflight && timeout < 20) begin tick; timeout = timeout + 1; end
            check(read_inflight, "read grant/inflight timeout");
        end
    endtask

    task release_read;
        begin
            wait_read_grant;
            tx_burst_committed = 1;
            tick;
            tx_burst_committed = 0;
        end
    endtask

    task pulse_clear;
        begin clear_counters = 1; tick; clear_counters = 0; end
    endtask

    initial begin
        repeat (3) tick;
        reset = 0;
        tick;
        check(ring_empty && occupancy_bytes == 0, "reset ring empty");
        check(write_pointer == BASE && read_pointer == BASE, "reset pointers");
        check(!started && !fatal_error, "reset control state");

        start_async = 1;
        init_calib_complete = 1;
        ingress_has_burst_async = 1;
        repeat (4) tick;
        check(started, "synchronized start after calibration");
        check(write_inflight, "first write grant");

        // Four good AXI completions fill every ring slot. Both the write
        // pointer and accounting totals are checked at every commit.
        for (i = 1; i <= 4; i = i + 1) begin
            old_toggle = write_grant_toggle;
            commit_write_ok;
            check(committed_bytes == i*BURST, "committed byte accounting");
            check(occupancy_bytes == i*BURST, "ring occupancy increments");
            if (i < 4)
                check(write_pointer == BASE + i*BURST, "write pointer advances");
            else
                check(write_pointer == BASE, "write pointer wraps at ring end");
        end
        check(ring_full, "ring full assertion");
        repeat (3) tick;
        check(write_stall_cycles >= 2, "full-ring write backpressure/stall count");
        check(!write_inflight, "no new write granted while full");
        check(drain_active, "high-water starts drain");

        // Fault-inject an impossible completion while full to exercise the
        // defensive overflow counter rather than relying on a behavioural model.
        force dut.write_inflight = 1'b1;
        axi_bvalid = 1; axi_bready = 1; axi_bresp = 0;
        tick;
        axi_bvalid = 0; axi_bready = 0;
        release dut.write_inflight;
        tick;
        check(ring_overflow_count == 1, "full-ring overflow fault injection");
        check(occupancy_bytes == 4096, "overflow cannot exceed ring capacity");

        // Hold downstream unavailable and prove read-side backpressure is
        // counted without issuing a request.
        tx_burst_space_available = 0;
        repeat (3) tick;
        check(read_stall_cycles >= 2 && !read_inflight, "downstream backpressure/read stall");
        tx_burst_space_available = 1;

        // Release all four slots, checking low-water hysteresis and pointer wrap.
        for (i = 1; i <= 4; i = i + 1) begin
            release_read;
            check(released_bytes == i*BURST, "released byte accounting");
            check(occupancy_bytes == (4-i)*BURST, "ring occupancy decrements");
            if (i < 4)
                check(read_pointer == BASE + i*BURST, "read pointer advances");
            else
                check(read_pointer == BASE, "read pointer wraps at ring end");
            if (i == 3) begin
                tick;
                check(!drain_active, "low-water stops hysteretic drain");
                // Deasserting start requests drain-to-empty for the final slot.
                start_async = 0;
                repeat (3) tick;
                check(drain_active, "stop requests final drain");
            end
        end
        check(ring_empty && occupancy_bytes == 0, "ring drains empty");

        // Defensive underflow path: inject a stale read completion at empty.
        force dut.read_inflight = 1'b1;
        tx_burst_committed = 1;
        tick;
        tx_burst_committed = 0;
        release dut.read_inflight;
        tick;
        check(ring_underflow_count == 1, "empty-ring underflow fault injection");
        check(occupancy_bytes == 0, "underflow cannot make occupancy negative");

        // Each error input must latch the common fatal state. Clear between
        // injections proves the UART-visible clear mechanism too.
        pulse_clear;
        check(!fatal_error && ring_overflow_count == 0 && ring_underflow_count == 0,
              "counter/fatal clear");
        packetizer_error = 1; tick; packetizer_error = 0;
        check(fatal_error, "packetizer error latches fatal");
        pulse_clear;
        wr_cmd_fifo_err = 1; tick; wr_cmd_fifo_err = 0;
        check(fatal_error, "write command FIFO error latches fatal");
        pulse_clear;
        wr_data_fifo_err = 1; tick; wr_data_fifo_err = 0;
        check(fatal_error, "write data FIFO error latches fatal");
        pulse_clear;
        rd_cmd_fifo_err = 1; tick; rd_cmd_fifo_err = 0;
        check(fatal_error, "read command FIFO error latches fatal");
        pulse_clear;
        rd_data_fifo_err = 1; tick; rd_data_fifo_err = 0;
        check(fatal_error, "read data FIFO error latches fatal");
        pulse_clear;

        // A non-OK AXI B response is also fatal and must not commit a slot.
        reset = 1; tick; reset = 0;
        start_async = 1; init_calib_complete = 1; ingress_has_burst_async = 1;
        repeat (4) tick;
        wait_write_grant;
        axi_bresp = 2'b10; axi_bvalid = 1; axi_bready = 1;
        tick;
        axi_bvalid = 0; axi_bready = 0; axi_bresp = 0;
        check(fatal_error, "AXI BRESP error latches fatal");
        check(committed_bytes == 0 && occupancy_bytes == 0, "failed AXI write is not committed");

        if (errors == 0)
            $display("PASS tb_v9_pipeline_controller: pointers/wrap/watermarks/backpressure/fault injection");
        else
            $display("FAIL tb_v9_pipeline_controller: %0d checks failed", errors);
        $finish;
    end
endmodule
