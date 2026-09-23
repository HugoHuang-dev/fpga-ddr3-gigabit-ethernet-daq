# Project 2 V9 Full-Validation Board Package

V9 extends the V8 dual-source design and common DDR3-to-UDP path. The final board image incorporates the updates following V8 board validation.

- Source 0: deterministic high-rate PRBS16 stimulus.
- Source 1: live on-chip four-channel XADC acquisition.
- Shared path: `valid/ready → ingress FIFO → DDR3 ring → packetizer → UDP → PC`.

V9 adds reproducible checks at each data-path stage: three self-checking ModelSim tests for FIFO, DDR ring control, packetization, sequence, backpressure, and fault injection; separate ILAs in the 125 MHz acquisition, MIG `ui_clk`, and PHY RX domains; a 64-bit first-sample index in the P2V9 UDP header; simultaneous host validation of packet sequence, sample index, and payload; bounded-sample Windows RIO monitoring; and post-implementation Vivado timing, resource, and DRC reports.

## Recorded status

Local checks passed: ModelSim **3/3**, PC validator self-tests **10/10**, and Vivado 2018.3 placement/routing and BIT/LTX generation with WNS **+0.292 ns**, TNS **0**, and zero DRC errors. On September 23, V9 board Gates 1 (source 0, 60 seconds), 2 (finite XADC 32,768), and 3 (XADC, 300 seconds) each produced passing JSON. Four ILA traces cover acquisition, RX, DDR commit, and the separately rearmed packet-done event.

Gate 5 ran for the full 3600 seconds, but its original JSON reports `passed=false`: average UDP payload throughput **397.845440 Mb/s**, **174,834,426 received packets**, **179,030,452,224 received bytes**, and **1,824 missing packets across 30 gaps**. PRBS16 byte checks, format, and metadata checks on received data all remained error-free. The run and its evidence are complete; Gate 5 did not meet the planned one-hour zero-loss criterion. V8 and V9 results are archived separately.

See the [validation plan](VALIDATION_PLAN_V9.md), [board procedure](BOARD_TEST_V9.md), [local evidence and hashes](../evidence/V9_PREBOARD_EVIDENCE_20260923.md), and [final board evidence](../evidence/board_20260923/V9_BOARD_EVIDENCE_FINAL.md). The latter contains the original board results, 22 screenshots, four ILA captures, Gate 5 JSON, 60 bounded sample fragments, and the verification conclusions.
