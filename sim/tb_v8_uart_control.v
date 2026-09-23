// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : tb_v8_uart_control.v
// Module  : tb_v8_uart_control
// Created : 2026-09-08
// Revised : 2026-09-23
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_v8_uart_control;
    reg clk=0, reset=1, uart_rxd=1;
    always #5 clk=~clk;

    reg finite_done=0, pipeline_idle=1;
    reg [31:0] run_words=0;
    reg [63:0] total_words=0;
    reg [11:0] ingress_level=0;
    reg [31:0] ingress_ovf=0,ingress_udf=0;
    reg [3:0] xadc_valid_mask=4'hf;
    reg [31:0] xadc_drop_count=0;
    reg [11:0] xadc_temperature=12'h977,xadc_vccint=12'h555;
    reg [11:0] xadc_vccaux=12'h999,xadc_vccbram=12'h556;
    reg [326:0] ui_snapshot=0;
    reg ui_ack=0;
    wire uart_txd,run_enable,finite_mode,clear_toggle,status_req;
    wire [7:0] source_select;
    wire [31:0] rate,finite_words,crc_errors,rejects;
    wire [15:0] packet_length;

    v8_uart_control #(.CLK_HZ(1000000),.BAUD(100000)) dut(
        .clk(clk),.reset(reset),.uart_rxd(uart_rxd),.uart_txd(uart_txd),
        .manual_start_pulse(1'b0),.finite_done(finite_done),
        .pipeline_idle(pipeline_idle),.run_words(run_words),
        .total_words(total_words),.ingress_level_words(ingress_level),
        .ingress_overflow_count(ingress_ovf),
        .ingress_underflow_count(ingress_udf),
        .xadc_valid_mask(xadc_valid_mask),.xadc_drop_count(xadc_drop_count),
        .xadc_temperature_raw(xadc_temperature),.xadc_vccint_raw(xadc_vccint),
        .xadc_vccaux_raw(xadc_vccaux),.xadc_vccbram_raw(xadc_vccbram),
        .ui_status_snapshot(ui_snapshot),.ui_status_ack_toggle(ui_ack),
        .run_enable(run_enable),.source_select(source_select),
        .rate_words_per_sec(rate),.packet_length(packet_length),
        .finite_mode(finite_mode),.finite_words(finite_words),
        .clear_toggle(clear_toggle),.status_request_toggle(status_req),
        .crc_error_count(crc_errors),.command_reject_count(rejects));

    function [15:0] crc_next;
        input [15:0] crc_in;
        input [7:0] data;
        integer k;
        reg [15:0] c;
        begin
            c=crc_in^data;
            for(k=0;k<8;k=k+1)
                c=c[0] ? ((c>>1)^16'hA001) : (c>>1);
            crc_next=c;
        end
    endfunction

    task uart_byte;
        input [7:0] value;
        integer b;
        begin
            uart_rxd=0; repeat(11) @(posedge clk);
            for(b=0;b<8;b=b+1) begin
                uart_rxd=value[b]; repeat(11) @(posedge clk);
            end
            uart_rxd=1; repeat(14) @(posedge clk);
        end
    endtask

    reg [7:0] payload [0:7];
    task send_frame;
        input [7:0] typ;
        input [7:0] seq;
        input [7:0] len;
        input corrupt;
        integer j;
        reg [15:0] c;
        begin
            c=16'hFFFF;
            uart_byte(8'hA5); uart_byte(8'h5A);
            uart_byte(typ); c=crc_next(c,typ);
            uart_byte(seq); c=crc_next(c,seq);
            uart_byte(len); c=crc_next(c,len);
            for(j=0;j<len;j=j+1) begin
                uart_byte(payload[j]); c=crc_next(c,payload[j]);
            end
            uart_byte(c[7:0] ^ (corrupt ? 8'h01 : 8'h00));
            uart_byte(c[15:8]);
        end
    endtask

    reg [7:0] tx_bytes [0:255];
    integer tx_count=0;
    always @(posedge clk) if(dut.uart_tx_en) begin
        tx_bytes[tx_count]=dut.uart_tx_data;
        tx_count=tx_count+1;
    end

    reg status_seen=0;
    always @(posedge clk) begin
        if(status_req!=status_seen) begin
            status_seen<=status_req;
            ui_snapshot[6:0]<=7'b0010011;
            ui_snapshot[38:7]<=32'h00001200;
            ui_snapshot[70:39]<=32'h0000002A;
            ui_ack<=status_req;
        end
    end

    task wait_reply;
        input integer expected_total;
        integer timeout;
        begin
            timeout=0;
            while(tx_count<expected_total && timeout<200000) begin
                @(posedge clk); timeout=timeout+1;
            end
            if(tx_count<expected_total) begin
                $display("FAIL reply timeout have=%0d want=%0d",tx_count,expected_total);
                $finish;
            end
            while(dut.tx_state!=0 || dut.uart_tx_busy) @(posedge clk);
            repeat(4) @(posedge clk);
        end
    endtask

    task check_last_simple;
        input [7:0] typ;
        input [7:0] seq;
        input [7:0] result;
        integer base;
        reg [15:0] c;
        begin
            base=tx_count-8;
            if(tx_bytes[base]!=8'hA5 || tx_bytes[base+1]!=8'h5A ||
               tx_bytes[base+2]!=(typ|8'h80) || tx_bytes[base+3]!=seq ||
               tx_bytes[base+4]!=1 || tx_bytes[base+5]!=result) begin
                $display("FAIL simple reply type=%02x seq=%02x result=%02x",typ,seq,result);
                $finish;
            end
            c=16'hFFFF;
            c=crc_next(c,tx_bytes[base+2]); c=crc_next(c,tx_bytes[base+3]);
            c=crc_next(c,tx_bytes[base+4]); c=crc_next(c,tx_bytes[base+5]);
            if(tx_bytes[base+6]!=c[7:0] || tx_bytes[base+7]!=c[15:8]) begin
                $display("FAIL reply CRC"); $finish;
            end
        end
    endtask

    integer count_before;
    integer init_i;
    initial begin
        repeat(8) @(posedge clk); reset=0; repeat(4) @(posedge clk);
        for(init_i=0;init_i<8;init_i=init_i+1) payload[init_i]=0;

        send_frame(8'h03,8'h01,0,0); wait_reply(8);
        check_last_simple(8'h03,8'h01,0);
        if(!run_enable) begin $display("FAIL START"); $finish; end

        send_frame(8'h11,8'h02,4,0); wait_reply(16);
        check_last_simple(8'h11,8'h02,8'h03);

        send_frame(8'h04,8'h03,0,0); wait_reply(24);
        check_last_simple(8'h04,8'h03,0);
        if(run_enable) begin $display("FAIL STOP"); $finish; end

        payload[0]=1;
        send_frame(8'h10,8'h0A,1,0); wait_reply(32);
        check_last_simple(8'h10,8'h0A,0);
        if(source_select!=1) begin $display("FAIL SOURCE XADC"); $finish; end

        payload[0]=0;payload[1]=8'h0F;payload[2]=8'h42;payload[3]=8'h40;
        send_frame(8'h11,8'h04,4,0); wait_reply(40);
        if(rate!=1000000) begin $display("FAIL SET_RATE %0d",rate); $finish; end

        payload[0]=8'h02;payload[1]=8'h00;
        send_frame(8'h12,8'h05,2,0); wait_reply(48);
        if(packet_length!=512) begin $display("FAIL PACKET_LENGTH"); $finish; end

        payload[0]=1;payload[1]=0;payload[2]=0;payload[3]=4;payload[4]=0;
        send_frame(8'h13,8'h06,5,0); wait_reply(56);
        if(!finite_mode || finite_words!=1024) begin $display("FAIL FINITE"); $finish; end

        send_frame(8'h03,8'h07,0,0); wait_reply(64);
        finite_done=1; repeat(2) @(posedge clk); finite_done=0; repeat(2) @(posedge clk);
        if(run_enable) begin $display("FAIL FINITE AUTO STOP"); $finish; end

        count_before=tx_count;
        send_frame(8'h15,8'h08,0,0); wait_reply(count_before+81);
        if(tx_bytes[count_before+2]!=8'h95 || tx_bytes[count_before+4]!=74 ||
           tx_bytes[count_before+5]!=0 || tx_bytes[count_before+6]!=8 ||
           tx_bytes[count_before+7]!=8'h1C || tx_bytes[count_before+8]!=1 ||
           tx_bytes[count_before+66]!=4'hf ||
           tx_bytes[count_before+71]!=8'h09 || tx_bytes[count_before+72]!=8'h77) begin
            $display("FAIL STATUS RESPONSE"); $finish;
        end

        count_before=tx_count;
        send_frame(8'h03,8'h09,0,1); repeat(3000) @(posedge clk);
        if(tx_count!=count_before || crc_errors==0) begin
            $display("FAIL BAD CRC rejection"); $finish;
        end

        $display("V8 UART CONTROL SIM PASSED: bytes=%0d rejects=%0d crc_errors=%0d",
            tx_count,rejects,crc_errors);
        $finish;
    end
endmodule
