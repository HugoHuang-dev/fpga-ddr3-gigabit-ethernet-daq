`timescale 1ns / 1ps

module icmp_send(
	input					 clk               ,
	input                    reset             ,

	input                    icmp_reply_req    ,  // icmp回复包请求	
	input       [15:0]       icmp_rx_identify  ,  // 标识符号
	input       [15:0]       icmp_rx_sequence  ,  // 序列号

	output reg               icmp_tx_data_vld  ,
	output reg               icmp_tx_data_last ,
	output reg     [7:0]     icmp_tx_data      ,
	output         [15:0]    icmp_tx_length            
    );

reg [5:0]   tx_cnt;
reg [15:0]  icmp_tx_identify;
reg [15:0]  icmp_tx_sequence;
reg [31:0]  icmp_tx_chack;

assign icmp_tx_length = 40;


always @(posedge clk) begin
    if (reset) begin
        icmp_tx_identify <= 0;
        icmp_tx_sequence <= 0;
    end
    else if (icmp_reply_req && ~icmp_tx_data_vld) begin
        icmp_tx_identify <= icmp_rx_identify;
        icmp_tx_sequence <= icmp_rx_sequence;
    end
    else begin
        icmp_tx_identify <= icmp_tx_identify;
        icmp_tx_sequence <= icmp_tx_sequence;    	
    end 
end

always @(posedge clk) begin
    if (reset) 
        tx_cnt <= 0;
    else if (tx_cnt == 39)
    	tx_cnt <= 0;
    else if (icmp_reply_req || tx_cnt != 0) 
        tx_cnt <= tx_cnt + 1;
    else 
        tx_cnt <= tx_cnt;
end

always @(posedge clk) begin
    if (reset) 
        icmp_tx_data_vld <= 0;
    else if (icmp_tx_data_last) 
        icmp_tx_data_vld <= 0;
    else if (icmp_reply_req)
    	icmp_tx_data_vld <= 1'b1;
    else 
    	icmp_tx_data_vld <= icmp_tx_data_vld;    
end

always @(posedge clk) begin
    if (reset) 
        icmp_tx_data_last <= 0;
    else if (tx_cnt == 39) 
        icmp_tx_data_last <= 1'b1;
    else 
        icmp_tx_data_last <= 0;
end

always @(posedge clk) begin
    if (reset) 
        icmp_tx_chack <= 0;
    else if (icmp_reply_req) 
        icmp_tx_chack <= icmp_rx_identify + icmp_rx_sequence; //相加
    else if (tx_cnt == 1)
    	icmp_tx_chack <= ~(icmp_tx_chack[31:16] + icmp_tx_chack[15:0]);
    else 
    	icmp_tx_chack <= icmp_tx_chack;
        
end

always @(posedge clk) begin
    if (reset) 
        icmp_tx_data <= 0;
    else begin
    	case(tx_cnt)
    		0 	: icmp_tx_data <= 0                     ; //类型，0应答,8为请求
    		1 	: icmp_tx_data <= 0                     ; //代码,默认为0
    		2 	: icmp_tx_data <= icmp_tx_chack[15:8]   ; //校验
    		3 	: icmp_tx_data <= icmp_tx_chack[7:0]    ;
    		4 	: icmp_tx_data <= icmp_tx_identify[15:8]; //标识,与发送方保持一致
    		5 	: icmp_tx_data <= icmp_tx_identify[7:0] ;
    		6 	: icmp_tx_data <= icmp_tx_sequence[15:8]; //序列号,与发送方保持一致
    		7 	: icmp_tx_data <= icmp_tx_sequence[7:0] ;
			default : icmp_tx_data <= 0                 ;     		    		    		    		    		    		    		    		    		    		    		
    	endcase
    end    
end


endmodule
