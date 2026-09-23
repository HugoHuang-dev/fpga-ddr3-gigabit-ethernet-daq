// -----------------------------------------------------------------------------
// Author : XiaoBai FPGA 
// File   : mac_layer.v
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module mac_layer #(
	parameter     LOCAL_MAC_ADDR    = 48'hffffffffffff   ,
	parameter     TARGET_MAC_ADDR   = 48'hffffffffffff   ,	
	parameter     CRC_CHECK_EN      = 1                  
)(
	input 			   		app_rx_clk         ,      //�û����ն�ʱ��
	input 			   		app_tx_clk         ,      //�û����Ͷ�ʱ��	
	input                   phy_tx_clk         ,     //phyоƬ���ܶ�ʱ��	
	input             		phy_rx_clk         ,     //phyоƬ���ܶ�ʱ��

	input                   phy_rx_reset       ,
	input                   phy_tx_reset       ,
	input                   app_tx_reset       ,
    input                   app_rx_reset       ,

	input              		gmii_rx_data_vld   ,
	input  [7:0]            gmii_rx_data       ,
	output                  gmii_tx_data_vld   ,
	output [7:0]            gmii_tx_data       ,

	output                  mac_rx_data_vld    ,
	output                  mac_rx_data_last   ,
	output [7:0]            mac_rx_data        ,
	output [15:0]           mac_rx_frame_type  ,

	input                   mac_tx_data_vld    ,
	input                   mac_tx_data_last   ,
	input  [7:0]            mac_tx_data        ,
	input  [15:0]           mac_tx_frame_type  ,
	input  [15:0]           mac_tx_length      ,

    input  [47:0]           rd_arp_list_mac    ,  
    input                   rd_arp_list_mac_vld  ,
    output                  frame_fifo_overflow  ,
    output                  data_fifo_overflow
    );


	wire             rx_crc_din_vld  ;
	wire     [7:0]   rx_crc_din      ;
	wire             rx_crc_done     ;
	wire     [31:0]  rx_crc_dout     ;

	wire             tx_crc_din_vld  ;
	wire     [7:0]   tx_crc_din      ;     
	wire             tx_crc_done     ;    
	wire     [31:0]  tx_crc_dout     ;


	mac_receive #(
			.LOCAL_MAC_ADDR(LOCAL_MAC_ADDR),
			.CRC_CHECK_EN(CRC_CHECK_EN)
		) mac_receive (
			.clk               (app_rx_clk),
			.phy_rx_clk        (phy_rx_clk),

			.phy_rx_reset      (phy_rx_reset),
			.reset             (app_rx_reset),

			.gmii_rx_data_vld  (gmii_rx_data_vld),
			.gmii_rx_data      (gmii_rx_data),

			.mac_rx_data_vld   (mac_rx_data_vld),
			.mac_rx_data_last  (mac_rx_data_last),
			.mac_rx_data       (mac_rx_data),
			.mac_rx_frame_type (mac_rx_frame_type),

			.rx_crc_din_vld    (rx_crc_din_vld),
			.rx_crc_din        (rx_crc_din),
			.rx_crc_done       (rx_crc_done),
			.rx_crc_dout       (rx_crc_dout)
		);

	mac_send #(
			.LOCAL_MAC_ADDR(LOCAL_MAC_ADDR),
			.TARGET_MAC_ADDR(TARGET_MAC_ADDR)
		) mac_send (
			.clk                 (app_tx_clk),
			.phy_tx_clk          (phy_tx_clk),

			.reset               (app_tx_reset),
            .phy_tx_reset        (phy_tx_reset),

			.gmii_tx_data_vld    (gmii_tx_data_vld),
			.gmii_tx_data        (gmii_tx_data),

			.mac_tx_data_vld     (mac_tx_data_vld),
			.mac_tx_data_last    (mac_tx_data_last),
			.mac_tx_data         (mac_tx_data),
			.mac_tx_frame_type   (mac_tx_frame_type),
			.mac_tx_length       (mac_tx_length),

			.rd_arp_list_mac     (rd_arp_list_mac),
			.rd_arp_list_mac_vld (rd_arp_list_mac_vld),			

			.tx_crc_din_vld      (tx_crc_din_vld),
			.tx_crc_din          (tx_crc_din),
			.tx_crc_done         (tx_crc_done),
			.tx_crc_dout         (tx_crc_dout),
			.frame_fifo_overflow (frame_fifo_overflow),
			.data_fifo_overflow  (data_fifo_overflow)
		);

	crc32_d8 rx_crc32_d8
		(
			.clk         (phy_rx_clk),
			.reset       (phy_rx_reset),

			.crc_din_vld (rx_crc_din_vld),
			.crc_din     (rx_crc_din),
			.crc_done    (rx_crc_done),
			.crc_dout    (rx_crc_dout)
		);

	crc32_d8 tx_crc32_d8
		(
			.clk         (phy_tx_clk),
			.reset       (phy_tx_reset),

			.crc_din_vld (tx_crc_din_vld),
			.crc_din     (tx_crc_din),
			.crc_done    (tx_crc_done),
			.crc_dout    (tx_crc_dout)
		);	

endmodule
