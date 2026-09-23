// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : v8_xadc_stream_source.v
// Module  : v8_xadc_stream_source
// Created : 2026-09-08
// Revised : 2026-09-22
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// Wrap Project1's four internal XADC status channels in the same valid/ready
// 16-bit stream contract used by the Project2 acquisition pipeline.
//
// Record format is preserved from Project1:
//   [15:14] channel: 0 temperature, 1 VCCINT, 2 VCCAUX, 3 VCCBRAM
//   [13:12] reserved zero
//   [11:0]  raw XADC code
//
// Project1 deliberately recorded one channel every millisecond.  V8 keeps that
// proven 1,000-record/s policy instead of pretending the slow internal sensors
// are a high-rate external ADC.  The pending register holds a sample across
// downstream backpressure; drop_count increments only if a second sampling
// instant arrives before the previous record is accepted.
module v8_xadc_stream_source #(
    parameter integer CLK_HZ = 125000000,
    parameter integer SAMPLE_RATE_HZ = 1000
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        clear_counters,
    input  wire        enable,
    input  wire        ready,
    input  wire        finite_mode,
    input  wire [31:0] finite_words,
    output wire        valid,
    output wire [15:0] data,
    output wire        finite_done,
    output reg  [31:0] run_words,
    output reg  [63:0] total_words,
    output reg  [31:0] drop_count,
    output wire [3:0]  valid_mask,
    output wire [11:0] temperature_raw,
    output wire [11:0] vccint_raw,
    output wire [11:0] vccaux_raw,
    output wire [11:0] vccbram_raw
);
    localparam integer SAMPLE_PERIOD = CLK_HZ / SAMPLE_RATE_HZ;
    localparam integer TIMER_WIDTH = $clog2(SAMPLE_PERIOD);

    reg [TIMER_WIDTH-1:0] sample_timer;
    reg [1:0] sample_channel;
    reg [15:0] pending_data;
    reg pending_valid;
    reg enable_d;
    reg [11:0] selected_raw;

    wire sensors_ready = &valid_mask;
    wire sample_tick = enable && sensors_ready &&
                       (sample_timer == SAMPLE_PERIOD-1);
    wire accepted = valid && ready;

    assign finite_done = finite_mode && (finite_words != 0) &&
                         (run_words >= finite_words);
    assign valid = pending_valid && enable && !finite_done;
    assign data = pending_data;

    xadc_multichannel u_xadc (
        .clk(clk), .rst(reset),
        .temperature(temperature_raw), .vccint(vccint_raw),
        .vccaux(vccaux_raw), .vccbram(vccbram_raw),
        .valid_mask(valid_mask));

    always @* begin
        case (sample_channel)
            2'd0: selected_raw = temperature_raw;
            2'd1: selected_raw = vccint_raw;
            2'd2: selected_raw = vccaux_raw;
            default: selected_raw = vccbram_raw;
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            sample_timer <= 0;
            sample_channel <= 0;
            pending_data <= 0;
            pending_valid <= 0;
            enable_d <= 0;
            run_words <= 0;
            total_words <= 0;
            drop_count <= 0;
        end else begin
            enable_d <= enable;

            if (clear_counters) begin
                sample_timer <= 0;
                sample_channel <= 0;
                pending_data <= 0;
                pending_valid <= 0;
                run_words <= 0;
                total_words <= 0;
                drop_count <= 0;
            end else if (!enable) begin
                sample_timer <= 0;
                pending_valid <= 0;
            end else begin
                if (!enable_d) begin
                    sample_timer <= 0;
                    sample_channel <= 0;
                    pending_valid <= 0;
                    run_words <= 0;
                end else if (!finite_done && sensors_ready) begin
                    if (sample_tick)
                        sample_timer <= 0;
                    else
                        sample_timer <= sample_timer + 1'b1;
                end

                if (sample_tick && !finite_done) begin
                    if (!pending_valid || ready) begin
                        pending_data <= {sample_channel, 2'b00, selected_raw};
                        pending_valid <= 1'b1;
                        sample_channel <= sample_channel + 1'b1;
                    end else begin
                        drop_count <= drop_count + 1'b1;
                    end
                end

                if (accepted) begin
                    run_words <= run_words + 1'b1;
                    total_words <= total_words + 1'b1;
                    if (!sample_tick)
                        pending_valid <= 1'b0;
                end
            end
        end
    end

    initial begin
        if (SAMPLE_RATE_HZ <= 0 || SAMPLE_RATE_HZ > CLK_HZ)
            $error("invalid V8 XADC sample rate");
        if ((CLK_HZ % SAMPLE_RATE_HZ) != 0)
            $error("V8 XADC sample rate must divide CLK_HZ exactly");
    end
endmodule
