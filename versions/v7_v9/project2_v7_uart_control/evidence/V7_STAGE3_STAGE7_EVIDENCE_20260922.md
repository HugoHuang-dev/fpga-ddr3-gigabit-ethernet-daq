# Project 2 V7 Board Evidence: Gates 3–7

## Validation results

Eighteen UART/receiver screenshots and four Windows RIO JSON files for the remaining V7 gates were cross-checked on September 22, 2026. Gates 3–7 all passed, completing V7 board validation.

| Gate | Configuration or function | Key result | Verdict |
| --- | --- | --- | --- |
| 3 | 1024 B, 12.5 Mword/s, 10 s | 244,178 packets; 250,038,272 B; 200.027857 Mb/s; zero data errors | PASS |
| 4 | 256 B, finite 1,048,576 words | Exactly 8,192 packets / 2,097,152 B; automatic stop and exact status counts | PASS |
| 5 | Unsupported source, in-run packet-length change, bad CRC | `UNSUPPORTED`, `BUSY`, silent discard; CRC=1, rejects=2 | PASS |
| 6 | 1024 B, maximum rate, 60 s | 2,925,342 packets; 2,995,550,208 B; 399.405333 Mb/s; zero data errors | PASS |
| 7 | 1024 B, maximum rate, 300 s | 14,626,556 packets; 14,977,593,344 B; 399.402011 Mb/s; zero data errors | PASS |

All four JSON files report `passed=true`, `first_sequence=0`, and zero missing/gap, duplicate, out-of-order, malformed, metadata, PRBS-data, and receive-completion errors.

RTL review explained `tx_underflow=12952` in the deliberately rate-limited Gate 3 and `tx_underflow=1` after Gate 5's slow fault-injection run. When `stream_expected=1` and the packetizer is idle without a complete packet, this counter increments for each starvation interval. Both 12.5 Mword/s (approximately 200 Mb/s) and 1000 words/s are below the roughly 400 Mb/s transmission capacity, so deliberate rate limiting creates idle intervals. The corresponding JSON remains continuous and PRBS-correct. After restoring maximum rate and issuing CLEAR_COUNTERS, the final 60- and 300-second statuses both returned to `tx_underflow=0`; other internal errors stayed at zero.

## Original evidence

| File |
| --- |
| [`v7_gate3_1024B_12M5_10s_20260922.json`](v7_gate3_1024B_12M5_10s_20260922.json) |
| [`v7_gate3_receiver_1024B_12M5_pass_20260922.png`](v7_gate3_receiver_1024B_12M5_pass_20260922.png) |
| [`v7_gate3_uart_configuration_20260922.png`](v7_gate3_uart_configuration_20260922.png) |
| [`v7_gate3_uart_start_20260922.png`](v7_gate3_uart_start_20260922.png) |
| [`v7_gate3_uart_stop_status_20260922.png`](v7_gate3_uart_stop_status_20260922.png) |
| [`v7_gate4_finite_1Mwords_256B_20260922.json`](v7_gate4_finite_1Mwords_256B_20260922.json) |
| [`v7_gate4_finite_configuration_20260922.png`](v7_gate4_finite_configuration_20260922.png) |
| [`v7_gate4_finite_final_status_20260922.png`](v7_gate4_finite_final_status_20260922.png) |
| [`v7_gate4_finite_receiver_pass_20260922.png`](v7_gate4_finite_receiver_pass_20260922.png) |
| [`v7_gate4_finite_uart_start_20260922.png`](v7_gate4_finite_uart_start_20260922.png) |
| [`v7_gate5_bad_crc_and_status_20260922.png`](v7_gate5_bad_crc_and_status_20260922.png) |
| [`v7_gate5_busy_rejection_20260922.png`](v7_gate5_busy_rejection_20260922.png) |
| [`v7_gate5_restore_and_clear_20260922.png`](v7_gate5_restore_and_clear_20260922.png) |
| [`v7_gate5_source_unsupported_20260922.png`](v7_gate5_source_unsupported_20260922.png) |
| [`v7_gate6_1024B_max_60s_20260922.json`](v7_gate6_1024B_max_60s_20260922.json) |
| [`v7_gate6_receiver_1024B_max_60s_pass_20260922.png`](v7_gate6_receiver_1024B_max_60s_pass_20260922.png) |
| [`v7_gate6_uart_start_20260922.png`](v7_gate6_uart_start_20260922.png) |
| [`v7_gate6_uart_stop_status_20260922.png`](v7_gate6_uart_stop_status_20260922.png) |
| [`v7_gate7_1024B_max_300s_20260922.json`](v7_gate7_1024B_max_300s_20260922.json) |
| [`v7_gate7_configuration_and_clear_20260922.png`](v7_gate7_configuration_and_clear_20260922.png) |
| [`v7_gate7_receiver_1024B_max_300s_pass_20260922.png`](v7_gate7_receiver_1024B_max_300s_pass_20260922.png) |
| [`v7_gate7_uart_stop_status_20260922.png`](v7_gate7_uart_stop_status_20260922.png) |

All listed files are stored in this `evidence` directory.
