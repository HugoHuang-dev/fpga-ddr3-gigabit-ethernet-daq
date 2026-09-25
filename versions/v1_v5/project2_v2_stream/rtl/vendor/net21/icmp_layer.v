`timescale 1ns / 1ps

module icmp_layer(

	input						app_rx_clk            ,
	input           			app_tx_clk            ,
	input           			app_rx_reset          ,
	input           			app_tx_reset          ,

	input                       icmp_rx_data_vld      ,
	input                       icmp_rx_data_last     ,
	input       [7:0]           icmp_rx_data          ,
	input       [15:0]          icmp_rx_length        ,

	output                      icmp_tx_data_vld      ,
	output                      icmp_tx_data_last     ,
	output      [7:0]           icmp_tx_data          ,
	output      [15:0]          icmp_tx_length    		


    );

	wire        icmp_reply_req;
	wire [15:0] icmp_rx_identify;
	wire [15:0] icmp_rx_sequence;

	icmp_receive icmp_receive
		(
			.app_rx_clk        (app_rx_clk),
			.app_tx_clk        (app_tx_clk),
			.app_rx_reset      (app_rx_reset),
			.app_tx_reset      (app_tx_reset),

			.icmp_rx_data_vld  (icmp_rx_data_vld),
			.icmp_rx_data_last (icmp_rx_data_last),
			.icmp_rx_data      (icmp_rx_data),
			.icmp_rx_length    (icmp_rx_length),

			.icmp_reply_req    (icmp_reply_req),
			.icmp_rx_identify  (icmp_rx_identify),
			.icmp_rx_sequence  (icmp_rx_sequence)
		);

	icmp_send icmp_send
		(
			.clk               (app_tx_clk),
			.reset             (app_tx_reset),

			.icmp_reply_req    (icmp_reply_req),
			.icmp_rx_identify  (icmp_rx_identify),
			.icmp_rx_sequence  (icmp_rx_sequence),

			.icmp_tx_data_vld  (icmp_tx_data_vld),
			.icmp_tx_data_last (icmp_tx_data_last),
			.icmp_tx_data      (icmp_tx_data),
			.icmp_tx_length    (icmp_tx_length)
		);


endmodule
