// -----------------------------------------------------------------------------
// File   : rgmii_recieve.v
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module rgmii_recieve(
	input               reset                ,

    input               idelay_refclk        ,

	input               phy_rgmii_rx_clk     ,
	input               phy_rgmii_rx_ctl     ,
	input  [3:0]        phy_rgmii_rx_data    ,

	output              gmii_rx_clk          ,
	output              gmii_rx_data_vld     ,
	output              gmii_rx_data_error   ,
	output [7:0]        gmii_rx_data             
    );


wire        phy_rgmii_rx_clk_ibuf;
wire        phy_rgmii_rx_ctl_ibuf;
wire  [3:0] phy_rgmii_rx_data_ibuf;

wire        phy_rgmii_rx_clk_bufio; 

wire        phy_rgmii_rx_ctl_delay;          
wire  [3:0] phy_rgmii_rx_data_delay;

wire        gmii_rx_data_error_xor;

assign      gmii_rx_data_error = gmii_rx_data_error_xor ^ gmii_rx_data_vld;

/*--------------------------------------------------*\
	                  IBUF
\*--------------------------------------------------*/
IBUF rgmii_clk_ibuf (
     .I              (phy_rgmii_rx_clk),
     .O              (phy_rgmii_rx_clk_ibuf)
);

IBUF rgmii_ctl_ibuf (
     .I              (phy_rgmii_rx_ctl),
     .O              (phy_rgmii_rx_ctl_ibuf)
);

genvar i_rx;
generate
	for (i_rx = 0; i_rx < 4; i_rx = i_rx + 1) begin
		IBUF rgmii_data_ibuf (
     		.I              (phy_rgmii_rx_data[i_rx]),
     		.O              (phy_rgmii_rx_data_ibuf[i_rx])
		);		
	end
endgenerate

/*--------------------------------------------------*\
	               BUFIO 、BUFG
\*--------------------------------------------------*/
BUFIO clk_bufio (
      .O(phy_rgmii_rx_clk_bufio), // 1-bit output: Clock output (connect to I/O clock loads).
      .I(phy_rgmii_rx_clk_ibuf)  // 1-bit input: Clock input (connect to an IBUF or BUFMR).
);

BUFG BUFG_rx_clk (
      .O(gmii_rx_clk), // 1-bit output: Clock output
      .I(phy_rgmii_rx_clk_ibuf)  // 1-bit input: Clock input
);

/*--------------------------------------------------*\
	                延时控制
\*--------------------------------------------------*/
   IDELAYCTRL  ldelayctrl_rx(
      .RDY(),       // 1-bit output: Ready output
      .REFCLK(idelay_refclk), // 1-bit input: Reference clock input
      .RST(0)        // 1-bit input: Active high reset input
   );

   IDELAYE2 #(
      .CINVCTRL_SEL("FALSE"),          // Enable dynamic clock inversion (FALSE, TRUE)
      .DELAY_SRC("IDATAIN"),           // Delay input (IDATAIN, DATAIN)
      .HIGH_PERFORMANCE_MODE("FALSE"), // Reduced jitter ("TRUE"), Reduced power ("FALSE")
      .IDELAY_TYPE("FIXED"),           // FIXED, VARIABLE, VAR_LOAD, VAR_LOAD_PIPE
      .IDELAY_VALUE(0),                // Input delay tap setting (0-31)
      .PIPE_SEL("FALSE"),              // Select pipelined mode, FALSE, TRUE
      .REFCLK_FREQUENCY(200.0),        // Must match the 200 MHz IDELAYCTRL reference clock.
      .SIGNAL_PATTERN("DATA")          // DATA, CLOCK input signal
   )
   IDELAYE2_rgmii_rx_ctl (
      .IDATAIN(phy_rgmii_rx_ctl_ibuf),         // 1-bit input: Data input from the I/O      
      .DATAOUT(phy_rgmii_rx_ctl_delay),         // 1-bit output: Delayed data output
      .CNTVALUEOUT(), // 5-bit output: Counter value output      
      .C(0),                     // 1-bit input: Clock input
      .CE(0),                   // 1-bit input: Active high enable increment/decrement input
      .CINVCTRL(0),       // 1-bit input: Dynamic clock inversion input
      .CNTVALUEIN(0),   // 5-bit input: Counter value input
      .DATAIN(0),           // 1-bit input: Internal delay data input
      .INC(0),                 // 1-bit input: Increment / Decrement tap delay input
      .LD(0),                   // 1-bit input: Load IDELAY_VALUE input
      .LDPIPEEN(0),       // 1-bit input: Enable PIPELINE register to load data input
      .REGRST(0)            // 1-bit input: Active-high reset tap-delay input
   );


genvar j_rx;
generate
	for (j_rx = 0; j_rx < 4; j_rx = j_rx + 1) begin

		    IDELAYE2 #(
             .CINVCTRL_SEL("FALSE"),          // Enable dynamic clock inversion (FALSE, TRUE)
             .DELAY_SRC("IDATAIN"),           // Delay input (IDATAIN, DATAIN)
             .HIGH_PERFORMANCE_MODE("FALSE"), // Reduced jitter ("TRUE"), Reduced power ("FALSE")
             .IDELAY_TYPE("FIXED"),           // FIXED, VARIABLE, VAR_LOAD, VAR_LOAD_PIPE
             .IDELAY_VALUE(0),                // Input delay tap setting (0-31)
             .PIPE_SEL("FALSE"),              // Select pipelined mode, FALSE, TRUE
             .REFCLK_FREQUENCY(200.0),        // IDELAYCTRL clock input frequency in MHz (190.0-210.0, 290.0-310.0).
             .SIGNAL_PATTERN("DATA")          // DATA, CLOCK input signal
            )
            IDELAYE2_rgmii_rx_data (
      			.IDATAIN(phy_rgmii_rx_data_ibuf[j_rx]),         // 1-bit input: Data input from the I/O      
      			.DATAOUT(phy_rgmii_rx_data_delay[j_rx]),         // 1-bit output: Delayed data output
     			.CNTVALUEOUT(), // 5-bit output: Counter value output      
      			.C(0),                     // 1-bit input: Clock input
      			.CE(0),                   // 1-bit input: Active high enable increment/decrement input
      			.CINVCTRL(0),       // 1-bit input: Dynamic clock inversion input
     			.CNTVALUEIN(0),   // 5-bit input: Counter value input
      			.DATAIN(0),           // 1-bit input: Internal delay data input
      			.INC(0),                 // 1-bit input: Increment / Decrement tap delay input
      			.LD(0),                   // 1-bit input: Load IDELAY_VALUE input
      			.LDPIPEEN(0),       // 1-bit input: Enable PIPELINE register to load data input
      			.REGRST(0)            // 1-bit input: Active-high reset tap-delay input
   			);

	end
endgenerate
/*--------------------------------------------------*\
	                IDDR
\*--------------------------------------------------*/
   IDDR #(
      .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"), // "OPPOSITE_EDGE", "SAME_EDGE"                                 //    or "SAME_EDGE_PIPELINED" 
      .INIT_Q1(1'b0), // Initial value of Q1: 1'b0 or 1'b1
      .INIT_Q2(1'b0), // Initial value of Q2: 1'b0 or 1'b1
      .SRTYPE("SYNC") // Set/Reset type: "SYNC" or "ASYNC" 
   ) IDDR_rgmii_rx_ctl (
      .Q1(gmii_rx_data_vld), // 1-bit output for positive edge of clock
      .Q2(gmii_rx_data_error_xor), // 1-bit output for negative edge of clock
      .C(phy_rgmii_rx_clk_bufio),   // 1-bit clock input
      .CE(1), // 1-bit clock enable input
      .D(phy_rgmii_rx_ctl_delay),   // 1-bit DDR data input
      .R(0),   // 1-bit reset
      .S(0)    // 1-bit set
   );


genvar q_rx;
generate

	for (q_rx = 0; q_rx < 4; q_rx = q_rx + 1) begin

   		IDDR #(
      		.DDR_CLK_EDGE("SAME_EDGE_PIPELINED"), // "OPPOSITE_EDGE", "SAME_EDGE"                                 //    or "SAME_EDGE_PIPELINED" 
      		.INIT_Q1(1'b0), // Initial value of Q1: 1'b0 or 1'b1
      		.INIT_Q2(1'b0), // Initial value of Q2: 1'b0 or 1'b1
      		.SRTYPE("SYNC") // Set/Reset type: "SYNC" or "ASYNC" 
   		) IDDR_rgmii_rx_data (
      		.Q1(gmii_rx_data[q_rx]), // 1-bit output for positive edge of clock
      		.Q2(gmii_rx_data[q_rx + 4]), // 1-bit output for negative edge of clock
      		.C(phy_rgmii_rx_clk_bufio),   // 1-bit clock input
      		.CE(1), // 1-bit clock enable input
     		.D(phy_rgmii_rx_data_delay[q_rx]),   // 1-bit DDR data input
      		.R(0),   // 1-bit reset
      		.S(0)    // 1-bit set
   );

   end
endgenerate



endmodule
