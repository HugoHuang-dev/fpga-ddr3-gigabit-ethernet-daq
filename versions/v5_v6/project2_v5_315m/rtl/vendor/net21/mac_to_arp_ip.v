// -----------------------------------------------------------------------------
// Author : XiaoBai FPGA 
// File   : mac_to_arp_ip.v
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module mac_to_arp_ip(
	input					clk,
	input					reset,

   /*-------与mac_receive模块交互信号----------*/
	input					mac_rx_data_vld,
	input					mac_rx_data_last,
	input		[7:0]		mac_rx_data,
	input		[15:0]		mac_rx_frame_type,  

   /*-------与ip_receive模块交互信号----------*/
	output reg				ip_rx_data_vld,
	output reg				ip_rx_data_last,
	output reg	[7:0]		ip_rx_data   ,

	/*-------arp相关的端口信号----------------*/  
	output reg				arp_rx_data_vld,
	output reg				arp_rx_data_last,
	output reg	[7:0]		arp_rx_data     

    );

localparam      ARP_TYPE  = 16'h0806;
localparam      IP_TYPE   = 16'h0800;

always @(posedge clk) begin
    if (mac_rx_frame_type == IP_TYPE) begin
        ip_rx_data_vld  <=  mac_rx_data_vld;
        ip_rx_data_last <=  mac_rx_data_last;
        ip_rx_data      <=  mac_rx_data;
    end
    else begin
        ip_rx_data_vld  <=  0;
        ip_rx_data_last <=  0;
        ip_rx_data      <=  0;  
    end     
end


always @(posedge clk) begin
    if (mac_rx_frame_type == ARP_TYPE) begin
        arp_rx_data_vld  <=  mac_rx_data_vld;
        arp_rx_data_last <=  mac_rx_data_last;
        arp_rx_data      <=  mac_rx_data;
    end
    else begin
        arp_rx_data_vld  <=  0;
        arp_rx_data_last <=  0;
        arp_rx_data      <=  0;  
    end     
end

endmodule
