// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : project2_v7_top.v
// Module  : project2_v7_top
// Created : 2026-09-02
// Revised : 2026-09-22
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module project2_v7_top (
    input wire sys_clk, input wire sys_rst_n, input wire start_n,
    input wire uart_rxd, output wire uart_txd,
    inout wire [15:0] ddr3_dq, inout wire [1:0] ddr3_dqs_n,
    inout wire [1:0] ddr3_dqs_p, output wire [13:0] ddr3_addr,
    output wire [2:0] ddr3_ba, output wire ddr3_ras_n,
    output wire ddr3_cas_n, output wire ddr3_we_n, output wire ddr3_reset_n,
    output wire [0:0] ddr3_ck_p, output wire [0:0] ddr3_ck_n,
    output wire [0:0] ddr3_cke, output wire [0:0] ddr3_cs_n,
    output wire [1:0] ddr3_dm, output wire [0:0] ddr3_odt,
    input wire eth_rxc, input wire eth_rx_ctl, input wire [3:0] eth_rxd,
    output wire eth_txc, output wire eth_tx_ctl, output wire [3:0] eth_txd,
    output wire eth_rst_n, output wire [1:0] led
);
    localparam integer BURST_BYTES = 1024;
    localparam integer RING_BYTES  = 262144;
    parameter LOCAL_MAC_ADDR=48'h02_00_00_00_00_11;
    parameter TARGET_MAC_ADDR=48'hff_ff_ff_ff_ff_ff;
    parameter LOCAL_IP_ADDR={8'd192,8'd168,8'd1,8'd11};
    parameter TARGET_IP_ADDR={8'd192,8'd168,8'd1,8'd100};
    parameter LOCAL_PORT=16'd8888;
    parameter TARGET_PORT=16'd6666;

    wire clk_125m, clk_150m, clk_200m, clock_reset;
    wire reset = clock_reset | ~sys_rst_n;
    wire ui_clk, ui_clk_sync_rst, init_calib_complete;
    wire adma_reset = reset | ui_clk_sync_rst;

    wire source_valid,source_ready; wire [15:0] source_data;
    wire [63:0] source_total_words;
    wire ingress_out_valid,ingress_out_ready,ingress_has_burst;
    wire [15:0] ingress_out_data; wire [11:0] ingress_level_words;
    wire ingress_high_water,ingress_low_water,source_run,ingress_drain_busy;
    wire [31:0] ingress_overflow_count,ingress_underflow_count;
    wire [31:0] ingress_completed_bursts,ingress_starvation_count;
    wire user_wr_en; wire [15:0] user_wr_data;
    wire write_grant_toggle;
    wire user_rd_req, user_rd_req_busy, user_rd_valid, user_rd_last;
    wire [7:0] user_rd_data;

    wire [3:0] awid,bid,arid,rid; wire [31:0] awaddr,araddr;
    wire [7:0] awlen,arlen; wire [2:0] awsize,awprot,arsize,arprot;
    wire [1:0] awburst,bresp,arburst,rresp;
    wire awlock,awvalid,awready,wlast,wvalid,wready,bvalid,bready;
    wire arlock,arvalid,arready,rlast,rvalid,rready;
    wire [3:0] awcache,awqos,arcache,arqos;
    wire [127:0] wdata,rdata; wire [15:0] wstrb;

    wire wr_cmd_fifo_err,wr_data_fifo_err,rd_cmd_fifo_err,rd_data_fifo_err;
    wire tx_burst_space_available,tx_burst_committed,packet_done,packetizer_error;
    wire [31:0] packet_sequence; wire [13:0] tx_fifo_byte_count;
    wire [3:0] tx_fifo_packet_count;
    wire [31:0] tx_overflow_count,tx_underflow_count;
    wire app_tx_data_vld,app_tx_data_last,app_tx_ready;
    wire [7:0] app_tx_data; wire [15:0] app_tx_length;

    wire ring_started,write_inflight,read_inflight,drain_active;
    wire [31:0] write_pointer,read_pointer,occupancy_bytes;
    wire [63:0] committed_bytes,released_bytes;
    wire ring_full,ring_empty; wire [31:0] write_stall_cycles,read_stall_cycles;
    wire [31:0] ring_overflow_count,ring_underflow_count;
    wire fatal_error;

    wire phy_rx_clk,gmii_rx_data_error,gmii_rx_data_vld,gmii_tx_data_vld;
    wire [7:0] gmii_rx_data,gmii_tx_data;
    reg [21:0] phy_reset_counter; reg phy_reset_released;
    reg start_meta,start_sync,start_sync_d;
    wire manual_start_pulse = start_sync_d && !start_sync;

    wire control_run_enable, control_finite_mode, control_finite_done;
    wire [7:0] control_source_select;
    wire [31:0] control_rate_words_per_sec, control_finite_words;
    wire [31:0] control_run_words, control_crc_errors, control_rejects;
    wire [15:0] control_packet_length;
    wire control_clear_toggle, control_status_request_toggle;
    reg clear_seen_125;
    wire clear_125 = control_clear_toggle != clear_seen_125;
    reg clear_meta_ui,clear_sync_ui,clear_seen_ui;
    wire clear_ui = clear_sync_ui != clear_seen_ui;
    reg [15:0] packet_length_meta_ui,packet_length_ui;
    reg pipeline_idle_meta,pipeline_idle_sync;
    wire pipeline_idle_ui = ring_empty && !write_inflight && !read_inflight &&
                            tx_fifo_byte_count == 0;
    wire pipeline_idle_125 = pipeline_idle_sync && ingress_level_words == 0 &&
                             !ingress_drain_busy;
    wire flush_ingress = !control_run_enable && !ingress_drain_busy &&
                         !ingress_has_burst && ingress_level_words != 0;

    wire ui_status_ack_toggle;
    wire [326:0] ui_status_snapshot_async;
    reg ui_status_ack_meta,ui_status_ack_sync;
    reg [326:0] ui_status_meta,ui_status_sync;

    assign eth_rst_n=phy_reset_released;
    assign led[0]=init_calib_complete;
    assign led[1]=control_run_enable && !fatal_error;

    clock_and_reset u_clock_and_reset(.clkin_50m(sys_clk),.clkout_125m(clk_125m),
        .clkout_150m(clk_150m),.clkout_200m(clk_200m),.reset(clock_reset));

    always @(posedge clk_125m or posedge reset) begin
        if(reset) begin phy_reset_counter<=0; phy_reset_released<=0; end
        else if(phy_reset_counter<22'd2_500_000) phy_reset_counter<=phy_reset_counter+1'b1;
        else phy_reset_released<=1'b1;
    end

    always @(posedge clk_125m or posedge reset) begin
        if(reset) begin
            start_meta<=1; start_sync<=1; start_sync_d<=1;
            clear_seen_125<=0;
            pipeline_idle_meta<=0; pipeline_idle_sync<=0;
            ui_status_ack_meta<=0; ui_status_ack_sync<=0;
            ui_status_meta<=0; ui_status_sync<=0;
        end
        else begin
            start_meta<=start_n; start_sync<=start_meta; start_sync_d<=start_sync;
            if(clear_125) clear_seen_125<=control_clear_toggle;
            pipeline_idle_meta<=pipeline_idle_ui;
            pipeline_idle_sync<=pipeline_idle_meta;
            ui_status_ack_meta<=ui_status_ack_toggle;
            ui_status_ack_sync<=ui_status_ack_meta;
            ui_status_meta<=ui_status_snapshot_async;
            ui_status_sync<=ui_status_meta;
        end
    end

    always @(posedge ui_clk) begin
        if(adma_reset) begin
            clear_meta_ui<=0; clear_sync_ui<=0; clear_seen_ui<=0;
            packet_length_meta_ui<=16'd1024;
            packet_length_ui<=16'd1024;
        end else begin
            clear_meta_ui<=control_clear_toggle;
            clear_sync_ui<=clear_meta_ui;
            if(clear_ui) clear_seen_ui<=clear_sync_ui;
            packet_length_meta_ui<=control_packet_length;
            packet_length_ui<=packet_length_meta_ui;
        end
    end

    v7_uart_control #(.CLK_HZ(125000000),.BAUD(115200)) u_uart_control(
        .clk(clk_125m),.reset(reset),.uart_rxd(uart_rxd),.uart_txd(uart_txd),
        .manual_start_pulse(manual_start_pulse),.finite_done(control_finite_done),
        .pipeline_idle(pipeline_idle_125),.run_words(control_run_words),
        .total_words(source_total_words),.ingress_level_words(ingress_level_words),
        .ingress_overflow_count(ingress_overflow_count),
        .ingress_underflow_count(ingress_underflow_count),
        .ui_status_snapshot(ui_status_sync),
        .ui_status_ack_toggle(ui_status_ack_sync),
        .run_enable(control_run_enable),.source_select(control_source_select),
        .rate_words_per_sec(control_rate_words_per_sec),
        .packet_length(control_packet_length),.finite_mode(control_finite_mode),
        .finite_words(control_finite_words),.clear_toggle(control_clear_toggle),
        .status_request_toggle(control_status_request_toggle),
        .crc_error_count(control_crc_errors),
        .command_reject_count(control_rejects));

    v7_rate_controlled_prbs #(.CLK_HZ(125000000),.PRBS_SEED(16'hACE1)) u_source(
        .clk(clk_125m),.reset(reset),.clear_counters(clear_125),
        .enable(control_run_enable && source_run),
        .ready(source_ready),.valid(source_valid),.data(source_data),
        .rate_words_per_sec(control_rate_words_per_sec),
        .finite_mode(control_finite_mode),.finite_words(control_finite_words),
        .finite_done(control_finite_done),.run_words(control_run_words),
        .total_words(source_total_words));

    v6_ingress_fifo #(.DEPTH_WORDS(2048),.HIGH_WATER_WORDS(1536),
        .LOW_WATER_WORDS(512),.BURST_WORDS(BURST_BYTES/2)) u_ingress_fifo(
        .clk(clk_125m),.reset(reset),.clear_counters(clear_125),
        .flush(flush_ingress),.enable(control_run_enable),
        .in_valid(source_valid),.in_data(source_data),.in_ready(source_ready),
        .out_ready(ingress_out_ready),.out_valid(ingress_out_valid),
        .out_data(ingress_out_data),.level_words(ingress_level_words),
        .has_burst(ingress_has_burst),.high_water(ingress_high_water),
        .low_water(ingress_low_water),.source_run(source_run),
        .overflow_count(ingress_overflow_count),.underflow_count(ingress_underflow_count));

    v6_ingress_drain #(.BURST_WORDS(BURST_BYTES/2)) u_ingress_drain(
        .clk(clk_125m),.reset(reset),.clear_counters(clear_125),.enable(1'b1),
        .grant_toggle_async(write_grant_toggle),.fifo_valid(ingress_out_valid),
        .fifo_data(ingress_out_data),.fifo_ready(ingress_out_ready),
        .user_wr_en(user_wr_en),.user_wr_data(user_wr_data),.busy(ingress_drain_busy),
        .completed_bursts(ingress_completed_bursts),
        .starvation_count(ingress_starvation_count));

    axi_adma_v1 #(.USER_RD_DATA_WIDTH(8),.USER_WR_DATA_WIDTH(16),
        .AXI_DATA_WIDTH(128),.AXI_ADDR_WIDTH(32)) u_adma(
        .user_wr_clk(clk_125m),.user_rd_clk(ui_clk),.axi_clk(ui_clk),
        .reset(adma_reset),.ddr_init_done(init_calib_complete),
        .user_wr_en(user_wr_en),.user_wr_data(user_wr_data),
        .user_wr_base_addr(32'h0),.user_wr_end_addr(RING_BYTES),
        .user_rd_req(user_rd_req),.user_rd_base_addr(32'h0),.user_rd_end_addr(RING_BYTES),
        .user_rd_req_busy(user_rd_req_busy),.user_rd_valid(user_rd_valid),
        .user_rd_last(user_rd_last),.user_rd_data(user_rd_data),
        .m_axi_awvalid(awvalid),.m_axi_awready(awready),.m_axi_awaddr(awaddr),
        .m_axi_awid(awid),.m_axi_awlen(awlen),.m_axi_awburst(awburst),
        .m_axi_awsize(awsize),.m_axi_awport(awprot),.m_axi_awqos(awqos),
        .m_axi_awlock(awlock),.m_axi_awcache(awcache),.m_axi_wvalid(wvalid),
        .m_axi_wready(wready),.m_axi_wdata(wdata),.m_axi_wstrb(wstrb),
        .m_axi_wlast(wlast),.m_axi_bid(bid),.m_axi_bresp(bresp),
        .m_axi_bvalid(bvalid),.m_axi_bready(bready),.m_axi_arvalid(arvalid),
        .m_axi_arready(arready),.m_axi_araddr(araddr),.m_axi_arid(arid),
        .m_axi_arlen(arlen),.m_axi_arburst(arburst),.m_axi_arsize(arsize),
        .m_axi_arport(arprot),.m_axi_arqos(arqos),.m_axi_arlock(arlock),
        .m_axi_arcache(arcache),.m_axi_rid(rid),.m_axi_rvalid(rvalid),
        .m_axi_rready(rready),.m_axi_rdata(rdata),.m_axi_rlast(rlast),
        .m_axi_rresp(rresp),.wr_cmd_fifo_err(wr_cmd_fifo_err),
        .wr_data_fifo_err(wr_data_fifo_err),.rd_cmd_fifo_err(rd_cmd_fifo_err),
        .rd_data_fifo_err(rd_data_fifo_err));

    ddr3_axi_mig_wrapper u_ddr3(
        .sys_clk_200m(clk_200m),.sys_reset_n(~reset),.ddr3_dq(ddr3_dq),
        .ddr3_dqs_n(ddr3_dqs_n),.ddr3_dqs_p(ddr3_dqs_p),.ddr3_addr(ddr3_addr),
        .ddr3_ba(ddr3_ba),.ddr3_ras_n(ddr3_ras_n),.ddr3_cas_n(ddr3_cas_n),
        .ddr3_we_n(ddr3_we_n),.ddr3_reset_n(ddr3_reset_n),.ddr3_ck_p(ddr3_ck_p),
        .ddr3_ck_n(ddr3_ck_n),.ddr3_cke(ddr3_cke),.ddr3_cs_n(ddr3_cs_n),
        .ddr3_dm(ddr3_dm),.ddr3_odt(ddr3_odt),.ui_clk(ui_clk),
        .ui_clk_sync_rst(ui_clk_sync_rst),.init_calib_complete(init_calib_complete),
        .s_axi_awid(awid),.s_axi_awaddr(awaddr[27:0]),.s_axi_awlen(awlen),
        .s_axi_awsize(awsize),.s_axi_awburst(awburst),.s_axi_awlock(awlock),
        .s_axi_awcache(awcache),.s_axi_awprot(awprot),.s_axi_awqos(awqos),
        .s_axi_awvalid(awvalid),.s_axi_awready(awready),.s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb),.s_axi_wlast(wlast),.s_axi_wvalid(wvalid),
        .s_axi_wready(wready),.s_axi_bid(bid),.s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid),.s_axi_bready(bready),.s_axi_arid(arid),
        .s_axi_araddr(araddr[27:0]),.s_axi_arlen(arlen),.s_axi_arsize(arsize),
        .s_axi_arburst(arburst),.s_axi_arlock(arlock),.s_axi_arcache(arcache),
        .s_axi_arprot(arprot),.s_axi_arqos(arqos),.s_axi_arvalid(arvalid),
        .s_axi_arready(arready),.s_axi_rid(rid),.s_axi_rdata(rdata),
        .s_axi_rresp(rresp),.s_axi_rlast(rlast),.s_axi_rvalid(rvalid),.s_axi_rready(rready));

    v6_pipeline_controller #(.BASE_ADDR(0),.RING_BYTES(RING_BYTES),
        .BURST_BYTES(BURST_BYTES),.DDR_HIGH_WATER_BYTES(65536),
        .DDR_LOW_WATER_BYTES(16384)) u_ring(
        .clk(ui_clk),.reset(adma_reset),.start_async(control_run_enable),
        .clear_counters(clear_ui),
        .init_calib_complete(init_calib_complete),
        .ingress_has_burst_async(ingress_has_burst),.axi_bvalid(bvalid),
        .axi_bready(bready),.axi_bresp(bresp),.user_rd_req_busy(user_rd_req_busy),
        .tx_burst_committed(tx_burst_committed),
        .tx_burst_space_available(tx_burst_space_available),
        .packetizer_error(packetizer_error),.wr_cmd_fifo_err(wr_cmd_fifo_err),
        .wr_data_fifo_err(wr_data_fifo_err),.rd_cmd_fifo_err(rd_cmd_fifo_err),
        .rd_data_fifo_err(rd_data_fifo_err),.write_grant_toggle(write_grant_toggle),
        .user_rd_req(user_rd_req),.started(ring_started),
        .write_inflight(write_inflight),.read_inflight(read_inflight),
        .drain_active(drain_active),
        .write_pointer(write_pointer),.read_pointer(read_pointer),
        .committed_bytes(committed_bytes),.released_bytes(released_bytes),
        .occupancy_bytes(occupancy_bytes),.ring_full(ring_full),.ring_empty(ring_empty),
        .write_stall_cycles(write_stall_cycles),.read_stall_cycles(read_stall_cycles),
        .ring_overflow_count(ring_overflow_count),
        .ring_underflow_count(ring_underflow_count),
        .fatal_error(fatal_error));

    // Controlled-host speed characterization step.
    // An additional 950 UI-clock cycles targets about 400 Mb/s while retaining
    // the same packet format, DDR ring flow and backpressure behavior.
    udp_v7_tx_fifo_packetizer #(.BURST_BYTES(BURST_BYTES),.FIFO_BURSTS(8),
        .POST_READY_IDLE_CYCLES(950)) u_packetizer(
        .clk(ui_clk),.reset(adma_reset),.clear_counters(clear_ui),
        .configured_payload_bytes(packet_length_ui),.user_rd_valid(user_rd_valid),
        .user_rd_last(user_rd_last),.user_rd_data(user_rd_data),
        .committed_bytes_low(committed_bytes[31:0]),.occupancy_bytes(occupancy_bytes),
        .stream_expected(drain_active),
        .burst_space_available(tx_burst_space_available),
        .burst_committed(tx_burst_committed),.packet_done(packet_done),
        .packet_sequence(packet_sequence),.framing_error(packetizer_error),
        .fifo_byte_count(tx_fifo_byte_count),.fifo_packet_count(tx_fifo_packet_count),
        .overflow_count(tx_overflow_count),.underflow_count(tx_underflow_count),
        .app_tx_data_vld(app_tx_data_vld),.app_tx_data_last(app_tx_data_last),
        .app_tx_data(app_tx_data),.app_tx_length(app_tx_length),.app_tx_ready(app_tx_ready));

    v7_ui_status_snapshot u_status_snapshot(
        .ui_clk(ui_clk),.reset(adma_reset),
        .request_toggle_async(control_status_request_toggle),
        .init_calib_complete(init_calib_complete),.ring_started(ring_started),
        .drain_active(drain_active),.write_inflight(write_inflight),
        .read_inflight(read_inflight),.ring_full(ring_full),
        .fatal_error(fatal_error),.occupancy_bytes(occupancy_bytes),
        .packet_sequence(packet_sequence),.ring_overflow_count(ring_overflow_count),
        .ring_underflow_count(ring_underflow_count),
        .tx_overflow_count(tx_overflow_count),.tx_underflow_count(tx_underflow_count),
        .write_stall_cycles(write_stall_cycles),.read_stall_cycles(read_stall_cycles),
        .committed_bytes_low(committed_bytes[31:0]),
        .released_bytes_low(released_bytes[31:0]),
        .acknowledge_toggle(ui_status_ack_toggle),
        .snapshot_data(ui_status_snapshot_async));

    rgmii_interface u_rgmii(.reset(reset),.idelay_refclk(clk_200m),
        .phy_rgmii_rx_clk(eth_rxc),.phy_rgmii_rx_ctl(eth_rx_ctl),
        .phy_rgmii_rx_data(eth_rxd),.phy_rgmii_tx_clk(eth_txc),
        .phy_rgmii_tx_ctl(eth_tx_ctl),.phy_rgmii_tx_data(eth_txd),
        .phy_rx_clk(phy_rx_clk),.gmii_rx_data_error(gmii_rx_data_error),
        .gmii_rx_data_vld(gmii_rx_data_vld),.gmii_rx_data(gmii_rx_data),
        .phy_tx_clk(clk_125m),.gmii_tx_data_vld(gmii_tx_data_vld),
        .gmii_tx_data(gmii_tx_data));

    udp_protocol_stack #(.LOCAL_MAC_ADDR(LOCAL_MAC_ADDR),.TARGET_MAC_ADDR(TARGET_MAC_ADDR),
        .LOCAL_IP_ADDR(LOCAL_IP_ADDR),.TARGET_IP_ADDR(TARGET_IP_ADDR),
        .LOCAL_PORT(LOCAL_PORT),.TARGET_PORT(TARGET_PORT)) u_udp(
        .phy_tx_clk(clk_125m),.phy_rx_clk(phy_rx_clk),.reset(reset),
        .gmii_rx_data_vld(gmii_rx_data_vld),.gmii_rx_data(gmii_rx_data),
        .gmii_tx_data_vld(gmii_tx_data_vld),.gmii_tx_data(gmii_tx_data),
        .app_rx_clk(clk_125m),.app_rx_data_vld(),.app_rx_data_last(),
        .app_rx_data(),.app_rx_length(),.app_tx_clk(ui_clk),
        .app_tx_data_vld(app_tx_data_vld),.app_tx_data_last(app_tx_data_last),
        .app_tx_data(app_tx_data),.app_tx_length(app_tx_length),.app_tx_ready(app_tx_ready));

    ila_v6 u_ila(.clk(ui_clk),.probe0(init_calib_complete),.probe1(ring_started),
        .probe2(ingress_level_words),.probe3(source_run),.probe4(ingress_has_burst),
        .probe5(ingress_overflow_count),.probe6(ingress_underflow_count),
        .probe7(ingress_drain_busy),.probe8(write_inflight),.probe9(read_inflight),
        .probe10(drain_active),.probe11(write_pointer),.probe12(read_pointer),
        .probe13(occupancy_bytes),.probe14(committed_bytes[31:0]),
        .probe15(released_bytes[31:0]),.probe16(tx_fifo_byte_count),
        .probe17(tx_fifo_packet_count),.probe18(tx_burst_space_available),
        .probe19(packet_done),.probe20(packet_sequence),.probe21(ring_full),
        .probe22(ring_empty),.probe23(write_stall_cycles),.probe24(read_stall_cycles),
        .probe25(ring_overflow_count),.probe26(ring_underflow_count),
        .probe27(tx_overflow_count),.probe28(tx_underflow_count),.probe29(fatal_error),
        .probe30(bvalid),.probe31(bready),.probe32(arvalid),.probe33(arready),
        .probe34(rvalid),.probe35(rlast),.probe36(awvalid),.probe37(wvalid),
        .probe38(tx_burst_committed));
endmodule

