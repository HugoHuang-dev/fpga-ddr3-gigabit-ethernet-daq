// -----------------------------------------------------------------------------
// File   : mac_receive.v
// 功能 : ①完成CRC校验、将MAC头部和有效数据分离出来
//        ②跨时钟域
// -----------------------------------------------------------------------------
module mac_receive #(
	parameter     LOCAL_MAC_ADDR    = 48'hffffffffffff,
	parameter     CRC_CHECK_EN      = 1
)(
	input 			            clk,            //用户接收端时钟
	input                       phy_rx_clk,     //phy芯片接受端时钟

	input                       phy_rx_reset,   //phy芯片接受端复位  
	input                       reset,          //用户接收端复位

    /*-------与rgmii_recieve模块交互信号--------*/
	input                       gmii_rx_data_vld,
	input [7:0]                 gmii_rx_data    ,

   /*-------与mac_to_arp_ip模块交互信号----------*/
	output reg                  mac_rx_data_vld,
	output reg                  mac_rx_data_last,
	output reg [7:0]            mac_rx_data,
	output reg [15:0]           mac_rx_frame_type,

   /*-------与rx_crc32_d8模块交互信号----------*/
	output reg                  rx_crc_din_vld,
	output reg [7:0]            rx_crc_din,
	output reg                  rx_crc_done,
	input      [31:0]           rx_crc_dout
);
/*--------------------------------------------------*\
	               状态机信号定义 
\*--------------------------------------------------*/
reg [2:0] cur_status;
reg [2:0] nxt_status;
localparam RX_IDLE = 3'b000;
localparam RX_PRE  = 3'b001;
localparam RX_DATA = 3'b010;
localparam RX_END  = 3'b100;
/*--------------------------------------------------*\
	               接受MAC信号 
\*--------------------------------------------------*/
reg [15:0]  rx_frame_type;
reg [47:0]  rx_target_mac;
reg	[10:0]	rx_cnt;
reg [55:0]  rx_preamble;
reg			rx_preamble_chack;
reg         rx_sfd_chack;
reg         rx_target_mac_chack;
reg         frame_fifo_crc;
reg			rx_crc_chack;
reg         rx_wr_vld;
/*--------------------------------------------------*\
	                打拍信号 
\*--------------------------------------------------*/
reg			gmii_rx_data_vld_d0;
reg			gmii_rx_data_vld_d1;
reg			gmii_rx_data_vld_d2;
reg			gmii_rx_data_vld_d3;
reg			gmii_rx_data_vld_d4;
reg	[7:0]	gmii_rx_data_d0;
reg	[7:0]	gmii_rx_data_d1;
reg	[7:0]	gmii_rx_data_d2;
reg	[7:0]	gmii_rx_data_d3;
reg	[7:0]	gmii_rx_data_d4;

wire        rx_data_last;
reg         rx_data_last_d0;
reg         rx_data_last_d1;
reg         rx_data_last_d2;
reg         rx_data_last_d3;
reg         rx_data_last_d4;
reg         rx_data_last_d5;
reg         rx_data_last_d6;
/*--------------------------------------------------*\
	                FIFO端口信号 
\*--------------------------------------------------*/
reg	 [16:0]  frame_din;
reg          frame_wren;
wire [16:0]  frame_dout;
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

assign rx_data_last = ~gmii_rx_data_vld & gmii_rx_data_vld_d0;

always @(posedge phy_rx_clk) begin
	gmii_rx_data_vld_d0 <= gmii_rx_data_vld;
	gmii_rx_data_vld_d1 <= gmii_rx_data_vld_d0;
	gmii_rx_data_vld_d2 <= gmii_rx_data_vld_d1;
	gmii_rx_data_vld_d3 <= gmii_rx_data_vld_d2;
	gmii_rx_data_vld_d4 <= gmii_rx_data_vld_d3;

	gmii_rx_data_d0     <= gmii_rx_data;
	gmii_rx_data_d1     <= gmii_rx_data_d0;
	gmii_rx_data_d2     <= gmii_rx_data_d1;
	gmii_rx_data_d3     <= gmii_rx_data_d2;	
	gmii_rx_data_d4     <= gmii_rx_data_d3;	

	rx_data_last_d0     <= rx_data_last;
	rx_data_last_d1     <= rx_data_last_d0;
	rx_data_last_d2     <= rx_data_last_d1;
	rx_data_last_d3     <= rx_data_last_d2;
	rx_data_last_d4     <= rx_data_last_d3;	
	rx_data_last_d5     <= rx_data_last_d4;		
    rx_data_last_d6     <= rx_data_last_d5;	
end

/*--------------------------------------------------*\
	                 cnt  
\*--------------------------------------------------*/
always @(posedge phy_rx_clk) begin
    if (phy_rx_reset) 
        rx_cnt <= 0;
    else if (gmii_rx_data_vld_d4)//打5拍计数
        rx_cnt <= rx_cnt + 1;
    else 
        rx_cnt <= 0;
end
/*--------------------------------------------------*\
	       校验preamble、sfd、mac addr  
\*--------------------------------------------------*/
always @(posedge phy_rx_clk) begin //先接收高字节
    if (gmii_rx_data_vld_d4 && rx_cnt < 7) 
        rx_preamble <= {rx_preamble[47:0],gmii_rx_data_d4};
    else 
        rx_preamble <= rx_preamble;
end

always @(posedge phy_rx_clk) begin
    if (gmii_rx_data_vld_d4 && rx_cnt > 7 && rx_cnt < 14) 
        rx_target_mac <= {rx_target_mac[39:0],gmii_rx_data_d4};
    else 
        rx_target_mac <= rx_target_mac;
end

always @(posedge phy_rx_clk) begin
    if (rx_preamble == 56'h5555_5555_5555_55) 
        rx_preamble_chack <= 1'b1;
    else if (rx_preamble != 56'h5555_5555_5555_55) 
        rx_preamble_chack <= 1'b0;
end

always @(posedge phy_rx_clk) begin
    if ( (rx_target_mac == LOCAL_MAC_ADDR) || (rx_target_mac == 48'hffffffffffff) ) //arp包
        rx_target_mac_chack <= 1'b1;
    else if ( (rx_target_mac != LOCAL_MAC_ADDR) &&  (rx_target_mac != 48'hffffffffffff) ) 
        rx_target_mac_chack <= 1'b0;
end

always @(posedge phy_rx_clk) begin
    if (rx_cnt == 7 && gmii_rx_data_d4 == 8'hd5) 
        rx_sfd_chack <= 1'b1;
    else if (rx_cnt == 7 && gmii_rx_data_d4 != 8'hd5) 
        rx_sfd_chack <= 1'b0; 
end
/*--------------------------------------------------*\
	                    CRC校验 
\*--------------------------------------------------*/
generate
	if (CRC_CHECK_EN == 0) begin

		always @(posedge phy_rx_clk) begin
 			rx_crc_chack <= 1'b1;
		end
		 
	end else if (CRC_CHECK_EN == 1) begin
		reg         crc_en;
		reg [31:0]  rc_crc;

		always @(posedge phy_rx_clk) begin
    		if (rx_cnt == 7) 
        		crc_en <= 1;
    		else if (rx_data_last) 
        		crc_en <= 0; 
		end

		always @(posedge phy_rx_clk) begin
			rx_crc_din_vld <= crc_en;
			rx_crc_din     <= gmii_rx_data_d4;
			rx_crc_done    <= rx_data_last_d6;
		end

		always @(posedge phy_rx_clk) begin //先接受低字节crc,向右边移位
    		if (rx_data_last_d0 || rx_data_last_d1 || rx_data_last_d2 || rx_data_last_d3) 
        		rc_crc <= {gmii_rx_data_d4,rc_crc[31:8]};
    		else 
        		rc_crc <= rc_crc;
		end	

		always @(posedge phy_rx_clk) begin
    		if (rx_data_last_d5 && rc_crc == rx_crc_dout) 
        		rx_crc_chack <= 1'b1;
    		else if (rx_data_last_d5 && rc_crc != rx_crc_dout) 
        		rx_crc_chack <= 1'b0;
		end

	end
endgenerate

/*--------------------------------------------------------------*\
	type和CRC校验结果写入frame_fifo、有效数据和last信号写入data_fifo  
\*---------------------------------------------------------------*/
always @(posedge phy_rx_clk) begin
    if (gmii_rx_data_vld_d4 && rx_cnt > 19 && rx_cnt < 22) //以太网帧类型在第21~22字节
        rx_frame_type <= {rx_frame_type[7:0],gmii_rx_data_d4};
    else 
        rx_frame_type <= rx_frame_type;
end

always @(posedge phy_rx_clk) begin
    if (rx_data_last_d6 && rx_preamble_chack && rx_sfd_chack && rx_target_mac_chack) begin
    	frame_din  <= {rx_crc_chack,rx_frame_type};
    	frame_wren <= 1'b1;
    end
    else begin
    	frame_din  <= frame_din;
    	frame_wren <= 1'b0;
    end  
end

always @(posedge phy_rx_clk) begin
    if (rx_preamble_chack && rx_sfd_chack && rx_target_mac_chack && gmii_rx_data_vld_d4 && rx_cnt == 21) 
       rx_wr_vld <= 1'b1; 
    else if (rx_data_last) 
       rx_wr_vld <= 1'b0;  
end

always @(posedge phy_rx_clk) begin
	data_wren <= rx_wr_vld;
	data_din  <= {rx_data_last,gmii_rx_data_d4};
end

/*--------------------------------------------------*\
	                 状态机 
\*--------------------------------------------------*/
always @(posedge clk) begin
	if (reset) 
		cur_status <= RX_IDLE;
	else 
		cur_status <= nxt_status;
end

always @(*) begin
	if (reset) begin
		nxt_status <= RX_IDLE;		
	end
	else begin
		case(cur_status)
			RX_IDLE : begin
				if (~frame_rdempty) 
					nxt_status <= RX_PRE;
				else 
					nxt_status <= cur_status;
			end
			RX_PRE : begin
				nxt_status <= RX_DATA;
			end
			RX_DATA : begin
				if (data_rden && data_dout[8])
					nxt_status <= RX_END;
				else 
					nxt_status <= cur_status;
			end
			RX_END : begin
				nxt_status <= RX_IDLE;
			end
			default : nxt_status <= RX_IDLE;
		endcase	
	end
end
/*--------------------------------------------------*\
	             从FIFO内读出数据 
\*--------------------------------------------------*/
always @(*) begin
	frame_rden <= cur_status == RX_PRE;
end

always @(posedge clk) begin
    if (frame_rden) begin
        mac_rx_frame_type <= frame_dout[15:0];
        frame_fifo_crc    <= frame_dout[16];
    end
end

always @(posedge clk) begin
    if (cur_status == RX_PRE) 
        data_rden <= 1'b1;
    else if (cur_status == RX_DATA && data_rden && data_dout[8]) 
        data_rden <= 1'b0;
    else 
        data_rden <= data_rden;
end

always @(posedge clk) begin
    if (data_rden && frame_fifo_crc) begin
    	mac_rx_data 	 <= data_dout[7:0];
    	mac_rx_data_last <= data_dout[8];
    	mac_rx_data_vld  <= 1'b1;
    end
    else begin
    	mac_rx_data 	 <= 0;
    	mac_rx_data_last <= 0;
    	mac_rx_data_vld  <= 0;
    end 
end

/*--------------------------------------------------*\
	       例化frame_fifo和data_fifo 
\*--------------------------------------------------*/

fifo_w17xd16 frame_fifo (
  .rst(phy_rx_reset),                      // input wire rst
  .wr_clk(phy_rx_clk),                // input wire wr_clk
  .rd_clk(clk),                // input wire rd_clk
  .din(frame_din),                      // input wire [16 : 0] din
  .wr_en(frame_wren),                  // input wire wr_en
  .rd_en(frame_rden),                  // input wire rd_en
  .dout(frame_dout),                    // output wire [16 : 0] dout
  .full(frame_wrfull),                    // output wire full
  .empty(frame_rdempty),                  // output wire empty
  .rd_data_count(frame_rdcount),  // output wire [3 : 0] rd_data_count
  .wr_data_count(frame_wrcount)  // output wire [3 : 0] wr_data_count
);

fifo_w9xd4096 data_fifo (
  .rst(phy_rx_reset),                      // input wire rst
  .wr_clk(phy_rx_clk),                // input wire wr_clk
  .rd_clk(clk),                // input wire rd_clk
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