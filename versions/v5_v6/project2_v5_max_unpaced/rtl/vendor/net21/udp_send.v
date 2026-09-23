// -----------------------------------------------------------------------------
// Author : XiaoBai FPGA 
// File   : udp_send.v
// Create : 2024-01-02 20:00:07
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module udp_send #(
    parameter       LOCAL_PORT  = 16'h0 ,
    parameter       TARGET_PORT = 16'h0     

)(
    input                          clk,
    input                          reset,

    /*-------ip_send块交互的信号--------------------*/    
    output  reg                    udp_tx_data_vld  ,
    output  reg                    udp_tx_data_last ,
    output  reg     [7:0]          udp_tx_data      ,   
    output  reg     [15:0]         udp_tx_length    ,

    /*----------------用户发送端信号 ----------------*/    
    input                          app_tx_data_vld  ,
    input                          app_tx_data_last ,
    input       [7:0]              app_tx_data      ,
    input       [15:0]             app_tx_length    ,
    output                         app_tx_req       ,
    output                         app_tx_ready         
    );


localparam  READY_CNT_MAX =  50;

reg  [7:0]  ready_cnt          ;
reg         app_tx_data_vld_r  ;
reg         app_tx_data_last_r ;
reg  [7:0]  app_tx_data_r      ;
reg  [15:0] app_tx_length_r    ;
reg  [10:0] tx_cnt             ;

wire [7:0]  app_tx_data_delay  ;

assign app_tx_req = app_tx_data_vld;

/*------------------------------------------*\
                  打拍
\*------------------------------------------*/
always @(posedge clk) begin
    if (app_tx_ready) begin
       app_tx_data_vld_r  <= app_tx_data_vld;
       app_tx_data_last_r <= app_tx_data_last;
       app_tx_data_r      <= app_tx_data;
    end
    else begin
       app_tx_data_vld_r  <= 0;
       app_tx_data_last_r <= 0;
       app_tx_data_r      <= 0;        
    end
end

always @(posedge clk) begin
    if (app_tx_data_vld && app_tx_ready) 
        app_tx_length_r <= app_tx_length;
    else 
        app_tx_length_r <= app_tx_length_r;
end

/*------------------------------------------*\
                  tx_cnt
\*------------------------------------------*/
always @(posedge clk) begin
    if (reset) 
        tx_cnt <= 0;
    else if (app_tx_length_r < 18 && tx_cnt == 25)  //数据最小帧长为18byte
        tx_cnt <= 0;
    else if (app_tx_length_r >= 18 && tx_cnt == app_tx_length_r + 7)
        tx_cnt <= 0;
    else if (app_tx_data_vld_r || tx_cnt != 0)
        tx_cnt <= tx_cnt + 1;
    else 
        tx_cnt <= tx_cnt;
end

/*------------------------------------------*\
                   组包
\*------------------------------------------*/

always @(posedge clk) begin
    if (reset) 
        udp_tx_data <= 0;
    else begin
        case(tx_cnt)
            0 : udp_tx_data <= LOCAL_PORT[15:8];
            1 : udp_tx_data <= LOCAL_PORT[7:0];

            2 : udp_tx_data <= TARGET_PORT[15:8];
            3 : udp_tx_data <= TARGET_PORT[7:0];
            
            4 : udp_tx_data <= udp_tx_length[15:8];
            5 : udp_tx_data <= udp_tx_length[7:0];

            6 : udp_tx_data <= 0;
            7 : udp_tx_data <= 0;

            default : udp_tx_data <= app_tx_data_delay;
        endcase
    end 
end

always @(posedge clk) begin
    if (app_tx_data_vld_r && app_tx_length_r <= 18) 
        udp_tx_length <= 26;
    else if (app_tx_data_vld_r &&  app_tx_length_r > 18) 
        udp_tx_length <= app_tx_length_r + 8;
    else 
        udp_tx_length <= udp_tx_length;
end

always @(posedge clk) begin
    if (reset) 
        udp_tx_data_vld <= 0;
    else if (udp_tx_data_last) 
        udp_tx_data_vld <= 0;
    else if (app_tx_data_vld_r)
        udp_tx_data_vld <= 1;
    else 
        udp_tx_data_vld <= udp_tx_data_vld;  
end

always @(posedge clk) begin
    if (reset) 
        udp_tx_data_last <= 0;
    else if (app_tx_length_r < 18 && tx_cnt == 25) 
        udp_tx_data_last <= 1'b1;
    else if (app_tx_length_r >= 18 && tx_cnt == app_tx_length_r + 7)
        udp_tx_data_last <= 1'b1;
    else 
        udp_tx_data_last <= 0;
        
end

/*----------------------------------------------*\
    可以控制ready信号来控制以太网每帧之间的间隔
\*----------------------------------------------*/
always @(posedge clk) begin
    if (reset) 
        ready_cnt <= 0;
    else if (ready_cnt == READY_CNT_MAX) 
        ready_cnt <= 0;
    else if (app_tx_data_last || ready_cnt != 0)
        ready_cnt <= ready_cnt + 1;
    else 
        ready_cnt <= ready_cnt;
end

assign app_tx_ready  = reset ? 1'b1 : ready_cnt == 0;

/*------------------------------------------*\
                  打拍
\*------------------------------------------*/
//注意 ： 如果A的值为7，udp_tx_data_delay打拍为8拍
c_shift_ram_0 udp_delay (
  .A(7),      // input wire [5 : 0] A
  .D(app_tx_data_r),      // input wire [7 : 0] D
  .CLK(clk),  // input wire CLK
  .Q(app_tx_data_delay)      // output wire [7 : 0] Q
);

endmodule
