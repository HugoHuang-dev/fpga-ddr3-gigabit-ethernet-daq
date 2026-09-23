// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : v4_transfer_controller.v
// Module  : v4_transfer_controller
// Created : 2026-08-02
// Revised : 2026-09-20
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module v4_transfer_controller #(
    parameter integer TOTAL_PACKETS = 64,
    parameter integer POST_WRITE_DELAY = 2048
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        init_calib_complete,
    input  wire        source_done,
    input  wire        axi_bvalid,
    input  wire        axi_bready,
    input  wire [1:0]  axi_bresp,
    input  wire        axi_rvalid,
    input  wire [1:0]  axi_rresp,
    input  wire        user_rd_req_busy,
    input  wire        user_rd_last,
    input  wire        packet_buffer_available,
    input  wire        packet_done,
    input  wire        packetizer_error,
    input  wire        wr_cmd_fifo_err,
    input  wire        wr_data_fifo_err,
    input  wire        rd_cmd_fifo_err,
    input  wire        rd_data_fifo_err,
    output reg         user_rd_req,
    output reg  [2:0]  phase,
    output reg  [7:0]  write_burst_count,
    output reg  [7:0]  read_burst_count,
    output reg  [7:0]  packet_count,
    output reg         transfer_done,
    output reg         transfer_error
);
    localparam [2:0] PH_WAIT_WRITE  = 3'd0;
    localparam [2:0] PH_WRITE_DELAY = 3'd1;
    localparam [2:0] PH_REQUEST     = 3'd2;
    localparam [2:0] PH_WAIT_READ   = 3'd3;
    localparam [2:0] PH_WAIT_PACKET = 3'd4;
    localparam [2:0] PH_DONE        = 3'd5;

    reg [15:0] delay_count;
    reg        source_done_meta;
    reg        source_done_sync;

    always @(posedge clk) begin
        if (reset) begin
            source_done_meta <= 1'b0;
            source_done_sync <= 1'b0;
            user_rd_req      <= 1'b0;
            phase            <= PH_WAIT_WRITE;
            write_burst_count<= 8'd0;
            read_burst_count <= 8'd0;
            packet_count     <= 8'd0;
            delay_count      <= 16'd0;
            transfer_done    <= 1'b0;
            transfer_error   <= 1'b0;
        end else begin
            // source_done is a sticky indication generated in the 125 MHz
            // acquisition domain. Synchronize it before using it here.
            source_done_meta <= source_done;
            source_done_sync <= source_done_meta;
            user_rd_req <= 1'b0;

            if (axi_bvalid && axi_bready) begin
                write_burst_count <= write_burst_count + 1'b1;
                if (axi_bresp != 2'b00)
                    transfer_error <= 1'b1;
            end
            if (axi_rvalid && axi_rresp != 2'b00)
                transfer_error <= 1'b1;
            if (packetizer_error || wr_cmd_fifo_err || wr_data_fifo_err ||
                rd_cmd_fifo_err || rd_data_fifo_err)
                transfer_error <= 1'b1;

            case (phase)
                PH_WAIT_WRITE: begin
                    if (source_done_sync && write_burst_count == TOTAL_PACKETS)
                        phase <= PH_WRITE_DELAY;
                end

                PH_WRITE_DELAY: begin
                    if (delay_count == POST_WRITE_DELAY-1) begin
                        delay_count <= 16'd0;
                        phase <= PH_REQUEST;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                PH_REQUEST: begin
                    if (packet_buffer_available && !user_rd_req_busy) begin
                        user_rd_req <= 1'b1;
                        phase <= PH_WAIT_READ;
                    end
                end

                PH_WAIT_READ: begin
                    if (user_rd_last) begin
                        read_burst_count <= read_burst_count + 1'b1;
                        phase <= PH_WAIT_PACKET;
                    end
                end

                PH_WAIT_PACKET: begin
                    if (packet_done) begin
                        packet_count <= packet_count + 1'b1;
                        if (packet_count == TOTAL_PACKETS-1) begin
                            transfer_done <= 1'b1;
                            phase <= PH_DONE;
                        end else begin
                            phase <= PH_REQUEST;
                        end
                    end
                end

                default: phase <= PH_DONE;
            endcase
        end
    end
endmodule
