// -----------------------------------------------------------------------------
// Hugo's FPGA Project
// -----------------------------------------------------------------------------
// Author  : sunmingyin.huang@haw-hamburg.de
// Project : FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System
// File    : clock_reset_gen.v
// Module  : clock_reset_gen
// Created : 2026-07-26
// Revised : 2026-09-19
// Editor  : Sublime Text 3 (Build 3211), Tab Size (4)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// Keep the course clocking structure: 50 MHz board clock -> 50/200 MHz.
// MIG uses the 200 MHz clock.  Reset remains asserted for 512 50 MHz cycles
// after the MMCM locks so the external DDR3 receives a clean startup.
module clock_reset_gen (
    input  wire clk_50m_in,
    output wire clk_50m,
    output wire clk_200m,
    output wire reset_n
);
    wire locked;
    reg [9:0] reset_count = 10'd0;
    reg reset_n_reg = 1'b0;

    clk_wiz_0 u_clk_wiz (
        .clk_out1(clk_50m),
        .clk_out2(clk_200m),
        .reset(1'b0),
        .locked(locked),
        .clk_in1(clk_50m_in)
    );

    always @(posedge clk_50m or negedge locked) begin
        if (!locked) begin
            reset_count <= 10'd0;
            reset_n_reg <= 1'b0;
        end else if (!reset_count[9]) begin
            reset_count <= reset_count + 1'b1;
            reset_n_reg <= 1'b0;
        end else begin
            reset_n_reg <= 1'b1;
        end
    end

    assign reset_n = reset_n_reg;
endmodule
