// -----------------------------------------------------------------------------
// Author : XiaoBai FPGA 
// File   : axi_rd_channel.v
// Create : 2023-12-30 16:40:14
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module axi_rd_channel #(
	parameter	AXI_DATA_WIDTH      = 128,
	parameter   AXI_ADDR_WIDTH      = 32 ,
	parameter   USER_RD_DATA_WIDTH	= 16

)(
	input                              user_rd_clk       , //用户端读时钟
	input                              axi_clk           , //axi的时钟
	input                              reset             ,

	input                              ddr_init_done     ,

    /*--------------用户端读请求信号----------------------*/
    input                              user_rd_req        , //上升沿触发用户读请求
    input    [AXI_ADDR_WIDTH-1:0]      user_rd_base_addr  , //一定要被4096整除
    input    [AXI_ADDR_WIDTH-1:0]      user_rd_end_addr   , //一定要被4096整除
    output                             user_rd_req_busy   , //用户读请求忙标志	
	output  						   user_rd_valid      ,
	output                             user_rd_last       ,
	output   [USER_RD_DATA_WIDTH-1:0]  user_rd_data       ,

    /*-------------AXI读通道端口信号---------------------*/
 	output                             m_axi_arvalid     ,
 	input                              m_axi_arready     ,
 	output   [AXI_ADDR_WIDTH-1:0]      m_axi_araddr      ,
 	output   [3:0]                     m_axi_arid        ,
 	output   [7:0]                     m_axi_arlen       ,
 	output   [1:0]                     m_axi_arburst     ,
 	output   [2:0]                     m_axi_arsize      ,
 	output   [2:0]                     m_axi_arport      ,
 	output   [3:0]                     m_axi_arqos       ,
 	output                             m_axi_arlock      ,
 	output   [3:0]                     m_axi_arcache     ,

    input    [3:0]                     m_axi_rid         ,
    input                              m_axi_rvalid      ,
    output                             m_axi_rready      ,
    input    [AXI_DATA_WIDTH-1:0]      m_axi_rdata       ,
    input                              m_axi_rlast       ,
    input    [1:0]                     m_axi_rresp       ,

	/*--------------fifo错误信号------------------------*/	 
 	output                             rd_cmd_fifo_err   ,
 	output                             rd_data_fifo_err     
    );

	wire                          rd_req_en       ;
	wire                [7:0]     rd_burst_length ;
	wire [AXI_ADDR_WIDTH-1:0]     rd_data_addr    ;
	wire                          rd_req_ready    ;

	wire                          axi_ar_req_en   ;
	wire                          axi_ar_ready    ;
	wire [7:0]                    axi_ar_burst_len;
	wire [AXI_ADDR_WIDTH-1:0]     axi_ar_addr     ;
	wire                          axi_r_valid     ;
	wire [AXI_DATA_WIDTH-1:0]     axi_r_data      ;
	wire                          axi_r_last      ;

	rd_ctrl #(
			.AXI_DATA_WIDTH(AXI_DATA_WIDTH),
			.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
			.RD_BURST_LENGTH(1024)
		) rd_ctrl (
			.clk               (user_rd_clk),
			.reset             (reset),

			.ddr_init_done     (ddr_init_done),

			.user_rd_req       (user_rd_req),
			.user_rd_base_addr (user_rd_base_addr),
			.user_rd_end_addr  (user_rd_end_addr),
			.user_rd_req_busy  (user_rd_req_busy),

			.rd_req_en         (rd_req_en),
			.rd_burst_length   (rd_burst_length),
			.rd_data_addr      (rd_data_addr),
			.rd_req_ready      (rd_req_ready)
		);

	rd_buffer #(
			.AXI_DATA_WIDTH(AXI_DATA_WIDTH),
			.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
			.USER_RD_DATA_WIDTH(USER_RD_DATA_WIDTH)
		) rd_buffer (
			.clk              (user_rd_clk),
			.axi_clk          (axi_clk),
			.reset            (reset),

			.rd_req_en        (rd_req_en),
			.rd_burst_length  (rd_burst_length),
			.rd_data_addr     (rd_data_addr),
			.rd_req_ready     (rd_req_ready),

			.axi_ar_req_en    (axi_ar_req_en),
			.axi_ar_ready     (axi_ar_ready),
			.axi_ar_burst_len (axi_ar_burst_len),
			.axi_ar_addr      (axi_ar_addr),
			.axi_r_valid      (axi_r_valid),
			.axi_r_data       (axi_r_data),
			.axi_r_last       (axi_r_last),

			.user_rd_valid    (user_rd_valid),
			.user_rd_last     (user_rd_last),
			.user_rd_data     (user_rd_data),

			.rd_cmd_fifo_err  (rd_cmd_fifo_err),
			.rd_data_fifo_err (rd_data_fifo_err)
		);

	axi_rd_master #(
			.AXI_DATA_WIDTH(AXI_DATA_WIDTH),
			.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
		) axi_rd_master (
			.axi_clk          (axi_clk),
			.reset            (reset),

			.axi_ar_req_en    (axi_ar_req_en),
			.axi_ar_ready     (axi_ar_ready),
			.axi_ar_burst_len (axi_ar_burst_len),
			.axi_ar_addr      (axi_ar_addr),
			.axi_r_valid      (axi_r_valid),
			.axi_r_data       (axi_r_data),
			.axi_r_last       (axi_r_last),

			.m_axi_arvalid    (m_axi_arvalid),
			.m_axi_arready    (m_axi_arready),
			.m_axi_araddr     (m_axi_araddr),
			.m_axi_arid       (m_axi_arid),
			.m_axi_arlen      (m_axi_arlen),
			.m_axi_arburst    (m_axi_arburst),
			.m_axi_arsize     (m_axi_arsize),
			.m_axi_arport     (m_axi_arport),
			.m_axi_arqos      (m_axi_arqos),
			.m_axi_arlock     (m_axi_arlock),
			.m_axi_arcache    (m_axi_arcache),

			.m_axi_rid        (m_axi_rid),
			.m_axi_rvalid     (m_axi_rvalid),
			.m_axi_rready     (m_axi_rready),
			.m_axi_rdata      (m_axi_rdata),
			.m_axi_rlast      (m_axi_rlast),
			.m_axi_rresp      (m_axi_rresp)
		);



endmodule
