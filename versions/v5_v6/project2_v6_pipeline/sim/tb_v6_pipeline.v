// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : tb_v6_pipeline.v
// Module  : tb_v6_pipeline
// Created : 2026-08-25
// Revised : 2026-09-22
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_v6_pipeline;
    reg clk=0, reset=1, start=0, calib=0;
    always #5 clk=~clk;

    wire src_valid,src_ready; wire [15:0] src_data; wire [63:0] src_words;
    wire fifo_valid,fifo_ready,has_burst,hi,lo,source_run;
    wire [15:0] fifo_data; wire [5:0] fifo_level;
    wire drain_busy,user_wr_en; wire [15:0] user_wr_data;
    wire [31:0] ingress_overflow,ingress_underflow,completed_bursts,starvation;
    wire grant;

    prbs16_stream_source u_src(.clk(clk),.reset(reset),.enable(start&&source_run),
        .ready(src_ready),.valid(src_valid),.data(src_data),.total_words(src_words));
    v6_ingress_fifo #(.DEPTH_WORDS(32),.HIGH_WATER_WORDS(24),
        .LOW_WATER_WORDS(8),.BURST_WORDS(8)) u_fifo(
        .clk(clk),.reset(reset),.enable(start),.in_valid(src_valid),.in_data(src_data),
        .in_ready(src_ready),.out_ready(fifo_ready),.out_valid(fifo_valid),
        .out_data(fifo_data),.level_words(fifo_level),.has_burst(has_burst),
        .high_water(hi),.low_water(lo),.source_run(source_run),
        .overflow_count(ingress_overflow),.underflow_count(ingress_underflow));
    v6_ingress_drain #(.BURST_WORDS(8)) u_drain(
        .clk(clk),.reset(reset),.enable(start),.grant_toggle_async(grant),
        .fifo_valid(fifo_valid),.fifo_data(fifo_data),.fifo_ready(fifo_ready),
        .user_wr_en(user_wr_en),.user_wr_data(user_wr_data),.busy(drain_busy),
        .completed_bursts(completed_bursts),.starvation_count(starvation));

    reg bvalid=0; reg [1:0] bresp=0; wire bready=1;
    reg rd_busy=0; wire rd_req;
    wire tx_commit,tx_space;
    wire started,wr_inflight,rd_inflight,drain_active,full,empty,fatal;
    wire [31:0] wr_ptr,rd_ptr,occupancy,wr_stall,rd_stall,ring_ovf,ring_udf;
    wire [63:0] committed,released;
    v6_pipeline_controller #(.RING_BYTES(128),.BURST_BYTES(16),
        .DDR_HIGH_WATER_BYTES(64),.DDR_LOW_WATER_BYTES(16)) u_ctrl(
        .clk(clk),.reset(reset),.start_async(start),.init_calib_complete(calib),
        .ingress_has_burst_async(has_burst),.axi_bvalid(bvalid),.axi_bready(bready),
        .axi_bresp(bresp),.user_rd_req_busy(rd_busy),.tx_burst_committed(tx_commit),
        .tx_burst_space_available(tx_space),.packetizer_error(1'b0),
        .wr_cmd_fifo_err(1'b0),.wr_data_fifo_err(1'b0),.rd_cmd_fifo_err(1'b0),
        .rd_data_fifo_err(1'b0),.write_grant_toggle(grant),.user_rd_req(rd_req),
        .started(started),.write_inflight(wr_inflight),.read_inflight(rd_inflight),
        .drain_active(drain_active),.write_pointer(wr_ptr),.read_pointer(rd_ptr),
        .committed_bytes(committed),.released_bytes(released),
        .occupancy_bytes(occupancy),.ring_full(full),.ring_empty(empty),
        .write_stall_cycles(wr_stall),.read_stall_cycles(rd_stall),
        .ring_overflow_count(ring_ovf),.ring_underflow_count(ring_udf),
        .fatal_error(fatal));

    reg rd_valid=0,rd_last=0; reg [7:0] rd_data=0;
    wire packet_done,packet_error,app_vld,app_last; wire [7:0] app_data;
    wire [15:0] app_len; reg app_ready=1;
    wire [31:0] packet_seq,tx_ovf,tx_udf; wire [13:0] tx_bytes;
    wire [3:0] tx_packets;
    udp_v6_tx_fifo_packetizer #(.DATA_BYTES(16),.FIFO_PACKETS(8),
        .POST_READY_IDLE_CYCLES(4)) u_pkt(
        .clk(clk),.reset(reset),.user_rd_valid(rd_valid),.user_rd_last(rd_last),
        .user_rd_data(rd_data),.committed_bytes_low(committed[31:0]),
        .occupancy_bytes(occupancy),.stream_expected(drain_active),
        .burst_space_available(tx_space),.burst_committed(tx_commit),
        .packet_done(packet_done),.packet_sequence(packet_seq),
        .framing_error(packet_error),.fifo_byte_count(tx_bytes),
        .fifo_packet_count(tx_packets),.overflow_count(tx_ovf),
        .underflow_count(tx_udf),.app_tx_data_vld(app_vld),
        .app_tx_data_last(app_last),.app_tx_data(app_data),
        .app_tx_length(app_len),.app_tx_ready(app_ready));

    reg [31:0] seen_completed=0; integer bdelay=0;
    integer rd_index=-1; integer ready_hold=0;
    reg saw_parallel=0,saw_hi=0,saw_lo_after_hi=0;
    integer tx_index=0;
    always @(posedge clk) begin
        bvalid<=0; rd_valid<=0; rd_last<=0;
        if(completed_bursts!=seen_completed) begin seen_completed<=completed_bursts; bdelay<=2; end
        else if(bdelay>1) bdelay<=bdelay-1;
        else if(bdelay==1) begin bdelay<=0; bvalid<=1; end

        if(rd_req && rd_index<0) rd_index<=0;
        else if(rd_index>=0) begin
            rd_valid<=1; rd_data<=rd_index[7:0]; rd_last<=(rd_index==15);
            if(rd_index==15) rd_index<=-1; else rd_index<=rd_index+1;
        end

        if(app_last) begin app_ready<=0;ready_hold<=12; end
        else if(ready_hold>1) begin app_ready<=0;ready_hold<=ready_hold-1; end
        else if(ready_hold==1) begin app_ready<=1;ready_hold<=0; end

        if(wr_inflight && (rd_inflight || app_vld)) saw_parallel<=1;
        if(app_vld && app_ready) begin
            if(tx_index==0 && app_data!="P") begin $display("FAIL header P"); $finish; end
            if(tx_index==1 && app_data!="2") begin $display("FAIL header 2"); $finish; end
            if(tx_index==2 && app_data!="V") begin $display("FAIL header V"); $finish; end
            if(tx_index==3 && app_data!="5") begin $display("FAIL V5 compatibility header"); $finish; end
            if(tx_index==4 && app_data!=8'h05) begin $display("FAIL V5 compatibility version"); $finish; end
            if(app_last) tx_index<=0; else tx_index<=tx_index+1;
        end
        if(hi) saw_hi<=1;
        if(saw_hi && lo) saw_lo_after_hi<=1;
        if(fatal || ring_ovf!=0 || ring_udf!=0 || ingress_underflow!=0 || starvation!=0 || tx_ovf!=0 || packet_error) begin
            $display("FAIL counter/fatal fatal=%0d ring=%0d/%0d ingress=%0d/%0d txovf=%0d frame=%0d",
                fatal,ring_ovf,ring_udf,ingress_overflow,ingress_underflow,tx_ovf,packet_error);
            $finish;
        end
    end

    initial begin
        repeat(6) @(posedge clk); reset<=0; start<=1; calib<=1;
        repeat(5000) @(posedge clk);
        if(packet_seq<8 || committed<256 || released<128) begin
            $display("FAIL insufficient flow packets=%0d committed=%0d released=%0d",packet_seq,committed,released); $finish;
        end
        if(!saw_parallel || !saw_hi || !saw_lo_after_hi) begin
            $display("FAIL pipeline/hysteresis parallel=%0d high=%0d low=%0d",saw_parallel,saw_hi,saw_lo_after_hi); $finish;
        end
        if(ingress_overflow!=0) begin
            $display("FAIL normal backpressure overflow=%0d",ingress_overflow); $finish;
        end
        $display("V6 PIPELINE SIM PASSED: packets=%0d committed=%0d released=%0d occupancy=%0d",packet_seq,committed,released,occupancy);
        $finish;
    end
endmodule
