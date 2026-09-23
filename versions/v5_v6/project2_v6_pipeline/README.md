# Project 2 V6 — Concurrent DDR3-to-UDP Pipeline

V6 extends V5's continuous ring-buffer architecture by allowing acquisition, DDR transfers, and UDP transmission to progress concurrently. The final board image was validated near 400 Mb/s:

1. Continuous PRBS16 words enter a 4 KiB ingress FIFO.
2. Independent 1,024-byte AXI write and read bursts use the 256 KiB DDR3 ring.
3. An eight-packet transmit FIFO supplies complete packets to the UDP module.

The ingress side pauses at 3 KiB and resumes at 1 KiB. DDR draining begins at 64 KiB occupancy and stops below 16 KiB. ILA observes watermarks, concurrent reads/writes, backpressure, overflow, and underflow. The UDP payload retains the `P2V5`/`0x05` header and remains compatible with the validated RIO receiver.

## Simulation, implementation, and board test

Behavioral simulation covered ingress hysteresis, concurrent reads/writes, full-ring backpressure, and complete-packet commitment. Vivado implementation completed with **+0.887 ns WNS**, zero TNS, 14,126 LUTs, 16,434 registers, and 36 BRAM tiles.

The 60-second board run received **2,925,356 packets** and **2,995,564,544 bytes** at an average UDP payload rate of **399.405 Mb/s**. Packet sequence, format, metadata, PRBS content, and receive-completion errors were all zero. The [raw JSON](../Project2_V6_400M_USB_Kit/results/20260922_102315_345/rio_result.json) retains the full statistics.

Seven ILA triggers and 14 upper/lower-probe screenshots verified ingress high/low watermarks, 64 KiB drain start, 256 KiB full-ring backpressure, overlapping DDR reads/writes, read bursts entering the transmit FIFO, and UDP packet completion. All images are linked from the [V6 evidence index](../../../evidence/V6.md).
