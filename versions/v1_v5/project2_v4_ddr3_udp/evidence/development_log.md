# Project 2 V4 Development Evidence

Design and verification-case planning: August 2–10, 2026  
Integrated implementation, regression, and board evidence: September 19–20, 2026

## Scope

V4 implements a one-shot transfer of a fixed 64 KiB data set:

`PRBS16 → ADMA asynchronous FIFO → AXI4 write → DDR3 → AXI4 read → ADMA asynchronous FIFO → UDP → PC`

This finite DDR3→UDP transfer established the end-to-end baseline for the later ring-buffer and sustained-throughput versions.

## 1. Datapath design and behavioral test cases

The V4 development phase defined 32,768 16-bit PRBS words, 64 UDP packets, and the interfaces among the FIFOs, AXI4/DDR3, and PC validator. Directed source/packetizer simulation cases check data order, packet boundaries, and the requirement that the source remain idle until KEY0 starts the transfer.

Those cases were run during integrated validation; their recorded result appears below.

## 2. Initial complete implementation: timing violation · September 19

The first complete synthesis/implementation produced a bitstream but failed setup timing. The detailed initial report showed about `−1.986 ns` WNS. Intermediate and final route estimates were `−1.993/−1.991 ns` WNS, with final TNS about `−520.725 ns`. The [original route log](initial_timing_failure.log) contains:

```text
Intermediate Timing Summary | WNS=-1.993 | TNS=-520.857
Estimated Timing Summary | WNS=-1.991 | TNS=-520.725
```

The worst path crossed MIG `clk_pll_i` and Clocking Wizard `clk_out2_clk_wiz_0`. They arise from different clock-management trees, but the initial constraints did not declare their asynchronous relationship; Vivado analyzed them as phase-related. The datapath actually crosses via ADMA asynchronous FIFOs, while sticky states such as `source_done` pass through explicit two-flop synchronizers.

The [V4 timing constraints](../constraints/project2_v4_timing.xdc) were corrected with:

```tcl
set_clock_groups -asynchronous \
    -group [get_clocks clk_out2_clk_wiz_0] \
    -group [get_clocks clk_pll_i]
```

This models the real CDC structure. Timing was not obtained by reducing the clock rate or excluding same-domain logic paths.

## 3. Behavioral regression and corrected implementation · September 20

The directed finite-source and UDP-packetizer simulation passed. The [September 20 simulation log](simulate.log) reports:

```text
V4 SOURCE/PACKETIZER SIM PASSED: words=16 packets=2 errors=0
```

The final [timing report](../reports/timing_summary.rpt) shows WNS `+0.982 ns`, TNS `0.000 ns`, zero failing setup endpoints, WHS `+0.056 ns`, THS `0.000 ns`, and zero failing hold endpoints: all user timing constraints were met.

The final [utilization report](../reports/utilization.rpt) records 10,538/20,800 slice LUTs (50.66%), 13,909/41,600 slice registers (33.44%), and 11/50 BRAM tiles (22.00%). The resulting files are [`project2_v4_top.bit`](../project2_v4_top.bit) and [`project2_v4_top.ltx`](../project2_v4_top.ltx).

## 4. End-to-end board validation · September 20

The board was tested with an external Type-C Gigabit Ethernet adapter. Once the PC receiver displayed `ARMED`, KEY0 started one finite transfer and LED1 lit afterward. The [formal result JSON](v4_result.json) records `passed=true`, 64/64 packets, zero missing/duplicate/out-of-order/malformed packets, zero corrupt packets/bytes, 65,536 payload-data bytes, 66,560 total UDP application-payload bytes, and 3.704822 seconds elapsed.

**Result: the finite V4 DDR3→UDP board transfer passed.** The 64 KiB PRBS data traversed ADMA write, DDR3 storage/readback, and UDP packetization; the PC found no sequence or byte-level content errors.

- [Receive progress](v4_board_test_rx_progress.png)
- [Final PASS and complete statistics](v4_board_test_pass.png)

ILA evidence also records MIG calibration, write/read burst counters, packet count, `transfer_done`, `transfer_error`, and all four FIFO error indicators.

## 5. Internal ILA evidence · September 20

Three formal capture groups were archived:

1. [Write status](v4_ila_write_status.png) and [AXI write](v4_ila_write_axi.png): triggered by `bvalid=1`; AXI write activity and an advancing write-burst count are visible, with error flags at zero.
2. [Read status](v4_ila_read_status.png) and [AXI read](v4_ila_read_axi.png): triggered by `arvalid=1`. At the trigger, `arvalid=1` and `arready=1`; `rvalid` data follows. The source had completed 32,768 words and 64 write bursts.
3. [Final status](v4_ila_final_status.png) and [final AXI/error state](v4_ila_final_axi.png): triggered by `transfer_done=1`. `phase` enters terminal state 5; write bursts, read bursts, and packets each total 64; the four FIFO errors and `transfer_error` remain zero.
