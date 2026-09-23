// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : tb_v7_source.v
// Module  : tb_v7_source
// Created : 2026-09-02
// Revised : 2026-09-22
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_v7_source;
    reg clk=0,reset=1,clear=0,enable=0,ready=1;
    always #5 clk=~clk;
    wire valid,done;
    wire [15:0] data;
    wire [31:0] run_words;
    wire [63:0] total_words;
    v7_rate_controlled_prbs #(.CLK_HZ(100),.PRBS_SEED(16'hACE1)) dut(
        .clk(clk),.reset(reset),.clear_counters(clear),.enable(enable),
        .ready(ready),.rate_words_per_sec(32'd25),.finite_mode(1'b1),
        .finite_words(32'd8),.valid(valid),.data(data),.finite_done(done),
        .run_words(run_words),.total_words(total_words));
    reg [15:0] expected=16'hACE1;
    integer cycles=0,accepts=0,last_accept_cycle=0;
    function [15:0] next_prbs;
        input [15:0] value;
        begin next_prbs={value[14:0],value[15]^value[13]^value[12]^value[10]}; end
    endfunction
    always @(posedge clk) begin
        cycles=cycles+1;
        if(valid&&ready) begin
            if(data!=expected) begin $display("FAIL PRBS got=%04x expected=%04x",data,expected);$finish;end
            if(accepts>0 && cycles-last_accept_cycle!=4) begin
                $display("FAIL rate interval=%0d expected=4",cycles-last_accept_cycle);$finish;
            end
            last_accept_cycle=cycles; accepts=accepts+1;
            expected=next_prbs(expected);
        end
    end
    initial begin
        repeat(4) @(posedge clk);reset=0;enable=1;
        while(!done && cycles<200) @(posedge clk);
        if(!done || run_words!=8 || total_words!=8) begin
            $display("FAIL finite words run=%0d total=%0d done=%0d",run_words,total_words,done);$finish;
        end
        if(accepts!=8) begin $display("FAIL accepted words=%0d",accepts);$finish;end
        enable=0;repeat(2)@(posedge clk);@(negedge clk);clear=1;
        @(posedge clk);@(negedge clk);clear=0;@(posedge clk);
        if(total_words!=0 || run_words!=0 || data!=16'hACE1) begin
            $display("FAIL clear total=%0d run=%0d data=%04x",total_words,run_words,data);$finish;
        end
        $display("V7 RATE/FINITE SOURCE SIM PASSED: cycles=%0d",cycles);
        $finish;
    end
endmodule
