// -----------------------------------------------------------------------------
// File   : rgmii_send.v
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module rgmii_send(
	input                reset                ,
	output               phy_rgmii_tx_clk     ,
	output               phy_rgmii_tx_ctl     ,
	output  [3:0]        phy_rgmii_tx_data    ,

	input                gmii_tx_clk          ,
	input                gmii_tx_data_vld     ,
	input [7:0]          gmii_tx_data      

    );

wire       rgmii_tx_ctl;
wire [3:0] rgmii_tx_data;

/*--------------------------------------------------*\
	                ODDR
\*--------------------------------------------------*/
   ODDR #(
      .DDR_CLK_EDGE("SAME_EDGE"), // "OPPOSITE_EDGE" or "SAME_EDGE" 
      .INIT(1'b0),    // Initial value of Q: 1'b0 or 1'b1
      .SRTYPE("SYNC") // Set/Reset type: "SYNC" or "ASYNC" 
   ) ODDR_ctl(
      .Q(rgmii_tx_ctl),   // 1-bit DDR output
      .C(gmii_tx_clk),   // 1-bit clock input
      .CE(1), // 1-bit clock enable input
      .D1(gmii_tx_data_vld), // 1-bit data input (positive edge)
      .D2(gmii_tx_data_vld ), // 1-bit data input (negative edge) //注意不要掉了异或
      .R(0),   // 1-bit reset
      .S(0)    // 1-bit set
   );

genvar i_tx;
generate
	for (i_tx = 0; i_tx < 4; i_tx = i_tx + 1) begin
		
    	ODDR #(
      		.DDR_CLK_EDGE("SAME_EDGE"), // "OPPOSITE_EDGE" or "SAME_EDGE" 
      		.INIT(1'b0),    // Initial value of Q: 1'b0 or 1'b1
      		.SRTYPE("SYNC") // Set/Reset type: "SYNC" or "ASYNC" 
   		) ODDR_data(
      		.Q(rgmii_tx_data[i_tx]),   // 1-bit DDR output
      		.C(gmii_tx_clk),   // 1-bit clock input
      		.CE(1), // 1-bit clock enable input
      		.D1(gmii_tx_data[i_tx]), // 1-bit data input (positive edge)
      		.D2(gmii_tx_data[i_tx + 4]), // 1-bit data input (negative edge)
      		.R(0),   // 1-bit reset
      		.S(0)    // 1-bit set
        );

	end
endgenerate

/*--------------------------------------------------*\
	                OBUF
\*--------------------------------------------------*/
   OBUF OBUF_clk (
      .O(phy_rgmii_tx_clk), // 1-bit output: Buffer output (connect directly to top-level port)
      .I(gmii_tx_clk)  // 1-bit input: Buffer input
   );

   OBUF OBUF_ctl (
      .O(phy_rgmii_tx_ctl), // 1-bit output: Buffer output (connect directly to top-level port)
      .I(rgmii_tx_ctl)  // 1-bit input: Buffer input
   );

genvar j_tx;
generate
	for (j_tx = 0; j_tx < 4; j_tx = j_tx + 1) begin

   		OBUF OBUF_data 
   		(
      		.O(phy_rgmii_tx_data[j_tx]), // 1-bit output: Buffer output (connect directly to top-level port)
      		.I(rgmii_tx_data[j_tx])  // 1-bit input: Buffer input

        );		
	end
endgenerate








endmodule
