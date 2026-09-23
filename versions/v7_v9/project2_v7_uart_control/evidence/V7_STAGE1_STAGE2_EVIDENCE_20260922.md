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

## Original evidence and SHA-256

| File | SHA-256 |
| --- | --- |
| [`v7_gate1_512B_25M_60s_20260922.json`](v7_gate1_512B_25M_60s_20260922.json) | `76370192C216539D54112E0D73053AC934AB23F5AAE5220A3D177DF7165BAD5E` |
| [`v7_gate1_receiver_512B_25M_60s_pass_20260922.png`](v7_gate1_receiver_512B_25M_60s_pass_20260922.png) | `8142C14FE5937D51CC6971DE2AECC202981FDA0B428815A964B33B9CED9BF6B5` |
| [`v7_gate1_uart_final_status_20260922.png`](v7_gate1_uart_final_status_20260922.png) | `A13BCD134B444AFAF8C86207983E5E01F94892C370857C940B495362480DF62C` |
| [`v7_gate1_uart_start_stop_20260922.png`](v7_gate1_uart_start_stop_20260922.png) | `E4756A420557B7512EEE3A347408A7C80490A6BD291A44DEB71745CAE98D41D4` |
| [`v7_gate2_256B_25M_10s_20260922.json`](v7_gate2_256B_25M_10s_20260922.json) | `6D8C208C17B133629DE5F3928B922A7D0ABF288AA2941397145D3EA5B96C5B2B` |
| [`v7_gate2_256B_receiver_pass_20260922.png`](v7_gate2_256B_receiver_pass_20260922.png) | `15F210117E4ABF9F9F22CC0FC1ADB6C42D652D78ECE3866D5715F7DF34A85F83` |
| [`v7_gate2_256B_uart_configuration_20260922.png`](v7_gate2_256B_uart_configuration_20260922.png) | `7AD2BDD556979EE238FDA7FB30DA4C9FF8C7F2996F4DA2FE99B3EA39E0610B39` |
| [`v7_gate2_256B_uart_start_20260922.png`](v7_gate2_256B_uart_start_20260922.png) | `836545D81C3B98B1FC5819818A7949CF509C515C43CE3960CD9973D630068791` |
| [`v7_gate2_256B_uart_stop_status_20260922.png`](v7_gate2_256B_uart_stop_status_20260922.png) | `CA7C279F0CD8EB48954BB768A82E91BF6D5762C371B79B544C8583C4897EC4B4` |
| [`v7_gate2_1024B_25M_10s_20260922.json`](v7_gate2_1024B_25M_10s_20260922.json) | `B4A19A0A01F30EFA7A208A6BF10D75ACEF847C51E985272668DEFAB93AFADAF7` |
| [`v7_gate2_1024B_receiver_pass_20260922.png`](v7_gate2_1024B_receiver_pass_20260922.png) | `274504CCD0425EEB7DC89829D8F792B05ED15D3D3AB48FF4A542CF53D392B471` |
| [`v7_gate2_1024B_uart_configuration_20260922.png`](v7_gate2_1024B_uart_configuration_20260922.png) | `A724069D3EA91038FFC220E43BCFC9E9FC8F3E652D7EC3DDC3279F0696143A87` |
| [`v7_gate2_1024B_uart_start_20260922.png`](v7_gate2_1024B_uart_start_20260922.png) | `5322B4BE03F9286CAB7843FCC75F1EDBA6BB1CEBA586B04CE2F67035A5234C6B` |
| [`v7_gate2_1024B_uart_stop_status_20260922.png`](v7_gate2_1024B_uart_stop_status_20260922.png) | `EE14D36BE8CDBF85A120232216B6DB66B7A2B600A396F7D95D29E830F3754F6F` |

All listed files are stored in this `evidence` directory.
