# Project 2 V8 Build Results

## Implementation

- Tool: Vivado 2018.3; device: `xc7a35tfgg484-2`; top: `project2_v8_top`.
- Synthesis, placement, routing, DRC, and bitstream generation: passed.
- Routed timing: WNS `+0.544 ns`, TNS `0 ns`, WHS `+0.031 ns`, THS `0 ns`; all user timing constraints met.
- DDR bus skew: all 20 checks MET; minimum margin `+6.778 ns`.
- DRC: 0 errors, 37 warnings, 2 advisories.
- Final optimization, placement, routing, and bitstream generation: 0 critical warnings and 0 errors.

| Resource | Used | Available | Utilization |
| --- | ---: | ---: | ---: |
| Slice LUT | 14,910 | 20,800 | 71.68% |
| Slice Register | 18,166 | 41,600 | 43.67% |
| Block RAM Tile | 36 | 50 | 72.00% |
| DSP | 0 | 90 | 0% |
| XADC | 1 | 1 | 100% |

The DRC warnings stem from inherited MIG/UDP IP, including input-buffer connections, asynchronous RAM controls, clock output buffers, and nets with no routable load. The original reports are retained under `reports/`; warnings are not presented as an entirely clean DRC run.

## Single-XADC integration

The initial build tried to use the device's sole XADC for both MIG internal temperature monitoring and the acquisition module, causing placement to fail with `XADC sites = 1`. The final design sets MIG XADC monitoring to Disabled/external temperature and connects the acquisition module's `temperature_raw` to MIG `device_temp_i`. Placement and routing then pass, and utilization confirms exactly one XADC instance.

The original acquisition module and the V8 copy have the same SHA-256:

`EF467DFEA1DC4867C85712CECA18A9C35EA69B958DF6607F58DEC8A45A58F936`

## Simulation

- XADC wrapper: PASS for four-channel DRP reads, valid/ready hold, 0/1/2/3 ordering, and finite counts.
- P2V8 packetizer: PASS for source tag and division of a 1024-byte burst into four 256-byte datagrams.
- UART control: PASS for serial receive timing, source 0/1, extended V8 status, rejection behavior, and CRC counters.
- Vivado XSim UART regression: PASS.

## SHA-256

- [`project2_v8_top.bit`](project2_v8_top.bit): `DAD9D9AE15C2380DC22ECF348BA5507E48AE659749717C62D5A78C3BD80637A4`
- [`project2_v8_top.ltx`](project2_v8_top.ltx): `84486ADDAB52CD3D26FB2410E629CBD61E271F0ACE1C2CA75D86E0B8ECBBCBE7`
- [`tools/udp_v8_monitor_rio.exe`](tools/udp_v8_monitor_rio.exe): `194E6BCA54DF2DD3E8B8C8C7A5FF3BC902DFFC0A632BCE676467245A7D88826A`
- [`host/v8_uart_control.py`](host/v8_uart_control.py): `E05B69AB79AB1A808ECFA4542B3741F9F61D2767014B0B39501B3C4CB8CA0B8E`

## Board acceptance

Independent V8 board validation completed on September 22, 2026. The 10-second high-rate source-0 regression received 487,592 packets and 499,294,208 payload bytes at 399.421790 Mb/s. Source-1 gates validated 73,728 live records over 60 seconds, exactly 32,768 finite records, and 319,488 records over 300 seconds. Every JSON reports `passed=true` with zero missing packets, gaps, duplicates, out-of-order packets, format/metadata/data errors, XADC channel-order errors, and receive-completion errors.

The [board evidence record](evidence/V8_BOARD_VALIDATION_EVIDENCE_20260922.md) contains the full quantitative results, screenshots, and SHA-256 hashes. V8 implementation and board acceptance are complete.
