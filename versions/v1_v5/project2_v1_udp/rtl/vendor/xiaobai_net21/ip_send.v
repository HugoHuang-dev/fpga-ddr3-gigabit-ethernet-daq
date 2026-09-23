// -----------------------------------------------------------------------------
// Author : XiaoBai FPGA 
// File   : ip_send.v
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module ip_send #(
	parameter     LOCAL_IP_ADDR     = {8'd0,8'd0,8'd0,8'd0},
	parameter     TARGET_IP_ADDR    = {8'd0,8'd0,8'd0,8'd0}
)(
	input					clk                       , //用户端发送时钟
	input					reset                     ,

   /*--------- 与mac_send模块交互-------------------------*/
	output reg   			ip_tx_data_vld            ,
	output reg   			ip_tx_data_last           ,
	output reg [15:0]       ip_tx_length              ,
	output reg [7:0]	    ip_tx_data                ,

  /*-----------------发送端口---------------------------*/
	input                   tx_data_vld           ,
	input                   tx_data_last          ,
	input      [7:0]        tx_data               ,
	input      [15:0]       tx_length             , //总长度
    input      [7:0]        tx_type               , //udp类型或者icmp类型。udp :8'd17 ,icmp:8'd1;

    output reg              rd_arp_list_en        ,
    output reg [31:0]       rd_arp_list_ip         

    );

reg  [10:0] tx_cnt;
reg  [15:0] package_id;
reg  [15:0] ip_head_chack;
reg  [31:0] add0;
reg  [31:0] add1;
reg  [31:0] add2;
reg  [31:0] chack_sum;
reg         tx_data_vld_d0;
reg         tx_data_vld_d1;
reg  [7:0]  tx_type_r;

wire [7:0]  tx_data_delay;

/*--------------------------------------------------*\
			      锁存长度和类型
\*--------------------------------------------------*/
always @(posedge clk) begin
    tx_data_vld_d0 <= tx_data_vld;
    tx_data_vld_d1 <= tx_data_vld_d0;
end

always @(posedge clk) begin
    if (tx_data_vld) 
        ip_tx_length <= tx_length + 20; //ip首部 20字节
    else 
        ip_tx_length <= ip_tx_length;
end

always @(posedge clk) begin
    if (tx_data_vld) 
        tx_type_r <= tx_type;
    else 
        tx_type_r <= tx_type_r;
end

/*--------------------------------------------------*\
				     cnt
\*--------------------------------------------------*/
always @(posedge clk) begin
    if (reset) 
        tx_cnt <= 0;
    else if (tx_cnt == ip_tx_length - 1) 
        tx_cnt <= 0;
    else if (tx_data_vld || tx_cnt != 0)
        tx_cnt <= tx_cnt + 1;
end

/*--------------------------------------------------*\
                  ip发送相关的信号
\*--------------------------------------------------*/
always @(posedge clk) begin
    if (tx_cnt == ip_tx_length - 1) 
        ip_tx_data_last <= 1;
    else 
        ip_tx_data_last <= 0;
end

always @(posedge clk) begin
    if (ip_tx_data_last) 
       ip_tx_data_vld <= 0; 
    else if (tx_data_vld) 
       ip_tx_data_vld <= 1; 
    else 
       ip_tx_data_vld <= ip_tx_data_vld; 
end

always @(posedge clk) begin
    if (reset) 
        ip_tx_data <= 0;
    else 
        case(tx_cnt)
        	0 :  ip_tx_data <= {4'h4,4'h5}; //版本ipv4 、首部长度5

        	1 :  ip_tx_data <= 0;           //服务类型

        	2 :  ip_tx_data <= ip_tx_length[15:8]; //总长度
        	3 :  ip_tx_data <= ip_tx_length[7 :0];

        	4 :  ip_tx_data <= package_id[15:8]; //标识，发完一包数据自加1
        	5 :  ip_tx_data <= package_id[7: 0];

        	6 :  ip_tx_data <= {3'b010,5'h0}; //标记 + 分段偏移
            7 :  ip_tx_data <= 8'h0;

            8 :  ip_tx_data <= 8'h80;   //生存时间

            9 :  ip_tx_data <= tx_type_r; //协议 udp或者icmp

            10 : ip_tx_data <= ip_head_chack[15:8]; //ip首部校验
            11 : ip_tx_data <= ip_head_chack[7:0];

            12 : ip_tx_data <= LOCAL_IP_ADDR[31:24];    //本地ip地址
            13 : ip_tx_data <= LOCAL_IP_ADDR[23:16];
            14 : ip_tx_data <= LOCAL_IP_ADDR[15:8];
            15 : ip_tx_data <= LOCAL_IP_ADDR[7: 0];

            16 : ip_tx_data <= TARGET_IP_ADDR[31:24]; //目标ip地址
            17 : ip_tx_data <= TARGET_IP_ADDR[23:16];
            18 : ip_tx_data <= TARGET_IP_ADDR[15:8];
            19 : ip_tx_data <= TARGET_IP_ADDR[7: 0];            
            
            default : ip_tx_data <= tx_data_delay; //发送IP层有效数据
        endcase
end

/*--------------------------------------------------*\
              发完一包数据自加1
\*--------------------------------------------------*/
always @(posedge clk) begin
    if (reset) 
        package_id <= 0;
    else if (ip_tx_data_last) 
        package_id <= package_id + 1;
    else 
        package_id <= package_id;
end

/*--------------------------------------------------*\
				     ip首部校验和
\*--------------------------------------------------*/

always @(posedge clk) begin     //2个clk计算完成
	add0      <= 16'h4500 + ip_tx_length + package_id;
	add1      <= 16'h4000 + {8'h80,tx_type_r} + LOCAL_IP_ADDR[31:16];
	add2      <= LOCAL_IP_ADDR[15:0] + TARGET_IP_ADDR[31:16] + TARGET_IP_ADDR[15:0];
	chack_sum <= add0 + add1 + add2;
end

always @(posedge clk) begin
    if (reset) 
        ip_head_chack <= 0;
    else if (tx_cnt == 5) 
        ip_head_chack <= chack_sum[31:16] + chack_sum[15:0];
    else if (tx_cnt == 6)
        ip_head_chack <= ~ip_head_chack;
    else
    	ip_head_chack <= ip_head_chack;
end

/*--------------------------------------------------*\
                查询arp动态链表
\*--------------------------------------------------*/
always @(posedge clk) begin
    if (reset) begin
       rd_arp_list_en <= 0;   
       rd_arp_list_ip <= 0;     
    end
    else if (tx_data_vld_d0 && ~tx_data_vld_d1) begin
        rd_arp_list_en <= 1'b1;
        rd_arp_list_ip <= TARGET_IP_ADDR;
    end
    else begin
        rd_arp_list_en <= 0;
        rd_arp_list_ip <= rd_arp_list_ip;        
    end 
end

/*--------------------------------------------------*\
				      例化
\*--------------------------------------------------*/
//注意：A的值为19，tx_data_delay相比于tx_data延迟20拍~
//如果A的值为10，则延迟11拍！

c_shift_ram_0 ip_delay (
  .A(19),      // input wire [5 : 0] A
  .D(tx_data),      // input wire [7 : 0] D
  .CLK(clk),  // input wire CLK
  .Q(tx_data_delay)      // output wire [7 : 0] Q
);


endmodule
