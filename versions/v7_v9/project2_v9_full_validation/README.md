# Project 2 V9 — Full Validation and Metric Collection

[V9 board images and native ILA files](../../../evidence/V9.md) · [V9 pin/timing constraints](../../../constraints/V9.md)

V9 is the system-level validation version of Project 2. It builds on V8's two-source design and DDR3→UDP main path; its final board image also incorporates revisions made after V8 hardware validation:

- Source 0: deterministic high-speed PRBS16 test data.
- Source 1: measured four-channel on-chip XADC data from Project 1.
- Shared path: `valid/ready → ingress FIFO → DDR3 ring → packetizer → UDP → PC`.

V9 brings the stages together into repeatable, quantitative system checks:

1. ModelSim self-checks FIFO behavior, DDR ring control, packetization, packet sequence, backpressure, and fault injection.
2. ILAs observe the 125 MHz acquisition domain, MIG `ui_clk` domain, and PHY RX domain separately; buses are not sampled directly across clock domains.
3. The P2V9 UDP header adds a 64-bit first-sample index so the PC can verify packet sequence, sample index, and payload independently.
4. The Windows RIO receiver reports throughput and all error categories online, retaining JSON summaries and bounded sample fragments rather than the entire payload stream.
5. Vivado records post-implementation timing, LUT/FF/BRAM/XADC utilization, WNS/TNS/WHS/THS, and DRC.

## Validation result

ModelSim **3/3** self-checks and PC validator **10/10** self-tests passed. Vivado 2018.3 completed routing and BIT/LTX generation with **+0.292 ns WNS**, zero TNS, and zero DRC errors. Board Gate 1 (60-second high-speed PRBS16), Gate 2 (finite XADC), and Gate 3 (300-second continuous XADC) all passed. Four ILA files record acquisition handshakes, PHY RX activity, DDR write commitment, and `packet_done`.

Gate 5 ran for the full **3,600 seconds** and received **174,834,426 packets** at an average UDP payload rate of **397.845 Mb/s**, or approximately **99.998957%** packet delivery. Thirty sequence gaps totaled 1,824 missing packets. All delivered packets passed PRBS, format, and metadata checks. This run did **not** pass its strict zero-loss criterion; the raw outcome is retained unchanged.

The [validation plan](VALIDATION_PLAN_V9.md) defines each gate and the [board procedure](BOARD_TEST_V9.md) gives the operating steps. The [implementation/simulation record](evidence/V9_PREBOARD_EVIDENCE_20260923.md), [board evidence](evidence/board_20260923/V9_BOARD_EVIDENCE_FINAL.md), and [versioned evidence index](../../../evidence/V9.md) provide the individual results.
