# Project 2 V5 — Approximately 248 Mb/s Diagnostic Image

This image sets `POST_READY_IDLE_CYCLES=2200` and places the PRBS source, DDR ring controller, and packetizer under the same `adma_reset`. ILA adds two sticky MAC FIFO overflow probes: `probe39=mac_frame_fifo_overflow` and `probe40=mac_data_fifo_overflow`. Both clear on reset.

## Image and test

- Load the matching [BIT](project2_v5_top.bit) and [LTX](project2_v5_top.ltx).
- Reset and wait for MIG calibration. Start the RIO receiver and press KEY0 when it displays `ARMED`.
- A 60-second board run at approximately **248 Mb/s** had one gap of **9 packets**. All received packets passed format and PRBS checks, and both sticky MAC FIFO overflow flags stayed at zero.

This run was compared with the 225 and 315 Mb/s results to characterize intermittent gaps. The later stable operating point and receive-host comparisons are in the [V5 development log](../../../DEVELOPMENT_LOG.md#v5).
