`timescale 1ns / 1ps

module arp_receive #(
	parameter LOCAL_IP_ADDR     =  {8'd0,8'd0,8'd0,8'd0}
)(
	input						app_rx_clk            ,
	input           			app_tx_clk            ,
	input           			app_rx_reset          ,
	input           			app_tx_reset          ,

	input       				arp_rx_data_vld       ,
	input       				arp_rx_data_last      ,
	input       	[7:0]		arp_rx_data           ,

	output reg                  rx_source_vld         ,
	output reg [47:0]           rx_source_mac_addr    ,
	output reg [31:0]           rx_source_ip_addr     ,

	output reg                  arp_reply_req   //arp回复包请求

    );


reg	 [15:0]		opcode             ;  //操作码,1表示ARP请求，2表示ARP应答
reg	 [31:0]		rx_target_ip       ;
reg				rx_target_ip_chack ;
reg	 [5:0]		rx_cnt             ;
reg	 [47:0]		source_mac_addr    ;
reg	 [31:0]		source_ip_addr     ;
reg				arp_reply_active   ;

reg	 [81:0]		arp_din            ;
reg				arp_wren           ;
wire [81:0]	    arp_dout           ;
wire			arp_rden           ;
wire			arp_wrfull         ;
wire			arp_rdempty        ;



assign arp_rden = ~arp_rdempty;

always @(posedge app_rx_clk) begin
    if (app_rx_reset) 
        rx_cnt <= 0;
    else if (arp_rx_data_vld) 
        rx_cnt <= rx_cnt + 1;
    else 
        rx_cnt <= 0;
end

always @(posedge app_rx_clk) begin
    if (app_rx_reset) 
        opcode <= 0;
    else if (rx_cnt == 6 || rx_cnt == 7) 
        opcode <= {opcode[7:0],arp_rx_data};
    else 
        opcode <= opcode;
end

always @(posedge app_rx_clk) begin
    if (app_rx_reset) 
    	source_mac_addr <= 0;
    else if (rx_cnt >= 8 && rx_cnt <= 13) 
        source_mac_addr <= {source_mac_addr[39:0],arp_rx_data};
    else 
        source_mac_addr <= source_mac_addr;
end

always @(posedge app_rx_clk) begin
    if (app_rx_reset) 
        source_ip_addr <= 0;
    else if (rx_cnt >= 14 && rx_cnt <= 17) 
    	source_ip_addr <= {source_ip_addr[23:0],arp_rx_data};
    else 
        source_ip_addr <= source_ip_addr;
end

always @(posedge app_rx_clk) begin
    if (app_rx_reset) 
        rx_target_ip <= 0;
    else if (rx_cnt >= 24 && rx_cnt <= 27) 
        rx_target_ip <= {rx_target_ip[23:0],arp_rx_data};
    else 
        rx_target_ip <= rx_target_ip;
end

always @(posedge app_rx_clk) begin
    if (app_rx_reset) 
        rx_target_ip_chack <= 0;
    else if (rx_target_ip == LOCAL_IP_ADDR) 
        rx_target_ip_chack <= 1'b1;
    else if (rx_target_ip != LOCAL_IP_ADDR)
        rx_target_ip_chack <= 1'b0;
    else 
    	rx_target_ip_chack <= rx_target_ip_chack;
end

always @(posedge app_rx_clk) begin
    if (app_rx_reset) 
        arp_reply_active <= 0;
    else if (rx_target_ip_chack && opcode == 1) //收到arp请求包，开启arp回复包
        arp_reply_active <= 1'b1;
    else if (!(rx_target_ip_chack && opcode == 1))
        arp_reply_active <= 0;
end

always @(posedge app_rx_clk) begin
    if (app_rx_reset) begin
    	arp_wren <= 0;
    	arp_din  <= 0;
    end
    else if (arp_rx_data_last) begin
        arp_wren <= 1'b1;
        arp_din  <= {arp_reply_active,source_mac_addr,source_ip_addr};
    end
    else begin
    	arp_wren <= 0;
    	arp_din  <= 0;
    end   
end

//跨时钟域处理
always @(posedge app_tx_clk) begin
    if (app_tx_reset) begin
    	rx_source_vld       <= 0;
    	rx_source_mac_addr  <= 0;
    	rx_source_ip_addr   <= 0;
    	arp_reply_req       <= 0;
    end
    else if (arp_rden) begin
    	rx_source_vld       <= 1'b1;
    	arp_reply_req       <= arp_dout[80];
    	rx_source_mac_addr  <= arp_dout[79:32];
    	rx_source_ip_addr   <= arp_dout[31:0];
    end  
    else begin
    	rx_source_vld       <= 0;
    	rx_source_mac_addr  <= 0;
    	rx_source_ip_addr   <= 0;
    	arp_reply_req       <= 0;
    end    
end

fifo_w81xd16 arp_rx_fifo (
  .rst(app_rx_reset),        // input wire rst
  .wr_clk(app_rx_clk),  // input wire wr_clk
  .rd_clk(app_tx_clk),  // input wire rd_clk
  .din(arp_din),        // input wire [80 : 0] din
  .wr_en(arp_wren),    // input wire wr_en
  .rd_en(arp_rden),    // input wire rd_en
  .dout(arp_dout),      // output wire [80 : 0] dout
  .full(arp_wrfull),      // output wire full
  .empty(arp_rdempty)    // output wire empty
);



endmodule
