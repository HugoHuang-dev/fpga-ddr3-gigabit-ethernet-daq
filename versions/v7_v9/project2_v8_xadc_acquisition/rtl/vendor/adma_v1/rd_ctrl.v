// -----------------------------------------------------------------------------
// Author : XiaoBai FPGA 
// File   : rd_ctrl.v
// Create : 2023-12-29 19:27:06
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module rd_ctrl #(
	parameter	AXI_DATA_WIDTH  = 128,
	parameter   AXI_ADDR_WIDTH  = 32,
	parameter   RD_BURST_LENGTH = 4096 
)(
	input                              clk               , //用户端读时钟
	input                              reset             ,
    
    /*-----DDR初始化完成信号，与MIG核交互------------------*/
	input                              ddr_init_done     ,

    /*--------------用户端读请求信号----------------------*/
    input                              user_rd_req       , //上升沿触发用户读请求
    input     [AXI_ADDR_WIDTH-1:0]     user_rd_base_addr , //一定要被4096整除
    input     [AXI_ADDR_WIDTH-1:0]     user_rd_end_addr  , //一定要被4096整除
    output                             user_rd_req_busy  , //用户读请求忙标志

    /*--------------与rd_buffer模块交互信号---------------*/
    output  reg                        rd_req_en         ,
    output       [7:0]                 rd_burst_length   ,
    output  reg  [AXI_ADDR_WIDTH-1:0]  rd_data_addr      ,
    input                              rd_req_ready         //用来指示rd_buffer模块里面的cmd_fifo是否爆满

    );

localparam	MAX_BURST_LENGTH = RD_BURST_LENGTH / (AXI_DATA_WIDTH/8) - 1;

/*--------------------------------------------------*\
				     定义状态机
\*--------------------------------------------------*/
reg	[1:0]	cur_status;
reg	[1:0]	nxt_status;
localparam 	RD_IDLE = 2'b00;
localparam 	RD_REQ  = 2'b01;
localparam 	RD_END  = 2'b10;

/*--------------------------------------------------*\
				     定义复位信号
\*--------------------------------------------------*/
(* dont_touch ="true" *) reg reset_sync_d0;
(* dont_touch ="true" *) reg reset_sync_d1;
(* dont_touch ="true" *) reg reset_sync;

/*--------------------------------------------------*\
				     定义其他信号
\*--------------------------------------------------*/
reg			ddr_init_done_d0;
reg			ddr_init_done_d1;
reg			ddr_rd_enable   ;
reg			user_rd_req_d0  ;
reg			user_rd_req_d1  ;
reg         rd_req_trig     ;
wire        user_rd_req_rise;

/*--------------------------------------------------*\
				      assign
\*--------------------------------------------------*/
assign user_rd_req_busy = cur_status != RD_IDLE;
assign rd_burst_length  = MAX_BURST_LENGTH;
assign user_rd_req_rise = user_rd_req_d0 & ~user_rd_req_d1;
/*--------------------------------------------------*\
				      CDC
\*--------------------------------------------------*/

always @(posedge clk) begin
	reset_sync_d0 <= reset;
	reset_sync_d1 <= reset_sync_d0;
	reset_sync    <= reset_sync_d1;    
end

always @(posedge clk) begin
	ddr_init_done_d0 <= ddr_init_done;
	ddr_init_done_d1 <= ddr_init_done_d0;
	ddr_rd_enable    <= ddr_init_done_d1;
end

always @(posedge clk) begin
	user_rd_req_d0 <= user_rd_req;
	user_rd_req_d1 <= user_rd_req_d0;
end

always @(posedge clk) begin
    if (ddr_rd_enable) 
        rd_req_trig <= user_rd_req_rise; 
    else 
        rd_req_trig <= 0;
end

/*--------------------------------------------------*\
				      状态机
\*--------------------------------------------------*/

always @(posedge clk) begin
    if (reset_sync) 
        cur_status <= RD_IDLE;
    else 
        cur_status <= nxt_status;
end

always @(*) begin
    if (reset_sync) 
        nxt_status <= RD_IDLE;
    else begin
    	case(cur_status)
    		RD_IDLE : begin
    			if (rd_req_trig) 
    				nxt_status <= RD_REQ;
    			else 
    				nxt_status <= cur_status;
    		end
    		RD_REQ : begin
    			if (rd_req_en && rd_req_ready) 
    				nxt_status <= RD_END;
    			else 
    				nxt_status <= cur_status;
    		end
    		RD_END : begin
    			nxt_status <= RD_IDLE;
    		end
    		default : nxt_status <= RD_IDLE;
    	endcase
    end
end

/*--------------------------------------------------*\
				       rd req 
\*--------------------------------------------------*/
always @(posedge clk) begin
    if (rd_req_en && rd_req_ready) 
       rd_req_en <= 0; 
    else if (cur_status == RD_REQ) 
       rd_req_en <= 1; 
    else 
       rd_req_en <= rd_req_en;
end


always @(posedge clk) begin
    if (reset_sync) 
        rd_data_addr <= user_rd_base_addr;
    else if (rd_req_en && rd_req_ready && rd_data_addr >= user_rd_end_addr - RD_BURST_LENGTH) 
        rd_data_addr <= user_rd_base_addr;
    else if (rd_req_en && rd_req_ready)
        rd_data_addr <= rd_data_addr + RD_BURST_LENGTH;
end

endmodule
