# Project 2 V5 — Approximately 225 Mb/s Diagnostic Image

This image retains a common reset boundary for the PRBS source and DDR ring controller, together with two sticky MAC FIFO overflow probes in ILA. It was used to compare intermittent packet gaps at different transmit rates.

## Image and test

- Load the matching [BIT](project2_v5_top.bit) and [LTX](project2_v5_top.ltx).
- Reset, wait for MIG calibration, and start the RIO receiver. Press KEY0 once after it displays `ARMED`.
- The 60-second run received **1,643,048 packets** at **224.331 Mb/s** on average. Two gaps totaled **311 missing packets**; all other receiver error counters were zero. This diagnostic run is retained as a non-passing zero-loss sample.
- Both `mac_frame_fifo_overflow` and `mac_data_fifo_overflow` stayed at zero in the corresponding ILA capture, providing transmit-side evidence for gap diagnosis.

Subsequent host-load comparisons and the stable operating point are documented in the [V5 development log](../../../DEVELOPMENT_LOG.md#v5).
