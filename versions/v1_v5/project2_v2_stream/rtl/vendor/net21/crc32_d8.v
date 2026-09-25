module crc32_d8(
	input			clk              ,
	input           reset            ,

	input           crc_din_vld      ,
	input [7:0]     crc_din          ,
	input           crc_done         ,
	output [31:0]   crc_dout         
);

wire [7:0]  crc_din_r;
reg  [31:0] crc_dout_r;
wire [31:0] crc_data;

assign crc_dout  = ~{crc_dout_r[0],crc_dout_r[1],crc_dout_r[2],crc_dout_r[3],crc_dout_r[4],crc_dout_r[5],crc_dout_r[6],crc_dout_r[7],crc_dout_r[8],crc_dout_r[9],
                    crc_dout_r[10],crc_dout_r[11],crc_dout_r[12],crc_dout_r[13],crc_dout_r[14],crc_dout_r[15],crc_dout_r[16],crc_dout_r[17],crc_dout_r[18],
                    crc_dout_r[19],crc_dout_r[20],crc_dout_r[21],crc_dout_r[22],crc_dout_r[23],crc_dout_r[24],crc_dout_r[25],crc_dout_r[26],crc_dout_r[27],
                    crc_dout_r[28],crc_dout_r[29],crc_dout_r[30],crc_dout_r[31]};

assign crc_din_r = {crc_din[0],crc_din[1],crc_din[2],crc_din[3],crc_din[4],crc_din[5],crc_din[6],crc_din[7]};

assign   crc_data[0] = crc_din_r[6] ^ crc_din_r[0] ^ crc_dout_r[24] ^ crc_dout_r[30];
assign   crc_data[1] = crc_din_r[7] ^ crc_din_r[6] ^ crc_din_r[1] ^ crc_din_r[0] ^ crc_dout_r[24] ^ crc_dout_r[25] ^ crc_dout_r[30] ^ crc_dout_r[31];
assign   crc_data[2] = crc_din_r[7] ^ crc_din_r[6] ^ crc_din_r[2] ^ crc_din_r[1] ^ crc_din_r[0] ^ crc_dout_r[24] ^ crc_dout_r[25] ^ crc_dout_r[26] ^ crc_dout_r[30] ^ crc_dout_r[31];
assign   crc_data[3] = crc_din_r[7] ^ crc_din_r[3] ^ crc_din_r[2] ^ crc_din_r[1] ^ crc_dout_r[25] ^ crc_dout_r[26] ^ crc_dout_r[27] ^ crc_dout_r[31];
assign   crc_data[4] = crc_din_r[6] ^ crc_din_r[4] ^ crc_din_r[3] ^ crc_din_r[2] ^ crc_din_r[0] ^ crc_dout_r[24] ^ crc_dout_r[26] ^ crc_dout_r[27] ^ crc_dout_r[28] ^ crc_dout_r[30];
assign   crc_data[5] = crc_din_r[7] ^ crc_din_r[6] ^ crc_din_r[5] ^ crc_din_r[4] ^ crc_din_r[3] ^ crc_din_r[1] ^ crc_din_r[0] ^ crc_dout_r[24] ^ crc_dout_r[25] ^ crc_dout_r[27] ^ crc_dout_r[28] ^ crc_dout_r[29] ^ crc_dout_r[30] ^ crc_dout_r[31];
assign   crc_data[6] = crc_din_r[7] ^ crc_din_r[6] ^ crc_din_r[5] ^ crc_din_r[4] ^ crc_din_r[2] ^ crc_din_r[1] ^ crc_dout_r[25] ^ crc_dout_r[26] ^ crc_dout_r[28] ^ crc_dout_r[29] ^ crc_dout_r[30] ^ crc_dout_r[31];
assign   crc_data[7] = crc_din_r[7] ^ crc_din_r[5] ^ crc_din_r[3] ^ crc_din_r[2] ^ crc_din_r[0] ^ crc_dout_r[24] ^ crc_dout_r[26] ^ crc_dout_r[27] ^ crc_dout_r[29] ^ crc_dout_r[31];
assign   crc_data[8] = crc_din_r[4] ^ crc_din_r[3] ^ crc_din_r[1] ^ crc_din_r[0] ^ crc_dout_r[0] ^ crc_dout_r[24] ^ crc_dout_r[25] ^ crc_dout_r[27] ^ crc_dout_r[28];
assign   crc_data[9] = crc_din_r[5] ^ crc_din_r[4] ^ crc_din_r[2] ^ crc_din_r[1] ^ crc_dout_r[1] ^ crc_dout_r[25] ^ crc_dout_r[26] ^ crc_dout_r[28] ^ crc_dout_r[29];
assign   crc_data[10] = crc_din_r[5] ^ crc_din_r[3] ^ crc_din_r[2] ^ crc_din_r[0] ^ crc_dout_r[2] ^ crc_dout_r[24] ^ crc_dout_r[26] ^ crc_dout_r[27] ^ crc_dout_r[29];
assign   crc_data[11] = crc_din_r[4] ^ crc_din_r[3] ^ crc_din_r[1] ^ crc_din_r[0] ^ crc_dout_r[3] ^ crc_dout_r[24] ^ crc_dout_r[25] ^ crc_dout_r[27] ^ crc_dout_r[28];
assign   crc_data[12] = crc_din_r[6] ^ crc_din_r[5] ^ crc_din_r[4] ^ crc_din_r[2] ^ crc_din_r[1] ^ crc_din_r[0] ^ crc_dout_r[4] ^ crc_dout_r[24] ^ crc_dout_r[25] ^ crc_dout_r[26] ^ crc_dout_r[28] ^ crc_dout_r[29] ^ crc_dout_r[30];
assign   crc_data[13] = crc_din_r[7] ^ crc_din_r[6] ^ crc_din_r[5] ^ crc_din_r[3] ^ crc_din_r[2] ^ crc_din_r[1] ^ crc_dout_r[5] ^ crc_dout_r[25] ^ crc_dout_r[26] ^ crc_dout_r[27] ^ crc_dout_r[29] ^ crc_dout_r[30] ^ crc_dout_r[31];
assign   crc_data[14] = crc_din_r[7] ^ crc_din_r[6] ^ crc_din_r[4] ^ crc_din_r[3] ^ crc_din_r[2] ^ crc_dout_r[6] ^ crc_dout_r[26] ^ crc_dout_r[27] ^ crc_dout_r[28] ^ crc_dout_r[30] ^ crc_dout_r[31];
assign   crc_data[15] = crc_din_r[7] ^ crc_din_r[5] ^ crc_din_r[4] ^ crc_din_r[3] ^ crc_dout_r[7] ^ crc_dout_r[27] ^ crc_dout_r[28] ^ crc_dout_r[29] ^ crc_dout_r[31];
assign   crc_data[16] = crc_din_r[5] ^ crc_din_r[4] ^ crc_din_r[0] ^ crc_dout_r[8] ^ crc_dout_r[24] ^ crc_dout_r[28] ^ crc_dout_r[29];
assign   crc_data[17] = crc_din_r[6] ^ crc_din_r[5] ^ crc_din_r[1] ^ crc_dout_r[9] ^ crc_dout_r[25] ^ crc_dout_r[29] ^ crc_dout_r[30];
assign   crc_data[18] = crc_din_r[7] ^ crc_din_r[6] ^ crc_din_r[2] ^ crc_dout_r[10] ^ crc_dout_r[26] ^ crc_dout_r[30] ^ crc_dout_r[31];
assign   crc_data[19] = crc_din_r[7] ^ crc_din_r[3] ^ crc_dout_r[11] ^ crc_dout_r[27] ^ crc_dout_r[31];
assign   crc_data[20] = crc_din_r[4] ^ crc_dout_r[12] ^ crc_dout_r[28];
assign   crc_data[21] = crc_din_r[5] ^ crc_dout_r[13] ^ crc_dout_r[29];
assign   crc_data[22] = crc_din_r[0] ^ crc_dout_r[14] ^ crc_dout_r[24];
assign   crc_data[23] = crc_din_r[6] ^ crc_din_r[1] ^ crc_din_r[0] ^ crc_dout_r[15] ^ crc_dout_r[24] ^ crc_dout_r[25] ^ crc_dout_r[30];
assign   crc_data[24] = crc_din_r[7] ^ crc_din_r[2] ^ crc_din_r[1] ^ crc_dout_r[16] ^ crc_dout_r[25] ^ crc_dout_r[26] ^ crc_dout_r[31];
assign   crc_data[25] = crc_din_r[3] ^ crc_din_r[2] ^ crc_dout_r[17] ^ crc_dout_r[26] ^ crc_dout_r[27];
assign   crc_data[26] = crc_din_r[6] ^ crc_din_r[4] ^ crc_din_r[3] ^ crc_din_r[0] ^ crc_dout_r[18] ^ crc_dout_r[24] ^ crc_dout_r[27] ^ crc_dout_r[28] ^ crc_dout_r[30];
assign   crc_data[27] = crc_din_r[7] ^ crc_din_r[5] ^ crc_din_r[4] ^ crc_din_r[1] ^ crc_dout_r[19] ^ crc_dout_r[25] ^ crc_dout_r[28] ^ crc_dout_r[29] ^ crc_dout_r[31];
assign   crc_data[28] = crc_din_r[6] ^ crc_din_r[5] ^ crc_din_r[2] ^ crc_dout_r[20] ^ crc_dout_r[26] ^ crc_dout_r[29] ^ crc_dout_r[30];
assign   crc_data[29] = crc_din_r[7] ^ crc_din_r[6] ^ crc_din_r[3] ^ crc_dout_r[21] ^ crc_dout_r[27] ^ crc_dout_r[30] ^ crc_dout_r[31];
assign   crc_data[30] = crc_din_r[7] ^ crc_din_r[4] ^ crc_dout_r[22] ^ crc_dout_r[28] ^ crc_dout_r[31];
assign   crc_data[31] = crc_din_r[5] ^ crc_dout_r[23] ^ crc_dout_r[29];

always @(posedge clk) begin
    if (reset) 
        crc_dout_r <= 32'hffffffff;
    else if (crc_done) 
        crc_dout_r <= 32'hffffffff;
    else if (crc_din_vld)
        crc_dout_r <= crc_data;
    else 
    	crc_dout_r <= crc_dout_r;
end


endmodule


