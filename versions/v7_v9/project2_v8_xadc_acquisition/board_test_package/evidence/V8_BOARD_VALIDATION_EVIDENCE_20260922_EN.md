# Project2 V8 board-validation evidence — 2026-09-22

## Verdict

All five V8 board gates pass. The evidence independently closes both source 0
(high-rate deterministic PRBS16) and source 1 (real internal XADC) through the
common ingress FIFO, DDR3 ring, UDP transmitter and Windows RIO receiver. No
retest or RTL/BIT change is required.

The user supplied 23 screenshot references. Two references pointed to the same
physical file (`f3b55f8d77093b53bb0d90a7db88e462.png`), so the archive contains
22 unique screenshots plus four original JSON result files.

## Quantitative results

| Gate | Source / mode | Duration | Packets | Payload bytes | Rate | Acquisition checks | Verdict |
| --- | --- | ---: | ---: | ---: | ---: | --- | --- |
| 0 | Initial status | — | — | — | — | V8, MIG calibrated, XADC mask `0xF`, drop 0, plausible live values | PASS |
| 1 | source 0, continuous, 1024 B, 25 Mword/s | 10.0003399 s | 487,592 | 499,294,208 | 399.421790 Mb/s | PRBS and every host error field 0 | PASS |
| 2 | source 1, continuous, 1024 B | 60.0875404 s | 144 | 147,456 | 0.019632 Mb/s | 73,728 records; 18,432/channel; order errors 0 | PASS |
| 3 | source 1, finite 32,768, 1024 B | 5.0185699 s after first packet | 64 | 65,536 | 0.104470 Mb/s | exact 32,768 records; 8,192/channel; finite done | PASS |
| 4 | source 1, continuous, 1024 B | 300.0529577 s | 624 | 638,976 | 0.017036 Mb/s | 319,488 records; 79,872/channel; order errors 0 | PASS |

Across all four JSON files, missing packets, gap events, duplicate and
out-of-order packets, malformed packets, metadata errors, data-error packets,
data-error bytes and receive-completion errors are zero. For source 1,
`xadc_invalid_records=0` and `xadc_channel_order_errors=0`.

The observed source-1 raw ranges were:

| Gate | temperature | VCCINT | VCCAUX | VCCBRAM |
| --- | --- | --- | --- | --- |
| 60 s | 2675–2706 | 1364–1378 | 2439–2455 | 1364–1379 |
| finite | 2677–2705 | 1363–1377 | 2440–2455 | 1366–1380 |
| 300 s | 2673–2707 | 1364–1377 | 2438–2455 | 1364–1378 |

These values are nonzero, within the 12-bit XADC range, and consistent with the
UART status samples (roughly 56.7–58.4 °C, VCCINT/VCCBRAM about 1.00 V and
VCCAUX about 1.79 V).

## Slow-source `tx_underflow` interpretation

The post-run UART screenshots show `tx_underflow=6` after the 60-second source-1
continuous test and `tx_underflow=13` after the 300-second test. Source 1 emits
only 1,000 records/s and the DDR path drains at a 65,536-byte high-water mark.
The packetizer therefore encounters a bounded empty interval between complete
DDR batches and counts that interval once. This is an idle/starvation diagnostic,
not a truncated-packet indication. The conclusion is supported by:

- zero loss, gaps, reordering, malformed data, XADC format/order faults and
  receive-completion errors in both JSON files;
- empty ingress and DDR occupancy after STOP;
- `xadc_drop_count=0` and `fatal=False`;
- the exact finite run completing 32,768 records / 64 packets with
  `tx_underflow=0`.

The board guide now states this source-1 exception explicitly. All other
internal error counters are zero in the final statuses.

## Archived JSON

| File |
| --- |
| [`v8_gate1_source0_1024B_25M_10s.json`](../../evidence/board_20260922/v8_gate1_source0_1024B_25M_10s.json) |
| [`v8_gate2_xadc_1024B_60s.json`](../../evidence/board_20260922/v8_gate2_xadc_1024B_60s.json) |
| [`v8_gate3_xadc_finite_32768.json`](../../evidence/board_20260922/v8_gate3_xadc_finite_32768.json) |
| [`v8_gate4_xadc_1024B_300s.json`](../../evidence/board_20260922/v8_gate4_xadc_1024B_300s.json) |

## Archived screenshots

| File |
| --- |
| [`01_initial_status.png`](../../evidence/board_20260922/01_initial_status.png) |
| [`02_gate1_configuration.png`](../../evidence/board_20260922/02_gate1_configuration.png) |
| [`03_gate1_start.png`](../../evidence/board_20260922/03_gate1_start.png) |
| [`04_gate1_receiver_pass.png`](../../evidence/board_20260922/04_gate1_receiver_pass.png) |
| [`05_gate1_stop.png`](../../evidence/board_20260922/05_gate1_stop.png) |
| [`06_gate1_final_status.png`](../../evidence/board_20260922/06_gate1_final_status.png) |
| [`07_gate2_configuration.png`](../../evidence/board_20260922/07_gate2_configuration.png) |
| [`08_gate2_pre_status.png`](../../evidence/board_20260922/08_gate2_pre_status.png) |
| [`09_gate2_start.png`](../../evidence/board_20260922/09_gate2_start.png) |
| [`10_gate2_receiver_pass.png`](../../evidence/board_20260922/10_gate2_receiver_pass.png) |
| [`11_gate2_stop.png`](../../evidence/board_20260922/11_gate2_stop.png) |
| [`12_gate2_final_status.png`](../../evidence/board_20260922/12_gate2_final_status.png) |
| [`13_gate3_configuration.png`](../../evidence/board_20260922/13_gate3_configuration.png) |
| [`14_gate3_start.png`](../../evidence/board_20260922/14_gate3_start.png) |
| [`15_gate3_receiver_pass.png`](../../evidence/board_20260922/15_gate3_receiver_pass.png) |
| [`16_gate3_final_status.png`](../../evidence/board_20260922/16_gate3_final_status.png) |
| [`17_gate4_configuration.png`](../../evidence/board_20260922/17_gate4_configuration.png) |
| [`18_gate4_start.png`](../../evidence/board_20260922/18_gate4_start.png) |
| [`19_gate4_progress.png`](../../evidence/board_20260922/19_gate4_progress.png) |
| [`20_gate4_receiver_pass.png`](../../evidence/board_20260922/20_gate4_receiver_pass.png) |
| [`21_gate4_stop.png`](../../evidence/board_20260922/21_gate4_stop.png) |
| [`22_gate4_final_status.png`](../../evidence/board_20260922/22_gate4_final_status.png) |

All files above are stored under `evidence/board_20260922/`.
