// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : tb_v5_units.v
// Module  : tb_v5_units
// Created : 2026-08-11
// Revised : 2026-09-20
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_v5_units;
    reg clk=0, reset=1, start=0, calib=0;
    always #5 clk=~clk;

    // Direct regression for the two IPv4 checksum carry-boundary sums that
    // were dropped by Windows before the second end-around carry was fixed.
    wire ip_vld, ip_last, arp_en; wire [15:0] ip_len;
    wire [7:0] ip_data; wire [31:0] arp_ip;
    ip_send #(.LOCAL_IP_ADDR(32'hC0A8010B),.TARGET_IP_ADDR(32'hC0A80164)) dut_ip(
        .clk(clk),.reset(reset),.ip_tx_data_vld(ip_vld),.ip_tx_data_last(ip_last),
        .ip_tx_length(ip_len),.ip_tx_data(ip_data),.tx_data_vld(1'b0),
        .tx_data_last(1'b0),.tx_data(8'h00),.tx_length(16'd1056),
        .tx_type(8'd17),.rd_arp_list_en(arp_en),.rd_arp_list_ip(arp_ip));

    reg bvalid=0, bready=1; reg [1:0] bresp=0;
    reg rd_busy=0, tx_commit=0, tx_space=0;
    reg packetizer_error=0, wr_cmd_err=0, wr_data_err=0, rd_cmd_err=0, rd_data_err=0;
    wire grant, rd_req, started, wr_inflight, rd_inflight;
    wire [31:0] wr_ptr, rd_ptr, occupancy, wr_stalls, rd_stalls;
    wire [63:0] committed, released;
    wire full, empty, fatal;

    v5_ring_flow_controller #(.BASE_ADDR(0),.RING_BYTES(4096),.BURST_BYTES(1024)) dut_ring(
        .clk(clk),.reset(reset),.start_async(start),.init_calib_complete(calib),
        .axi_bvalid(bvalid),.axi_bready(bready),.axi_bresp(bresp),
        .user_rd_req_busy(rd_busy),.tx_burst_committed(tx_commit),
        .tx_burst_space_available(tx_space),.packetizer_error(packetizer_error),
        .wr_cmd_fifo_err(wr_cmd_err),.wr_data_fifo_err(wr_data_err),
        .rd_cmd_fifo_err(rd_cmd_err),.rd_data_fifo_err(rd_data_err),
        .write_grant_toggle(grant),.user_rd_req(rd_req),.started(started),
        .write_inflight(wr_inflight),.read_inflight(rd_inflight),
        .write_pointer(wr_ptr),.read_pointer(rd_ptr),.committed_bytes(committed),
        .released_bytes(released),.occupancy_bytes(occupancy),.ring_full(full),
        .ring_empty(empty),.write_stall_cycles(wr_stalls),
        .read_stall_cycles(rd_stalls),.fatal_error(fatal));

    reg grant_seen=0; integer bdelay=0; integer rdelay=0;
    always @(posedge clk) begin
        bvalid<=0; tx_commit<=0;
        if(grant!=grant_seen) begin grant_seen<=grant; bdelay<=3; end
        else if(bdelay>1) bdelay<=bdelay-1;
        else if(bdelay==1) begin bdelay<=0; bvalid<=1; end
        if(rd_req) rdelay<=3;
        else if(rdelay>1) rdelay<=rdelay-1;
        else if(rdelay==1) begin rdelay<=0; tx_commit<=1; end
        if(occupancy>4096) begin $display("FAIL occupancy overflow %0d",occupancy); $finish; end
        if(fatal) begin $display("FAIL fatal error"); $finish; end
    end

    reg p_reset=1, p_valid=0, p_last=0; reg [7:0] p_data=0;
    reg p_ready=1; integer ready_count=0;
    wire p_space,p_commit,p_done,p_error,p_vld,p_last_out;
    wire [31:0] p_seq; wire [11:0] p_bytes; wire [1:0] p_packets;
    wire [7:0] p_out; wire [15:0] p_len;
    udp_v5_tx_fifo_packetizer #(.DATA_BYTES(16),.FIFO_PACKETS(2),
        .POST_READY_IDLE_CYCLES(8)) dut_packetizer(
        .clk(clk),.reset(p_reset),.user_rd_valid(p_valid),.user_rd_last(p_last),
        .user_rd_data(p_data),.committed_bytes_low(32'd32),.occupancy_bytes(32'd16),
        .burst_space_available(p_space),.burst_committed(p_commit),
        .packet_done(p_done),.packet_sequence(p_seq),.framing_error(p_error),
        .fifo_byte_count(p_bytes),.fifo_packet_count(p_packets),
        .app_tx_data_vld(p_vld),.app_tx_data_last(p_last_out),
        .app_tx_data(p_out),.app_tx_length(p_len),.app_tx_ready(p_ready));

    // Match net21/udp_send.v: ready is still high on the clock edge that
    // accepts app_tx_data_last, then remains low for 50 clocks.
    always @(posedge clk) begin
        if(p_reset) begin
            p_ready<=1;
            ready_count<=0;
        end else if(p_last_out) begin
            p_ready<=0;
            ready_count<=50;
        end else if(ready_count>1) begin
            p_ready<=0;
            ready_count<=ready_count-1;
        end else if(ready_count==1) begin
            p_ready<=1;
            ready_count<=0;
        end else begin
            p_ready<=1;
        end
    end

    integer out_index=0; integer out_packet=0; integer errors=0;
    always @(negedge clk) begin
        if(p_vld && !p_ready) begin
            $display("FAIL packetizer drove data while app_tx_ready was low");
            errors=errors+1;
        end
        if(p_vld && p_ready) begin
            if(out_index==0 && p_out!="P") errors=errors+1;
            if(out_index==1 && p_out!="2") errors=errors+1;
            if(out_index==2 && p_out!="V") errors=errors+1;
            if(out_index==3 && p_out!="5") errors=errors+1;
            if(out_index==4 && p_out!=8'h05) errors=errors+1;
            if(out_index>=24 && p_out!=(out_packet*16+out_index-24)) errors=errors+1;
            if(out_index==39) begin out_index=0; out_packet=out_packet+1; end
            else out_index=out_index+1;
        end
    end

    integer i;
    initial begin
        repeat(5) @(posedge clk); reset<=0; p_reset<=0; calib<=1; start<=1;
        force dut_ip.tx_cnt = 11'd5;
        force dut_ip.chack_sum = 32'h0002fffe;
        @(posedge clk); #1;
        if(dut_ip.ip_head_chack!==16'hfffe) begin
            $display("FAIL IPv4 checksum fold sum=0x2fffe got=%h",dut_ip.ip_head_chack); $finish;
        end
        force dut_ip.chack_sum = 32'h0002ffff;
        @(posedge clk); #1;
        if(dut_ip.ip_head_chack!==16'hfffd) begin
            $display("FAIL IPv4 checksum fold sum=0x2ffff got=%h",dut_ip.ip_head_chack); $finish;
        end
        release dut_ip.chack_sum;
        release dut_ip.tx_cnt;
        wait(full); repeat(2) @(posedge clk); if(occupancy!=4096 || committed!=4096) begin
            $display("FAIL ring did not fill occupancy=%0d committed=%0d",occupancy,committed); $finish;
        end
        repeat(10) @(posedge clk); if(wr_stalls==0) begin $display("FAIL no full stall"); $finish; end
        tx_space<=1;

        for(i=0;i<32;i=i+1) begin
            @(posedge clk); p_valid<=1; p_data<=i[7:0]; p_last<=((i%16)==15);
        end
        @(posedge clk); p_valid<=0; p_last<=0;

        repeat(400) @(posedge clk);
        if(released==0) begin $display("FAIL no ring release"); $finish; end
        if(out_packet!=2 || p_error || errors!=0) begin
            $display("FAIL packetizer packets=%0d framing=%0d errors=%0d",out_packet,p_error,errors); $finish;
        end
        $display("V5 RING/FLOW SIM PASSED: committed=%0d released=%0d occupancy=%0d stalls=%0d packets=%0d",
            committed,released,occupancy,wr_stalls,out_packet);
        $finish;
    end
endmodule
