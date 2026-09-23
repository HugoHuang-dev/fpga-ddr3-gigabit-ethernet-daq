`timescale 1ns / 1ps

module uart_dma #(
	parameter         CLK_FREQ   = 50000000,
	parameter         BAUD_RATE  = 115200,
    parameter         DATA_WIDTH = 8,
    parameter         STOP_WIDTH = 1, //停止位宽 1或者2
    parameter         CHACK_TYPE = 0 // 0说明无校验位，1为奇校验、2为偶校验
)(
	input           			clk,
	input           			reset,

	output          			uart_txd,
	input           			uart_rxd,

	input           			uart_tx_en,
	input [DATA_WIDTH-1:0]      uart_tx_data,
	output          			uart_tx_busy,

	output          			uart_rx_en,
	output [DATA_WIDTH-1:0]     uart_rx_data
    );




	uart_tx #(
			.CLK_FREQ(CLK_FREQ),
			.BAUD_RATE(BAUD_RATE),
		    .DATA_WIDTH(DATA_WIDTH),
			.STOP_WIDTH(STOP_WIDTH),
			.CHACK_TYPE(CHACK_TYPE)
		) uart_tx (
			.clk          (clk),
			.reset        (reset),

			.uart_txd     (uart_txd),
			.uart_tx_en   (uart_tx_en),
			.uart_tx_data (uart_tx_data),
			.uart_tx_busy (uart_tx_busy)
		);

	uart_rx #(
			.CLK_FREQ (CLK_FREQ),
			.BAUD_RATE(BAUD_RATE),
		    .DATA_WIDTH(DATA_WIDTH),
			.STOP_WIDTH(STOP_WIDTH),
			.CHACK_TYPE(CHACK_TYPE)			
		) uart_rx (
			.clk          (clk),
			.reset        (reset),

			.uart_rxd     (uart_rxd),
			.uart_rx_en   (uart_rx_en),
			.uart_rx_data (uart_rx_data)
		);




endmodule
