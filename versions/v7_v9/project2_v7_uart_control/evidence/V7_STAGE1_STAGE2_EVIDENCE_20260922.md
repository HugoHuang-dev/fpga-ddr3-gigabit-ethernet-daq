# Project 2 V7 Board Evidence: Gates 1–2

## Validation results

UART screenshots and Windows RIO JSON were cross-checked on September 22, 2026. Gates 1, 2A, and 2B all passed their strict acceptance criteria.

| Gate | Configuration | Duration | Packets | Payload | Measured rate | Result |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| 1 | 512 B, 25 Mword/s, continuous | 60.0003887 s | 3,898,575 | 1,996,070,400 B | 266.140996 Mb/s | PASS |
| 2A | 256 B, 25 Mword/s, continuous | 10.0004083 s | 779,493 | 199,550,208 B | 159.633649 Mb/s | PASS |
| 2B | 1024 B, 25 Mword/s, continuous | 10.0002455 s | 487,592 | 499,294,208 B | 399.425561 Mb/s | PASS |

All three JSON files report `passed=true`, `first_sequence=0`, and zero missing packets, gaps, duplicates, out-of-order packets, format/metadata errors, PRBS errors, and receive-completion errors. All START/STOP replies were OK. After STOP, `run_enable=False`, `fatal=False`, ingress level and DDR occupancy were zero, and ingress, ring, TX, UART CRC, and command-reject counters were zero.

Payload throughput varies with packet length: approximately 159.6, 266.1, and 399.4 Mb/s. Gate 2 tests variable packetization, sequence continuity, and PRBS correctness rather than equal line rate at every packet length.

## Original evidence

| File |
| --- |
| [`v7_gate1_512B_25M_60s_20260922.json`](v7_gate1_512B_25M_60s_20260922.json) |
| [`v7_gate1_receiver_512B_25M_60s_pass_20260922.png`](v7_gate1_receiver_512B_25M_60s_pass_20260922.png) |
| [`v7_gate1_uart_final_status_20260922.png`](v7_gate1_uart_final_status_20260922.png) |
| [`v7_gate1_uart_start_stop_20260922.png`](v7_gate1_uart_start_stop_20260922.png) |
| [`v7_gate2_256B_25M_10s_20260922.json`](v7_gate2_256B_25M_10s_20260922.json) |
| [`v7_gate2_256B_receiver_pass_20260922.png`](v7_gate2_256B_receiver_pass_20260922.png) |
| [`v7_gate2_256B_uart_configuration_20260922.png`](v7_gate2_256B_uart_configuration_20260922.png) |
| [`v7_gate2_256B_uart_start_20260922.png`](v7_gate2_256B_uart_start_20260922.png) |
| [`v7_gate2_256B_uart_stop_status_20260922.png`](v7_gate2_256B_uart_stop_status_20260922.png) |
| [`v7_gate2_1024B_25M_10s_20260922.json`](v7_gate2_1024B_25M_10s_20260922.json) |
| [`v7_gate2_1024B_receiver_pass_20260922.png`](v7_gate2_1024B_receiver_pass_20260922.png) |
| [`v7_gate2_1024B_uart_configuration_20260922.png`](v7_gate2_1024B_uart_configuration_20260922.png) |
| [`v7_gate2_1024B_uart_start_20260922.png`](v7_gate2_1024B_uart_start_20260922.png) |
| [`v7_gate2_1024B_uart_stop_status_20260922.png`](v7_gate2_1024B_uart_stop_status_20260922.png) |

All listed files are stored in this `evidence` directory.
