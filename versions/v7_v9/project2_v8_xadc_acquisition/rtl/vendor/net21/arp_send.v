`timescale 1ns / 1ps

module arp_send #(
	parameter     LOCAL_MAC_ADDR    =  48'hffffffffffff              ,
	parameter     LOCAL_IP_ADDR     =  {8'd0,8'd0,8'd0,8'd0}    

)(
		input 					       clk                   ,
		input           		       reset                 ,

	    input     [47:0]               rx_source_mac_addr    ,
	    input     [31:0]               rx_source_ip_addr     ,
	    input                          arp_reply_req         ,

	    output reg                     arp_tx_data_vld       ,
	    output reg                     arp_tx_data_last      ,
	    output reg  [7:0]              arp_tx_data           ,  
	    output      [15:0]             arp_tx_length                        

    );


reg  [5:0]       tx_cnt;
reg  [47:0]      target_mac_addr;
reg  [31:0]      target_ip_addr ;

assign arp_tx_length  = 46;

always @(posedge clk) begin
    if (arp_reply_req && ~arp_tx_data_vld)begin
    	target_mac_addr <= rx_source_mac_addr;
    	target_ip_addr  <= rx_source_ip_addr; 
    end
    else begin
    	target_mac_addr <= target_mac_addr;
    	target_ip_addr  <= target_ip_addr;     	
    end   
end

always @(posedge clk) begin
    if (reset) 
        tx_cnt <= 0;
    else if (tx_cnt == 45)
        tx_cnt <= 0;
    else if (arp_reply_req || tx_cnt != 0) 
        tx_cnt <= tx_cnt + 1;
    else 
        tx_cnt <= tx_cnt;
end

always @(posedge clk) begin
    if (reset) 
        arp_tx_data_vld <= 0;
    else if (arp_reply_req) 
        arp_tx_data_vld <= 1'b1;
    else if (arp_tx_data_last)
        arp_tx_data_vld <= 1'b0;
end

always @(posedge clk) begin
    if (reset) 
        arp_tx_data_last <= 0;
    else if (tx_cnt == 45) 
        arp_tx_data_last <= 1'b1;
    else 
        arp_tx_data_last <= 0;
end

always @(posedge clk) begin
    if (reset) 
    	arp_tx_data <= 0; 
    else begin
    	case(tx_cnt)
    		0 	:	arp_tx_data <= 0                      ;	
    		1 	:	arp_tx_data <= 1                      ;
    		2 	:	arp_tx_data <= 8                      ;
    		3 	:	arp_tx_data <= 0                      ;  
    		4 	:	arp_tx_data <= 6                      ;   
    		5 	:	arp_tx_data <= 4                      ; 
    		6 	:	arp_tx_data <= 0                      ;    		    		 		  		    		    		 
    		7 	:	arp_tx_data <= 2                      ;	
    		8 	:	arp_tx_data <= LOCAL_MAC_ADDR[47:40]  ;
    		9 	:	arp_tx_data <= LOCAL_MAC_ADDR[39:32]  ;
    		10 	:	arp_tx_data <= LOCAL_MAC_ADDR[31:24]  ;  
    		11 	:	arp_tx_data <= LOCAL_MAC_ADDR[23:16]  ;   
    		12 	:	arp_tx_data <= LOCAL_MAC_ADDR[15:8]   ; 
    		13 	:	arp_tx_data <= LOCAL_MAC_ADDR[7:0]    ; 
    		14 	:	arp_tx_data <= LOCAL_IP_ADDR[31:24]   ;	
    		15 	:	arp_tx_data <= LOCAL_IP_ADDR[23:16]   ;
    		16 	:	arp_tx_data <= LOCAL_IP_ADDR[15:8]    ;
    		17 	:	arp_tx_data <= LOCAL_IP_ADDR[7:0]     ;  
    		18 	:	arp_tx_data <= target_mac_addr[47:40] ;   
    		19 	:	arp_tx_data <= target_mac_addr[39:32] ; 
    		20 	:	arp_tx_data <= target_mac_addr[31:24] ; 
    		21 	:	arp_tx_data <= target_mac_addr[23:16] ;	
    		22 	:	arp_tx_data <= target_mac_addr[15:8]  ;
    		23 	:	arp_tx_data <= target_mac_addr[7:0]   ;
    		24 	:	arp_tx_data <= target_ip_addr[31:24]  ;  
    		25 	:	arp_tx_data <= target_ip_addr[23:16]  ;   
    		26 	:	arp_tx_data <= target_ip_addr[15:8]   ; 
    		27 	:	arp_tx_data <= target_ip_addr[7:0]    ; 

    		default : arp_tx_data <= 0;
    	endcase
    end    
end

endmodule
