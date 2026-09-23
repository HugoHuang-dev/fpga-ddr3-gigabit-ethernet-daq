// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : udp_v8_tx_fifo_packetizer.v
// Module  : udp_v8_tx_fifo_packetizer
// Created : 2026-09-08
// Revised : 2026-09-22
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// V8 keeps DDR transfers fixed at BURST_BYTES but can divide each complete
// burst into 256, 512 or 1024-byte UDP payloads. Ring space is released when
// the complete DDR burst enters this FIFO, exactly as in V6. Header byte 5
// identifies the selected acquisition source (0 PRBS, 1 internal XADC).
module udp_v8_tx_fifo_packetizer #(
    parameter integer BURST_BYTES = 1024,
    parameter integer FIFO_BURSTS = 8,
    parameter integer POST_READY_IDLE_CYCLES = 950
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        clear_counters,
    input  wire [15:0] configured_payload_bytes,
    input  wire [7:0]  source_id,
    input  wire        user_rd_valid,
    input  wire        user_rd_last,
    input  wire [7:0]  user_rd_data,
    input  wire [31:0] committed_bytes_low,
    input  wire [31:0] occupancy_bytes,
    input  wire        stream_expected,
    output wire        burst_space_available,
    output wire        burst_committed,
    output reg         packet_done,
    output reg  [31:0] packet_sequence,
    output reg         framing_error,
    output reg  [13:0] fifo_byte_count,
    output reg  [3:0]  fifo_packet_count,
    output reg  [31:0] overflow_count,
    output reg  [31:0] underflow_count,
    output reg         app_tx_data_vld,
    output reg         app_tx_data_last,
    output reg  [7:0]  app_tx_data,
    output wire [15:0] app_tx_length,
    input  wire        app_tx_ready
);
    localparam integer HEADER_BYTES = 24;
    localparam integer FIFO_BYTES = BURST_BYTES * FIFO_BURSTS;
    localparam integer PTR_BITS = $clog2(FIFO_BYTES);
    localparam [2:0] ST_IDLE=0, ST_SEND=1, ST_WAIT_READY_LOW=2,
                     ST_WAIT_READY_HIGH=3, ST_PACE=4;

    reg [7:0] data_mem [0:FIFO_BYTES-1];
    reg [31:0] meta_committed [0:FIFO_BURSTS-1];
    reg [31:0] meta_occupancy [0:FIFO_BURSTS-1];
    reg [PTR_BITS-1:0] write_ptr, read_ptr;
    reg [$clog2(BURST_BYTES)-1:0] burst_write_index;
    reg [$clog2(FIFO_BURSTS)-1:0] meta_write_ptr, meta_read_ptr;
    reg [15:0] active_payload_bytes;
    reg [15:0] segment_offset;
    reg [10:0] tx_index;
    reg [2:0] state;
    reg [15:0] pace_count;
    reg starvation_latched;

    wire push = user_rd_valid && (fifo_byte_count < FIFO_BYTES);
    wire push_last = push && user_rd_last;
    wire pop = (state == ST_SEND) && (tx_index >= HEADER_BYTES);
    wire packet_last = (tx_index == HEADER_BYTES + active_payload_bytes - 1'b1);
    wire pop_last = pop && packet_last;
    wire burst_pop_last = pop_last &&
        (segment_offset + active_payload_bytes == BURST_BYTES);
    wire payload_valid = configured_payload_bytes == 16'd256 ||
                         configured_payload_bytes == 16'd512 ||
                         configured_payload_bytes == 16'd1024;

    assign burst_space_available = (fifo_byte_count <= FIFO_BYTES-BURST_BYTES);
    assign burst_committed = push_last;
    assign app_tx_length = HEADER_BYTES + active_payload_bytes;

    function [7:0] header_byte;
        input [4:0] index;
        input [31:0] seq_value;
        input [31:0] committed;
        input [31:0] occupancy;
        input [15:0] payload_bytes;
        reg [15:0] packet_bytes;
        begin
            packet_bytes = HEADER_BYTES + payload_bytes;
            case (index)
                0:  header_byte = "P";
                1:  header_byte = "2";
                2:  header_byte = "V";
                3:  header_byte = "8";
                4:  header_byte = 8'h08;
                5:  header_byte = source_id;
                6:  header_byte = packet_bytes[15:8];
                7:  header_byte = packet_bytes[7:0];
                8:  header_byte = seq_value[31:24];
                9:  header_byte = seq_value[23:16];
                10: header_byte = seq_value[15:8];
                11: header_byte = seq_value[7:0];
                12: header_byte = payload_bytes[15:8];
                13: header_byte = payload_bytes[7:0];
                14: header_byte = HEADER_BYTES[15:8];
                15: header_byte = HEADER_BYTES[7:0];
                16: header_byte = committed[31:24];
                17: header_byte = committed[23:16];
                18: header_byte = committed[15:8];
                19: header_byte = committed[7:0];
                20: header_byte = occupancy[31:24];
                21: header_byte = occupancy[23:16];
                22: header_byte = occupancy[15:8];
                default: header_byte = occupancy[7:0];
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            write_ptr<=0; read_ptr<=0; burst_write_index<=0;
            meta_write_ptr<=0; meta_read_ptr<=0;
            fifo_byte_count<=0; fifo_packet_count<=0;
            active_payload_bytes<=16'd1024; segment_offset<=0;
            tx_index<=0; state<=ST_IDLE; pace_count<=0;
            packet_done<=0; packet_sequence<=0; framing_error<=0;
            overflow_count<=0; underflow_count<=0;
            starvation_latched<=0;
            app_tx_data_vld<=0; app_tx_data_last<=0; app_tx_data<=0;
        end else begin
            packet_done<=0; app_tx_data_vld<=0; app_tx_data_last<=0;

            if (clear_counters) begin
                write_ptr<=0; read_ptr<=0; burst_write_index<=0;
                meta_write_ptr<=0; meta_read_ptr<=0;
                fifo_byte_count<=0; fifo_packet_count<=0;
                segment_offset<=0; tx_index<=0; state<=ST_IDLE;
                packet_sequence<=0; framing_error<=0;
                overflow_count<=0; underflow_count<=0;
                starvation_latched<=0;
            end else begin
                if (user_rd_valid && fifo_byte_count == FIFO_BYTES) begin
                    framing_error<=1;
                    overflow_count<=overflow_count+1'b1;
                end

                if (stream_expected && packet_sequence != 0 &&
                    state == ST_IDLE && fifo_packet_count == 0) begin
                    if (!starvation_latched)
                        underflow_count<=underflow_count+1'b1;
                    starvation_latched<=1;
                end else if (fifo_packet_count != 0) begin
                    starvation_latched<=0;
                end

                if (push) begin
                    data_mem[write_ptr]<=user_rd_data;
                    write_ptr<=write_ptr+1'b1;
                    if (user_rd_last != (burst_write_index == BURST_BYTES-1))
                        framing_error<=1;
                    if (user_rd_last) begin
                        burst_write_index<=0;
                        meta_committed[meta_write_ptr]<=committed_bytes_low;
                        meta_occupancy[meta_write_ptr]<=occupancy_bytes;
                        meta_write_ptr<=meta_write_ptr+1'b1;
                    end else burst_write_index<=burst_write_index+1'b1;
                end

                case ({push,pop})
                    2'b10: fifo_byte_count<=fifo_byte_count+1'b1;
                    2'b01: fifo_byte_count<=fifo_byte_count-1'b1;
                    default: fifo_byte_count<=fifo_byte_count;
                endcase
                case ({push_last,burst_pop_last})
                    2'b10: fifo_packet_count<=fifo_packet_count+1'b1;
                    2'b01: fifo_packet_count<=fifo_packet_count-1'b1;
                    default: fifo_packet_count<=fifo_packet_count;
                endcase

                case (state)
                    ST_IDLE: begin
                        if (fifo_packet_count != 0 && app_tx_ready) begin
                            if (!payload_valid) begin
                                framing_error<=1;
                            end else begin
                                active_payload_bytes<=configured_payload_bytes;
                                tx_index<=0;
                                state<=ST_SEND;
                            end
                        end
                    end
                    ST_SEND: begin
                        app_tx_data_vld<=1;
                        app_tx_data_last<=packet_last;
                        if (tx_index < HEADER_BYTES)
                            app_tx_data<=header_byte(tx_index[4:0],packet_sequence,
                                meta_committed[meta_read_ptr],
                                meta_occupancy[meta_read_ptr],active_payload_bytes);
                        else begin
                            app_tx_data<=data_mem[read_ptr];
                            read_ptr<=read_ptr+1'b1;
                        end
                        if (packet_last) begin
                            packet_done<=1;
                            packet_sequence<=packet_sequence+1'b1;
                            if (segment_offset + active_payload_bytes == BURST_BYTES) begin
                                segment_offset<=0;
                                meta_read_ptr<=meta_read_ptr+1'b1;
                            end else begin
                                segment_offset<=segment_offset+active_payload_bytes;
                            end
                            state<=ST_WAIT_READY_LOW;
                        end else tx_index<=tx_index+1'b1;
                    end
                    ST_WAIT_READY_LOW: if (!app_tx_ready)
                        state<=ST_WAIT_READY_HIGH;
                    ST_WAIT_READY_HIGH: if (app_tx_ready) begin
                        if (POST_READY_IDLE_CYCLES == 0) state<=ST_IDLE;
                        else begin pace_count<=POST_READY_IDLE_CYCLES; state<=ST_PACE; end
                    end
                    ST_PACE: begin
                        if (pace_count>1) pace_count<=pace_count-1'b1;
                        else begin pace_count<=0; state<=ST_IDLE; end
                    end
                    default: state<=ST_IDLE;
                endcase
            end
        end
    end
endmodule
