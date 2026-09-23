// -----------------------------------------------------------------------------
// Author : Xiao Bai FPGA
// File   : XiaoBai_FPGA_Arbit.v
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module XiaoBai_FPGA_Arbit(
	input						   clk           ,
	input                          reset         ,

	input	      [15:0]           ch0_type      ,  //默认所有通道传来的信号都是reg型，所以进行无需打拍
	input	      [15:0]           ch0_length    ,
	input	                       ch0_data_vld  ,
	input	                       ch0_data_last ,
	input	      [7:0]            ch0_data      ,

	input	      [15:0]           ch1_type      ,
	input	      [15:0]           ch1_length    ,
	input	                       ch1_data_vld  ,
	input	                       ch1_data_last ,
	input	      [7:0]            ch1_data      ,

	output	reg   [15:0]           send_type      ,
	output	reg   [15:0]           send_length    ,
	output	reg                    send_data_vld  ,
	output	reg                    send_data_last ,
	output	reg   [7:0]            send_data      

    );
/*--------------------------------------------------*\
	                状态机信号定义 
\*--------------------------------------------------*/
reg [2:0]  cur_status;
reg [2:0]  nxt_status;
localparam IDLE      = 2'b00;
localparam CH0_SEND  = 2'b01;
localparam CH1_SEND  = 2'b10;
/*--------------------------------------------------*\
	                FIFO端口信号 
\*--------------------------------------------------*/
reg	 [31:0]  ch0_frame_din    ;
reg          ch0_frame_wren   ;
wire [31:0]  ch0_frame_dout   ;
reg 		 ch0_frame_rden   ;
wire		 ch0_frame_wrfull ;
wire		 ch0_frame_rdempty;
wire [4:0]   ch0_frame_count  ;

reg	 [31:0]  ch1_frame_din    ;
reg          ch1_frame_wren   ;
wire [31:0]  ch1_frame_dout   ;
reg 		 ch1_frame_rden   ;
wire		 ch1_frame_wrfull ;
wire		 ch1_frame_rdempty;
wire [4:0]   ch1_frame_count  ;

reg	 [8:0]   ch0_data_din    ;
reg          ch0_data_wren   ;
wire [8:0]   ch0_data_dout   ;
reg 		 ch0_data_rden   ;
wire		 ch0_data_wrfull ;
wire		 ch0_data_rdempty;
wire [11:0]  ch0_data_count  ;

reg	 [8:0]   ch1_data_din    ;
reg          ch1_data_wren   ;
wire [8:0]   ch1_data_dout   ;
reg 		 ch1_data_rden   ;
wire		 ch1_data_wrfull ;
wire		 ch1_data_rdempty;
wire [11:0]  ch1_data_count  ;

/*--------------------------------------------------*\
	               其他端口信号 
\*--------------------------------------------------*/
reg           ch0_busy;
reg           ch1_busy;

reg           ch0_frame_fifo_err;
reg           ch1_frame_fifo_err;
reg           ch0_data_fifo_err ;
reg           ch1_data_fifo_err ;

/*--------------------------------------------------*\
	          通道0、通道1的数据写入FIFO 
\*--------------------------------------------------*/
always @(posedge clk) begin
	ch0_frame_wren <= ch0_data_last;
	ch0_frame_din  <= {ch0_type,ch0_length};
	ch1_frame_wren <= ch1_data_last;
	ch1_frame_din  <= {ch1_type,ch1_length};    
end

always @(posedge clk) begin
	ch0_data_wren  <= ch0_data_vld;
	ch0_data_din   <= {ch0_data_last,ch0_data};	     
	ch1_data_wren  <= ch1_data_vld;
	ch1_data_din   <= {ch1_data_last,ch1_data};		  
end

/*--------------------------------------------------*\
	                 busy信号
\*--------------------------------------------------*/
always @(posedge clk) begin
    if (reset) 
        ch0_busy <= 0;
    else if (cur_status == CH0_SEND && send_data_last) 
        ch0_busy <= 0;
    else if (cur_status == CH0_SEND && ~ch0_frame_rdempty)
        ch0_busy <= 1;
end

always @(posedge clk) begin
    if (reset) 
        ch1_busy <= 0;
    else if (cur_status == CH1_SEND && send_data_last) 
        ch1_busy <= 0;
    else if (cur_status == CH1_SEND && ~ch1_frame_rdempty)
        ch1_busy <= 1;
end

/*--------------------------------------------------*\
	                 状态机设计
\*--------------------------------------------------*/
always @(posedge clk) begin
	if (reset) 
		cur_status <= IDLE;
	else 
		cur_status <= nxt_status;
end

always @(*) begin
	if (reset) begin
		nxt_status <= IDLE;		
	end
	else begin
		case(cur_status)
			IDLE : begin
				nxt_status <= CH0_SEND;
			end
			CH0_SEND : begin
				if (~ch0_busy && ch0_frame_rdempty)
					nxt_status <= CH1_SEND;
				else if (send_data_last)
					nxt_status <= CH1_SEND;
				else 
					nxt_status <= cur_status;
			end
			CH1_SEND : begin
				if (~ch1_busy && ch1_frame_rdempty)
					nxt_status <= CH0_SEND;
				else if (send_data_last)
					nxt_status <= CH0_SEND;
				else 
					nxt_status <= cur_status;
			end
			default : nxt_status <= IDLE;
		endcase	
	end
end

always @(posedge clk) begin
	if (reset) begin
		send_type      <= 0;
		send_length    <= 0;
        send_data_vld  <= 0;
        send_data_last <= 0;
        send_data      <= 0;
	end
	else begin
		case(cur_status)
			IDLE : begin
				send_type      <= 0;
				send_length    <= 0;
                send_data_vld  <= 0;
                send_data_last <= 0;
                send_data      <= 0;
			end
			CH0_SEND : begin
				if (ch0_frame_rden) begin
					send_type   <= ch0_frame_dout[31:16];
					send_length <= ch0_frame_dout[15:0];
				end
				else begin
					send_type   <= send_type;
					send_length <= send_length;
				end

				if (ch0_data_rden) begin
					send_data_vld  <= 1'b1;
					send_data_last <= ch0_data_dout[8];
					send_data      <= ch0_data_dout[7:0];
				end
				else begin
					send_data_vld  <= 0;
					send_data_last <= 0;
					send_data      <= 0;
				end

			end
			CH1_SEND : begin
				if (ch1_frame_rden) begin
					send_type   <= ch1_frame_dout[31:16];
					send_length <= ch1_frame_dout[15:0];
				end
				else begin
					send_type   <= send_type;
					send_length <= send_length;
				end

				if (ch1_data_rden) begin
					send_data_vld  <= 1'b1;
					send_data_last <= ch1_data_dout[8];
					send_data      <= ch1_data_dout[7:0];
				end
				else begin
					send_data_vld  <= 0;
					send_data_last <= 0;
					send_data      <= 0;
				end		
			end
			default : ;
		endcase
	end
end

/*--------------------------------------------------*\
	                FIFO读使能设计
\*--------------------------------------------------*/
always @(posedge clk) begin
    if (reset) 
        ch0_frame_rden <= 0;
    else if (cur_status == CH0_SEND && ~ch0_frame_rdempty && ~ch0_busy) 
        ch0_frame_rden <= 1'b1;
    else 
        ch0_frame_rden <= 0;
end

always @(posedge clk) begin
    if (reset) 
        ch1_frame_rden <= 0;
    else if (cur_status == CH1_SEND && ~ch1_frame_rdempty && ~ch1_busy) 
        ch1_frame_rden <= 1'b1;
    else 
        ch1_frame_rden <= 0;
end

always @(posedge clk) begin
    if (reset) 
    	ch0_data_rden <= 0;
    else if (ch0_data_rden && ch0_data_dout[8]) 
        ch0_data_rden <= 0;
    else if (ch0_frame_rden)
        ch0_data_rden <= 1'b1;
    else 
    	ch0_data_rden <= ch0_data_rden;
end

always @(posedge clk) begin
    if (reset) 
    	ch1_data_rden <= 0;
    else if (ch1_data_rden && ch1_data_dout[8]) 
        ch1_data_rden <= 0;
    else if (ch1_frame_rden)
        ch1_data_rden <= 1'b1;
    else 
    	ch1_data_rden <= ch1_data_rden;
end


/*--------------------------------------------------*\
	                   调试信号 
\*--------------------------------------------------*/
always @(posedge clk) begin
    if (reset) 
        ch0_frame_fifo_err <= 0;
    else if (ch0_frame_wren && ch0_frame_wrfull) 
        ch0_frame_fifo_err <= 1;
    else 
        ch0_frame_fifo_err <= ch0_frame_fifo_err;
end

always @(posedge clk) begin
    if (reset) 
        ch1_frame_fifo_err <= 0;
    else if (ch1_frame_wren && ch1_frame_wrfull) 
        ch1_frame_fifo_err <= 1;
    else 
        ch1_frame_fifo_err <= ch1_frame_fifo_err;
end

always @(posedge clk) begin
    if (reset) 
        ch0_data_fifo_err <= 0;
    else if (ch0_data_wren && ch0_data_wrfull) 
        ch0_data_fifo_err <= 1;
    else 
        ch0_data_fifo_err <= ch0_data_fifo_err;
end

always @(posedge clk) begin
    if (reset) 
        ch1_data_fifo_err <= 0;
    else if (ch1_data_wren && ch1_data_wrfull) 
        ch1_data_fifo_err <= 1;
    else 
        ch1_data_fifo_err <= ch1_data_fifo_err;
end

/*--------------------------------------------------*\
	                   例化 
\*--------------------------------------------------*/
fifo_w9xd2048 ch0_data_fifo (
  .clk       (clk),                 // input wire clk
  .srst      (reset),               // input wire srst
  .din       (ch0_data_din),        // input wire [8 : 0] din
  .wr_en     (ch0_data_wren),       // input wire wr_en
  .rd_en     (ch0_data_rden),       // input wire rd_en
  .dout      (ch0_data_dout),       // output wire [8 : 0] dout
  .full      (ch0_data_wrfull),     // output wire full
  .empty     (ch0_data_rdempty),    // output wire empty
  .data_count(ch0_data_count)       // output wire [11 : 0] data_count
);

fifo_w9xd2048 ch1_data_fifo (
  .clk       (clk),                 // input wire clk
  .srst      (reset),               // input wire srst
  .din       (ch1_data_din),        // input wire [8 : 0] din
  .wr_en     (ch1_data_wren),       // input wire wr_en
  .rd_en     (ch1_data_rden),       // input wire rd_en
  .dout      (ch1_data_dout),       // output wire [8 : 0] dout
  .full      (ch1_data_wrfull),     // output wire full
  .empty     (ch1_data_rdempty),    // output wire empty
  .data_count(ch1_data_count)       // output wire [11 : 0] data_count
);

fifo_w32xd16 ch0_frame_fifo (
  .clk       (clk),                // input wire clk
  .srst      (reset),              // input wire srst
  .din       (ch0_frame_din),      // input wire [31 : 0] din
  .wr_en     (ch0_frame_wren),     // input wire wr_en
  .rd_en     (ch0_frame_rden),     // input wire rd_en
  .dout      (ch0_frame_dout),     // output wire [31 : 0] dout
  .full      (ch0_frame_wrfull),   // output wire full
  .empty     (ch0_frame_rdempty),  // output wire empty
  .data_count(ch0_frame_count)    // output wire [4 : 0] data_count
);

fifo_w32xd16 ch1_frame_fifo (
  .clk       (clk),                // input wire clk
  .srst      (reset),              // input wire srst
  .din       (ch1_frame_din),      // input wire [31 : 0] din
  .wr_en     (ch1_frame_wren),     // input wire wr_en
  .rd_en     (ch1_frame_rden),     // input wire rd_en
  .dout      (ch1_frame_dout),     // output wire [31 : 0] dout
  .full      (ch1_frame_wrfull),   // output wire full
  .empty     (ch1_frame_rdempty),  // output wire empty
  .data_count(ch1_frame_count)    // output wire [4 : 0] data_count
);

endmodule
