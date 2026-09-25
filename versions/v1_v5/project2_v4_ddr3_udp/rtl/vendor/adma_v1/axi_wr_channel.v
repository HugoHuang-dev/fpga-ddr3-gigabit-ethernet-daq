// -----------------------------------------------------------------------------
// File   : axi_wr_channel.v
// Create : 2023-12-29 13:35:19
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module axi_wr_channel #(
	parameter		USER_WR_DATA_WIDTH = 16  ,
	parameter       AXI_DATA_WIDTH     = 128 ,
	parameter       AXI_ADDR_WIDTH     = 32  
)(
	input                              user_wr_clk       , //用户端写时钟
	input                              axi_clk           , // AXI4端时钟
	input                              reset             ,

	input                              ddr_init_done     ,

    /*-------------用户写端口信号------------------------*/
	input                              user_wr_en        ,
	input   [USER_WR_DATA_WIDTH-1:0]   user_wr_data      ,
	input   [AXI_ADDR_WIDTH-1:0]       user_wr_base_addr , //一定要被4096整除
	input   [AXI_ADDR_WIDTH-1:0]       user_wr_end_addr  , //一定要被4096整除	


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
    /*-------------FIFO错误信号--------------------------*/
 	output                             wr_cmd_fifo_err   ,
 	output                             wr_data_fifo_err  

    ); 

	wire                          wr_req_en;
	wire [7:0]                    wr_burst_length;
	wire [AXI_ADDR_WIDTH-1:0]     wr_data_addr;
	wire                          wr_data_valid;
	wire [AXI_DATA_WIDTH-1:0]     wr_data_out;
	wire                          wr_data_last;

	wire                          axi_aw_req_en;
	wire                      	  axi_aw_ready;
	wire [7:0] 	  				  axi_aw_burst_len;
	wire [AXI_ADDR_WIDTH-1:0] 	  axi_aw_addr;
	wire                      	  axi_w_valid;
	wire                      	  axi_w_ready;
	wire [AXI_DATA_WIDTH-1:0] 	  axi_w_data;
	wire                      	  axi_w_last;

	wr_ctrl #(
			.USER_WR_DATA_WIDTH(USER_WR_DATA_WIDTH),
			.AXI_DATA_WIDTH(AXI_DATA_WIDTH),
			.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
			.WR_BURST_LENGTH(1024)
		) wr_ctrl (
			.clk               (user_wr_clk),
			.reset             (reset),

			.ddr_init_done     (ddr_init_done),

			.user_wr_en        (user_wr_en),
			.user_wr_data      (user_wr_data),
			.user_wr_base_addr (user_wr_base_addr),
			.user_wr_end_addr  (user_wr_end_addr),

			.wr_req_en         (wr_req_en),
			.wr_burst_length   (wr_burst_length),
			.wr_data_addr      (wr_data_addr),
			.wr_data_valid     (wr_data_valid),
			.wr_data_out       (wr_data_out),
			.wr_data_last      (wr_data_last)
		);


	wr_buffer #(
			.AXI_DATA_WIDTH(AXI_DATA_WIDTH),
			.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
		) wr_buffer (
			.clk              (user_wr_clk),
			.axi_clk          (axi_clk),
			.reset            (reset),

			.wr_req_en        (wr_req_en),
			.wr_burst_length  (wr_burst_length),
			.wr_data_addr     (wr_data_addr),
			.wr_data_valid    (wr_data_valid),
			.wr_data_in       (wr_data_out),
			.wr_data_last     (wr_data_last),

			.axi_aw_req_en    (axi_aw_req_en),
			.axi_aw_ready     (axi_aw_ready),
			.axi_aw_burst_len (axi_aw_burst_len),
			.axi_aw_addr      (axi_aw_addr),			
			.axi_w_valid      (axi_w_valid),
			.axi_w_ready      (axi_w_ready),
			.axi_w_data       (axi_w_data),
			.axi_w_last       (axi_w_last),

			.wr_cmd_fifo_err  (wr_cmd_fifo_err),
			.wr_data_fifo_err (wr_data_fifo_err)
		);

	axi_wr_master #(
			.AXI_DATA_WIDTH(AXI_DATA_WIDTH),
			.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
		) axi_wr_master (
			.axi_clk          (axi_clk),
			.reset            (reset),

			.axi_aw_req_en    (axi_aw_req_en),
			.axi_aw_ready     (axi_aw_ready),
			.axi_aw_burst_len (axi_aw_burst_len),
			.axi_aw_addr      (axi_aw_addr),
			.axi_w_valid      (axi_w_valid),
			.axi_w_ready      (axi_w_ready),
			.axi_w_data       (axi_w_data),
			.axi_w_last       (axi_w_last),

			.m_axi_awvalid    (m_axi_awvalid),
			.m_axi_awready    (m_axi_awready),
			.m_axi_awaddr     (m_axi_awaddr),
			.m_axi_awid       (m_axi_awid),
			.m_axi_awlen      (m_axi_awlen),
			.m_axi_awburst    (m_axi_awburst),
			.m_axi_awsize     (m_axi_awsize),
			.m_axi_awport     (m_axi_awport),
			.m_axi_awqos      (m_axi_awqos),
			.m_axi_awlock     (m_axi_awlock),
			.m_axi_awcache    (m_axi_awcache),

			.m_axi_wvalid     (m_axi_wvalid),
			.m_axi_wready     (m_axi_wready),
			.m_axi_wdata      (m_axi_wdata),
			.m_axi_wstrb      (m_axi_wstrb),
			.m_axi_wlast      (m_axi_wlast),

		    .m_axi_bid        (m_axi_bid),
			.m_axi_bresp      (m_axi_bresp),
			.m_axi_bvalid     (m_axi_bvalid),
			.m_axi_bready     (m_axi_bready)
		);












endmodule
