`timescale 1ns / 1ps

module arp_layer #(
	parameter     LOCAL_MAC_ADDR    = 48'hffffffffffff                 ,
	parameter     TARGET_MAC_ADDR   = 48'hffffffffffff                 ,	
	parameter     LOCAL_IP_ADDR     =  {8'd0,8'd0,8'd0,8'd0}    ,
	parameter     TARGET_IP_ADDR    =  {8'd0,8'd0,8'd0,8'd0}   

)(
	input 			   		     app_rx_clk         ,      //用户接收端时钟
	input 			   		     app_tx_clk         ,      //用户发送端时钟	
	input                        app_tx_reset       ,
    input                        app_rx_reset       ,

	input       				 arp_rx_data_vld    ,
	input       				 arp_rx_data_last   ,
	input     [7:0]		         arp_rx_data        ,  
  
	output                       arp_tx_data_vld    ,
	output                       arp_tx_data_last   ,
	output    [7:0]              arp_tx_data        ,  
	output    [15:0]             arp_tx_length      ,

	input                        rd_arp_list_en     ,
	input     [31:0]             rd_arp_list_ip     ,
	output    [47:0]             rd_arp_list_mac    ,  
	output                       rd_arp_list_mac_vld
    );

	wire        rx_source_vld      ;
	wire [47:0] rx_source_mac_addr ;
	wire [31:0] rx_source_ip_addr  ;
	wire        arp_reply_req      ;

	arp_receive #(
			.LOCAL_IP_ADDR(LOCAL_IP_ADDR)
		) arp_receive (
			.app_rx_clk         (app_rx_clk),
			.app_tx_clk         (app_tx_clk),
			.app_rx_reset       (app_rx_reset),
			.app_tx_reset       (app_tx_reset),

			.arp_rx_data_vld    (arp_rx_data_vld),
			.arp_rx_data_last   (arp_rx_data_last),
			.arp_rx_data        (arp_rx_data),

			.rx_source_vld      (rx_source_vld),
			.rx_source_mac_addr (rx_source_mac_addr),
			.rx_source_ip_addr  (rx_source_ip_addr),
			.arp_reply_req      (arp_reply_req)
		);

	arp_send #(
			.LOCAL_MAC_ADDR(LOCAL_MAC_ADDR),
			.LOCAL_IP_ADDR(LOCAL_IP_ADDR)
		) arp_send (
			.clk                (app_tx_clk),
			.reset              (app_tx_reset),

			.rx_source_mac_addr (rx_source_mac_addr),
			.rx_source_ip_addr  (rx_source_ip_addr),
			.arp_reply_req      (arp_reply_req),

			.arp_tx_data_vld    (arp_tx_data_vld),
			.arp_tx_data_last   (arp_tx_data_last),
			.arp_tx_data        (arp_tx_data),
			.arp_tx_length      (arp_tx_length)
		);

	arp_dynamic_list arp_dynamic_list
		(
			.clk             (app_tx_clk),
			.reset           (app_tx_reset),

			.wr_arp_en       (rx_source_vld),
			.wr_ip_addr      (rx_source_ip_addr),
			.wr_mac_addr     (rx_source_mac_addr),

			.rd_arp_en       (rd_arp_list_en),
			.rd_ip_addr      (rd_arp_list_ip),
			.rd_mac_addr     (rd_arp_list_mac),
			.rd_mac_addr_vld (rd_arp_list_mac_vld)
		);


		



endmodule
