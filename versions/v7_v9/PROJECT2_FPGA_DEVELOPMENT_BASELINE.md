# Project 2 FPGA Development Baseline

Recorded September 22, 2026. This checkpoint captures the closed V6 data path and the measurements used to plan V7–V9. Later version records supersede the forward-looking tasks at the end of this document.

## System objective

The Artix-7 implementation connects a continuous acquisition or test source to a clock-crossing ingress FIFO, an AXI4/MIG-managed DDR3 ring buffer, a complete-burst TX FIFO, UDP over Gigabit Ethernet, and PC-side sequence, metadata, and byte-level validation.

The engineering challenge is coordination across different clocks and rates: preserving unread DDR data, complete packets, continuous sequence, and data integrity while applying backpressure at each stage.

## Closed V6 baseline

V6 combines a continuous PRBS test source, 4 KiB ingress FIFO, 3 KiB pause/1 KiB resume thresholds, a 256 KiB DDR3 ring, 1024-byte AXI write and read bursts, 64 KiB drain-start/16 KiB drain-stop thresholds, and an eight-complete-packet TX FIFO. UDP retains the verified `P2V5` / version `0x05` format and Windows RIO receiver. DDR write, DDR read, and UDP transmission progress concurrently.

Behavioral simulation and fault counters, Vivado implementation/timing/DRC, a strict 60-second 400 Mb/s board run, and ILA captures all passed. ILA coverage includes ingress hysteresis, DDR drain startup, full-ring backpressure, overlapping read/write, complete-burst transfer into the TX FIFO, and UDP packet completion. BIT, LTX, receiver, JSON, screenshots, hashes, and work log were archived together.

```text
V6 CLOSED — IMPLEMENTATION AND BOARD VALIDATION PASSED
```

## V6 measured results

The 60.0005534-second run measured **399.404922022 Mb/s** UDP payload rate, **2,925,356 packets**, and **2,995,564,544 validated bytes**. Missing packets, gaps, duplicates, reordering, malformed/metadata/PRBS errors, RIO completion errors, Windows NIC receive errors/discards, all ingress/ring/TX overflow and underflow counters, and `fatal_error` were zero.

Routed implementation: WNS **+0.887 ns**, TNS **0**, WHS **+0.055 ns**, THS **0**; LUT **14,126/20,800 (67.91%)**, registers **16,434/41,600 (39.50%)**, BRAM **36/50 (72%)**, DSP **0**. DRC had zero errors; remaining warnings/advisories originated in MIG/FIFO/UDP IP.

Artifact SHA-256:

- BIT: `514043C21BB8780886AF774E51BE701DE17FBF2B67611006206BF46BE94E2254`
- LTX: `84486ADDAB52CD3D26FB2410E629CBD61E271F0ACE1C2CA75D86E0B8ECBBCBE7`
- V6 board-test ZIP: `EE18FAAA1CE55355F940B503F8FF7AF9F1F84FB5A5907DD21CEBA2ADD4574982`
- 60-second `rio_result.json`: `9E01CB3842CA0509411DBFCC5E480F9108FD83BE2B7FAE7AF84D3908DD30E08E`
- Manifest for 14 V6 ILA screenshots: `13973396AD3B8005E2310CA0098E44321CA135C7C4B14592FC9C4C14D40DA8F8`

## V5/MAX performance context

These measurements characterize the earlier V5 implementation and are kept separate from the V6 baseline:

| Configuration | Recorded result |
| --- | --- |
| V5 315 Mb/s | 300 seconds, zero loss and data errors |
| V5 400 Mb/s | 60 seconds, zero loss and data errors |
| MAX, no extra pacing | 60 seconds at 680.207 Mb/s, zero loss and data errors |
| MAX endurance | One hour at 680.198 Mb/s; 306.089 GB validated; 660 missing packets in 25 gaps (about 2.208 ppm); received payload bytes error-free |

At this checkpoint, the highest short zero-loss result was 680.207 Mb/s for 60 seconds; the established multi-minute zero-loss point was 315 Mb/s for five minutes; and V6's strict passing board point was 399.405 Mb/s for 60 seconds. The MAX one-hour run is recorded with its measured loss rather than combined with the short-run pass.

## Resolved engineering issues

- **UDP transmit handshake:** The earlier packetizer could begin another packet on the clock edge after the previous packet ended, before `app_tx_ready` deasserted. It then consumed FIFO data and advanced sequence numbers, creating gaps despite correct contents in received packets. The repaired packetizer waits for the next valid ready condition; regression exercises real ready behavior.
- **IPv4 checksum:** Repair removed a periodic packet-loss signature and separated protocol correctness from host receive performance.
- **CDC timing-constraint timing:** The 125 MHz acquisition/Ethernet domain and 100 MHz MIG UI domain are asynchronous. A conditional constraint had been read before generated clocks existed, leaving it unapplied and producing an apparent approximately −2 ns violation. Applying it through the post-link hook restored the intended timing analysis.
- **Complete-burst release:** DDR ring space is released only after the entire 1024-byte burst enters the TX FIFO, preventing premature read-pointer movement and partial-packet reuse.
- **Continuous-source watermark behavior:** Input can outrun paced 400 Mb/s UDP output. Once occupancy first reaches 64 KiB, `drain_active` may remain asserted and occupancy may not fall back to 16 KiB during the sustained board run. Simulation covers the low-watermark stop branch; board ILA validates the reachable full-ring backpressure state.

## Development and verification method

Each version freezes a passing baseline and one primary change. Observability—status bits, counters, ILA probes, JSON fields, and pass criteria—is specified before RTL changes. Modular RTL separates acquisition, ingress FIFO, DDR scheduling/ring control, egress FIFO, packetizer, and UDP stack. Behavioral regression covers normal transfer, ready stalls, FIFO limits, watermark hysteresis, wraparound, concurrent reads/writes, and injected errors. Vivado checks timing, CDC structure, bus skew, resources, and DRC before generating a matched BIT/LTX pair with hashes.

Board validation starts with a short, strict receiver run without packet capture; ILA diagnosis is performed separately so capture does not perturb host throughput. NIC, cable, IP settings, 1 Gbps link, power mode, buffers, process priority, and adapter counters are recorded. Acceptance uses JSON sequence, format, metadata, and byte-level PRBS checks, not a visual impression of terminal output. ILA captures retain trigger line, Name/Value, and upper/lower probe views. Duration then increases from 60 seconds through repeat runs and several minutes to 30 minutes or an hour, retaining failed outcomes and their diagnostic context.

## Next development steps at this checkpoint

The plan following V6 was to preserve the closed V5/V6 directories, extend endurance testing without changing the 400 Mb/s BIT/LTX, expose a common `sample_data + sample_valid + sample_ready` interface, keep PRBS as a selectable self-test source, integrate four-channel on-chip XADC acquisition, and prepare final architecture, bug/root-cause, verification, timing/resource, ILA, and host-results material. The subsequent [V7](project2_v7_uart_control/README.md), [V8](project2_v8_xadc_acquisition/README.md), and [V9](project2_v9_full_validation/README.md) records document the work actually completed.
