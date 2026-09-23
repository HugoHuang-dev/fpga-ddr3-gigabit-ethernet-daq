`timescale 1ns / 1ps

module uart_rx #(
	parameter         CLK_FREQ   = 50000000,  //时钟频率
	parameter         BAUD_RATE  = 115200,    //波特率
    parameter         DATA_WIDTH = 8,         //数据位宽
    parameter         STOP_WIDTH = 1,         //停止位宽 1或者2
    parameter         CHACK_TYPE = 0          // 0说明无校验位，1为奇校验、2为偶校验
)(
	input				           clk,
	input                          reset,

	input                          uart_rxd,

	output reg                     uart_rx_en,
	output reg [DATA_WIDTH-1:0]    uart_rx_data
    );




localparam BAUD_CNT_MAX       = CLK_FREQ / BAUD_RATE; //只需要计算一次，上电复位之前已经计算好了；
localparam BAUD_CNT_MAX_HALF  = BAUD_CNT_MAX / 2;

reg uart_rxd_d0;
reg uart_rxd_d1;

reg                              rx_flag;
reg [3:0]                        bit_cnt;
reg [$clog2(BAUD_CNT_MAX) -1 :0] baud_cnt; //clog2函数自动计算最小位宽



//FPGA外部信号传入FPGA内部，进行打两拍，降低亚稳态
always @(posedge clk) begin
	uart_rxd_d0 <= uart_rxd;
	uart_rxd_d1 <= uart_rxd_d0;
end


always @(posedge clk) begin
    if (reset) 
        baud_cnt <= 13'd0;
    else if ( ~rx_flag || baud_cnt == BAUD_CNT_MAX) 
        baud_cnt <= 13'd0;
    else if (rx_flag)
        baud_cnt <= baud_cnt + 1'b1;
    else
        baud_cnt <= baud_cnt;         
end

always @(posedge clk) begin
    if (reset) 
        bit_cnt <= 4'd0;
    else if (~rx_flag) 
        bit_cnt <= 4'd0;
    else if (baud_cnt == BAUD_CNT_MAX)
        bit_cnt <= bit_cnt + 1'b1;
    else 
        bit_cnt <= bit_cnt;   
end

always @(posedge clk) begin
    if (reset)
        uart_rx_data <= 8'd0;
    else if (baud_cnt == BAUD_CNT_MAX_HALF && bit_cnt >= 1 && bit_cnt <= DATA_WIDTH) 
        uart_rx_data <= {uart_rxd_d1,uart_rx_data[DATA_WIDTH - 1 :1]};
    else 
        uart_rx_data <= uart_rx_data;
end


generate
    if (CHACK_TYPE == 0) begin 

        always @(posedge clk) begin
            if (reset) 
                rx_flag <= 1'b0;  
            else if (~uart_rxd_d0 && uart_rxd_d1) 
                rx_flag <= 1'b1;
            else if (bit_cnt == DATA_WIDTH && baud_cnt == BAUD_CNT_MAX) 
                rx_flag <= 1'b0; 
        end       

        always @(posedge clk) begin
            if (reset) 
                uart_rx_en <= 1'b0;
            else if (baud_cnt == BAUD_CNT_MAX_HALF + 2 && bit_cnt == DATA_WIDTH) 
                uart_rx_en <= 1'b1;
            else 
                uart_rx_en <= 1'b0;
        end


    end else if (CHACK_TYPE == 1) begin
        reg rx_chack;

        always @(posedge clk) begin
            if (reset) 
                rx_chack <= 1'b0;  
            else if (bit_cnt == DATA_WIDTH + 1 && baud_cnt == BAUD_CNT_MAX) 
                rx_chack <= 1'b0;  
            else if (baud_cnt == BAUD_CNT_MAX_HALF && bit_cnt >= 1 && bit_cnt <= DATA_WIDTH + 1) 
                rx_chack <= rx_chack ^ uart_rxd_d1; 
        end 


        always @(posedge clk) begin
            if (reset) 
                rx_flag <= 1'b0;  
            else if (~uart_rxd_d0 && uart_rxd_d1) 
                rx_flag <= 1'b1;
            else if (bit_cnt == DATA_WIDTH + 1 && baud_cnt == BAUD_CNT_MAX) 
                rx_flag <= 1'b0; 
        end  

         always @(posedge clk) begin
            if (reset)              
                uart_rx_en <= 1'b0;                                                 //奇校验
            else if (baud_cnt == BAUD_CNT_MAX_HALF + 2 && bit_cnt == DATA_WIDTH + 1 && rx_chack) 
                uart_rx_en <= 1'b1;
            else 
                uart_rx_en <= 1'b0;
        end

    end else if (CHACK_TYPE == 2) begin
        reg rx_chack;

         always @(posedge clk) begin
            if (reset) 
                rx_flag <= 1'b0;  
            else if (~uart_rxd_d0 && uart_rxd_d1) 
                rx_flag <= 1'b1;
            else if (bit_cnt == DATA_WIDTH + 1 && baud_cnt == BAUD_CNT_MAX) 
                rx_flag <= 1'b0; 
        end  

        always @(posedge clk) begin
            if (reset) 
                rx_chack <= 1'b0;  
            else if (bit_cnt == DATA_WIDTH + 1 && baud_cnt == BAUD_CNT_MAX) 
                rx_chack <= 1'b0;  
            else if (baud_cnt == BAUD_CNT_MAX_HALF && bit_cnt >= 1 && bit_cnt <= DATA_WIDTH + 1) 
                rx_chack <= rx_chack ^ uart_rxd_d1; 
        end 

        always @(posedge clk) begin
            if (reset)              
                uart_rx_en <= 1'b0;                                                    //偶校验
            else if (baud_cnt == BAUD_CNT_MAX_HALF + 2 && bit_cnt == DATA_WIDTH + 1 && ~rx_chack) 
                uart_rx_en <= 1'b1;
            else 
                uart_rx_en <= 1'b0;
        end

    end
endgenerate


endmodule
