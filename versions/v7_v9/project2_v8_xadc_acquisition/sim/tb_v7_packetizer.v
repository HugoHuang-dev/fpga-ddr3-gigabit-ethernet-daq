// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : tb_v7_packetizer.v
// Module  : tb_v7_packetizer
// Created : 2026-09-02
// Revised : 2026-09-22
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_v7_packetizer;
    reg clk=0,reset=1,clear=0;
    always #5 clk=~clk;
    reg rd_valid=0,rd_last=0;
    reg [7:0] rd_data=0;
    reg app_ready=1;
    wire space,committed,packet_done,frame_error;
    wire [31:0] packet_sequence,overflow_count,underflow_count;
    wire [13:0] fifo_bytes;
    wire [3:0] fifo_bursts;
    wire app_valid,app_last;
    wire [7:0] app_data;
    wire [15:0] app_length;

    udp_v7_tx_fifo_packetizer #(.BURST_BYTES(1024),.FIFO_BURSTS(2),
        .POST_READY_IDLE_CYCLES(2)) dut(
        .clk(clk),.reset(reset),.clear_counters(clear),
        .configured_payload_bytes(16'd256),.user_rd_valid(rd_valid),
        .user_rd_last(rd_last),.user_rd_data(rd_data),
        .committed_bytes_low(32'd1024),.occupancy_bytes(32'd1024),
        .stream_expected(1'b0),.burst_space_available(space),
        .burst_committed(committed),.packet_done(packet_done),
        .packet_sequence(packet_sequence),.framing_error(frame_error),
        .fifo_byte_count(fifo_bytes),.fifo_packet_count(fifo_bursts),
        .overflow_count(overflow_count),.underflow_count(underflow_count),
        .app_tx_data_vld(app_valid),.app_tx_data_last(app_last),
        .app_tx_data(app_data),.app_tx_length(app_length),
        .app_tx_ready(app_ready));

    integer input_index=0,wire_index=0,payload_index=0,packets=0;
    integer ready_delay=0;
    always @(posedge clk) begin
        if(app_valid) begin
            if(wire_index==0 && app_data!="P") begin $display("FAIL magic P");$finish;end
            if(wire_index==1 && app_data!="2") begin $display("FAIL magic 2");$finish;end
            if(wire_index==2 && app_data!="V") begin $display("FAIL magic V");$finish;end
            if(wire_index==3 && app_data!="7") begin $display("FAIL magic 7");$finish;end
            if(wire_index==4 && app_data!=7) begin $display("FAIL version");$finish;end
            if(wire_index==6 && app_data!=8'h01) begin $display("FAIL length hi");$finish;end
            if(wire_index==7 && app_data!=8'h18) begin $display("FAIL length lo");$finish;end
            if(wire_index==12 && app_data!=8'h01) begin $display("FAIL payload hi");$finish;end
            if(wire_index==13 && app_data!=8'h00) begin $display("FAIL payload lo");$finish;end
            if(wire_index>=24 && app_data!=payload_index[7:0]) begin
                $display("FAIL payload packet=%0d wire=%0d got=%02x expected=%02x",
                    packets,wire_index,app_data,payload_index[7:0]); $finish;
            end
            if(wire_index>=24) payload_index=payload_index+1;
            if(app_last) begin
                if(wire_index!=279 || app_length!=280) begin
                    $display("FAIL packet boundary index=%0d length=%0d",wire_index,app_length);
                    $finish;
                end
                packets=packets+1;
                wire_index=0;
                app_ready<=0;
                ready_delay=8;
            end else wire_index=wire_index+1;
        end
        if(ready_delay>1) ready_delay=ready_delay-1;
        else if(ready_delay==1) begin ready_delay=0; app_ready<=1; end
    end

    initial begin
        repeat(5) @(posedge clk); reset=0; repeat(3) @(posedge clk);
        for(input_index=0;input_index<1024;input_index=input_index+1) begin
            @(negedge clk);
            rd_valid=1;rd_data=input_index[7:0];rd_last=(input_index==1023);
            @(posedge clk);
        end
        @(negedge clk); rd_valid=0;rd_last=0;
        while(packets<4) @(posedge clk);
        repeat(20) @(posedge clk);
        if(packet_sequence!=4 || payload_index!=1024 || fifo_bytes!=0 ||
           fifo_bursts!=0 || frame_error || overflow_count!=0 ||
           underflow_count!=0) begin
            $display("FAIL final seq=%0d payload=%0d bytes=%0d bursts=%0d frame=%0d ovf=%0d udf=%0d",
                packet_sequence,payload_index,fifo_bytes,fifo_bursts,frame_error,
                overflow_count,underflow_count); $finish;
        end
        $display("V7 PACKETIZER SIM PASSED: one 1024-byte burst -> %0d x 256-byte packets",packets);
        $finish;
    end
endmodule
