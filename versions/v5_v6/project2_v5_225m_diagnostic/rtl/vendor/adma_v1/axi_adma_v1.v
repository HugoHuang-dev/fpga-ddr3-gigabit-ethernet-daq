// -----------------------------------------------------------------------------
// File   : axi_adma_v1.v
// Create : 2023-12-30 16:53:01
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module axi_adma_v1 #(
	parameter	AXI_DATA_WIDTH      = 128,
	parameter   AXI_ADDR_WIDTH      = 32 ,
	parameter   USER_RD_DATA_WIDTH	= 16 ,
	parameter   USER_WR_DATA_WIDTH  = 16  

)(
	input                              user_wr_clk       , //用户端写时钟
	input                              user_rd_clk       , //用户端读时钟	
	input                              axi_clk           , // AXI4端时钟
	input                              reset             ,

    /*-----DDR初始化完成信号，与MIG核交互------------------*/
	input                              ddr_init_done     ,

    /*-------------用户端口信号---------------------------*/
	input                              user_wr_en        ,
	input   [USER_WR_DATA_WIDTH-1:0]   user_wr_data      ,
	input   [AXI_ADDR_WIDTH-1:0]       user_wr_base_addr , //一定要被4096整除
	input   [AXI_ADDR_WIDTH-1:0]       user_wr_end_addr  , //一定要被4096整除	

    input                              user_rd_req       , //上升沿触发用户读请求
    input    [AXI_ADDR_WIDTH-1:0]      user_rd_base_addr , //一定要被4096整除
    input    [AXI_ADDR_WIDTH-1:0]      user_rd_end_addr  , //一定要被4096整除
    output                             user_rd_req_busy  , //用户读请求忙标志	
	output  						   user_rd_valid     ,
	output                             user_rd_last      ,
	output   [USER_RD_DATA_WIDTH-1:0]  user_rd_data      ,

    /*-------------AXI写通道端口信号---------------------*/
 	output                             m_axi_awvalid     ,
 	input                              m_axi_awready     ,
 	output  [AXI_ADDR_WIDTH-1:0]       m_axi_awaddr      ,
 	output  [3:0]                      m_axi_awid        ,
 	output  [7:0]                      m_axi_awlen       ,
 	output  [1:0]                      m_axi_awburst     ,
 	output  [2:0]                      m_axi_awsize      ,
 	output  [2:0]                      m_axi_awport      ,
 	output  [3:0]                      m_axi_awqos       ,
 	output                             m_axi_awlock      ,
 	output  [3:0]                      m_axi_awcache     ,

 	output                             m_axi_wvalid      ,
 	input                              m_axi_wready      ,
 	output  [AXI_DATA_WIDTH-1:0]       m_axi_wdata       ,
 	output  [AXI_DATA_WIDTH/8-1:0]     m_axi_wstrb       ,   	
 	output                             m_axi_wlast  	 ,

    input      [3:0]                   m_axi_bid         ,
    input      [1:0]                   m_axi_bresp       ,
    input                              m_axi_bvalid      ,
    output                             m_axi_bready      , 	

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

    // Project2 v4 observability: expose the sticky FIFO error flags that
    // are latched by the ADMA FIFO control logic.
    output                             wr_cmd_fifo_err  ,
    output                             wr_data_fifo_err ,
    output                             rd_cmd_fifo_err  ,
    output                             rd_data_fifo_err

    );

	axi_wr_channel #(
			.USER_WR_DATA_WIDTH(USER_WR_DATA_WIDTH),
			.AXI_DATA_WIDTH    (AXI_DATA_WIDTH),
			.AXI_ADDR_WIDTH    (AXI_ADDR_WIDTH)
		) axi_wr_channel (
			.user_wr_clk       (user_wr_clk),
			.axi_clk           (axi_clk),
			.reset             (reset),

			.ddr_init_done     (ddr_init_done),

			.user_wr_en        (user_wr_en),
			.user_wr_data      (user_wr_data),
			.user_wr_base_addr (user_wr_base_addr),
			.user_wr_end_addr  (user_wr_end_addr),

			.m_axi_awvalid     (m_axi_awvalid),
			.m_axi_awready     (m_axi_awready),
			.m_axi_awaddr      (m_axi_awaddr),
			.m_axi_awid        (m_axi_awid),
			.m_axi_awlen       (m_axi_awlen),
			.m_axi_awburst     (m_axi_awburst),
			.m_axi_awsize      (m_axi_awsize),
			.m_axi_awport      (m_axi_awport),
			.m_axi_awqos       (m_axi_awqos),
			.m_axi_awlock      (m_axi_awlock),
			.m_axi_awcache     (m_axi_awcache),

			.m_axi_wvalid      (m_axi_wvalid),
			.m_axi_wready      (m_axi_wready),
			.m_axi_wdata       (m_axi_wdata),
			.m_axi_wstrb       (m_axi_wstrb),
			.m_axi_wlast       (m_axi_wlast),

		    .m_axi_bid         (m_axi_bid)   ,
			.m_axi_bresp       (m_axi_bresp) ,
			.m_axi_bvalid      (m_axi_bvalid),
			.m_axi_bready      (m_axi_bready),

			.wr_cmd_fifo_err   (wr_cmd_fifo_err),
			.wr_data_fifo_err  (wr_data_fifo_err)
		);

	axi_rd_channel #(
			.AXI_DATA_WIDTH    (AXI_DATA_WIDTH),
			.AXI_ADDR_WIDTH    (AXI_ADDR_WIDTH),
			.USER_RD_DATA_WIDTH(USER_RD_DATA_WIDTH)
		) axi_rd_channel (
			.user_rd_clk       (user_rd_clk),
			.axi_clk           (axi_clk),
			.reset             (reset),

			.ddr_init_done     (ddr_init_done),

			.user_rd_req       (user_rd_req),
			.user_rd_base_addr (user_rd_base_addr),
			.user_rd_end_addr  (user_rd_end_addr),
			.user_rd_req_busy  (user_rd_req_busy),
			.user_rd_valid     (user_rd_valid),
			.user_rd_last      (user_rd_last),
			.user_rd_data      (user_rd_data),

			.m_axi_arvalid     (m_axi_arvalid),
			.m_axi_arready     (m_axi_arready),
			.m_axi_araddr      (m_axi_araddr),
			.m_axi_arid        (m_axi_arid),
			.m_axi_arlen       (m_axi_arlen),
			.m_axi_arburst     (m_axi_arburst),
			.m_axi_arsize      (m_axi_arsize),
			.m_axi_arport      (m_axi_arport),
			.m_axi_arqos       (m_axi_arqos),
			.m_axi_arlock      (m_axi_arlock),
			.m_axi_arcache     (m_axi_arcache),

			.m_axi_rid         (m_axi_rid),
			.m_axi_rvalid      (m_axi_rvalid),
			.m_axi_rready      (m_axi_rready),
			.m_axi_rdata       (m_axi_rdata),
			.m_axi_rlast       (m_axi_rlast),
			.m_axi_rresp       (m_axi_rresp),

			.rd_cmd_fifo_err   (rd_cmd_fifo_err),
			.rd_data_fifo_err  (rd_data_fifo_err)
		);







endmodule
