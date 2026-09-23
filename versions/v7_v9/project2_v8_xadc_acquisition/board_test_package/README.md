# Project 2 V8 Four-Channel XADC Board Package

V8 adds on-chip, four-channel XADC acquisition to the UART-controlled DDR3 ring-buffer and UDP data path established in V7. The board image also includes the updates made after V7 board validation.

## Data sources

- `source 0`: deterministic PRBS16 source for high-rate performance and link regression.
- `source 1`: on-board XADC acquisition of temperature, VCCINT, VCCAUX, and VCCBRAM in sequence, at 1,000 records/s in total.

Each XADC record is a 16-bit little-endian word: bits `[15:14]` are the channel number, `[13:12]` are zero, and `[11:0]` hold the raw XADC code. Both sources share the `valid/ready → ingress FIFO → DDR3 ring → UDP → PC` path.

## Single-XADC resource

The Artix-7 has one XADC. MIG's original internal temperature-monitoring configuration would also consume it. V8 configures MIG for external temperature input and feeds it the acquisition module's raw temperature reading. The final implementation uses **1/1 XADC**, preserving DDR3 temperature compensation without instantiating a second XADC.

## Files

- [BIT](project2_v8_top.bit) and [LTX](project2_v8_top.ltx): board programming and ILA probes.
- `board_test_package/`: board-test files and full procedure.
- `rtl/`: V8 RTL, inherited V7/V6 data path, and vendor modules.
- [UART utility](../host/v8_uart_control.py): commands and extended status decoding.
- [Windows RIO receiver](../tools/udp_v8_monitor_rio.exe): P2V8, PRBS, and XADC validation.
- [Board procedure](BOARD_TEST_V8.md), [protocol](PROTOCOL_V8.md), and [build results](BUILD_RESULTS_V8.md).
- `evidence/`: build, simulation, and board-test evidence.

## Result

RTL, host tools, three directed behavioral simulations, Vivado 2018.3 synthesis/place/route/timing, and bitstream generation are complete. All V8 board gates passed on September 22, 2026: source 0 reached 399.422 Mb/s, and source-1 continuous (60 seconds), finite (32,768 records), and endurance (300 seconds) runs passed. PC continuity, format, data, and channel-order errors were all zero. The original JSON, screenshots, and hashes are archived.
