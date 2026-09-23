# Project2 V6 continuous DDR3-to-UDP pipeline

V6 evolves the verified V5 400 Mb/s image into a three-stage streaming pipeline:

1. A continuous PRBS acquisition source fills a 4 KiB ingress FIFO.
2. Independent 1024-byte AXI write and read bursts move data through a 256 KiB DDR3 ring.
3. An eight-packet egress FIFO feeds the UDP stack at the proven 400 Mb/s pacing point.

Flow control uses hysteresis instead of single thresholds. The ingress source pauses at
3 KiB and resumes at 1 KiB. DDR draining starts at 64 KiB and continues down to 16 KiB.
Overflow and underflow conditions are counted separately and are visible in the ILA.

The UDP payload header remains `P2V5`/version `0x05`, because the packet layout did
not change. This lets V6 use the already validated `udp_v5_monitor_rio.exe` receiver.

V5 sources and evidence are not modified.

## Board status

The first controlled V6 board run passed at 399.404922 Mb/s for 60.0005534 seconds.
The receiver verified 2,925,356 packets and 2,995,564,544 payload bytes with zero
missing, gap, duplicate, out-of-order, malformed, metadata, PRBS-data, completion,
adapter-error, or adapter-discard counts. The complete result is
`../Project2_V6_400M_USB_Kit/results/20260922_102315_345`.

The V6 board ILA set is also complete. Seven triggered acquisitions, retained as 14
upper/lower panel screenshots, verify ingress pause/resume hysteresis, 64 KiB DDR
drain activation, safe 256 KiB full-ring backpressure, overlapping DDR writes and
reads, read-burst commitment to the egress FIFO, UDP packet completion, and zero
internal overflow/underflow/fatal counters. The evidence and SHA-256 manifest are in
`../evidence/ila_v6_*`.
