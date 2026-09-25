// -----------------------------------------------------------------------------
// File   : mac_send.v
// ���� : �����CRCУ�顢MACͷ������Ч���ݡ�CRCУ��....�����
//        �ڿ�ʱ����
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module mac_send #(
	parameter     LOCAL_MAC_ADDR    = 48'hffffffffffff,
	parameter     TARGET_MAC_ADDR   = 48'hffffffffffff
)(
	input 			   clk                 ,      //�û����Ͷ�ʱ��
	input              phy_tx_clk          ,     //phyоƬ���Ͷ�ʱ��

    input              phy_tx_reset        ,
	input              reset               ,

 /*----------��rgmii_sendģ�齻���ź�----------*/
	output reg         gmii_tx_data_vld     ,  
	output reg [7:0]   gmii_tx_data         ,

    /*-------��ip_sendģ�齻���ź�----------*/     
	input              mac_tx_data_vld      ,
	input              mac_tx_data_last     ,
	input      [7:0]   mac_tx_data          ,
	input      [15:0]  mac_tx_frame_type    , 
	input      [15:0]  mac_tx_length        ,

   /*-------��ѯarp������ mac��ַ-------------*/
    input      [47:0]  rd_arp_list_mac      ,  
    input              rd_arp_list_mac_vld  ,

   /*-------��tx_crc32_d8ģ�齻���ź�----------*/
	output reg         tx_crc_din_vld       ,
	output     [7:0]   tx_crc_din           ,
	output reg         tx_crc_done          ,
	input      [31:0]  tx_crc_dout          ,
	output reg         frame_fifo_overflow  ,
	output reg         data_fifo_overflow

);
/*--------------------------------------------------*\
	               ״̬���źŶ��� 
\*--------------------------------------------------*/
reg [2:0] cur_status;
reg [2:0] nxt_status;
localparam TX_IDLE = 3'b000;
localparam TX_PRE  = 3'b001;
localparam TX_DATA = 3'b010;
localparam TX_END  = 3'b100;
/*--------------------------------------------------*\
	                FIFO�˿��ź� 
\*--------------------------------------------------*/
reg	 [63:0]  frame_din;
reg          frame_wren;
wire [63:0]  frame_dout;
reg 		 frame_rden;
wire		 frame_wrfull;
wire		 frame_rdempty;
wire [3:0]   frame_wrcount;
wire [3:0]   frame_rdcount;

reg	 [8:0]   data_din;
reg          data_wren;
wire [8:0]   data_dout;
reg 		 data_rden;
wire		 data_wrfull;
wire		 data_rdempty;
wire [11:0]  data_wrcount;
wire [11:0]  data_rdcount;
/*--------------------------------------------------*\
	                �źŶ��� 
\*--------------------------------------------------*/
reg [10:0] tx_cnt;
reg [7:0]  send_data;
reg        send_data_en;
reg        send_data_last;
reg [7:0]  crc_data;
reg        crc_data_en;
reg [2:0]  crc_cnt;
reg [15:0] mac_type;
reg [47:0] send_target_mac;
reg [47:0] send_target_mac_cdc; //��ʱ������mac��ַ

/*--------------------------------------------------------------*\
                      ����Ŀ��mac��ַ    
\*--------------------------------------------------------------*/
always @(posedge clk) begin
    if (reset) 
        send_target_mac <= TARGET_MAC_ADDR; //��λ����ʼ��Ŀ��mac��ַ
    else if (rd_arp_list_mac_vld) 
        send_target_mac <= rd_arp_list_mac; //��ѯarp��̬������Ŀ��mac
    else if (mac_tx_data_vld && mac_tx_frame_type == 16'h0806) //arp����Ŀ��macΪ48'hffffffffffff
        send_target_mac <= 48'hffffffffffff;
    else 
        send_target_mac <= send_target_mac;
end

/*--------------------------------------------------------------*\
         typeд��frame_fifo����Ч���ݺ�last�ź�д��data_fifo    
\*--------------------------------------------------------------*/
always @(posedge clk) begin
	frame_din  <= {send_target_mac,mac_tx_frame_type};
	frame_wren <= mac_tx_data_last;
end

always @(posedge clk) begin
	 data_wren <= mac_tx_data_vld;
	 data_din  <= {mac_tx_data_last,mac_tx_data};    
end

// The inherited stack does not backpressure these asynchronous FIFOs. Keep
// sticky evidence if a write is attempted while either FIFO is full.
always @(posedge clk) begin
    if (reset) begin
        frame_fifo_overflow <= 1'b0;
        data_fifo_overflow  <= 1'b0;
    end else begin
        if (frame_wren && frame_wrfull)
            frame_fifo_overflow <= 1'b1;
        if (data_wren && data_wrfull)
            data_fifo_overflow <= 1'b1;
    end
end

/*--------------------------------------------------*\
	                 ״̬�� 
\*--------------------------------------------------*/
always @(posedge phy_tx_clk) begin
	if (phy_tx_reset) 
		cur_status <= TX_IDLE;
	else 
		cur_status <= nxt_status;
end

always @(*) begin
	if (phy_tx_reset) begin
		nxt_status <= TX_IDLE;		
	end
	else begin
		case(cur_status)
			TX_IDLE : begin
				if (~frame_rdempty)
					nxt_status <= TX_PRE;
				else 
					nxt_status <= cur_status;
			end
			TX_PRE : begin
				nxt_status <= TX_DATA;
			end
			TX_DATA : begin
				if (crc_cnt == 3 && crc_data_en)
					nxt_status <= TX_END;
				else 
					nxt_status <= cur_status;
			end
			TX_END : begin
				nxt_status <= TX_IDLE;
			end
			default : nxt_status <= TX_IDLE;
		endcase	
	end
end

/*--------------------------------------------------*\
	                 tx_cnt ����MAC��
\*--------------------------------------------------*/
always @(posedge phy_tx_clk) begin
    if (phy_tx_reset) 
        tx_cnt <= 0;
    else if (cur_status == TX_DATA) 
        tx_cnt <= tx_cnt + 1;
    else 
        tx_cnt <= 0;
end

always @(posedge phy_tx_clk) begin
    if (phy_tx_reset) 
        send_data <= 0;
    else 
    	case(tx_cnt)
    		0,1,2,3,4,5,6  : send_data <= 8'h55; //ǰ����
    		7              : send_data <= 8'hd5; //֡��ʼ�����

    		8              : send_data <= send_target_mac_cdc[47:40]; //Ŀ��MAC
    		9              : send_data <= send_target_mac_cdc[39:32];
    		10             : send_data <= send_target_mac_cdc[31:24];
    		11             : send_data <= send_target_mac_cdc[23:16];
    		12             : send_data <= send_target_mac_cdc[15:8];
    		13             : send_data <= send_target_mac_cdc[7:0];

    		14             : send_data <= LOCAL_MAC_ADDR[47:40]; //����MAC
    		15             : send_data <= LOCAL_MAC_ADDR[39:32];
    		16             : send_data <= LOCAL_MAC_ADDR[31:24];
    		17             : send_data <= LOCAL_MAC_ADDR[23:16];
    		18             : send_data <= LOCAL_MAC_ADDR[15:8];
    		19             : send_data <= LOCAL_MAC_ADDR[7:0];    		    		    		    		
   
            20             : send_data <= mac_type[15:8]; //����
            21             : send_data <= mac_type[7:0];  
            default        : send_data <= data_dout[7:0]; //��Ч����
    	endcase 
end

always @(*) begin
	frame_rden <= cur_status == TX_PRE;
end

always @(posedge phy_tx_clk) begin
    if (frame_rden) begin
        mac_type             <= frame_dout[15:0];
        send_target_mac_cdc  <= frame_dout[63:16];
    end
    else begin
        mac_type             <= mac_type;
        send_target_mac_cdc  <= send_target_mac_cdc;
    end
end

always @(posedge phy_tx_clk) begin
    if (cur_status == TX_DATA && tx_cnt == 21) 
        data_rden <= 1'b1;
    else if (data_rden && data_dout[8]) //����last����
        data_rden <= 1'b0;
    else 
        data_rden <= data_rden;
end

always @(posedge phy_tx_clk) begin
    if (data_rden && data_dout[8]) 
        send_data_last <= 1'b1;
    else 
        send_data_last <= 0;
end

always @(posedge phy_tx_clk) begin
    if (phy_tx_reset)
        send_data_en <= 0;
    else if (cur_status == TX_DATA && tx_cnt == 0) 
        send_data_en <= 1'b1;
    else if (send_data_last) 
        send_data_en <= 0;
    else 
        send_data_en <= send_data_en;
end

/*--------------------------------------------------*\
	                 crc 
\*--------------------------------------------------*/
always @(posedge phy_tx_clk) begin
    if (tx_cnt == 8) 
        tx_crc_din_vld <= 1'b1;
    else if (send_data_last) 
        tx_crc_din_vld <= 0;
    else 
        tx_crc_din_vld <= tx_crc_din_vld;
end

assign tx_crc_din = send_data;

always @(posedge phy_tx_clk) begin
    if (crc_data_en && crc_cnt == 3) 
        tx_crc_done <= 1'b1;
    else 
        tx_crc_done <= 0;
end

always @(posedge phy_tx_clk) begin
    if (phy_tx_reset) 
        crc_cnt <= 0;
    else if (crc_data_en && crc_cnt == 3) 
        crc_cnt <= 0;
    else if (crc_data_en)
        crc_cnt <= crc_cnt + 1'b1;
    else 
    	crc_cnt <= crc_cnt;
end

always @(posedge phy_tx_clk) begin
    if (phy_tx_reset)
        crc_data_en <= 0;
    else if (crc_data_en && crc_cnt == 3) 
        crc_data_en <= 0;
    else if (send_data_last) 
        crc_data_en <= 1;
    else 
        crc_data_en <= crc_data_en;
end

always @(*) begin
    if (phy_tx_reset) 
       crc_data <= 0; 
    else
    	case(crc_cnt) //ע���ȷ��͵͵��ֽ�
    		0 : crc_data <= tx_crc_dout[7:0];
    		1 : crc_data <= tx_crc_dout[15:8];
            2 : crc_data <= tx_crc_dout[23:16];
            3 : crc_data <= tx_crc_dout[31:24];            
    	endcase
end

/*--------------------------------------------------*\
	                 ��� 
\*--------------------------------------------------*/
always @(posedge phy_tx_clk) begin
    if (phy_tx_reset) 
        gmii_tx_data <= 0;
    else if (send_data_en) 
        gmii_tx_data <= send_data;
    else if (crc_data_en)
    	gmii_tx_data <= crc_data;
    else  
    	gmii_tx_data <= gmii_tx_data;  
end

always @(posedge phy_tx_clk) begin
    if (phy_tx_reset) 
        gmii_tx_data_vld <= 0;
    else 
        gmii_tx_data_vld <= crc_data_en | send_data_en;
end

/*--------------------------------------------------*\
                     ����FIFO 
\*--------------------------------------------------*/

fifo_w64xd16 frame_fifo (
  .rst(phy_tx_reset),                      // input wire rst
  .wr_clk(clk),                // input wire wr_clk
  .rd_clk(phy_tx_clk),                // input wire rd_clk
  .din(frame_din),                      // input wire [63 : 0] din
  .wr_en(frame_wren),                  // input wire wr_en
  .rd_en(frame_rden),                  // input wire rd_en
  .dout(frame_dout),                    // output wire [63 : 0] dout
  .full(frame_wrfull),                    // output wire full
  .empty(frame_rdempty),                  // output wire empty
  .rd_data_count(frame_rdcount),  // output wire [4 : 0] rd_data_count
  .wr_data_count(frame_wrcount)  // output wire [4 : 0] wr_data_count
);

fifo_w9xd4096 data_fifo (
  .rst(phy_tx_reset),                      // input wire rst
  .wr_clk(clk),                // input wire wr_clk
  .rd_clk(phy_tx_clk),                // input wire rd_clk
  .din(data_din),                      // input wire [8 : 0] din
  .wr_en(data_wren),                  // input wire wr_en
  .rd_en(data_rden),                  // input wire rd_en
  .dout(data_dout),                    // output wire [8 : 0] dout
  .full(data_wrfull),                    // output wire full
  .empty(data_rdempty),                  // output wire empty
  .rd_data_count(data_rdcount),  // output wire [11 : 0] rd_data_count
  .wr_data_count(data_wrcount)  // output wire [11 : 0] wr_data_count
);


endmodule
