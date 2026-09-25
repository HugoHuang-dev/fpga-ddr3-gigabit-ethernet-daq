// -----------------------------------------------------------------------------
// File   : udp_protocol_stack.v
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module udp_protocol_stack #(
	parameter     LOCAL_MAC_ADDR    = 48'hffffffffffff                 ,
	parameter     TARGET_MAC_ADDR   = 48'hffffffffffff                 ,	
	parameter     LOCAL_IP_ADDR     =  {8'd0,8'd0,8'd0,8'd0}           ,
	parameter     TARGET_IP_ADDR    =  {8'd0,8'd0,8'd0,8'd0}           ,
	parameter     LOCAL_PORT        = 16'h8060		                   ,
    parameter     TARGET_PORT       = 16'h8060   	
)(
	input                   phy_tx_clk         ,     //phyоƬ���ܶ�ʱ��	
	input             		phy_rx_clk         ,     //phyоƬ���ܶ�ʱ��
	input              		reset              ,

    /*----------GMII�ӿ��ź�-------------------*/
	input              		gmii_rx_data_vld   ,
	input   [7:0]           gmii_rx_data       ,
	output                  gmii_tx_data_vld   ,
	output  [7:0]           gmii_tx_data       ,

    /*----------�û����ܶ˽ӿ��ź�---------------*/
	input 			   		app_rx_clk         ,  //�û����ն�ʱ��
    output			        app_rx_data_vld    ,
    output			        app_rx_data_last   ,
    output	[7:0]	        app_rx_data        ,
    output	[15:0]	        app_rx_length      ,

    /*----------�û����Ͷ˽ӿ��ź�---------------*/
	input 			   		app_tx_clk         ,  //�û����Ͷ�ʱ��
    input			        app_tx_data_vld    ,
    input			        app_tx_data_last   ,
    input	[7:0]	        app_tx_data        ,
    input	[15:0]	        app_tx_length      , //����ܳ���1500 - 28 = 1472
    output			        app_tx_ready,
    output                  mac_frame_fifo_overflow,
    output                  mac_data_fifo_overflow
    );


	wire			mac_rx_data_vld;
	wire			mac_rx_data_last;
	wire	[7:0]	mac_rx_data;
	wire	[15:0]	mac_rx_frame_type;

	wire			mac_tx_data_vld;
	wire			mac_tx_data_last;
	wire	[7:0]	mac_tx_data;
	wire	[15:0]	mac_tx_frame_type;
	wire	[15:0]	mac_tx_length;

	wire			ip_rx_data_vld;
	wire			ip_rx_data_last;
	wire	[7:0]	ip_rx_data;

	wire			ip_tx_data_vld;
	wire			ip_tx_data_last;
	wire	[15:0]	ip_tx_length;
	wire	[7:0]	ip_tx_data;

	wire			udp_rx_data_vld;
	wire			udp_rx_data_last;
	wire	[7:0]	udp_rx_data;
	wire	[15:0]	udp_rx_length;
	
	wire			udp_tx_data_vld;
	wire			udp_tx_data_last;
	wire	[7:0]	udp_tx_data;
	wire	[15:0]	udp_tx_length;

	wire			icmp_rx_data_vld;
	wire			icmp_rx_data_last;
	wire	[7:0]	icmp_rx_data;
	wire	[15:0]	icmp_rx_length;

	wire			icmp_tx_data_vld;
	wire			icmp_tx_data_last;
	wire	[7:0]	icmp_tx_data;
	wire	[15:0]	icmp_tx_length;	
    
    wire			app_tx_req;

	wire			arp_rx_data_vld;
	wire			arp_rx_data_last;
	wire	[7:0]	arp_rx_data;   

	wire			arp_tx_data_vld;
	wire			arp_tx_data_last;
	wire	[7:0]	arp_tx_data;
	wire	[15:0]	arp_tx_length;
	
	wire			rd_arp_list_en;
	wire	[31:0]	rd_arp_list_ip;
	wire	[47:0]	rd_arp_list_mac;
	wire			rd_arp_list_mac_vld;

	wire			ip_send_data_vld ;
	wire			ip_send_data_last;
	wire	[7:0]	ip_send_data;
	wire	[15:0]	ip_send_length;
	wire	[15:0]	ip_send_type;

/*--------------------------------------------------*\
				       ��λ�źŴ���
\*--------------------------------------------------*/
	reg [19:0] phy_rx_reset_timer;
	reg        phy_rx_reset_d0;
	reg        phy_rx_reset_d1;
	reg        phy_rx_reset;

	always @(posedge phy_rx_clk or posedge reset) begin
		if (reset) 
			phy_rx_reset_timer <= 20'd0;
		else if (phy_rx_reset_timer <= 20'h00fff)
			phy_rx_reset_timer <= phy_rx_reset_timer + 1'b1;
		else 
			phy_rx_reset_timer <= phy_rx_reset_timer;
	end

	always @(posedge phy_rx_clk or posedge reset) begin
		if (reset)begin
			phy_rx_reset_d0 <= 1'b1;
			phy_rx_reset_d1 <= 1'b1;
			phy_rx_reset    <= 1'b1;
		end		
		else begin
			phy_rx_reset_d0 <= phy_rx_reset_timer <= 20'h00fff;
			phy_rx_reset_d1 <= phy_rx_reset_d0;
			phy_rx_reset    <= phy_rx_reset_d1;
		end		
	end
//----------------------------------------------------------------
	reg [19:0] phy_tx_reset_timer;
	reg        phy_tx_reset_d0;
	reg        phy_tx_reset_d1;
	reg        phy_tx_reset;

	always @(posedge phy_tx_clk or posedge reset) begin
		if (reset) 
			phy_tx_reset_timer <= 20'd0;
		else if (phy_tx_reset_timer <= 20'h00fff)
			phy_tx_reset_timer <= phy_tx_reset_timer + 1'b1;
		else 
			phy_tx_reset_timer <= phy_tx_reset_timer;
	end

	always @(posedge phy_tx_clk or posedge reset) begin
		if (reset)begin
			phy_tx_reset_d0 <= 1'b1;
			phy_tx_reset_d1 <= 1'b1;
			phy_tx_reset    <= 1'b1;
		end		
		else begin
			phy_tx_reset_d0 <= phy_tx_reset_timer <= 20'h00fff;
			phy_tx_reset_d1 <= phy_tx_reset_d0;
			phy_tx_reset    <= phy_tx_reset_d1;
		end		
	end

//------------------------------------------------------------------
	reg [19:0] app_rx_reset_timer;
	reg        app_rx_reset_d0;
	reg        app_rx_reset_d1;
	reg        app_rx_reset;

	always @(posedge app_rx_clk or posedge reset) begin
		if (reset) 
			app_rx_reset_timer <= 20'd0;
		else if (app_rx_reset_timer <= 20'h00fff)
			app_rx_reset_timer <= app_rx_reset_timer + 1'b1;
		else 
			app_rx_reset_timer <= app_rx_reset_timer;
	end

	always @(posedge app_rx_clk or posedge reset) begin
		if (reset)begin
			app_rx_reset_d0 <= 1'b1;
			app_rx_reset_d1 <= 1'b1;
			app_rx_reset    <= 1'b1;
		end		
		else begin
			app_rx_reset_d0 <= app_rx_reset_timer <= 20'h00fff;
			app_rx_reset_d1 <= app_rx_reset_d0;
			app_rx_reset    <= app_rx_reset_d1;
		end		
	end
//---------------------------------------------------------------------
	reg [19:0] app_tx_reset_timer;
	reg        app_tx_reset_d0;
	reg        app_tx_reset_d1;
	reg        app_tx_reset;

	always @(posedge app_tx_clk or posedge reset) begin
		if (reset) 
			app_tx_reset_timer <= 20'd0;
		else if (app_tx_reset_timer <= 20'h00fff)
			app_tx_reset_timer <= app_tx_reset_timer + 1'b1;
		else 
			app_tx_reset_timer <= app_tx_reset_timer;
	end

	always @(posedge app_tx_clk or posedge reset) begin
		if (reset)begin
			app_tx_reset_d0 <= 1'b1;
			app_tx_reset_d1 <= 1'b1;
			app_tx_reset    <= 1'b1;
		end		
		else begin
			app_tx_reset_d0 <= app_tx_reset_timer <= 20'h00fff;
			app_tx_reset_d1 <= app_tx_reset_d0;
			app_tx_reset    <= app_tx_reset_d1;
		end		
	end

/*--------------------------------------------------*\
				       ģ������
\*--------------------------------------------------*/
	mac_layer #(
			.LOCAL_MAC_ADDR(LOCAL_MAC_ADDR),
			.TARGET_MAC_ADDR(TARGET_MAC_ADDR),
			.CRC_CHECK_EN(1)
		) u0 (
	        .app_rx_clk          (app_rx_clk)      ,			   	      
	        .app_tx_clk          (app_tx_clk)      ,			   		         
			.phy_tx_clk          (phy_tx_clk)      ,
			.phy_rx_clk          (phy_rx_clk)      ,

			.phy_rx_reset        (phy_rx_reset)    ,
			.phy_tx_reset        (phy_tx_reset)    ,
			.app_tx_reset        (app_tx_reset)    ,
            .app_rx_reset        (app_rx_reset)    ,

			.gmii_rx_data_vld    (gmii_rx_data_vld),
			.gmii_rx_data        (gmii_rx_data),
			.gmii_tx_data_vld    (gmii_tx_data_vld),
			.gmii_tx_data        (gmii_tx_data)    ,

			.mac_rx_data_vld     (mac_rx_data_vld),
			.mac_rx_data_last    (mac_rx_data_last),
			.mac_rx_data         (mac_rx_data),
			.mac_rx_frame_type   (mac_rx_frame_type),			

			.mac_tx_data_vld     (mac_tx_data_vld),
			.mac_tx_data_last    (mac_tx_data_last),
			.mac_tx_data         (mac_tx_data),
			.mac_tx_frame_type   (mac_tx_frame_type),
			.mac_tx_length       (mac_tx_length)	,

			.rd_arp_list_mac     (rd_arp_list_mac)  ,
			.rd_arp_list_mac_vld (rd_arp_list_mac_vld),
			.frame_fifo_overflow (mac_frame_fifo_overflow),
			.data_fifo_overflow  (mac_data_fifo_overflow)

		);

	udp_tx_arbiter u1
		(
			.clk            (app_tx_clk),
			.reset          (app_tx_reset),

			.ch0_type       (16'h0800),
			.ch0_length     (ip_tx_length),
			.ch0_data_vld   (ip_tx_data_vld),
			.ch0_data_last  (ip_tx_data_last),
			.ch0_data       (ip_tx_data),

			.ch1_type       (16'h0806),
			.ch1_length     (arp_tx_length),
			.ch1_data_vld   (arp_tx_data_vld),
			.ch1_data_last  (arp_tx_data_last),
			.ch1_data       (arp_tx_data),

			.send_type      (mac_tx_frame_type),
			.send_length    (mac_tx_length),
			.send_data_vld  (mac_tx_data_vld),
			.send_data_last (mac_tx_data_last),
			.send_data      (mac_tx_data)
		);

	mac_to_arp_ip u2
		(
			.clk               (app_rx_clk),
			.reset             (app_rx_reset),

			.mac_rx_data_vld   (mac_rx_data_vld),
			.mac_rx_data_last  (mac_rx_data_last),
			.mac_rx_data       (mac_rx_data),
			.mac_rx_frame_type (mac_rx_frame_type),

			.ip_rx_data_vld    (ip_rx_data_vld),
			.ip_rx_data_last   (ip_rx_data_last),
			.ip_rx_data        (ip_rx_data),

			.arp_rx_data_vld   (arp_rx_data_vld),
			.arp_rx_data_last  (arp_rx_data_last),
			.arp_rx_data       (arp_rx_data)
		);

	arp_layer #(
			.LOCAL_MAC_ADDR(LOCAL_MAC_ADDR),
			.TARGET_MAC_ADDR(TARGET_MAC_ADDR),
			.LOCAL_IP_ADDR(LOCAL_IP_ADDR),
			.TARGET_IP_ADDR(TARGET_IP_ADDR)
		) u3 (
			.app_rx_clk          (app_rx_clk),
			.app_tx_clk          (app_tx_clk),
			.app_tx_reset        (app_tx_reset),
			.app_rx_reset        (app_rx_reset),

			.arp_rx_data_vld     (arp_rx_data_vld),
			.arp_rx_data_last    (arp_rx_data_last),
			.arp_rx_data         (arp_rx_data),

			.arp_tx_data_vld     (arp_tx_data_vld),
			.arp_tx_data_last    (arp_tx_data_last),
			.arp_tx_data         (arp_tx_data),
			.arp_tx_length       (arp_tx_length),

			.rd_arp_list_en      (rd_arp_list_en),
			.rd_arp_list_ip      (rd_arp_list_ip),
			.rd_arp_list_mac     (rd_arp_list_mac),
			.rd_arp_list_mac_vld (rd_arp_list_mac_vld)
		);

	ip_layer #(
			.LOCAL_IP_ADDR(LOCAL_IP_ADDR),
			.TARGET_IP_ADDR(TARGET_IP_ADDR)
		) u4 (
			.app_rx_clk        (app_rx_clk),
			.app_tx_clk        (app_tx_clk),
			.app_tx_reset      (app_tx_reset),
			.app_rx_reset      (app_rx_reset),

			.ip_rx_data_vld    (ip_rx_data_vld),
			.ip_rx_data_last   (ip_rx_data_last),
			.ip_rx_data        (ip_rx_data),

			.ip_tx_data_vld    (ip_tx_data_vld),
			.ip_tx_data_last   (ip_tx_data_last),
			.ip_tx_length      (ip_tx_length),
			.ip_tx_data        (ip_tx_data),

			.udp_rx_data_vld   (udp_rx_data_vld),
			.udp_rx_data_last  (udp_rx_data_last),
			.udp_rx_data       (udp_rx_data),
			.udp_rx_length     (udp_rx_length),

			.icmp_rx_data_vld  (icmp_rx_data_vld),
			.icmp_rx_data_last (icmp_rx_data_last),
			.icmp_rx_data      (icmp_rx_data),
			.icmp_rx_length    (icmp_rx_length),

			.tx_data_vld       (ip_send_data_vld),
			.tx_data_last      (ip_send_data_last),
			.tx_data           (ip_send_data),
			.tx_length         (ip_send_length),
			.tx_type           (ip_send_type[7:0]),

			.rd_arp_list_en    (rd_arp_list_en),
			.rd_arp_list_ip    (rd_arp_list_ip)
		);

	udp_tx_arbiter u5
		(
			.clk            (app_tx_clk),
			.reset          (app_tx_reset),

			.ch0_type       ({8'd0,8'd1}),
			.ch0_length     (icmp_tx_length),
			.ch0_data_vld   (icmp_tx_data_vld),
			.ch0_data_last  (icmp_tx_data_last),
			.ch0_data       (icmp_tx_data),

			.ch1_type       ({8'd0,8'd17}),
			.ch1_length     (udp_tx_length),
			.ch1_data_vld   (udp_tx_data_vld),
			.ch1_data_last  (udp_tx_data_last),
			.ch1_data       (udp_tx_data),

			.send_type      (ip_send_type)  ,
			.send_length    (ip_send_length),
			.send_data_vld  (ip_send_data_vld),
			.send_data_last (ip_send_data_last),
			.send_data      (ip_send_data)
		);


	icmp_layer u6
		(
			.app_rx_clk        (app_rx_clk),
			.app_tx_clk        (app_tx_clk),
			.app_rx_reset      (app_rx_reset),
			.app_tx_reset      (app_tx_reset),

			.icmp_rx_data_vld  (icmp_rx_data_vld),
			.icmp_rx_data_last (icmp_rx_data_last),
			.icmp_rx_data      (icmp_rx_data),
			.icmp_rx_length    (icmp_rx_length),

			.icmp_tx_data_vld  (icmp_tx_data_vld),
			.icmp_tx_data_last (icmp_tx_data_last),
			.icmp_tx_data      (icmp_tx_data),
			.icmp_tx_length    (icmp_tx_length)
		);		

	udp_layer #(
			.LOCAL_PORT(LOCAL_PORT),
			.TARGET_PORT(TARGET_PORT)
		) u7 (
	        .app_rx_clk        (app_rx_clk) ,			   	      
	        .app_tx_clk        (app_tx_clk) ,

			.app_tx_reset      (app_tx_reset),
            .app_rx_reset      (app_rx_reset),

			.udp_rx_data_vld  (udp_rx_data_vld),
			.udp_rx_data_last (udp_rx_data_last),
			.udp_rx_data      (udp_rx_data),
			.udp_rx_length    (udp_rx_length),
			.udp_tx_data_vld  (udp_tx_data_vld),
			.udp_tx_data_last (udp_tx_data_last),
			.udp_tx_data      (udp_tx_data),
			.udp_tx_length    (udp_tx_length),

			.app_rx_data_vld  (app_rx_data_vld),
			.app_rx_data_last (app_rx_data_last),
			.app_rx_data      (app_rx_data),
			.app_rx_length    (app_rx_length),
			.app_tx_data_vld  (app_tx_data_vld),
			.app_tx_data_last (app_tx_data_last),
			.app_tx_data      (app_tx_data),
			.app_tx_length    (app_tx_length),
			.app_tx_req       (app_tx_req),
			.app_tx_ready     (app_tx_ready)
		);


endmodule
