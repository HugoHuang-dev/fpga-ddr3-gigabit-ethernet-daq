# Project 2 V5 — Ring-Buffer Development and Early Diagnostics

## Datapath

V5 adds a 256 KiB DDR3 ring buffer to V4's validated MIG/AXI and UDP paths, extending the fixed-length transfer into a continuous PRBS16 stream. The ring contains 256 slots of 1,024 bytes. A successful AXI write response advances write commitment; a complete read burst entering the transmit FIFO releases ring space. ILA observes read/write pointers, committed/released totals, occupancy, full/empty state, stalls, and errors. A small-ring simulation deliberately exercised filling, backpressure, and recovery before Vivado implementation.

## Early board tests and revisions

1. The first Python receiver generated PRBS references sequentially for every skipped packet after a sequence gap, causing a processing cascade. It was changed to precompute a full PRBS period and index the reference directly by packet sequence. The local loopback self-test is retained.
2. Optimized Python and native Winsock receivers each reached a stable ceiling near 39.7 kpackets/s. Windows RIO improved reception and error statistics using pre-posted registered buffers and batched completion processing.
3. The packetizer and UDP `app_tx_ready` interface had a last-beat timing conflict. `WAIT_READY_LOW` and `WAIT_READY_HIGH` recovery states were added, and simulation modeled the real duration of `ready` low. Both the failing pre-fix and passing post-fix regressions are retained.
4. The asynchronous constraint between 125 MHz and MIG UI domains was moved to post-link, where the generated clocks are visible. The final implementation met timing.
5. A retest near 200 Mb/s showed two fixed packet gaps per 16-bit IP-ID cycle. Inspection of IPv4 checksum carry folding and a regression at the `0x72FA/0x72FB` boundary eliminated those periodic gaps.

These investigations established the basis for subsequent host-load comparisons, rate steps, and final ILA captures. The full sequence is in the [V5 development log](../../../../DEVELOPMENT_LOG.md#v5); [individual images](../../../../evidence/V5.md) and the [V5 version description](../README.md) are directly linked. Raw results remain in the corresponding JSON files.
