`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/10/10 20:42:00
// Design Name: 
// Module Name: clock_and_reset
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module clock_and_reset(
	input   		clkin_50m    ,
	output          clkout_125m  ,
	output          clkout_150m  ,
	output          clkout_200m  ,
	output reg		reset
    );

wire		locked;
wire		clk_out1;
wire		clk_out2;
wire        clk_out3;
reg	[11:0]	cnt;

// CLKOUT0 is the only fractional MMCM output.  Use it for 200 MHz so the
// three requested clocks (200/125/150 MHz) are all exact from the 50 MHz input.
assign clkout_200m = clk_out1;
assign clkout_125m = clk_out2;
assign clkout_150m = clk_out3;

// Generate the board-wide reset in the 125 MHz protocol clock domain.  This
// keeps reset release synchronous with the MAC/application logic; 200 MHz is
// reserved exclusively for IDELAYCTRL.
always @(posedge clk_out2 or negedge locked) begin
	if (~locked) begin
		cnt   <= 12'd0;
		reset <= 1'b1;
	end
	else if (cnt <= 12'd500) begin
		cnt   <= cnt + 1'b1;
		reset <= 1'b1;
	end
	else begin
		cnt   <= cnt;
		reset <= 1'b0;
	end
end
  
  clk_wiz_0 clk_wiz_0
   (
    // Clock out ports
    .clk_out1(clk_out1),     // output clk_out1
    .clk_out2(clk_out2),     // output clk_out2
    .clk_out3(clk_out3),     // output clk_out3
    // Status and control signals
    .reset   (1'b0),         // input reset
    .locked  (locked),       // output locked
   // Clock in ports
    .clk_in1 (clkin_50m)     // input clk_in1
    );      
//



endmodule
