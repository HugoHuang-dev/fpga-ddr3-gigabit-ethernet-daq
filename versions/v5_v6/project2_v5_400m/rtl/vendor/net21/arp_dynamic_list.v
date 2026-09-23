

module arp_dynamic_list(
		input				     clk             ,
		input       		     reset           ,

/*---------更新动态链表的写入端口信号----------------*/
		input                    wr_arp_en       ,
		input      [31:0]        wr_ip_addr      ,
		input      [47:0]        wr_mac_addr     ,

/*---------查询动态链表的读出端口信号----------------*/
		input                    rd_arp_en       ,
		input      [31:0]        rd_ip_addr      ,
		output reg [47:0]        rd_mac_addr     ,
		output reg               rd_mac_addr_vld
    );

localparam SIZE = 4; //arp动态链表的深度

reg [31:0] ip_addr_buffer [SIZE-1:0];
reg [47:0] mac_addr_buffer[SIZE-1:0];
reg [3:0]  pointer;  //指针

always @(posedge clk) begin
    if (reset) begin 
    	ip_addr_buffer[0]  <= 0;  //初始化
    	ip_addr_buffer[1]  <= 0;
    	ip_addr_buffer[2]  <= 0;
    	ip_addr_buffer[3]  <= 0;    	
    	mac_addr_buffer[0] <= 0;
    	mac_addr_buffer[1] <= 0;
    	mac_addr_buffer[2] <= 0;
    	mac_addr_buffer[3] <= 0;    
    	pointer            <= 0;	    	    	   	    	
    end
    else if (wr_arp_en) begin
    	case(wr_ip_addr)
    		ip_addr_buffer[0] : mac_addr_buffer[0] <= wr_mac_addr; //更新mac地址
    		ip_addr_buffer[1] : mac_addr_buffer[1] <= wr_mac_addr;
    		ip_addr_buffer[2] : mac_addr_buffer[2] <= wr_mac_addr;
    		ip_addr_buffer[3] : mac_addr_buffer[3] <= wr_mac_addr;  
    		default : begin
    			mac_addr_buffer[pointer] <= wr_mac_addr;
    			ip_addr_buffer [pointer] <= wr_ip_addr;
    			pointer                  <= pointer == 3 ? 0 : pointer + 1;
    		end  		    		
    	endcase
    end   
end

always @(posedge clk) begin
    if (reset) begin
    	rd_mac_addr      <= 0;
    end  
    else if (rd_arp_en) begin
    	case(rd_ip_addr)
    		ip_addr_buffer[0] : rd_mac_addr <= mac_addr_buffer[0];
    		ip_addr_buffer[1] : rd_mac_addr <= mac_addr_buffer[1];
    		ip_addr_buffer[2] : rd_mac_addr <= mac_addr_buffer[2];
    		ip_addr_buffer[3] : rd_mac_addr <= mac_addr_buffer[3];   
    		default :           rd_mac_addr <= 0;		
    	endcase
    end      
end

always @(posedge clk) begin
    if (reset) 
        rd_mac_addr_vld <= 0;
    else if (rd_arp_en) 
        rd_mac_addr_vld <= 1'b1;
    else 
        rd_mac_addr_vld <= 0;
end

endmodule
