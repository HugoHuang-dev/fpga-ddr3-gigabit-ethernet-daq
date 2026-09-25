// -----------------------------------------------------------------------------
// File   : wr_ctrl.v
// Create : 2023-12-27 20:30:55
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module wr_ctrl #(
	parameter		USER_WR_DATA_WIDTH = 16  ,
	parameter       AXI_DATA_WIDTH     = 128 ,
	parameter       AXI_ADDR_WIDTH     = 32  ,
	parameter       WR_BURST_LENGTH    = 4096   //可以为4096,2048,1024....字节
)(
	input                              clk               , //用户端写时钟
	input                              reset             ,
    
    /*-----DDR初始化完成信号，与MIG核交互------------------*/
	input                              ddr_init_done     ,

    /*-------------用户写端口信号------------------------*/
	input                              user_wr_en        ,
	input   [USER_WR_DATA_WIDTH-1:0]   user_wr_data      ,
	input   [AXI_ADDR_WIDTH-1:0]       user_wr_base_addr , //一定要被4096整除
	input   [AXI_ADDR_WIDTH-1:0]       user_wr_end_addr  , //一定要被4096整除

    /*-------------与wr_buffer模块交互信号----------------*/

    output  reg                        wr_req_en         ,
    output       [7:0]                 wr_burst_length   ,
    output  reg  [AXI_ADDR_WIDTH-1:0]  wr_data_addr      ,
    output  reg                        wr_data_valid     ,
    output  reg  [AXI_DATA_WIDTH-1:0]  wr_data_out       ,
    output  reg                        wr_data_last      

    );


localparam  WR_CNT_MAX       = AXI_DATA_WIDTH / USER_WR_DATA_WIDTH - 1;
localparam  MAX_BURST_LENGTH = WR_BURST_LENGTH / (AXI_DATA_WIDTH / 8) - 1;

(* dont_touch ="true" *)        reg reset_sync_d0;
(* dont_touch ="true" *)        reg reset_sync_d1;
(* dont_touch ="true" *)        reg reset_sync;

reg                             ddr_init_done_d0;
reg                             ddr_init_done_d1;
reg                             ddr_wr_enable   ;
reg                             user_wr_en_d    ;
reg [USER_WR_DATA_WIDTH-1:0]    user_wr_data_d  ;

reg [$clog2(WR_CNT_MAX) - 1 :0] wr_cnt          ;
reg [7:0]                       wr_burst_cnt    ;


/*--------------------------------------------------*\
				     CDC process
\*--------------------------------------------------*/
always @(posedge clk) begin
	reset_sync_d0 <= reset;
	reset_sync_d1 <= reset_sync_d0;
	reset_sync    <= reset_sync_d1;    
end

always @(posedge clk) begin
	ddr_init_done_d0 <= ddr_init_done;
	ddr_init_done_d1 <= ddr_init_done_d0;
	ddr_wr_enable    <= ddr_init_done_d1;
end

always @(posedge clk) begin
    if (ddr_wr_enable) begin
    	user_wr_en_d   <= user_wr_en;
    	user_wr_data_d <= user_wr_data;
    end  
    else begin
    	user_wr_en_d   <= 0;
    	user_wr_data_d <= 0;
    end 
end

/*--------------------------------------------------*\
				     data
\*--------------------------------------------------*/
always @(posedge clk) begin
    if (reset_sync) begin
    	wr_cnt          <= 0;
    	wr_burst_cnt    <= 0;
    end
    else if (user_wr_en_d) begin
    	if (wr_cnt == WR_CNT_MAX)begin
    		wr_cnt          <= 0;
    		wr_burst_cnt    <= (wr_burst_cnt == MAX_BURST_LENGTH) ? 0 : wr_burst_cnt + 1;
    	end
    	else begin
    		wr_cnt          <= wr_cnt + 1;
    		wr_burst_cnt    <= wr_burst_cnt;
    	end
    end   
end

always @(posedge clk) begin
    if (wr_cnt == WR_CNT_MAX) 
        wr_data_valid <= 1'b1;
    else 
        wr_data_valid <= 0; 
end

always @(posedge clk) begin
    if (user_wr_en_d) 
       wr_data_out <= {user_wr_data_d,wr_data_out[AXI_DATA_WIDTH-1 : USER_WR_DATA_WIDTH]}; 
    else 
       wr_data_out <= wr_data_out;
end

always @(posedge clk) begin
    if (wr_cnt == WR_CNT_MAX && wr_burst_cnt == MAX_BURST_LENGTH) 
        wr_data_last <= 1'b1;
    else 
        wr_data_last <= 0; 
end

/*--------------------------------------------------*\
				        req
\*--------------------------------------------------*/
always @(posedge clk) begin
    if (wr_cnt == WR_CNT_MAX && wr_burst_cnt == MAX_BURST_LENGTH) 
        wr_req_en <= 1'b1;
    else 
       	wr_req_en <= 0; 
end

always @(posedge clk) begin
    if (reset) 
        wr_data_addr <= user_wr_base_addr;
    else if (wr_req_en && wr_data_addr >= user_wr_end_addr - WR_BURST_LENGTH) 
        wr_data_addr <= user_wr_base_addr;
    else if (wr_req_en)
        wr_data_addr  <=  wr_data_addr + WR_BURST_LENGTH;
end

assign wr_burst_length = MAX_BURST_LENGTH;


endmodule
