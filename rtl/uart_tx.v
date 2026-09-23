`timescale 1ns / 1ps

module uart_tx #(
	parameter         CLK_FREQ  = 50000000,
	parameter         BAUD_RATE = 115200,
    parameter         DATA_WIDTH = 8,
    parameter         STOP_WIDTH = 1, // 停止位宽 1或者2
    parameter         CHACK_TYPE = 0 // 0说明无校验位，1为奇校验、2为偶校验    
)(
	input                      clk,
	input                      reset,

	output reg                 uart_txd,

	input                      uart_tx_en,
	input [DATA_WIDTH-1:0]     uart_tx_data,
	output reg                 uart_tx_busy
    );


localparam BAUD_CNT_MAX       = CLK_FREQ / BAUD_RATE; //只需要计算一次，上电复位之前已经计算好了；
localparam BAUD_CNT_MAX_HALF  = BAUD_CNT_MAX / 2;

reg                             tx_flag;
reg [3:0]                       bit_cnt;
reg [$clog2(BAUD_CNT_MAX) -1:0] baud_cnt;

reg [DATA_WIDTH-1 :0] uart_tx_data_d0;


always @(posedge clk) begin
    if (uart_tx_en) 
       uart_tx_data_d0 <= uart_tx_data;
    else if (baud_cnt == BAUD_CNT_MAX && bit_cnt <= DATA_WIDTH - 1)
       uart_tx_data_d0 <= uart_tx_data_d0 >> 1;
end

always @(posedge clk) begin
    if (reset) 
        baud_cnt <= 13'd0;
    else if ( ~tx_flag || baud_cnt == BAUD_CNT_MAX) 
        baud_cnt <= 13'd0;
    else if (tx_flag)
    	baud_cnt <= baud_cnt + 1'b1;
    else
    	baud_cnt <= baud_cnt;	      
end

always @(posedge clk) begin
    if (reset) 
        bit_cnt <= 4'd0;
    else if (~tx_flag) 
        bit_cnt <= 4'd0;
    else if (baud_cnt == BAUD_CNT_MAX)
        bit_cnt <= bit_cnt + 1'b1;
    else 
    	bit_cnt <= bit_cnt;   
end


always @(posedge clk) begin
    uart_tx_busy <= tx_flag;
end

generate
    if (CHACK_TYPE == 0) begin


        always @(posedge clk) begin
            if (reset) 
                tx_flag <= 1'b0;
            else if (bit_cnt == DATA_WIDTH + STOP_WIDTH && baud_cnt == BAUD_CNT_MAX) 
                tx_flag <= 1'b0;
            else if (uart_tx_en)
                tx_flag <= 1'b1;     
        end    

        always @(posedge clk) begin
            if (reset) 
                uart_txd <= 1'b1;
            else if (~tx_flag && uart_tx_en) 
                uart_txd <= 1'b0;                     //发送起始位   
            else if (baud_cnt == BAUD_CNT_MAX && bit_cnt <= DATA_WIDTH -1 )
                uart_txd <= uart_tx_data_d0[0]; //发送数据位
            else if (baud_cnt == BAUD_CNT_MAX && bit_cnt == DATA_WIDTH)
                uart_txd <= 1'b1;                     //发送停止位    
        end


    end else if (CHACK_TYPE == 1) begin
        reg tx_chack;

        always @(posedge clk) begin
            if (reset) 
                tx_flag <= 1'b0;
            else if (bit_cnt == DATA_WIDTH + STOP_WIDTH + 1 && baud_cnt == BAUD_CNT_MAX) 
                tx_flag <= 1'b0;
            else if (uart_tx_en)
                tx_flag <= 1'b1;     
        end

         always @(posedge clk) begin
            if (reset) 
                tx_chack <= 1'b0;
            else if (bit_cnt == DATA_WIDTH + STOP_WIDTH + 1 && baud_cnt == BAUD_CNT_MAX) 
                tx_chack <= 1'b0;
            else if (baud_cnt == BAUD_CNT_MAX_HALF && bit_cnt >= 1 && bit_cnt <= DATA_WIDTH )
                tx_chack <=  tx_chack ^  uart_txd;   
        end    

        always @(posedge clk) begin
            if (reset) 
                uart_txd <= 1'b1;
            else if (~tx_flag && uart_tx_en) 
                uart_txd <= 1'b0;                     //发送起始位   
            else if (baud_cnt == BAUD_CNT_MAX && bit_cnt <= DATA_WIDTH -1 )
                uart_txd <= uart_tx_data_d0[0];     //发送数据位
            else if (baud_cnt == BAUD_CNT_MAX && bit_cnt == DATA_WIDTH ) begin
                uart_txd <= ~tx_chack;             //发送校验位
            end    
            else if (baud_cnt == BAUD_CNT_MAX && bit_cnt == DATA_WIDTH + 1)
                uart_txd <= 1'b1;                     //发送停止位    
        end

    end else if (CHACK_TYPE == 2) begin
        reg tx_chack;

        always @(posedge clk) begin
            if (reset) 
                tx_flag <= 1'b0;
            else if (bit_cnt == DATA_WIDTH + STOP_WIDTH + 1 && baud_cnt == BAUD_CNT_MAX) 
                tx_flag <= 1'b0;
            else if (uart_tx_en)
                tx_flag <= 1'b1;     
        end

         always @(posedge clk) begin
            if (reset) 
                tx_chack <= 1'b0;
            else if (bit_cnt == DATA_WIDTH + STOP_WIDTH + 1 && baud_cnt == BAUD_CNT_MAX) 
                tx_chack <= 1'b0;
            else if (baud_cnt == BAUD_CNT_MAX_HALF && bit_cnt >= 1 && bit_cnt <= DATA_WIDTH )
                tx_chack <=  tx_chack ^  uart_txd;   
        end

        always @(posedge clk) begin
            if (reset) 
                uart_txd <= 1'b1;
            else if (~tx_flag && uart_tx_en) 
                uart_txd <= 1'b0;                     //发送起始位   
            else if (baud_cnt == BAUD_CNT_MAX && bit_cnt <= DATA_WIDTH -1 )
                uart_txd <= uart_tx_data_d0[0];     //发送数据位
            else if (baud_cnt == BAUD_CNT_MAX && bit_cnt == DATA_WIDTH ) 
                uart_txd <= tx_chack;   
            else if (baud_cnt == BAUD_CNT_MAX && bit_cnt == DATA_WIDTH + 1)
                uart_txd <= 1'b1;                     //发送停止位    
        end

    end
endgenerate




endmodule
