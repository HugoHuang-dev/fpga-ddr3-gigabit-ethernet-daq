// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : tb_v8_xadc_source.v
// Module  : XADC
// Created : 2026-09-08
// Revised : 2026-09-22
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module XADC #(
    parameter INIT_40=0, INIT_41=0, INIT_42=0, INIT_48=0, INIT_49=0,
    parameter SIM_DEVICE="7SERIES"
)(
    input DCLK, input [6:0] DADDR, input DEN, input [15:0] DI, input DWE,
    input RESET, input CONVST, input CONVSTCLK, input [15:0] VAUXP,
    input [15:0] VAUXN, input VP, input VN,
    output reg [15:0] DO, output reg DRDY, output reg EOC,
    output reg [4:0] CHANNEL,
    output [7:0] ALM, output BUSY, EOS, JTAGBUSY, JTAGLOCKED,
    JTAGMODIFIED, OT, output [4:0] MUXADDR
);
    assign {ALM,BUSY,EOS,JTAGBUSY,JTAGLOCKED,JTAGMODIFIED,OT,MUXADDR}=0;
    reg [1:0] phase, sensor_index;
    always @(posedge DCLK) begin
        if (RESET) begin
            DO<=0; DRDY<=0; EOC<=0; CHANNEL<=0; phase<=0; sensor_index<=0;
        end else begin
            EOC<=0; DRDY<=0;
            if (phase==3) begin
                case(sensor_index)
                    0: CHANNEL<=5'h00;
                    1: CHANNEL<=5'h01;
                    2: CHANNEL<=5'h02;
                    3: CHANNEL<=5'h06;
                endcase
                EOC<=1; sensor_index<=sensor_index+1'b1; phase<=0;
            end else phase<=phase+1'b1;
            if (DEN) begin
                case(DADDR)
                    7'h00: DO<=16'h9770;
                    7'h01: DO<=16'h5550;
                    7'h02: DO<=16'h9990;
                    7'h06: DO<=16'h5560;
                    default: $fatal(1,"unexpected DRP address %02x",DADDR);
                endcase
                DRDY<=1;
            end
        end
    end
endmodule

module tb_v8_xadc_source;
    reg clk=0, reset=1, clear_counters=0, enable=0, ready=1;
    wire valid, finite_done;
    wire [15:0] data;
    wire [31:0] run_words,drop_count;
    wire [63:0] total_words;
    wire [3:0] valid_mask;
    wire [11:0] temperature_raw,vccint_raw,vccaux_raw,vccbram_raw;
    integer accepted=0;
    reg [15:0] expected;

    always #5 clk=~clk;

    v8_xadc_stream_source #(.CLK_HZ(1000),.SAMPLE_RATE_HZ(100)) dut(
        .clk(clk),.reset(reset),.clear_counters(clear_counters),
        .enable(enable),.ready(ready),.finite_mode(1'b1),.finite_words(32'd12),
        .valid(valid),.data(data),.finite_done(finite_done),
        .run_words(run_words),.total_words(total_words),.drop_count(drop_count),
        .valid_mask(valid_mask),.temperature_raw(temperature_raw),
        .vccint_raw(vccint_raw),.vccaux_raw(vccaux_raw),
        .vccbram_raw(vccbram_raw));

    always @(posedge clk) begin
        if (valid && ready) begin
            case (accepted[1:0])
                0: expected=16'h0977;
                1: expected=16'h4555;
                2: expected=16'h8999;
                default: expected=16'hC556;
            endcase
            if (data !== expected)
                $fatal(1,"record %0d got %04x expected %04x",accepted,data,expected);
            accepted=accepted+1;
        end
    end

    initial begin
        repeat(5) @(posedge clk); reset=0;
        wait(valid_mask==4'hf);
        @(posedge clk); enable=1;
        wait(accepted==4);
        @(negedge clk); ready=0;
        wait(valid);
        repeat(5) @(negedge clk);
        if (!valid) $fatal(1,"pending XADC sample was not held during backpressure");
        ready=1;
        wait(finite_done);
        repeat(2) @(posedge clk);
        if (accepted!=12 || run_words!=12 || total_words!=12 || drop_count!=0)
            $fatal(1,"bad counters accepted=%0d run=%0d total=%0d drops=%0d",
                accepted,run_words,total_words,drop_count);
        if (temperature_raw!=12'h977 || vccint_raw!=12'h555 ||
            vccaux_raw!=12'h999 || vccbram_raw!=12'h556)
            $fatal(1,"bad XADC snapshot values");
        $display("PASS: V8 Project1 XADC wrapper valid/ready, channel order and finite count");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1,"timeout accepted=%0d valid_mask=%x",accepted,valid_mask);
    end
endmodule
