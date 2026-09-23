# Project 2 V9 Validation and Metrics Plan

## 1. Scope

V9 validates two defined sources:

- Source 0 exercises high-rate link throughput, byte-exact deterministic data, and long-duration continuity.
- Source 1 exercises live four-channel XADC record format, channel order, sample accounting, and the complete DDR3-to-PC path.

Each P2V9 packet carries a packet sequence and a 64-bit `first_word_index`. Sequence numbers measure UDP packet continuity; the independent word index checks the payload's 16-bit record range and exposes offsets that packet counting alone would miss.

## 2. ModelSim gates

Each test must run under ModelSim 10.6c with `vlog`/`vsim` and end in a self-checking PASS.

| Gate | RTL under test | Normal path | Backpressure / boundaries | Injected faults |
| --- | --- | --- | --- | --- |
| M1 | `v6_ingress_fifo` | Ordering, occupancy level, watermarks, complete bursts | `out_ready=0`, full/empty, flush | Write while full; read while empty |
| M2 | `udp_v9_tx_fifo_packetizer` | P2V9 header, 256/512/1024 B, payload, sequence, word index | Deassert/reassert `app_tx_ready` | Early/late `user_rd_last`, FIFO overflow, starvation |
| M3 | `v6_pipeline_controller` | Write, commit, read, release, occupancy | No TX space; AXI/ADMA busy; ring wrap | AXI response, FIFO, and packetizer faults with fatal latching |
| M4 | Combined audit | Every testbench passes | Unknown values cannot masquerade as a pass | Every injection increments its matching counter or latches fatal |

Retain each testbench transcript, the combined summary, tool version, and SHA-256 of the RTL under test.

## 3. Clock-domain-specific ILA capture

V9 uses three independent ILAs:

| ILA | Sampling clock | Signals observed |
| --- | --- | --- |
| Acquisition/control | `clk_125m` | Source valid/ready/data, ingress FIFO, drain, UART-control-domain state |
| DDR/ring/TX | MIG `ui_clk` | AXI handshakes, ring pointers/occupancy, packetizer FIFO, sequence/word index, TX handshakes |
| Ethernet RX | `phy_rx_clk` | PHY RX-domain valid/error/data only |

Do not attach an unsynchronized multibit bus from another domain directly to an ILA. A transferred control bit is observed in the destination-domain ILA only after synchronization or a stable snapshot handshake. Trigger and export each ILA independently.

## 4. Online PC validation

The Windows RIO receiver checks P2V9 magic, version, header/packet/payload lengths, and source; 32-bit packet-sequence gaps, duplicates, and reordering; 64-bit first-word-index continuity; byte-for-byte source-0 PRBS16 reference generated from the explicit sample index; source-1 reserved bits, 0→1→2→3 channel order, counts and min/max; per-second and aggregate throughput; and receive-completion errors. Gap/error details, JSON, and datagram-prefix samples are bounded in size so the long run does not accumulate the complete stream in memory or on disk.

Before board testing, the receiver's offline `--self-test` must pass both normal-stream cases and independently injected packet-sequence, sample-index, payload-byte, and header faults, each detected by its corresponding counter.

## 5. Vivado implementation metrics

Use Vivado 2018.3 to synthesize, place, route, run DRC, and generate a bitstream for `xc7a35tfgg484-2`. Capture metrics from the **routed design**, not synthesis estimates:

- WNS, TNS, WHS, THS.
- Slice LUT, Slice Register, Block RAM Tile, DSP, and XADC.
- DRC error, warning, and advisory counts.
- Actual instances and clock connections of all three ILAs.
- SHA-256 for BIT, LTX, PC EXE, UART utility, and key RTL.

The implementation gate requires WNS ≥ 0, TNS = 0, WHS ≥ 0, THS = 0, zero DRC errors, and successful bitstream generation.

## 6. Board and endurance gates

Run in sequence, preserving every failed gate before any retest:

1. Initial status: V9, MIG calibrated, XADC mask `0xF`, no fatal error.
2. Source 0, 1024 B, 25 Mword/s, 60-second regression.
3. Source 1, finite 32,768 records: exactly 64 packets and 8,192 records/channel.
4. After Gate 2, arm all three domain-specific ILAs **before** the 300-second continuous source-1 run; capture and export waveforms during that run.
5. Source 0, 1024 B, 25 Mword/s, 3600-second endurance run.

The one-hour run produces roughly 180 GB of payload. The receiver compares it online and retains only one JSON summary, at most 64 sampled fragments of up to 256 bytes each (including the 32-byte P2V9 header), a manifest with packet/word indices, copied byte counts, CRC32, and filenames, plus initial/live/FINAL/PASS/status screenshots.

## 7. Acceptance criteria and recorded outcome

The planned V9 acceptance requires passing ModelSim gates with all injected errors detected; passing offline PC self-tests; routed timing and DRC meeting the implementation gate; every board JSON passing; zero missing/gap/duplicate/out-of-order/malformed/metadata/sample-index/payload/receive-completion errors; zero invalid XADC records, channel-order errors, and XADC drops; empty ingress/DDR and no fatal error after STOP; and complete archival of summaries, samples, screenshots, and hashes.

The [board-validation record](evidence/board_20260923/V9_BOARD_EVIDENCE_FINAL.md) documents the executed result: Gates 1–3 passed, while the full 3600-second Gate 5 run recorded missing packets and did not satisfy the strict zero-loss acceptance criterion.
