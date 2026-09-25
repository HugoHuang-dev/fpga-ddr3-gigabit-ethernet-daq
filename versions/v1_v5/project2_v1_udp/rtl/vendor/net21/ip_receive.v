// -----------------------------------------------------------------------------
// File   : ip_receive.v
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module ip_receive #(
	parameter     LOCAL_IP_ADDR    = {8'd0,8'd0,8'd0,8'd0}
)(

	input					clk               ,
	input					reset             ,

   /*--------与mac_to_arp_ip模块交互信号---*/
	input    				ip_rx_data_vld    ,
	input    				ip_rx_data_last   ,
	input    	[7:0]		ip_rx_data        , 

   /*--------与udp_receive模块交互信号------*/
	output reg              udp_rx_data_vld   ,
	output reg              udp_rx_data_last  ,
	output reg [7:0]        udp_rx_data       ,
	output reg [15:0]       udp_rx_length     ,

   /*--------icmp信号------------------------*/
	output reg              icmp_rx_data_vld  ,
	output reg              icmp_rx_data_last ,
	output reg [7:0]        icmp_rx_data      ,
	output reg [15:0]       icmp_rx_length  
    );

localparam      UDP_TYPE    = 8'd17;
localparam      ICMP_TYPE   = 8'd1;

reg	[10:0]	rx_cnt;
reg [31:0]  rx_target_ip;
reg [7:0]   ip_protocol;
reg [15:0]  total_length;

/*--------------------------------------------------*\
				     cnt
\*--------------------------------------------------*/
always @(posedge clk) begin
    if (reset) 
       rx_cnt <= 0; 
    else if (ip_rx_data_vld) 
       rx_cnt <= rx_cnt + 1;
    else 
       rx_cnt <= 0;  
end
/*--------------------------------------------------*\
		    获取总长度、协议类型、目的IP地址
\*--------------------------------------------------*/
always @(posedge clk) begin
    if (rx_cnt == 2 || rx_cnt == 3) 
        total_length <= {total_length[7:0],ip_rx_data};
    else 
        total_length <= total_length;
end

always @(posedge clk) begin
    if (rx_cnt == 9) 
        ip_protocol <= ip_rx_data;
    else 
        ip_protocol  <= ip_protocol;
end

always @(posedge clk) begin
    if (rx_cnt > 15 && rx_cnt < 20) 
        rx_target_ip <= {rx_target_ip[23:0],ip_rx_data};
    else 
        rx_target_ip <= rx_target_ip;
end

/*--------------------------------------------------*\
		            输出UDP和ICMP
\*--------------------------------------------------*/
always @(posedge clk) begin
    if (ip_protocol == UDP_TYPE && rx_target_ip == LOCAL_IP_ADDR && rx_cnt >= 20) begin
        udp_rx_data_vld  <= ip_rx_data_vld;
        udp_rx_data_last <= ip_rx_data_last;
        udp_rx_data      <= ip_rx_data;
        udp_rx_length    <= total_length - 20;
    end
    else begin
        udp_rx_data_vld  <= 0;
        udp_rx_data_last <= 0;
        udp_rx_data      <= 0;
        udp_rx_length    <= 0;
    end 
end

always @(posedge clk) begin
    if (ip_protocol == ICMP_TYPE && rx_target_ip == LOCAL_IP_ADDR && rx_cnt >= 20) begin
        icmp_rx_data_vld  <= ip_rx_data_vld;
        icmp_rx_data_last <= ip_rx_data_last;
        icmp_rx_data      <= ip_rx_data;
        icmp_rx_length    <= total_length - 20;
    end
    else begin
        icmp_rx_data_vld  <= 0;
        icmp_rx_data_last <= 0;
        icmp_rx_data      <= 0;
        icmp_rx_length    <= 0;
    end 
end

endmodule
