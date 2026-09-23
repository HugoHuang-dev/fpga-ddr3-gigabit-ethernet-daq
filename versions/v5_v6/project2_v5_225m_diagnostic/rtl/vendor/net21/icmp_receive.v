`timescale 1ns / 1ps

module icmp_receive(
	input						app_rx_clk            ,
	input           			app_tx_clk            ,
	input           			app_rx_reset          ,
	input           			app_tx_reset          ,

	input                       icmp_rx_data_vld      ,
	input                       icmp_rx_data_last     ,
	input       [7:0]           icmp_rx_data          ,
	input       [15:0]          icmp_rx_length        ,

	output reg                  icmp_reply_req        ,  // icmp回复包请求	
	output reg  [15:0]          icmp_rx_identify      ,  // 标识符号
	output reg  [15:0]          icmp_rx_sequence         // 序列号

    );

reg	 [10:0]		rx_cnt       ;
reg	 [15:0]		rx_identify  ;
reg	 [15:0]		rx_sequence  ;
reg	 [7:0]		imcp_type    ;

reg	 [31:0]		icmp_din     ;
reg				icmp_wren    ;
wire [31:0]	    icmp_dout    ;
wire			icmp_rden    ;
wire			icmp_wrfull  ;
wire			icmp_rdempty ;

assign icmp_rden = ~icmp_rdempty;

always @(posedge app_rx_clk) begin
    if (app_rx_reset) 
        rx_cnt <= 0;
    else if (icmp_rx_data_vld) 
        rx_cnt <= rx_cnt + 1;
    else 
        rx_cnt <= 0;
end

always @(posedge app_rx_clk) begin
    if (app_rx_reset) 
        imcp_type <= 0;
    else if (rx_cnt == 0) 
        imcp_type <= icmp_rx_data;
    else 
        imcp_type <= imcp_type;
end

always @(posedge app_rx_clk) begin
    if (app_rx_reset) 
        rx_identify <= 0;
    else if (rx_cnt == 4 || rx_cnt == 5) 
        rx_identify <= {rx_identify[7:0],icmp_rx_data};
    else 
        rx_identify <= rx_identify;
end

always @(posedge app_rx_clk) begin
    if (app_rx_reset) 
        rx_sequence <= 0;
    else if (rx_cnt == 6 || rx_cnt == 7) 
        rx_sequence <= {rx_sequence[7:0],icmp_rx_data};
    else 
        rx_sequence <= rx_sequence;
end

always @(posedge app_rx_clk) begin
    if (app_rx_reset) begin
    	icmp_wren <= 0;
    	icmp_din  <= 0;
    end  
    else begin
    	icmp_wren <= icmp_rx_data_last;
    	icmp_din  <= {rx_identify,rx_sequence};
    end
end

//跨时钟域处理
always @(posedge app_tx_clk) begin
    if (app_tx_reset) begin
    	icmp_reply_req   <= 0;
    	icmp_rx_identify <= 0;
    	icmp_rx_sequence <= 0;
    end 
    else if (icmp_rden) begin
    	icmp_reply_req   <= 1;
    	icmp_rx_identify <= icmp_dout[31:16];
    	icmp_rx_sequence <= icmp_dout[15:0];    	
    end 
    else begin
    	icmp_reply_req   <= 0;
    	icmp_rx_identify <= 0;
    	icmp_rx_sequence <= 0;    	
    end     
end

fifo_w32xd16_async icmp_rx_fifo (
  .rst(app_rx_reset),        // input wire rst
  .wr_clk(app_rx_clk),  // input wire wr_clk
  .rd_clk(app_tx_clk),  // input wire rd_clk
  .din(icmp_din),        // input wire [31 : 0] din
  .wr_en(icmp_wren),    // input wire wr_en
  .rd_en(icmp_rden),    // input wire rd_en
  .dout(icmp_dout),      // output wire [31 : 0] dout
  .full(icmp_wrfull),      // output wire full
  .empty(icmp_rdempty)    // output wire empty
);


endmodule
