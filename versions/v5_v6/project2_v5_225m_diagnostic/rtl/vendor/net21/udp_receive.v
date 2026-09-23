// -----------------------------------------------------------------------------
// Author : XiaoBai FPGA 
// File   : udp_receive.v
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module udp_receive #(
	parameter     LOCAL_PORT    = 16'h8060	
)(
	input					clk             ,
	input					reset           ,

	input                   udp_rx_data_vld  ,
	input                   udp_rx_data_last ,
	input      [7:0]        udp_rx_data      ,
	input      [15:0]       udp_rx_length    ,

    output reg              app_rx_data_vld  ,
    output reg              app_rx_data_last ,
    output reg [7:0]        app_rx_data      ,
    output reg [15:0]       app_rx_length    
 
    );
/*--------------------------------------------------*\
	                信号定义
\*--------------------------------------------------*/
reg	[10:0]	rx_cnt;
reg	[15:0]	rx_target_port;

/*--------------------------------------------------*\
				     cnt 、 rx_target_port
\*--------------------------------------------------*/
always @(posedge clk) begin
    if (reset) 
        rx_cnt <= 0;
    else if (udp_rx_data_vld) 
        rx_cnt <= rx_cnt + 1;
    else 
        rx_cnt <= 0;
end

always @(posedge clk) begin
    if (rx_cnt == 2 || rx_cnt == 3) 
        rx_target_port <= {rx_target_port[7:0],udp_rx_data}; 
    else 
        rx_target_port <= rx_target_port;
end

/*--------------------------------------------------*\
				     输出有效数据
\*--------------------------------------------------*/
always @(posedge clk) begin
    if (LOCAL_PORT == rx_target_port && rx_cnt >= 8) begin //udp头部8个字节，去掉udp头部，输出有效数据
    	app_rx_data_vld    <= udp_rx_data_vld;
    	app_rx_data_last   <= udp_rx_data_last;
		app_rx_data        <= udp_rx_data;
		app_rx_length      <= udp_rx_length - 8;	
    end
    else begin
    	app_rx_data_vld    <= 0;
    	app_rx_data_last   <= 0;
		app_rx_data        <= 0;
		app_rx_length      <= 0;    	
    end   
end

endmodule
