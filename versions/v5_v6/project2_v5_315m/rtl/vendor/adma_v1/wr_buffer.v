// -----------------------------------------------------------------------------
// Author : XiaoBai FPGA 
// File   : wr_buffer.v
// Create : 2023-12-28 18:53:46
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module wr_buffer #(
	parameter       AXI_DATA_WIDTH     = 128 ,
	parameter       AXI_ADDR_WIDTH     = 32  

)(
	input                             clk               , //用户端写时钟
	input                             axi_clk           , //AXI4端时钟
	input                             reset             ,

    /*-------------wr_ctrl模块交互信号----------------*/
    input                             wr_req_en         ,
    input       [7:0]                 wr_burst_length   ,
    input       [AXI_ADDR_WIDTH-1:0]  wr_data_addr      ,
    input                             wr_data_valid     ,
    input       [AXI_DATA_WIDTH-1:0]  wr_data_in       ,
    input                             wr_data_last      , 
 
 	output reg                        axi_aw_req_en     , //表示AXI4写请求
 	input                             axi_aw_ready      , //axi_aw_req_en 和axi_aw_ready同时为高，开启一次AXI4写传输
 	output reg  [7:0]                 axi_aw_burst_len  ,
 	output reg  [AXI_ADDR_WIDTH-1:0]  axi_aw_addr       ,

    /*-------------axi_wr_master_模块交互信号-------------*/
 	output reg                        axi_w_valid       ,
 	input                             axi_w_ready       ,
 	output reg  [AXI_DATA_WIDTH-1:0]  axi_w_data        ,
 	output reg                        axi_w_last        ,

 	output reg                        wr_cmd_fifo_err   ,
 	output reg                        wr_data_fifo_err  

    );

(* dont_touch ="true" *)reg reset_sync_d0;    //用户端复位信号
(* dont_touch ="true" *)reg reset_sync_d1;
(* dont_touch ="true" *)reg reset_sync;

(* dont_touch ="true" *)reg a_reset_sync_d0; // axi4端的复位信号
(* dont_touch ="true" *)reg a_reset_sync_d1;
(* dont_touch ="true" *)reg a_reset_sync;

/*------------------------------------------*\
                FIFO端口信号定义
\*------------------------------------------*/
reg				cmd_wren;
wire [39:0]	    cmd_dout;
wire			cmd_rden;
wire			cmd_wrfull;
wire			cmd_rdempty;
wire [4:0]	    cmd_wrcount;
wire [4:0]	    cmd_rdcount;
reg	 [39:0]		cmd_din;

reg				data_wren;
reg				data_rden;
wire			data_wrfull;
wire			data_rdempty;

/*------------------------------------------*\
                状态机
\*------------------------------------------*/
reg [2:0] cur_status;
reg [2:0] nxt_status;

localparam WR_IDLE     = 3'b000;
localparam WR_REQ      = 3'b001;
localparam WR_DATA_EN  = 3'b010;
localparam WR_DATA_END = 3'b100;

/*--------------------------------------------------*\
				     CDC process
\*--------------------------------------------------*/
always @(posedge clk) begin
	reset_sync_d0 <= reset;
	reset_sync_d1 <= reset_sync_d0;
	reset_sync    <= reset_sync_d1;    
end

always @(posedge axi_clk) begin
	a_reset_sync_d0 <= reset;
	a_reset_sync_d1 <= a_reset_sync_d0;
	a_reset_sync    <= a_reset_sync_d1;    
end

/*--------------------------------------------------*\
		     将地址和length写入CMD fifo
\*--------------------------------------------------*/
always @(posedge clk) begin
    if (wr_req_en) begin
    	cmd_wren <= 1'b1;
    	cmd_din  <= {wr_burst_length,wr_data_addr};
    end
    else begin
    	cmd_wren <= 0;
    	cmd_din  <= 0;    	
    end  
end

/*--------------------------------------------------*\
		   状态机  ,注意时钟域，是在axi_clk时钟下
\*--------------------------------------------------*/
always @(posedge axi_clk) begin
    if (a_reset_sync) 
        cur_status <= WR_IDLE;
    else 
        cur_status <= nxt_status;
end

always @(*) begin
    if (a_reset_sync) 
        nxt_status <= WR_IDLE;
    else begin
    	case(cur_status)
    		WR_IDLE : begin
    			if (~cmd_rdempty)
    				nxt_status <= WR_REQ;
    			else 
    				nxt_status <= cur_status;
    		end
    		WR_REQ : begin
    			if (axi_aw_req_en && axi_aw_ready)	
    				nxt_status <= WR_DATA_EN;
    			else 
    				nxt_status <= cur_status;
    		end
    		WR_DATA_EN : begin
    			if (axi_w_valid && axi_w_ready && axi_w_last)
    				nxt_status <= WR_DATA_END;
    			else 
    				nxt_status <= cur_status;
    		end
    		WR_DATA_END : begin
    			nxt_status <= WR_IDLE;
    		end
    		default : nxt_status <= WR_IDLE;
    	endcase
    end
end

always @(posedge axi_clk) begin
    if (a_reset_sync) 
        axi_aw_req_en <= 0;
    else if (axi_aw_req_en && axi_aw_ready) 
        axi_aw_req_en <= 0;
    else if (cur_status == WR_REQ)
        axi_aw_req_en <= 1; 
    else 
    	axi_aw_req_en <= axi_aw_req_en;
end

always @(*) begin
    if (a_reset_sync) begin
        axi_aw_burst_len <= 0;
        axi_aw_addr      <= 0;
    end
    else begin
        axi_aw_burst_len <= cmd_dout[39:32];
        axi_aw_addr      <= cmd_dout[31:0] ;
    end
end

assign cmd_rden = axi_aw_req_en && axi_aw_ready;

/*--------------------------------------------------*\
		               cmd fifo
\*--------------------------------------------------*/
fifo_w40xd16 wr_cmd_fifo (
  .rst(reset_sync),                      // input wire rst
  .wr_clk(clk),                // input wire wr_clk
  .rd_clk(axi_clk),                // input wire rd_clk
  .din(cmd_din),                      // input wire [39 : 0] din
  .wr_en(cmd_wren),                  // input wire wr_en
  .rd_en(cmd_rden),                  // input wire rd_en
  .dout(cmd_dout),                    // output wire [39 : 0] dout
  .full(cmd_wrfull),                    // output wire full
  .empty(cmd_rdempty),                  // output wire empty
  .rd_data_count(cmd_rdcount),  // output wire [4 : 0] rd_data_count
  .wr_data_count(cmd_wrcount)  // output wire [4 : 0] wr_data_count
);

/*--------------------------------------------------*\
		       generate.... if......
\*--------------------------------------------------*/

generate
	if (AXI_DATA_WIDTH == 256) begin
		reg  [287:0] data_din;
		wire [287:0] data_dout;
		wire [9:0]   data_wrcount;
		wire [9:0]   data_rdcount; 		

		always @(posedge clk) begin
			data_din  <= {31'h0,wr_data_last,wr_data_in};
			data_wren <= wr_data_valid;
		end
		
		always @(posedge axi_clk) begin
		    if (axi_aw_req_en && axi_aw_ready) 
		        axi_w_valid <= 1'b1;
		    else if (axi_w_valid && axi_w_ready && axi_w_last) 
		        axi_w_valid <= 0;
		    else 
		        axi_w_valid <= axi_w_valid; 
		end
		
		always @(*) begin
		    if (data_rden) begin
		        axi_w_data <= data_dout[255:0];
		        axi_w_last <= data_dout[256];
		    end
		    else begin
		    	axi_w_data <= 0;
		    	axi_w_last <= 0;
		    end 
		end
		
		always @(*) begin
			data_rden <= axi_w_valid && axi_w_ready && cur_status == WR_DATA_EN;
		end
		

		fifo_w288xd512 wr_data_fifo (
		  .rst(reset_sync),                      // input wire rst
		  .wr_clk(clk),                // input wire wr_clk
		  .rd_clk(axi_clk),                // input wire rd_clk
		  .din(data_din),                      // input wire [287 : 0] din
		  .wr_en(data_wren),                  // input wire wr_en
		  .rd_en(data_rden),                  // input wire rd_en
		  .dout(data_dout),                    // output wire [287 : 0] dout
		  .full(data_wrfull),                    // output wire full
		  .empty(data_rdempty),                  // output wire empty
		  .rd_data_count(data_rdcount),  // output wire [9 : 0] rd_data_count
		  .wr_data_count(data_wrcount)  // output wire [9 : 0] wr_data_count 
		);

	end else if (AXI_DATA_WIDTH == 128) begin
		reg  [143:0] data_din;
		wire [143:0] data_dout;
		wire [9:0]   data_wrcount;
		wire [9:0]   data_rdcount; 		

		always @(posedge clk) begin
			data_din  <= {15'h0,wr_data_last,wr_data_in};
			data_wren <= wr_data_valid;
		end
		
		always @(posedge axi_clk) begin
		    if (axi_aw_req_en && axi_aw_ready) 
		        axi_w_valid <= 1'b1;
		    else if (axi_w_valid && axi_w_ready && axi_w_last) 
		        axi_w_valid <= 0;
		    else 
		        axi_w_valid <= axi_w_valid; 
		end
		
		always @(*) begin
		    if (data_rden) begin
		        axi_w_data <= data_dout[127:0];
		        axi_w_last <= data_dout[128];
		    end
		    else begin
		    	axi_w_data <= 0;
		    	axi_w_last <= 0;
		    end 
		end
		
		always @(*) begin
			data_rden <= axi_w_valid && axi_w_ready && cur_status == WR_DATA_EN;
		end
		

		fifo_w144xd512 wr_data_fifo (
		  .rst(reset_sync),                      // input wire rst
		  .wr_clk(clk),                // input wire wr_clk
		  .rd_clk(axi_clk),                // input wire rd_clk
		  .din(data_din),                      // input wire [287 : 0] din
		  .wr_en(data_wren),                  // input wire wr_en
		  .rd_en(data_rden),                  // input wire rd_en
		  .dout(data_dout),                    // output wire [287 : 0] dout
		  .full(data_wrfull),                    // output wire full
		  .empty(data_rdempty),                  // output wire empty
		  .rd_data_count(data_rdcount),  // output wire [9 : 0] rd_data_count
		  .wr_data_count(data_wrcount)  // output wire [9 : 0] wr_data_count 
		);

	end else if (AXI_DATA_WIDTH == 64) begin
		reg  [71:0] data_din;
		wire [71:0] data_dout;
		wire [9:0]  data_wrcount;
		wire [9:0]  data_rdcount; 		

		always @(posedge clk) begin
			data_din  <= {7'h0,wr_data_last,wr_data_in};
			data_wren <= wr_data_valid;
		end
		
		always @(posedge axi_clk) begin
		    if (axi_aw_req_en && axi_aw_ready) 
		        axi_w_valid <= 1'b1;
		    else if (axi_w_valid && axi_w_ready && axi_w_last) 
		        axi_w_valid <= 0;
		    else 
		        axi_w_valid <= axi_w_valid; 
		end
		
		always @(*) begin
		    if (data_rden) begin
		        axi_w_data <= data_dout[63:0];
		        axi_w_last <= data_dout[64];
		    end
		    else begin
		    	axi_w_data <= 0;
		    	axi_w_last <= 0;
		    end 
		end
		
		always @(*) begin
			data_rden <= axi_w_valid && axi_w_ready && cur_status == WR_DATA_EN;
		end
		
		fifo_w72xd512 wr_data_fifo (
		  .rst(reset_sync),                      // input wire rst
		  .wr_clk(clk),                // input wire wr_clk
		  .rd_clk(axi_clk),                // input wire rd_clk
		  .din(data_din),                      // input wire [287 : 0] din
		  .wr_en(data_wren),                  // input wire wr_en
		  .rd_en(data_rden),                  // input wire rd_en
		  .dout(data_dout),                    // output wire [287 : 0] dout
		  .full(data_wrfull),                    // output wire full
		  .empty(data_rdempty),                  // output wire empty
		  .rd_data_count(data_rdcount),  // output wire [9 : 0] rd_data_count
		  .wr_data_count(data_wrcount)  // output wire [9 : 0] wr_data_count 
		);
	end

	
endgenerate

/*------------------------------------------*\
                 调试信号
\*------------------------------------------*/
always @(posedge clk) begin
    if (reset_sync) 
        wr_data_fifo_err <= 0;
    else if (data_wrfull && data_wren) 
        wr_data_fifo_err <= 1;
    else 
        wr_data_fifo_err <= wr_data_fifo_err;
end

always @(posedge clk) begin
    if (reset_sync) 
        wr_cmd_fifo_err <= 0;
    else if (cmd_wrfull && cmd_wren) 
        wr_cmd_fifo_err <= 1;
    else 
        wr_cmd_fifo_err <= wr_cmd_fifo_err;
end

endmodule
