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

## Archived JSON SHA-256

| File | SHA-256 |
| --- | --- |
| [`v8_gate1_source0_1024B_25M_10s.json`](board_20260922/v8_gate1_source0_1024B_25M_10s.json) | `75C0A2C5C96DD5ABF19B91DA693444FA9B63CEC318709298EC116D3EB05C8684` |
| [`v8_gate2_xadc_1024B_60s.json`](board_20260922/v8_gate2_xadc_1024B_60s.json) | `ED60D14CD3BC13F106D1AB298A3747FA0EAFD71CE18D5401833CEA09BA43ACB1` |
| [`v8_gate3_xadc_finite_32768.json`](board_20260922/v8_gate3_xadc_finite_32768.json) | `87DA6FCC0EB9D098E4ACB315ABEE01C35601F7A0EE26026849B1C843DF9A2987` |
| [`v8_gate4_xadc_1024B_300s.json`](board_20260922/v8_gate4_xadc_1024B_300s.json) | `26F69AED83D276A1085EBA0DDF7617D1B56A480A7497062F92DD9346F4F78D91` |

## Archived screenshot SHA-256

| File | SHA-256 |
| --- | --- |
| [`01_initial_status.png`](board_20260922/01_initial_status.png) | `ABC8544372452F0922BC5B47A937376517779740CBF1C4FE7A2943B8E55208BB` |
| [`02_gate1_configuration.png`](board_20260922/02_gate1_configuration.png) | `89AD6309A322CAE0B7D3F2FF4385BC1F84EE043E390B886D81BF27B591AF4EB8` |
| [`03_gate1_start.png`](board_20260922/03_gate1_start.png) | `DE680B37EA7D7AD37C5556F82F194B548D7A9CDC1BB6B8CC6B226EE0F2F24E47` |
| [`04_gate1_receiver_pass.png`](board_20260922/04_gate1_receiver_pass.png) | `B7C25B5CD138B9D694FEC2D2296A1995307B8B1A6550774A13F7FFD08EE7D92B` |
| [`05_gate1_stop.png`](board_20260922/05_gate1_stop.png) | `DCAEC19DA397F72866930A32CA392B8ECEE887FEB913BB6E05F33DEA1F1895CC` |
| [`06_gate1_final_status.png`](board_20260922/06_gate1_final_status.png) | `75F009821E0132DE5699D9FF8FB50F45435FD93764F7DA55D533C4A8FA1FE001` |
| [`07_gate2_configuration.png`](board_20260922/07_gate2_configuration.png) | `9402FF06E110A4FB833126D5DAA7A935E389F27E05C9C20BDA6F91306BE5C735` |
| [`08_gate2_pre_status.png`](board_20260922/08_gate2_pre_status.png) | `EB2C4B67DF1AD852253C188B089F5D34DF54720150262A178D62D774EAFE5DDC` |
| [`09_gate2_start.png`](board_20260922/09_gate2_start.png) | `2F0ACDB0EC2B2DCB6F48D1FA6E65BE5A0A1F5C98AEEE30650D8F3BB65F74C01F` |
| [`10_gate2_receiver_pass.png`](board_20260922/10_gate2_receiver_pass.png) | `2DC9B9DECB53DD6EDC05510DEFC7CCE52A1CF47A4D0F5175EC759DFA98E584AE` |
| [`11_gate2_stop.png`](board_20260922/11_gate2_stop.png) | `49CDC55825FFCD2A33FD01A2975F741CFB5F2413D082D0A98BC39256D9AD5526` |
| [`12_gate2_final_status.png`](board_20260922/12_gate2_final_status.png) | `61644503F8C8CCBCDD9D8DE9494CF70CACFFC7FFDC744DB302C64C087F5A1E35` |
| [`13_gate3_configuration.png`](board_20260922/13_gate3_configuration.png) | `A58617514D4F192629DDB39295F520BEBE74240DAE3895280896CAF490A3EE64` |
| [`14_gate3_start.png`](board_20260922/14_gate3_start.png) | `1F4324A32E2456591D2B2684DD2215E9BAEC67D5EBBE73D29A6E8B4D16AE1A8C` |
| [`15_gate3_receiver_pass.png`](board_20260922/15_gate3_receiver_pass.png) | `5D7893171484CD2244BE31F30760B8A8EF09D98BA3A366DBDA2A6540A327E32D` |
| [`16_gate3_final_status.png`](board_20260922/16_gate3_final_status.png) | `6A11CAAD4D2DBD6E1BAAEE19D56B6A2C78457022835139E624833A28F30D5BCA` |
| [`17_gate4_configuration.png`](board_20260922/17_gate4_configuration.png) | `FE59DCFDA48A1812F150C6A393FAC73BD6455329883785F8430E1D1015EA1F23` |
| [`18_gate4_start.png`](board_20260922/18_gate4_start.png) | `EAAA5B8EC40580CAFF9CB32280890E7E17E4BE4895F89EA89A848C75811AA59F` |
| [`19_gate4_progress.png`](board_20260922/19_gate4_progress.png) | `922D931F6E2C12B520C013AEE1C05343EA258CD7B6D4D9C2DD0C5ED3C2B55079` |
| [`20_gate4_receiver_pass.png`](board_20260922/20_gate4_receiver_pass.png) | `4A729F5A00824D90A61DFE38B85BACCCEF006E4B87A518218CA0400B9D41797D` |
| [`21_gate4_stop.png`](board_20260922/21_gate4_stop.png) | `82C28A1F87D6719513E6099ADD29653F1EAA45FE1110458B042809D2C8F4BE0F` |
| [`22_gate4_final_status.png`](board_20260922/22_gate4_final_status.png) | `F98A44E98507558F7E512E86E7F74B89CB977D538C61362152C43A027EF958D3` |

All files above are stored under `evidence/board_20260922/`.
