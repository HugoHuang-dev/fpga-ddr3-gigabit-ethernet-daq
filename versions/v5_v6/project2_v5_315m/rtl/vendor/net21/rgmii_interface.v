// -----------------------------------------------------------------------------
// File   : rgmii_interface.v
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module rgmii_interface(
	input			reset                ,

    input           idelay_refclk        ,

	input			phy_rgmii_rx_clk     ,
	input			phy_rgmii_rx_ctl     ,
	input	[3:0]	phy_rgmii_rx_data    ,

	output			phy_rgmii_tx_clk     ,
	output			phy_rgmii_tx_ctl     ,
	output	[3:0]	phy_rgmii_tx_data    ,

	output			phy_rx_clk           ,
	output			gmii_rx_data_vld     ,
	output			gmii_rx_data_error   ,
	output	[7:0]	gmii_rx_data         ,

	input			phy_tx_clk           ,
	input			gmii_tx_data_vld     ,
	input	[7:0]	gmii_tx_data 
    );








	rgmii_recieve u0
		(
			.reset              (reset)             ,

            .idelay_refclk      (idelay_refclk)     ,
            
			.phy_rgmii_rx_clk   (phy_rgmii_rx_clk)  ,
			.phy_rgmii_rx_ctl   (phy_rgmii_rx_ctl)  ,
			.phy_rgmii_rx_data  (phy_rgmii_rx_data) ,

			.gmii_rx_clk        (phy_rx_clk)        ,
			.gmii_rx_data_vld   (gmii_rx_data_vld)  ,
			.gmii_rx_data_error (gmii_rx_data_error),
			.gmii_rx_data       (gmii_rx_data)
		);

	rgmii_send u1
		(
			.reset             (reset),

			.phy_rgmii_tx_clk  (phy_rgmii_tx_clk),
			.phy_rgmii_tx_ctl  (phy_rgmii_tx_ctl),
			.phy_rgmii_tx_data (phy_rgmii_tx_data),

			.gmii_tx_clk       (phy_tx_clk),
			.gmii_tx_data_vld  (gmii_tx_data_vld),
			.gmii_tx_data      (gmii_tx_data)
		);


endmodule
