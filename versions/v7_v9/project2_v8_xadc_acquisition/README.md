# Project 2 V8 — Four-Channel On-Chip XADC Acquisition

[V8 board images](../../../evidence/V8.md) · [V8 pin/timing constraints](../../../constraints/V8.md)

V8 connects Project 1's on-chip multichannel XADC acquisition module to the UART control, DDR3 ring buffer, and UDP path designed in V7. The final board version also incorporates revisions made after V7 hardware validation.

## Data sources

- `source 0`: V7's deterministic high-speed PRBS16 source for throughput and link regression.
- `source 1`: on-chip XADC sampling temperature, VCCINT, VCCAUX, and VCCBRAM in sequence, for a combined 1,000 records/s.

Each XADC record is a little-endian 16-bit word: bits `[15:14]` identify the channel, bits `[13:12]` are zero, and bits `[11:0]` contain the raw XADC reading. Both sources share `valid/ready → ingress FIFO → DDR3 ring → UDP → PC`.

## Sharing the single XADC resource

The Artix-7 device has one XADC. MIG's original configuration also uses an internal XADC for temperature compensation. V8 configures MIG for an external temperature input and feeds it the raw temperature sample from the Project 1 XADC module. The final utilization report shows `1/1` XADC, preserving DDR3 temperature compensation without a second instance.

## Directory guide

- [`project2_v8_top.bit`](project2_v8_top.bit) / [`project2_v8_top.ltx`](project2_v8_top.ltx): board programming files.
- `board_test_package/`: board-only files and complete operating procedure.
- `rtl/`: V8 RTL, inherited V7/V6 datapath, and vendor modules.
- [`host/v8_uart_control.py`](host/v8_uart_control.py): V8 UART commands and extended status decoder.
- [`tools/udp_v8_monitor_rio.exe`](tools/udp_v8_monitor_rio.exe): Windows RIO receiver validating P2V8, PRBS, and XADC records.
- [`BOARD_TEST_V8.md`](BOARD_TEST_V8.md): programming-to-acceptance procedure.
- [`PROTOCOL_V8.md`](PROTOCOL_V8.md): UART, status, and UDP formats.
- [`BUILD_RESULTS_V8.md`](BUILD_RESULTS_V8.md): simulation, implementation, timing, utilization, and hashes.
- `evidence/`: build, simulation, and board-validation evidence.

## Validation result

RTL, host tools, three behavioral simulations, Vivado 2018.3 synthesis/place-and-route, timing closure, and bitstream generation are complete. All V8 board gates completed on September 22, 2026. Source 0 reached **399.422 Mb/s**. Source 1 passed a 60-second continuous run, a 32,768-record finite run, and a 300-second endurance run. PC continuity, format, data, and channel-order error counts were all zero. Raw JSON, screenshots, and hashes are in the [V8 board evidence](evidence/V8_BOARD_VALIDATION_EVIDENCE_20260922.md) and [versioned evidence index](../../../evidence/V8.md).
