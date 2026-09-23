# v5 development log

## 2026-09-20

- Reused the board-proven v4 MIG, ADMA v1 data mover and net21 Gigabit Ethernet/UDP stack.
- Replaced the write-last-to-read coupling with an explicit ring-buffer ownership manager.
- Defined a 256 KiB ring consisting of 256 independently accounted 1024-byte slots.
- Made successful AXI B-channel completion the only write-commit event.
- Added a two-packet transmit FIFO and made acceptance of the final read byte into that FIFO the only DDR-space-release event.
- Added logical read/write pointers, 64-bit committed/released counters, occupancy, full/empty state, stall counters and fatal-error latching.
- Added a continuous PRBS16 source with a synchronized toggle grant so exactly one 1024-byte acquisition burst is produced for each scheduler grant.
- Added a v5 UDP header carrying sequence, committed-byte snapshot and occupancy snapshot.
- Behavioral simulation passed with deliberate ring-full backpressure and resume.
- An early implementation reported WNS +0.982 ns; after adding the exact `tx_burst_committed` ILA probe, another run reported +0.554 ns. Later reproducibility work showed that the intended inter-clock exception was not reliably applied because the generated clocks did not yet exist when the XDC was first evaluated. The post-link constraint correction and definitive rebuilt BIT/LTX are documented below.
- Project generation now omits two bundled but unused FIFO IP archives, avoiding irrelevant missing-module XDC messages on a clean rebuild.
- Board validation is pending and must not be reported as complete until the PC monitor and ILA evidence pass.

## First continuous board run: host-monitor bottleneck

The first 60-second v5 board run received 21,232 packets but reported 679,324 missing sequence numbers. This run is retained as useful development evidence rather than a passing result:

- Every received packet had a valid frame and PRBS payload: `malformed=0`, `data_error_packets=0`, `data_error_bytes=0` and `metadata_errors=0`.
- The FPGA committed-byte snapshot, transmitted sequence progress and 256 KiB occupancy were mutually consistent. The ring filled and correctly throttled further writes rather than overflowing.
- Numerically, `21232 received + 679324 missing = 700556` sequence positions, corresponding to 717,369,344 payload bytes. Adding the reported 262,144-byte ring occupancy gives 717,631,488 bytes, only one 1024-byte burst from the captured `committed_bytes_low=717630464`; that one-burst offset is consistent with header snapshot timing.
- The original PC monitor generated every skipped 1024-byte PRBS packet in a Python loop before processing the next socket datagram. Once the first receive gap occurred, this recovery work delayed reception, caused more socket-buffer loss, and produced a positive-feedback collapse from an initially much higher receive rate to 2.899 Mb/s average.
- Screenshots [`v5_pc_monitor_bottleneck_01.png`](v5_pc_monitor_bottleneck_01.png) through `_04.png` preserve the full progression and final result.

The PC monitor was therefore upgraded to v2. It precomputes the complete 65,535-word PRBS period once, derives any packet reference directly from its 32-bit sequence number in constant time, validates the normal payload with a C-level buffer comparison, uses `recvfrom_into` to avoid per-datagram receive allocation, and requests a configurable 32 MiB socket receive buffer. A 750,000-packet reference-lookup benchmark completed in approximately 0.2 seconds on the development PC. A loopback end-to-end self-test then passed with zero missing, malformed, metadata or payload errors; its result is stored as [`v5_monitor_v2_loopback_selftest.json`](v5_monitor_v2_loopback_selftest.json). The failed board run remains excluded from final performance claims.

## Second continuous board run: Python receive ceiling

The optimized v2 monitor removed the first tool's positive-feedback collapse, but the second 60-second run still failed the zero-loss criterion. This second failure is also retained as development evidence:

- The receive rate remained flat at approximately 325.4 Mb/s for the whole run instead of degrading over time. The tool received 2,383,269 packets and classified 2,598,671 sequence positions as missing.
- `malformed=0`, `metadata_errors=0`, `data_error_packets=0`, `data_error_bytes=0`, `duplicate=0` and `out_of_order=0`. Every packet that reached the application was structurally correct and matched the direct-index PRBS reference.
- Received plus missing sequence positions total 4,981,940 packets. This corresponds to 5,101,506,560 payload bytes or 680.20 Mb/s over 60 seconds; including the approximate Ethernet framing overhead gives about 724.04 Mb/s on the wire.
- The Python process retained 47.8% of the transmitted packets at a stable 325.40 Mb/s. A 32 MiB receive buffer can absorb a short burst but cannot compensate for a permanent producer/consumer rate difference.
- The low 32 bits of transmitted payload plus the full 256 KiB ring occupancy equal 806,801,408, just one 1024-byte snapshot interval from `committed_bytes_low=806800384`. This again supports correct FPGA-side accounting and flow control.
- Screenshots [`v5_pc_monitor_v2_limit_01.png`](v5_pc_monitor_v2_limit_01.png) through `_04.png` and [`v5_60s_v2_result.json`](v5_60s_v2_result.json) preserve this run.

The tool-development path is therefore: v1 established protocol correctness but coupled loss recovery to skipped-payload generation; v2 changed PRBS validation to constant-time direct indexing and exposed the stable Python/socket processing ceiling; v3 moves the hot receive, parse, sequence and `memcmp` path into a compiled native Windows program while retaining the same JSON evidence format. FPGA throttling is deliberately not used for this diagnosis because it would hide the host-tool limit and lower the measured end-to-end ceiling.

## Native monitor v3 preparation

The native Windows monitor was implemented in C++ and built with the installed Visual Studio optimizing compiler. It preserves the v2 packet checks and JSON fields, raises the requested receive buffer from 32 MiB to 64 MiB, and removes Python object allocation and interpreter dispatch from the per-packet path. The first local build exposed two ordinary Windows SDK integration issues—ICMP header ordering and the `min`/`max` macros—which were corrected with the proper include order and `NOMINMAX`; these are tool-build notes, not FPGA failures.

Before another board run, v3 passed a controlled 300-packet loopback test: `missing=0`, `duplicate=0`, `out_of_order=0`, `malformed=0`, `metadata_errors=0`, `data_error_packets=0` and `data_error_bytes=0`. The machine granted the full requested 64 MiB socket buffer. The JSON result and terminal output are retained as [`v5_monitor_v3_loopback_selftest.json`](v5_monitor_v3_loopback_selftest.json) and [`v5_monitor_v3_loopback_stdout.txt`](v5_monitor_v3_loopback_stdout.txt). The next board test will determine whether native receive processing can sustain the FPGA's approximately 680.2 Mb/s payload stream; no FPGA rebuild is required for that test.

## Third continuous board run: synchronous Winsock packet-rate ceiling

The native v3 receiver produced essentially the same result as Python v2, which falsified the narrower hypothesis that Python byte processing was the remaining bottleneck:

- It received 2,383,511 packets at 325.426 Mb/s and reported 2,598,463 skipped sequence positions in 60.001 seconds.
- The received packet rate was approximately 39,725 packets/s, almost identical to v2, despite replacing Python parsing with optimized native C++ and doubling the requested/actual receive buffer to 64 MiB.
- Every delivered packet again passed all checks: malformed, metadata, PRBS, duplicate and out-of-order counts were all zero.
- Received plus skipped positions total 4,981,974 packets, equivalent to 680.200 Mb/s payload and approximately 724.041 Mb/s including estimated Ethernet framing overhead.
- The accounting cross-check remained exact to one burst: transmitted-position bytes plus 262,144 B occupancy modulo 2^32 equal 806,836,224, while the captured committed snapshot was 806,835,200.

The repeatable approximately 39.7 kpacket/s ceiling now points to the one-datagram-per-`recvfrom` Windows/USB receive path rather than PRBS computation or FPGA data corruption. Screenshots [`v5_native_v3_failure_01.png`](v5_native_v3_failure_01.png) through `_03.png` and [`v5_60s_v3_result.json`](v5_60s_v3_result.json) preserve this failed run. It remains excluded from final performance claims.

The next host tool uses Windows Registered I/O (RIO): many receive buffers are posted in advance, completion records are dequeued in batches, and packet validation runs over registered memory. This directly targets per-packet kernel transitions. It will also record gap-event count and maximum gap, which distinguishes a steady packet-rate ceiling from isolated bursts. If RIO still reproduces the same ceiling, the next investigation boundary is the USB Ethernet adapter/driver receive path and FPGA MAC FIFO observability, not further socket-buffer growth.

RIO monitor v4 was subsequently built with 4096 pre-posted 2048-byte registered buffers and completion dequeue batches of up to 256. Its controlled 300-packet loopback test passed with zero missing packets, zero gap events, zero completion errors and zero protocol/data errors; the result is retained in [`v5_monitor_v4_rio_loopback_selftest.json`](v5_monitor_v4_rio_loopback_selftest.json). The attached Realtek USB GbE adapter was also inspected read-only: the link is 1 Gbit/s, flow control is enabled, energy-saving modes are disabled, but the driver exposes only 8 pending receive URBs and a receive-buffer setting of 34. Those relatively small USB receive queues are the next likely constraint only if the RIO board run still shows the same ceiling; they have not been changed automatically.

## Fourth continuous board run: RIO appeared to falsify the host-bottleneck hypothesis

The Windows RIO run received 2,383,334 packets at 325.404 Mb/s and reported 2,598,678 missing sequence positions, 82,179 gap events and a largest gap of 343 packets. It had zero RIO completion errors, duplicates, out-of-order packets, malformed packets, metadata errors and PRBS errors. This is effectively identical to the Python v2 and synchronous native v3 results despite a fundamentally different registered, pre-posted, batched receive engine. The repeated result falsifies the previous host-monitor/USB receive-ceiling hypothesis; the earlier monitor versions remain valuable because they progressively isolated and eliminated PC-side variables rather than being discarded.

The board screenshots are retained as [`v5_rio_v4_failure_01.png`](v5_rio_v4_failure_01.png) through `_03.png`, and the structured result as [`v5_60s_v4_rio_result.json`](v5_60s_v4_rio_result.json).

## Confirmed defect and initial root-cause conclusion: stale UDP ready level

Inspection of the [`net21/udp_send.v`](../rtl/vendor/net21/udp_send.v) interface found the deterministic cause. Its `app_tx_ready` is derived from `ready_cnt==0`. On the clock edge that accepts `app_tx_data_last`, the old ready value is still high; only after that edge does `ready_cnt` become nonzero and hold ready low for 50 clocks. The original v5 packetizer returned directly to IDLE after the last byte, observed the stale high level, and started the next packet. Once in SEND it ignored later ready changes, so the UDP block discarded the beginning of that packet while the packetizer still consumed FIFO data and incremented its packet sequence. This exactly predicts the observed signature: all delivered frames and PRBS payloads are correct, but packet sequence numbers contain repeated gaps.

The original unit test tied `app_tx_ready` permanently high and therefore could not expose the protocol mismatch. A targeted regression now models the real high-on-last then 50-cycle-low behavior. Before the RTL fix it reported 40 cycles of data driven while ready was low and only one of two packets arrived intact; this evidence is retained in [`v5_ready_handshake_regression_before_fix.txt`](v5_ready_handshake_regression_before_fix.txt). The packetizer was changed to pass through explicit WAIT_READY_LOW and WAIT_READY_HIGH states between packets. The same regression now passes with two complete packets and no ready violation, while the ring full/stall/release checks also pass.

## Timing-constraint execution correction and rebuilt image

The investigation also explained the earlier approximately -1.99 ns implementation report. A later diagnostic build showed WNS -2.224 ns, with the failing paths crossing between the 125 MHz acquisition/Ethernet clock and 100 MHz MIG UI clock. These paths use asynchronous FIFO/synchronizer structures and must not be timed as synchronous. The intended XDC conditional was evaluated before the IP-generated clock objects existed, so the exception silently did nothing. A post-link implementation hook now applies the asynchronous clock groups only after both generated clocks are present; the build log confirms `POST_LINK_CDC_CONSTRAINT_APPLIED`.

The corrected instrumented implementation completes with WNS +0.982 ns, TNS 0, WHS +0.052 ns and THS 0. The new BIT/LTX pair was generated at 18:34 and must replace the older programmed image before the next board run. Board validation of this fix is still pending; no success claim is made until the RIO zero-loss run passes.

## Fifth continuous board run: handshake fix improves gap shape but not throughput

The rebuilt handshake-corrected image was programmed and retested with the same Windows RIO v4 receiver. The result remained a board-level failure: 2,383,530 packets were received at 325.429 Mb/s and 2,598,496 sequence positions were missing during 60.001 seconds. All delivered data remained clean: duplicates, out-of-order packets, malformed packets, metadata errors, PRBS errors and RIO completion errors were all zero.

This result corrects the previous root-cause conclusion. The stale-ready defect was real and its regression remains valuable, but it was not the dominant cause of the persistent throughput ceiling. Its repair changed the loss signature materially: the largest gap fell from 343 packets to 36. However, the received packet rate and total missing count remained essentially unchanged. Received plus missing positions total 4,982,026 packets, equivalent to 680.207 Mb/s attempted payload. The 82,174 gap events contain an average of 31.62 missing packets each, which is consistent with repeated bounded receive-queue overflow rather than corrupted FPGA frames.

Screenshots [`v5_post_handshake_failure_01.png`](v5_post_handshake_failure_01.png) through `_03.png` and [`v5_60s_post_handshake_fix_result.json`](v5_60s_post_handshake_fix_result.json) preserve this fifth run. The earlier statement that RIO falsified the host/USB bottleneck hypothesis is therefore withdrawn. Python v2, native synchronous Winsock v3 and RIO v4 all converge on approximately 39.7 kpacket/s and 325.4 Mb/s on the same Realtek USB GbE path, while every packet that reaches software is valid. The strongest remaining hypothesis is now the adapter/driver/Windows receive path under a sustained stream of 1048-byte UDP payloads.

## Controlled-rate diagnostic image

Instead of producing another PC receiver variant, the FPGA packetizer now supports an explicit post-ready idle interval. The diagnostic top level inserts 1500 cycles of the 100 MHz UI clock after the UDP block has completed its low-then-high ready handshake. Based on the measured unpaced source rate, the expected payload rate is approximately 302.921 Mb/s, below the repeatable 325.4 Mb/s receive ceiling.

The paced RTL passed the same behavioral ring-flow and realistic UDP-ready regression. A new BIT/LTX pair was generated at 18:55. Final implementation timing is WNS +0.982 ns, TNS 0, WHS +0.054 ns and THS 0; all user timing constraints are met. The next board run is a discriminating experiment: zero missing/gap events at about 303 Mb/s supports the host/adapter ceiling hypothesis, whereas continued loss below that ceiling sends the investigation back to FPGA packet scheduling or physical Ethernet behavior.

## Sixth continuous board run: 315 Mb/s exposes transient, not sustained, loss

The 1500-cycle paced image reduced the failure by more than three orders of magnitude but did not reach the strict zero-loss criterion. In 60.000 seconds, RIO received 2,306,079 packets at 314.856 Mb/s and reported 695 missing sequence positions across only 38 gap events. The largest event contained 589 missing packets; most other events added exactly two packets. All received packets again passed format, metadata and PRBS validation, with zero duplicates, out-of-order packets or RIO completion errors.

This is not the same failure mode as the earlier 325 Mb/s ceiling. The old run lost 2,598,496 positions in 82,174 repeated queue-overflow events; the paced run retained 99.9699% of the observed sequence range and was clean for long intervals. The result supports a transient receive-service interruption in the Realtek USB GbE/Windows path. The adapter exposes only 8 receive URBs and a receive-buffer value of 34, so an occasional USB/DPC scheduling pause can exhaust the device-side queue even though 16 MiB or more remains available above it in the socket/RIO layer. Windows adapter statistics report zero discards, but those counters do not prove that losses before the exposed NDIS counter are absent.

The measured 314.856 Mb/s also corrects the earlier 302.921 Mb/s prediction. Inferring a source rate from the old missing-sequence total was invalid because the old handshake bug could advance packet sequence without producing a corresponding valid frame. The paced hardware itself shows an approximately 2602-cycle packet period at 100 MHz: 1048 application bytes, protocol-ready recovery/state overhead, and the configured 1500 idle cycles.

The monitor's sequence accounting was audited as part of this run. RIO v4 initialized `expected_sequence` to zero and therefore counted the unknown prefix before the first delivered packet as loss; the initial two missing positions in this run are a startup-boundary artifact. RIO v5 now anchors continuity to the first valid packet, records that first sequence, raises the process/thread receive priority, and expands pre-posted registered receive slots from 4096 to 16384. All subsequent gaps remain strict failures.

The four screenshots are retained as [`v5_paced_300m_failure_01.png`](v5_paced_300m_failure_01.png) through `_04.png`, with the structured result in [`v5_60s_paced_300m_result.json`](v5_60s_paced_300m_result.json).

## End-to-end flow-control boundary and next diagnostic

The v5 ownership rules provide correct FPGA-internal flow control: DDR space is released only after a complete burst enters the transmit FIFO. They do not provide end-to-end reliability after a UDP frame leaves the FPGA. The UDP stack does not return a PC-consumption acknowledgement to the ring manager, so a host/USB queue overflow cannot stop or replay already released data. Strict indefinite zero loss would require a later acknowledgement/window/retransmission protocol or working Ethernet PAUSE handling; rate limiting can establish a reliable operating point but is not an end-to-end delivery guarantee.

The next image uses a 3000-cycle post-ready interval, corresponding to approximately 199.7 Mb/s from the measured packet period. Combined with RIO v5's deeper posted queue and higher receive priority, this provides a substantially larger transient margin while retaining continuous DDR ring-buffer operation and internal backpressure.

The 200 Mb/s diagnostic BIT/LTX pair was generated at 19:17. Final implementation reports WNS +0.982 ns, TNS 0, WHS +0.056 ns and THS 0, with all user timing constraints met and zero implementation errors. RIO v5 was rebuilt at 19:12. Exact artifact hashes are recorded in [`v5_simulation.txt`](v5_simulation.txt).

## Seventh continuous board run: deterministic IPv4 checksum boundary defect

The 3000-cycle image was tested for 60.000 seconds at 199.713 Mb/s. RIO v5 received 1,462,744 packets and reported 299 missing positions in 24 gap events; all delivered packets again had zero malformed, metadata, PRBS, duplicate, out-of-order and RIO completion errors. Screenshots are retained as [`v5_paced_200m_failure_01.png`](v5_paced_200m_failure_01.png) through `_04.png`, with the structured result in [`v5_60s_paced_200m_result.json`](v5_60s_paced_200m_result.json).

This run changed the diagnosis because most missing increments were exactly two packets and repeated every roughly 2.69 seconds. At 199.7 Mb/s the receiver handles about 24,388 packets/s, so a 16-bit period spans `65536 / 24388 = 2.687` seconds. Inspection of the inherited [`net21/ip_send.v`](../rtl/vendor/net21/ip_send.v) found that its IPv4 one's-complement checksum folded the 32-bit sum into 16 bits only once and immediately complemented it. A first fold can itself generate a carry and therefore requires a second end-around fold.

For the current 1076-byte IP packet, UDP protocol number and `192.168.1.11 -> 192.168.1.100` addresses, the header-word constant before the identification field is `0x28D04`. Exhaustive evaluation of all 65,536 identification values finds exactly two failures: IDs `0x72FA` and `0x72FB` produce raw sums `0x2FFFE` and `0x2FFFF`, whose first folds are `0x10000` and `0x10001`. The old 16-bit assignment discarded the new carry and emitted checksums numerically one greater than required. Windows discarded those invalid IPv4 frames, while the application sequence counter continued, yielding exactly the observed periodic two-packet gap. This proves that the dominant regular loss was FPGA protocol-stack code, not a false report by the PC monitor.

The checksum logic now performs a 17-bit first fold, adds that carry back a second time, and then complements the result. A targeted Vivado regression forces both boundary sums and verifies corrected checksums `0xFFFE` and `0xFFFD`; the existing ring-full, flow-control and UDP-ready regression also remains passing. The larger isolated gap near 10 seconds is not attributed to this defect and may still represent a host/USB service interruption.

RIO monitor v6 now records up to 128 exact gap triples (`expected`, `received`, `missing`) both live and in JSON so any remaining loss can be classified by sequence position rather than inferred from one-second totals. A controlled localhost test deliberately omitted sequences 100 and 101; v6 reported exactly `expected=100`, `received=102`, `missing=2`, with every format, metadata, PRBS and completion-error field remaining zero. The evidence is retained as [`v5_monitor_v6_gap_selftest.json`](v5_monitor_v6_gap_selftest.json) and [`v5_monitor_v6_gap_selftest_stdout.txt`](v5_monitor_v6_gap_selftest_stdout.txt).

The checksum-fixed BIT/LTX and validated v6 monitor were rebuilt. Final implementation reports WNS +0.982 ns, TNS 0, WHS +0.057 ns and THS 0, with DRC reporting zero errors. The next board result must use [`v5_60s_ipv4_checksum_fix_result.json`](v5_60s_ipv4_checksum_fix_result.json); no board-level pass is claimed yet.

## Eighth board run: checksum fix removes periodic gaps; two bursts remain

Recovered in the continuation task on 2026-09-20 from the actual JSON and all four screenshots. Duration 60.0001563 s; received 1,462,700 packets; validated payload 1,497,804,800 bytes; payload rate 199.70678643 Mb/s. Missing 345 sequence positions across exactly two gaps: expected 11400, received 11734, missing 334; expected 397018, received 397029, missing 11. First sequence 0. All duplicate, out-of-order, malformed, metadata, PRBS and RIO completion error counts are zero. This is a FAILED zero-loss run.

Screenshots are archived as v5_checksum_fixed_failure_01.png through _04.png. The original v5_60s_ipv4_checksum_fix_result.json remains unchanged. The former repeated two-packet/65536-position signature is absent in this observation window, supporting the checksum repair. The two remaining bursts are not localized: neither host/USB loss nor FPGA MAC loss has been established. Zero adapter error/discard counters do not settle that question.

Next discriminating experiment: retain the identical BIT/LTX and RIO v6; collect a NIC-ingress packet trace alongside the 60-second application result and compare exact P2V5 sequence intervals. Packets present in the ingress trace but absent in the application localize loss after that observation point, subject to verifying packet validity. Packets absent in both require capture-loss checks and further FPGA MAC/FIFO and link/adapter observation; they do not prove FPGA loss. Existing mac_send.v contains data/frame FIFO full signals, but these are not covered by the four ADMA FIFO error probes.

Local pktmon help is available, but pktmon status returned access denied for its driver in the current non-elevated session. No trace was started and no adapter setting changed. Capture instructions are prepared in the continuation task outputs. The README LUT count was corrected from 11419 to 11424 using reports/utilization.rpt. Current artifact SHA-256 values match v5_simulation.txt; no new RTL or bitstream was produced during handoff.

## Ninth board run: first 60-second zero-loss v5 result; rate-step baseline

Verified from evidence/ingress_20260920_230946/rio_result.json and five user screenshots. Duration 60.0000134 s; 1,463,042 packets from first sequence 0; 1,498,155,008 validated PRBS data bytes (1.498155008 decimal GB); payload throughput 199.753956455 Mb/s. Missing packets, gaps, duplicates, out-of-order, malformed, metadata errors, PRBS packet/byte errors and RIO completion errors all zero. Result: PASS for this 60-second application-level board test. Maximum reported ring occupancy 262144 B.

How this result was obtained: the existing v5 checksum-fixed 3000-cycle paced image and unchanged RIO v6 were used. Earlier changes retained in this image/tool are the UDP-ready handshake fix, IPv4 double carry fold, post-link asynchronous clock constraints, 200 Mb/s pacing, direct-index PRBS checking and 16384 preposted RIO buffers. In this continuation no further FPGA or receiver logic fix preceded the pass. The user launched NIC PktMon capture and ran the same receiver in an elevated PowerShell. After initial ping-check failures, local checks showed correct 1 Gb/s link, static IPv4 address, route and replies; retry reached ARMED. The transient ping failure was not localized. The inherited ICMP transmitter uses a fixed 32-byte zero payload, which explains ordinary ping payload-mismatch output but does not establish the earlier timeout cause.

This run proves observed zero loss over 60 seconds at this rate. It does not establish that elevation or capture cured the previous intermittent loss, that the 300+ Mb/s ceiling is removed, or that long-duration operation is qualified. PktMon was active according to screenshots; ingress.etl was still 0 bytes when inspected, with no stop output or finalized packet-trace analysis yet. Finalize capture before any no-capture performance comparison. Existing failures remain valid historical evidence.

Five screenshots archived as v5_first_zero_loss_01.png through _05.png. The successful BIT/LTX, unchanged RIO v6 binary and exact JSON are copied to the continuation outputs/v5_200m_pass_baseline directory. The original v5 source and BIT/LTX remain unchanged.

User authorized controlled speed increases. A separate project2_v5_315m candidate copies the fixed source and changes only the functional pacing constant from 3000 to 1500 UI clocks, targeting approximately 315 Mb/s based on prior measured packet period. This differs from the old 315 Mb/s failed run because the IPv4 checksum fix is now included. Preserve 200 Mb/s as the known short-test baseline; first compare a no-capture 200 Mb/s run, then qualify the 315 Mb/s candidate for 60 s. If it passes, extend to 5 minutes, then step toward ~400 and ~500 Mb/s; if loss recurs, use exact gap records and capture/FPGA observation to locate it. Select the final operating rate with margin and validate 30 minutes and hours. Higher-rate performance remains unmeasured until board tests finish.

315 Mb/s candidate build completed in the separate continuation outputs/project2_v5_315m directory. Unit regression passed; BIT/LTX generated; WNS +0.785 ns, WHS +0.051 ns, TNS/THS 0; 11431 LUT, 15121 Registers, 23 BRAM Tile. DRC has no errors. The inherited XDC unsupported-if critical warning remains, with POST_LINK_CDC_CONSTRAINT_APPLIED confirmed. Routed bus-skew report generated separately. Exact artifact hashes and checks are in candidate validation.txt. Candidate board validation remains pending; original 200 Mb/s image untouched.

## Tenth board run: zero sequence gaps but complete PRBS phase mismatch

The user ran the 200 Mb/s image for 60.0005419 seconds without PktMon from a non-elevated PowerShell. The receiver obtained 1,463,056 packets and 1,498,169,344 payload bytes at 199.754108421 Mb/s. Sequence continuity was perfect: first sequence 0, missing 0, gap events 0, duplicates 0 and out-of-order 0. Packet framing, metadata and RIO completion errors were also zero. However, all 1,463,056 packets failed the PRBS payload comparison, with 1,492,339,862 mismatching bytes, so the final result was correctly FAIL.

This is not a packet-loss failure and it is not evidence that ordinary PowerShell corrupts received bytes. The approximately 99.61 percent byte mismatch rate is the expected signature of a valid PRBS stream checked at the wrong phase. RTL inspection found a reset-coherence risk that exactly permits this signature: the ring controller, ADMA path and packetizer use `adma_reset = reset | ui_clk_sync_rst`, while `prbs16_burst_source` uses only `reset`. If the MIG UI domain resets after the PRBS source has advanced, packet sequence and DDR ownership restart at zero while the PRBS LFSR can retain its old phase. The host then sees a continuous sequence beginning at zero but every payload is referenced to the wrong PRBS position. Administrator elevation may correlate with a clean test setup or scheduling, but it cannot itself realign FPGA PRBS state; elevation is therefore not accepted as the cause of this payload failure.

The run overwrote the older [`v5_60s_paced_200m_result.json`](v5_60s_paced_200m_result.json) because the old filename was reused. The new contents were preserved verbatim as [`v5_200m_noncapture_zero_gap_prbs_phase_failure.json`](v5_200m_noncapture_zero_gap_prbs_phase_failure.json), SHA-256 `A60EE5D06148D5F8DFD9FE21557EE67DD6FFE19A4EDB061595659999C9302AA9`. The previous result remains documented by its screenshots and earlier log entry, but its original same-named JSON is no longer present. Future commands must use timestamped filenames.

Before qualifying 315 Mb/s, repeat 200 Mb/s after a deliberate full board reset and wait for MIG calibration. If that run passes, the reset-state hypothesis remains plausible but not proven. The durable RTL correction is to reset/reseed the PRBS source coherently whenever the UI data path resets, then add a mid-stream UI-reset regression. Until that correction is built and tested, this run is retained as a real reset-recovery defect rather than waived as an operator or privilege issue.

## Eleventh board run: clean-reset 200 Mb/s passes without elevation

After a deliberate board RESET and MIG recalibration, the unchanged 200 Mb/s image was tested from a non-elevated PowerShell. The 60.0000781-second run received 1,463,042 packets and 1,498,155,008 payload bytes at 199.753741054 Mb/s. The first sequence was zero and every error field was zero: missing, gaps, duplicate, out-of-order, malformed, metadata, PRBS packet/byte errors and RIO completion errors. The result is preserved as [`v5_200m_clean_reset_nonadmin_20260920.json`](v5_200m_clean_reset_nonadmin_20260920.json), SHA-256 `6BC1CD621F4035AE25F337DC57F69F3193448D270415F2D18447C4980A631CEC`, with screenshots [`v5_200m_clean_reset_pass_01.png`](v5_200m_clean_reset_pass_01.png) through `_04.png`.

This controlled result falsifies the claim that administrator elevation is required for a clean 200 Mb/s run. Together with the preceding all-packet PRBS phase failure, it supports the need for a clean reset/reseed boundary before each run and keeps the RTL reset-coherence issue open for a durable fix.

## Twelfth board run: checksum-fixed 315 Mb/s has one 14-packet gap

The separate 1500-cycle pacing candidate produced 314.948837309 Mb/s for 60.0004115 seconds. It delivered 2,306,770 packets and 2,362,132,480 payload bytes. Every received packet passed framing, metadata and PRBS validation, and there were no duplicates, out-of-order packets or RIO completion errors. One gap occurred near 9.7 seconds: expected sequence 373776, received 373790, missing 14. No further gap occurred through 60 seconds. The result is retained as [`v5_315m_checksum_fixed_20260920_234834.json`](v5_315m_checksum_fixed_20260920_234834.json), SHA-256 `ADACC89877AF4C633BD2255917688DB89AC4C31351A06C911D0F113DF5DE0D90`. This is a strict FAIL, but its isolated 14-packet signature is not sustained-rate saturation.

PktMon had remained active from the earlier `ingress_20260920_230946` session. The attempted second `start` did not redirect the global capture into `ingress_20260920_234803`; therefore that new directory has no ETL and its zero-byte PCAP is invalid. Stopping PktMon finalized the real file in `ingress_20260920_230946`. It converted successfully to `ingress_final.pcapng`: 3,363,237 formatted packets, PktMon drop count zero, SHA-256 `2DCBFAE86A71B1757A2BB9D84F23DF369D9A6585BBB65BF75556DB469A709566`.

Direct parsing of every P2V5 header in the final PCAP found sequences 373770 through 373775 twice each at the captured NIC layers, sequences 373776 through 373789 zero times, and sequence 373790 onward twice each. Thus the same 14 packets missing from RIO were also absent at the PktMon NIC observation point. Adapter before/after statistics reported zero receive errors and zero receive discards, and PktMon reported no capture-event loss. The loss boundary is therefore before delivery to Windows/RIO: FPGA MAC/PHY, physical link, USB adapter/front-end queue, or an earlier unobserved point. This evidence does not distinguish those remaining locations.

The next discriminating run must use the identical 315 Mb/s BIT and a clean full reset, with PktMon confirmed stopped, to test whether capture/system load induced a front-end queue overflow. If a no-capture run passes, repeat it before accepting the speed. If it still fails, instrument the inherited MAC frame/data FIFO full conditions as sticky status/ILA probes before selecting a lower operating point.

## Thirteenth board run: 315 Mb/s fails again without capture

The identical 315 Mb/s image was tested after a clean reset with PktMon stopped. It ran for 60.0000409 seconds, received 2,306,648 packets and 2,362,007,552 payload bytes at 314.934125587 Mb/s, and reported three gaps totaling 123 packets: expected 1088770/received 1088846/missing 76; expected 1280510/received 1280552/missing 42; expected 2121830/received 2121835/missing 5. Every delivered packet again passed all format, metadata and PRBS checks; duplicate, out-of-order and RIO completion errors were zero. The result is [`v5_315m_nocapture_clean_reset_20260921.json`](v5_315m_nocapture_clean_reset_20260921.json).

An additional retained 315 Mb/s result, [`v5_315m_checksum_fixed_20260920_235323.json`](v5_315m_checksum_fixed_20260920_235323.json), independently failed with three gaps totaling 509 packets (301, 110 and 98). Together with the captured 14-packet failure, the checksum-fixed 315 Mb/s candidate has now failed three 60-second observations. The failures are intermittent bursts rather than a continuous receive-rate ceiling, but 315 Mb/s is not an acceptable operating point on the current setup.

The next candidate targets approximately 248 Mb/s using 2200 post-ready UI cycles. It also resets the PRBS source with the same ADMA/UI reset used by the ring and packetizer, and exposes sticky inherited-MAC `frame_fifo_overflow` and `data_fifo_overflow` conditions as ILA probes 39 and 40. This diagnostic version is maintained separately so the validated 200 Mb/s baseline remains immutable.

## Approximately 248 Mb/s diagnostic image built

The separate `project2_v5_250m_diagnostic` candidate was completed without modifying the 200 Mb/s baseline or 315 Mb/s candidate. Its post-ready pacing is 2200 UI-clock cycles, predicting approximately 248 Mb/s from the two measured pacing points. The PRBS source now resets from `adma_reset`, matching the ring controller, ADMA path and packetizer and closing the previously observed reset-phase mismatch mechanism.

The inherited Ethernet MAC transmitter now exports two sticky diagnostic flags. `mac_frame_fifo_overflow` latches if a frame-descriptor write is attempted while its FIFO is full; `mac_data_fifo_overflow` latches if a data-byte write is attempted while its FIFO is full. They are carried through the stack to ILA probes 39 and 40 and remain asserted until board reset. A failed board run can therefore distinguish an FPGA MAC FIFO rejection from loss occurring later in the PHY/link/adapter path. The matching LTX contains both named probes.

Behavioral ring/flow regression passed. Implementation completed with WNS +0.380 ns, TNS 0, WHS +0.053 ns and THS 0; all user timing constraints are met. The post-link CDC marker is present, routed bus-skew constraints have positive slack, and DRC reports zero errors. Final SHA-256 hashes are `61965B6466B97F202CC36B33A1B269DCDC579781201707E96AF00FBD69DA0DF9` for the BIT and `7EEBB68F7DF07BC0F406E21123A449CB7B3B8941C15F8F174DD6068AA00CC846` for the LTX. This candidate has not yet been tested on the board.

## Fourteenth board run: 248 Mb/s has one nine-packet gap; MAC FIFO probes remain clear

The approximately 248 Mb/s diagnostic image was tested for 60.0002029 seconds from a non-elevated PowerShell without PktMon. It received 1,817,596 packets and validated 1,861,218,304 payload bytes at 248.161601334 Mb/s. One gap occurred near 43 seconds: expected sequence 1304804, received 1304813, missing 9. All delivered packets passed framing, metadata and PRBS checks; duplicate, out-of-order and RIO completion errors were zero. The result is a strict FAIL and is preserved as [`v5_250m_diagnostic_clean_reset_20260921.json`](v5_250m_diagnostic_clean_reset_20260921.json), SHA-256 `78B90B7CAF3664171AD8C55008872A6DC0FF1F7AA8930451F5E8036DBE8FB5D9`.

Immediately after the failed run, before any board reset, the user invoked the ILA immediate trigger. Both sticky diagnostic values were zero: `mac_frame_fifo_overflow=0` and `mac_data_fifo_overflow=0`. Because these flags latch on the first rejected MAC FIFO write and clear only on reset, this observation rules out the two instrumented MAC transmit FIFO-full conditions during the run. It does not rule out a defect elsewhere in the FPGA MAC state machine, PHY, physical link or USB Ethernet front end. Together with the earlier PktMon boundary result, the evidence continues to place the intermittent loss before Windows/RIO while excluding the currently instrumented transmit FIFO write-overflow paths.

The next rate candidate is approximately 225 Mb/s, between the repeatedly clean 200 Mb/s point and the failed 248 Mb/s point. It retains the coherent PRBS reset and the two sticky ILA probes. A 60-second pass is only the first gate; qualification requires at least 5 minutes followed by 30 minutes before selecting it as the operating rate.

## Approximately 225 Mb/s diagnostic image built

The separate 225 Mb/s candidate uses 2550 post-ready UI-clock cycles and retains the 248 Mb/s image's coherent PRBS reset and sticky MAC FIFO probes. Behavioral regression passed. Implementation completed with WNS +0.982 ns, TNS 0, WHS +0.057 ns and THS 0; all timing constraints are met. The post-link CDC marker is present, the routed bus-skew report has no violated entry, DRC reports zero errors, and the matching LTX contains both named probes. SHA-256 is `715D1FD4565129A87150922E5D4805152B6315E721056F4A8AA3A8EC4B251A91` for the BIT and `7EEBB68F7DF07BC0F406E21123A449CB7B3B8941C15F8F174DD6068AA00CC846` for the LTX. Board validation is pending.


## Fifteenth board run and diagnostic reset of approach

225 Mb/s candidate: 60.0000058 seconds, 1,643,048 received packets, 224.330798581 Mb/s, 311 missing in two gaps: 140746 -> 140981 (235), 141153 -> 141229 (76). All other receiver error counters are zero. The supplied ILA screenshot shows both MAC FIFO sticky flags zero. This is a strict FAIL. Fewer Mbps did not produce monotonically fewer losses; rate stepping is stopped at the user's request.

Correction to earlier conclusions: the 200 Mb/s observations are short successful runs, not a qualified stable baseline. Two clear FIFO flags cover only the instrumented full/write conditions and cannot exclude other FPGA faults or an intervening internal reset. The 315 Mb/s capture comparison applies to that run only; it does not establish the location of the uncaptured 248/225 Mb/s losses. PRBS reset wiring was aligned, but full reset-recovery correctness has not been proven by a dedicated regression.

The archived 200 Mb/s BIT, LTX and RIO executable hashes were rechecked against the original SHA256.txt and all match. The next experiment restores the first successful setup's known conditions: original artifacts, board RESET, elevated receiver, NIC PktMon capture at 128 bytes and 1024 MB circular, 60 seconds, same Ethernet connection. Historical OS/USB scheduling and all adapter settings were not recorded completely, so exact environmental identity cannot be claimed. A replay script records current adapters, routes, settings, before/after counters, receiver JSON, transcript, finalized ETL and PCAPNG in a unique folder. It finalizes any leftover capture before starting a new one and aborts if capture cannot start. Existing PktMon filters are logged and retained; the FPGA-specific filter is added.

Decision gate: a pass only demonstrates another short success and requires same-condition repeatability before changing any variable. A failure is analyzed by comparing its exact missing sequence positions against this same run's trace, including capture-loss checks. No further speed candidate is justified by these results alone. Hardware programming and physical RESET/KEY0 remain pending user actions; the replay script has been syntax-checked but not run against the board.

## Sixteenth run: original 200 Mb/s replay fails; same-run ingress comparison completed

The archived original 200 Mb/s BIT/LTX/receiver was restored with elevated reception and NIC capture. Result: 60.00019 s, 1,463,032 packets, 199.752003185 Mb/s, seven missing positions 112676 through 112682 in one gap. Every other receiver error counter was zero. The complete PCAPNG scan found each missing position zero times and neighboring positions twice each. PktMon reported no event loss and converted 2,945,188 packet records. Detailed analysis and sequence hits are retained in continuation outputs/v5_200m_pass_baseline/replays/20260921_120735_373/analysis.md and sequence_analysis.txt.

Conclusion: 200 Mb/s is not a qualified stable baseline. This same-run comparison supports a loss boundary before the recorded NIC observation point, without distinguishing FPGA, PHY/link, NIC/USB or pre-capture driver behavior. Do not attribute all losses to RIO, declare FPGA cleared, or quantify prior success as low probability from these observations. Rate stepping remains stopped. The next useful experiment substitutes an available independent Ethernet receiver path while keeping the exact transmitter image; an independent wire observation is the alternative if no substitute receiver is available. Hardware availability must be established before giving further test steps.
## V5 verification closed with four-part 400 Mb/s ILA evidence

The final planned ILA set was captured using the validated 400 Mb/s image. The DDR write-commit capture shows an accepted successful B response followed by exactly 1,024-byte increases in the write pointer, committed count and occupancy. The read-release capture shows `tx_burst_committed`, a 1,024-byte read-pointer/released-count advance and a corresponding occupancy decrease after the complete burst enters the transmit FIFO. The wrap capture shows the 256 KiB ring write pointer move from `0x0003FC00` to `0x00000000`. The final immediate capture shows MIG calibrated, ring running, sequence advancing, and `fatal_error` plus all four ADMA FIFO errors at zero; full-ring intervals increase the write-stall counter as intended.

The screenshots are archived as [`ila_400m_01_write_commit_a.png`](ila_400m_01_write_commit_a.png) through [`ila_400m_04_stable_state_b.png`](ila_400m_04_stable_state_b.png). This completes the planned v5 functional verification record across simulation, timing-closed implementation, host sequence/data checking and on-chip ILA observation. The separate MAX results remain documented as a 680.207 Mb/s zero-loss 60-second peak and a 680.198 Mb/s one-hour endurance measurement with 2.208 ppm packet loss and zero corruption among received packets.
