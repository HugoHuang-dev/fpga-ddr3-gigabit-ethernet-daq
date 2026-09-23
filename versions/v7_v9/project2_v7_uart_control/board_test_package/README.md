# Project 2 V7 UART-Control Board Package

This package contains the board validation files for V7 UART control, variable packet lengths, and finite/continuous transmission. Program the matching [BIT](project2_v7_top.bit) and [LTX](project2_v7_top.ltx), configure source, rate, packet length, and mode over UART, and validate packet sequence, format, and PRBS16 content with the PC's RIO receiver.

## Validation scope

- UART START/STOP, configuration replies, CRC checking, busy-state rejection, and atomic status reads.
- UDP payloads of 256, 512, and 1024 bytes, including a 12.5 Mword/s rate-limited run.
- Exact auto-stop and accounting for a finite run of 1,048,576 words.
- A 60-second screening run and 300-second run at approximately 400 Mb/s with 1024-byte payloads.

All board gates completed. The 300-second run received **14,626,556 packets** and **14,977,593,344 bytes** at an average **399.402 Mb/s**, with all receiver-validation errors at zero. See the [V7 board procedure](BOARD_TEST_V7.md), [Gates 1–2 evidence](../evidence/V7_STAGE1_STAGE2_EVIDENCE_20260922.md), and [Gates 3–7 evidence](../evidence/V7_STAGE3_STAGE7_EVIDENCE_20260922.md). The [version record](../README.md) and [development log](../../../../DEVELOPMENT_LOG.md#v7) document the implementation and integration work.
