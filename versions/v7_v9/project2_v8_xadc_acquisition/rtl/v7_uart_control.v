// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : v7_uart_control.v
// Module  : v7_uart_control
// Created : 2026-09-02
// Revised : 2026-09-22
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// UART physical layer uses uart_dma, uart_rx, and uart_tx.
// Framing and CRC-16/MODBUS follow the verified
// Project1 protocol: A5 5A | TYPE | SEQ | LEN | PAYLOAD | CRC_LO | CRC_HI.
module v7_uart_control #(
    parameter integer CLK_HZ = 125000000,
    parameter integer BAUD = 115200
) (
    input  wire         clk,
    input  wire         reset,
    input  wire         uart_rxd,
    output wire         uart_txd,
    input  wire         manual_start_pulse,

    input  wire         finite_done,
    input  wire         pipeline_idle,
    input  wire [31:0]  run_words,
    input  wire [63:0]  total_words,
    input  wire [11:0]  ingress_level_words,
    input  wire [31:0]  ingress_overflow_count,
    input  wire [31:0]  ingress_underflow_count,
    input  wire [326:0] ui_status_snapshot,
    input  wire         ui_status_ack_toggle,

    output reg          run_enable,
    output reg  [7:0]   source_select,
    output reg  [31:0]  rate_words_per_sec,
    output reg  [15:0]  packet_length,
    output reg          finite_mode,
    output reg  [31:0]  finite_words,
    output reg          clear_toggle,
    output reg          status_request_toggle,
    output reg  [31:0]  crc_error_count,
    output reg  [31:0]  command_reject_count
);
    localparam [7:0] CMD_START       = 8'h03;
    localparam [7:0] CMD_STOP        = 8'h04;
    localparam [7:0] CMD_SOURCE      = 8'h10;
    localparam [7:0] CMD_RATE        = 8'h11;
    localparam [7:0] CMD_PACKET_LEN  = 8'h12;
    localparam [7:0] CMD_MODE        = 8'h13;
    localparam [7:0] CMD_CLEAR       = 8'h14;
    localparam [7:0] CMD_STATUS      = 8'h15;

    localparam [7:0] RESULT_OK          = 8'h00;
    localparam [7:0] RESULT_BAD_LENGTH  = 8'h01;
    localparam [7:0] RESULT_BAD_VALUE   = 8'h02;
    localparam [7:0] RESULT_BUSY        = 8'h03;
    localparam [7:0] RESULT_UNSUPPORTED = 8'h04;

    wire [7:0] uart_rx_data;
    wire uart_rx_en;
    reg [7:0] uart_tx_data;
    reg uart_tx_en;
    wire uart_tx_busy;

    uart_dma #(.CLK_FREQ(CLK_HZ), .BAUD_RATE(BAUD), .DATA_WIDTH(8),
        .STOP_WIDTH(1), .CHACK_TYPE(0)) u_uart_dma (
        .clk(clk), .reset(reset), .uart_txd(uart_txd), .uart_rxd(uart_rxd),
        .uart_tx_en(uart_tx_en), .uart_tx_data(uart_tx_data),
        .uart_tx_busy(uart_tx_busy), .uart_rx_en(uart_rx_en),
        .uart_rx_data(uart_rx_data));

    localparam [2:0] P_HEAD1=0, P_HEAD2=1, P_TYPE=2, P_SEQ=3,
                     P_LEN=4, P_PAYLOAD=5, P_CRC_LO=6, P_CRC_HI=7;
    reg [2:0] parse_state;
    reg [7:0] cmd_type, cmd_seq, cmd_len, bytes_left, payload_index;
    reg [7:0] cmd_payload [0:7];
    reg [7:0] rx_crc_low;
    reg request_valid;
    reg [7:0] request_type, request_seq, request_len;
    reg request_oversize;
    reg crc_clear_seen;
    wire [15:0] rx_crc16;
    wire rx_crc_reset = uart_rx_en && parse_state == P_HEAD2 &&
                        uart_rx_data == 8'h5A;
    wire rx_crc_feed = uart_rx_en && (parse_state == P_TYPE ||
        parse_state == P_SEQ || parse_state == P_LEN ||
        parse_state == P_PAYLOAD);

    crc16_d8 u_rx_crc (.clk(clk), .reset(reset),
        .crc_din_vld(rx_crc_feed), .crc_din(uart_rx_data),
        .crc_dout_f(rx_crc16), .crc_done(rx_crc_reset));

    integer pi;
    always @(posedge clk) begin
        if (reset) begin
            parse_state <= P_HEAD1;
            cmd_type <= 0; cmd_seq <= 0; cmd_len <= 0;
            bytes_left <= 0; payload_index <= 0; rx_crc_low <= 0;
            request_valid <= 0; request_type <= 0; request_seq <= 0;
            request_len <= 0; request_oversize <= 0;
            crc_error_count <= 0;
            crc_clear_seen <= 0;
            for (pi=0; pi<8; pi=pi+1) cmd_payload[pi] <= 0;
        end else begin
            request_valid <= 0;
            if (clear_toggle != crc_clear_seen) begin
                crc_clear_seen <= clear_toggle;
                crc_error_count <= 0;
            end
            if (uart_rx_en) begin
                case (parse_state)
                    P_HEAD1: if (uart_rx_data == 8'hA5) parse_state <= P_HEAD2;
                    P_HEAD2: if (uart_rx_data == 8'h5A) parse_state <= P_TYPE;
                             else if (uart_rx_data != 8'hA5) parse_state <= P_HEAD1;
                    P_TYPE: begin cmd_type <= uart_rx_data; parse_state <= P_SEQ; end
                    P_SEQ: begin cmd_seq <= uart_rx_data; parse_state <= P_LEN; end
                    P_LEN: begin
                        cmd_len <= uart_rx_data;
                        bytes_left <= uart_rx_data;
                        payload_index <= 0;
                        request_oversize <= (uart_rx_data > 8);
                        parse_state <= (uart_rx_data == 0) ? P_CRC_LO : P_PAYLOAD;
                    end
                    P_PAYLOAD: begin
                        if (payload_index < 8)
                            cmd_payload[payload_index] <= uart_rx_data;
                        payload_index <= payload_index + 1'b1;
                        bytes_left <= bytes_left - 1'b1;
                        if (bytes_left == 1) parse_state <= P_CRC_LO;
                    end
                    P_CRC_LO: begin
                        rx_crc_low <= uart_rx_data;
                        parse_state <= P_CRC_HI;
                    end
                    P_CRC_HI: begin
                        if ({uart_rx_data,rx_crc_low} == rx_crc16 &&
                            !request_oversize) begin
                            request_valid <= 1'b1;
                            request_type <= cmd_type;
                            request_seq <= cmd_seq;
                            request_len <= cmd_len;
                        end else begin
                            crc_error_count <= crc_error_count + 1'b1;
                        end
                        parse_state <= P_HEAD1;
                    end
                    default: parse_state <= P_HEAD1;
                endcase
            end
        end
    end

    reg [7:0] response_payload [0:63];
    reg [7:0] response_type, response_seq, response_len;
    reg response_pending;
    reg status_waiting;
    reg [7:0] status_seq;
    reg [7:0] tx_index;
    reg [1:0] tx_state;
    reg tx_seen_busy;
    reg tx_crc_reset;
    reg tx_crc_feed;
    wire [15:0] tx_crc16;
    wire [6:0] ui_flags = ui_status_snapshot[6:0];
    wire [31:0] ui_occupancy = ui_status_snapshot[38:7];
    wire [31:0] ui_packet_sequence = ui_status_snapshot[70:39];
    wire [31:0] ui_ring_overflow = ui_status_snapshot[102:71];
    wire [31:0] ui_ring_underflow = ui_status_snapshot[134:103];
    wire [31:0] ui_tx_overflow = ui_status_snapshot[166:135];
    wire [31:0] ui_tx_underflow = ui_status_snapshot[198:167];
    wire [31:0] requested_rate = {cmd_payload[0],cmd_payload[1],
                                  cmd_payload[2],cmd_payload[3]};
    wire [15:0] requested_packet_length = {cmd_payload[0],cmd_payload[1]};
    wire [31:0] requested_finite_words = {cmd_payload[1],cmd_payload[2],
                                          cmd_payload[3],cmd_payload[4]};

    crc16_d8 u_tx_crc (.clk(clk), .reset(reset),
        .crc_din_vld(tx_crc_feed), .crc_din(uart_tx_data),
        .crc_dout_f(tx_crc16), .crc_done(tx_crc_reset));

    function [7:0] tx_frame_byte;
        input [7:0] index;
        begin
            if (index == 0) tx_frame_byte = 8'hA5;
            else if (index == 1) tx_frame_byte = 8'h5A;
            else if (index == 2) tx_frame_byte = response_type;
            else if (index == 3) tx_frame_byte = response_seq;
            else if (index == 4) tx_frame_byte = response_len;
            else if (index < 5 + response_len)
                tx_frame_byte = response_payload[index-5];
            else if (index == 5 + response_len)
                tx_frame_byte = tx_crc16[7:0];
            else tx_frame_byte = tx_crc16[15:8];
        end
    endfunction

    task make_simple_response;
        input [7:0] rsp_type;
        input [7:0] rsp_seq;
        input [7:0] result;
        begin
            response_type <= rsp_type | 8'h80;
            response_seq <= rsp_seq;
            response_len <= 1;
            response_payload[0] <= result;
            response_pending <= 1'b1;
            if (result != RESULT_OK)
                command_reject_count <= command_reject_count + 1'b1;
        end
    endtask

    integer ri;
    always @(posedge clk) begin
        if (reset) begin
            run_enable <= 0;
            source_select <= 0;
            rate_words_per_sec <= 0;
            packet_length <= 16'd1024;
            finite_mode <= 0;
            finite_words <= 32'd512;
            clear_toggle <= 0;
            status_request_toggle <= 0;
            command_reject_count <= 0;
            response_type <= 0; response_seq <= 0; response_len <= 0;
            response_pending <= 0; status_waiting <= 0; status_seq <= 0;
            tx_index <= 0; tx_state <= 0; tx_seen_busy <= 0;
            uart_tx_en <= 0; uart_tx_data <= 0;
            tx_crc_reset <= 0; tx_crc_feed <= 0;
            for (ri=0; ri<64; ri=ri+1) response_payload[ri] <= 0;
        end else begin
            uart_tx_en <= 0;
            tx_crc_reset <= 0;
            tx_crc_feed <= 0;

            if (finite_done)
                run_enable <= 0;
            if (manual_start_pulse)
                run_enable <= 1;

            if (request_valid && !response_pending && !status_waiting &&
                tx_state == 0) begin
                case (request_type)
                    CMD_START: begin
                        if (request_len != 0)
                            make_simple_response(request_type,request_seq,RESULT_BAD_LENGTH);
                        else if (finite_mode && (finite_words == 0 || finite_words[8:0] != 0))
                            make_simple_response(request_type,request_seq,RESULT_BAD_VALUE);
                        else begin
                            run_enable <= 1;
                            make_simple_response(request_type,request_seq,RESULT_OK);
                        end
                    end
                    CMD_STOP: begin
                        if (request_len != 0)
                            make_simple_response(request_type,request_seq,RESULT_BAD_LENGTH);
                        else begin
                            run_enable <= 0;
                            make_simple_response(request_type,request_seq,RESULT_OK);
                        end
                    end
                    CMD_SOURCE: begin
                        if (request_len != 1)
                            make_simple_response(request_type,request_seq,RESULT_BAD_LENGTH);
                        else if (run_enable)
                            make_simple_response(request_type,request_seq,RESULT_BUSY);
                        else if (cmd_payload[0] != 0)
                            make_simple_response(request_type,request_seq,RESULT_UNSUPPORTED);
                        else begin
                            source_select <= cmd_payload[0];
                            make_simple_response(request_type,request_seq,RESULT_OK);
                        end
                    end
                    CMD_RATE: begin
                        if (request_len != 4)
                            make_simple_response(request_type,request_seq,RESULT_BAD_LENGTH);
                        else if (run_enable)
                            make_simple_response(request_type,request_seq,RESULT_BUSY);
                        else if (requested_rate > CLK_HZ)
                            make_simple_response(request_type,request_seq,RESULT_BAD_VALUE);
                        else begin
                            rate_words_per_sec <= requested_rate;
                            make_simple_response(request_type,request_seq,RESULT_OK);
                        end
                    end
                    CMD_PACKET_LEN: begin
                        if (request_len != 2)
                            make_simple_response(request_type,request_seq,RESULT_BAD_LENGTH);
                        else if (run_enable || !pipeline_idle)
                            make_simple_response(request_type,request_seq,RESULT_BUSY);
                        else if (requested_packet_length != 16'd256 &&
                                 requested_packet_length != 16'd512 &&
                                 requested_packet_length != 16'd1024)
                            make_simple_response(request_type,request_seq,RESULT_BAD_VALUE);
                        else begin
                            packet_length <= requested_packet_length;
                            make_simple_response(request_type,request_seq,RESULT_OK);
                        end
                    end
                    CMD_MODE: begin
                        if (request_len != 5)
                            make_simple_response(request_type,request_seq,RESULT_BAD_LENGTH);
                        else if (run_enable)
                            make_simple_response(request_type,request_seq,RESULT_BUSY);
                        else if (cmd_payload[0] > 1 ||
                            (cmd_payload[0] == 1 &&
                             (requested_finite_words == 0 ||
                              requested_finite_words[8:0] != 0)))
                            make_simple_response(request_type,request_seq,RESULT_BAD_VALUE);
                        else begin
                            finite_mode <= cmd_payload[0];
                            finite_words <= requested_finite_words;
                            make_simple_response(request_type,request_seq,RESULT_OK);
                        end
                    end
                    CMD_CLEAR: begin
                        if (request_len != 0)
                            make_simple_response(request_type,request_seq,RESULT_BAD_LENGTH);
                        else if (run_enable || !pipeline_idle)
                            make_simple_response(request_type,request_seq,RESULT_BUSY);
                        else begin
                            clear_toggle <= ~clear_toggle;
                            command_reject_count <= 0;
                            make_simple_response(request_type,request_seq,RESULT_OK);
                        end
                    end
                    CMD_STATUS: begin
                        if (request_len != 0)
                            make_simple_response(request_type,request_seq,RESULT_BAD_LENGTH);
                        else begin
                            status_seq <= request_seq;
                            status_request_toggle <= ~status_request_toggle;
                            status_waiting <= 1'b1;
                        end
                    end
                    default: make_simple_response(request_type,request_seq,RESULT_UNSUPPORTED);
                endcase
            end

            if (status_waiting &&
                ui_status_ack_toggle == status_request_toggle) begin
                status_waiting <= 0;
                response_type <= CMD_STATUS | 8'h80;
                response_seq <= status_seq;
                response_len <= 61;
                response_payload[0] <= RESULT_OK;
                response_payload[1] <= 8'h07;
                response_payload[2] <= {1'b0,ui_flags[6],ui_flags[5],
                    ui_flags[1],ui_flags[0],finite_mode,finite_done,run_enable};
                response_payload[3] <= source_select;
                response_payload[4] <= rate_words_per_sec[31:24];
                response_payload[5] <= rate_words_per_sec[23:16];
                response_payload[6] <= rate_words_per_sec[15:8];
                response_payload[7] <= rate_words_per_sec[7:0];
                response_payload[8] <= packet_length[15:8];
                response_payload[9] <= packet_length[7:0];
                response_payload[10] <= {7'd0,finite_mode};
                response_payload[11] <= finite_words[31:24];
                response_payload[12] <= finite_words[23:16];
                response_payload[13] <= finite_words[15:8];
                response_payload[14] <= finite_words[7:0];
                response_payload[15] <= run_words[31:24];
                response_payload[16] <= run_words[23:16];
                response_payload[17] <= run_words[15:8];
                response_payload[18] <= run_words[7:0];
                response_payload[19] <= {4'd0,ingress_level_words[11:8]};
                response_payload[20] <= ingress_level_words[7:0];
                response_payload[21] <= ui_occupancy[31:24];
                response_payload[22] <= ui_occupancy[23:16];
                response_payload[23] <= ui_occupancy[15:8];
                response_payload[24] <= ui_occupancy[7:0];
                response_payload[25] <= ui_packet_sequence[31:24];
                response_payload[26] <= ui_packet_sequence[23:16];
                response_payload[27] <= ui_packet_sequence[15:8];
                response_payload[28] <= ui_packet_sequence[7:0];
                response_payload[29] <= ingress_overflow_count[31:24];
                response_payload[30] <= ingress_overflow_count[23:16];
                response_payload[31] <= ingress_overflow_count[15:8];
                response_payload[32] <= ingress_overflow_count[7:0];
                response_payload[33] <= ingress_underflow_count[31:24];
                response_payload[34] <= ingress_underflow_count[23:16];
                response_payload[35] <= ingress_underflow_count[15:8];
                response_payload[36] <= ingress_underflow_count[7:0];
                response_payload[37] <= ui_ring_overflow[31:24];
                response_payload[38] <= ui_ring_overflow[23:16];
                response_payload[39] <= ui_ring_overflow[15:8];
                response_payload[40] <= ui_ring_overflow[7:0];
                response_payload[41] <= ui_ring_underflow[31:24];
                response_payload[42] <= ui_ring_underflow[23:16];
                response_payload[43] <= ui_ring_underflow[15:8];
                response_payload[44] <= ui_ring_underflow[7:0];
                response_payload[45] <= ui_tx_overflow[31:24];
                response_payload[46] <= ui_tx_overflow[23:16];
                response_payload[47] <= ui_tx_overflow[15:8];
                response_payload[48] <= ui_tx_overflow[7:0];
                response_payload[49] <= ui_tx_underflow[31:24];
                response_payload[50] <= ui_tx_underflow[23:16];
                response_payload[51] <= ui_tx_underflow[15:8];
                response_payload[52] <= ui_tx_underflow[7:0];
                response_payload[53] <= crc_error_count[31:24];
                response_payload[54] <= crc_error_count[23:16];
                response_payload[55] <= crc_error_count[15:8];
                response_payload[56] <= crc_error_count[7:0];
                response_payload[57] <= command_reject_count[31:24];
                response_payload[58] <= command_reject_count[23:16];
                response_payload[59] <= command_reject_count[15:8];
                response_payload[60] <= command_reject_count[7:0];
                response_pending <= 1'b1;
            end

            case (tx_state)
                0: if (response_pending) begin
                    response_pending <= 0;
                    tx_index <= 0;
                    tx_crc_reset <= 1'b1;
                    tx_state <= 1;
                end
                1: begin
                    uart_tx_data <= tx_frame_byte(tx_index);
                    uart_tx_en <= 1'b1;
                    tx_crc_feed <= (tx_index >= 2 &&
                                    tx_index < 5 + response_len);
                    tx_seen_busy <= 0;
                    tx_state <= 2;
                end
                2: begin
                    if (uart_tx_busy) tx_seen_busy <= 1'b1;
                    if (tx_seen_busy && !uart_tx_busy) begin
                        if (tx_index == 6 + response_len)
                            tx_state <= 0;
                        else begin
                            tx_index <= tx_index + 1'b1;
                            tx_state <= 1;
                        end
                    end
                end
                default: tx_state <= 0;
            endcase
        end
    end
endmodule
