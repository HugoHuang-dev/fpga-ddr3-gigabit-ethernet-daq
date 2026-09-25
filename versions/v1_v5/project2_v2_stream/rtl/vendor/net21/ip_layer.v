// -----------------------------------------------------------------------------
// File   : ip_layer.v
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
module ip_layer #(
		parameter     LOCAL_IP_ADDR     =  {8'd0,8'd0,8'd0,8'd0},
	    parameter     TARGET_IP_ADDR    =  {8'd0,8'd0,8'd0,8'd0}		
)(

	input 			   		app_rx_clk         ,   //用户接收端时钟
	input 			   		app_tx_clk         ,   //用户发送端时钟

	input                   app_tx_reset       ,  //用户发送端复位
    input                   app_rx_reset       ,  //用户接收端复位

	input    				ip_rx_data_vld    ,
	input    				ip_rx_data_last   ,
	input      [7:0]		ip_rx_data        ,

	output      			ip_tx_data_vld    ,
	output      			ip_tx_data_last   ,
	output     [15:0]       ip_tx_length      ,
	output     [7:0]	    ip_tx_data        ,	

	output                  udp_rx_data_vld   ,
	output                  udp_rx_data_last  ,
	output     [7:0]        udp_rx_data       ,
	output     [15:0]       udp_rx_length     ,

	output                  icmp_rx_data_vld   ,
	output                  icmp_rx_data_last  ,
	output     [7:0]        icmp_rx_data       ,
	output     [15:0]       icmp_rx_length     ,	

/*-----------------发送端口---------------------------*/
	input                   tx_data_vld           ,
	input                   tx_data_last          ,
	input      [7:0]        tx_data               ,
	input      [15:0]       tx_length             , //总长度
    input      [7:0]        tx_type               , //udp类型或者icmp类型。udp :8'd17 ,icmp:8'd1;

/*-----------------arp查询端口-------------------------*/
    output                  rd_arp_list_en     ,
    output     [31:0]       rd_arp_list_ip  	
    );

	ip_receive #(
			.LOCAL_IP_ADDR(LOCAL_IP_ADDR)
		) ip_receive (
			.clk               (app_rx_clk),
			.reset             (app_rx_reset),

			.ip_rx_data_vld    (ip_rx_data_vld),
			.ip_rx_data_last   (ip_rx_data_last),
			.ip_rx_data        (ip_rx_data),

			.udp_rx_data_vld   (udp_rx_data_vld),
			.udp_rx_data_last  (udp_rx_data_last),
			.udp_rx_data       (udp_rx_data),
			.udp_rx_length     (udp_rx_length),

			.icmp_rx_data_vld  (icmp_rx_data_vld),
			.icmp_rx_data_last (icmp_rx_data_last),
			.icmp_rx_data      (icmp_rx_data),
			.icmp_rx_length    (icmp_rx_length)
		);

	ip_send #(
			.LOCAL_IP_ADDR(LOCAL_IP_ADDR),
			.TARGET_IP_ADDR(TARGET_IP_ADDR)
		) ip_send (
			.clk             (app_tx_clk),
			.reset           (app_tx_reset),

			.ip_tx_data_vld  (ip_tx_data_vld),
			.ip_tx_data_last (ip_tx_data_last),
			.ip_tx_length    (ip_tx_length),
			.ip_tx_data      (ip_tx_data),

			.tx_data_vld     (tx_data_vld),
			.tx_data_last    (tx_data_last),
			.tx_data         (tx_data),
			.tx_length       (tx_length),
			.tx_type         (tx_type),

			.rd_arp_list_en  (rd_arp_list_en),
			.rd_arp_list_ip  (rd_arp_list_ip)
		);

endmodule
