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
- Screenshots [`v5_pc_monitor_bottleneck_01.png`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_pc_monitor_bottleneck_01.png) through `_04.png` preserve the full progression and final result.

The PC monitor was therefore upgraded to v2. It precomputes the complete 65,535-word PRBS period once, derives any packet reference directly from its 32-bit sequence number in constant time, validates the normal payload with a C-level buffer comparison, uses `recvfrom_into` to avoid per-datagram receive allocation, and requests a configurable 32 MiB socket receive buffer. A 750,000-packet reference-lookup benchmark completed in approximately 0.2 seconds on the development PC. A loopback end-to-end self-test then passed with zero missing, malformed, metadata or payload errors; its result is stored as [`v5_monitor_v2_loopback_selftest.json`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_monitor_v2_loopback_selftest.json). The failed board run remains excluded from final performance claims.

## Second continuous board run: Python receive ceiling

The optimized v2 monitor removed the first tool's positive-feedback collapse, but the second 60-second run still failed the zero-loss criterion. This second failure is also retained as development evidence:

- The receive rate remained flat at approximately 325.4 Mb/s for the whole run instead of degrading over time. The tool received 2,383,269 packets and classified 2,598,671 sequence positions as missing.
- `malformed=0`, `metadata_errors=0`, `data_error_packets=0`, `data_error_bytes=0`, `duplicate=0` and `out_of_order=0`. Every packet that reached the application was structurally correct and matched the direct-index PRBS reference.
- Received plus missing sequence positions total 4,981,940 packets. This corresponds to 5,101,506,560 payload bytes or 680.20 Mb/s over 60 seconds; including the approximate Ethernet framing overhead gives about 724.04 Mb/s on the wire.
- The Python process retained 47.8% of the transmitted packets at a stable 325.40 Mb/s. A 32 MiB receive buffer can absorb a short burst but cannot compensate for a permanent producer/consumer rate difference.
- The low 32 bits of transmitted payload plus the full 256 KiB ring occupancy equal 806,801,408, just one 1024-byte snapshot interval from `committed_bytes_low=806800384`. This again supports correct FPGA-side accounting and flow control.
- Screenshots [`v5_pc_monitor_v2_limit_01.png`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_pc_monitor_v2_limit_01.png) through `_04.png` and [`v5_60s_v2_result.json`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_60s_v2_result.json) preserve this run.

The tool-development path is therefore: v1 established protocol correctness but coupled loss recovery to skipped-payload generation; v2 changed PRBS validation to constant-time direct indexing and exposed the stable Python/socket processing ceiling; v3 moves the hot receive, parse, sequence and `memcmp` path into a compiled native Windows program while retaining the same JSON evidence format. FPGA throttling is deliberately not used for this diagnosis because it would hide the host-tool limit and lower the measured end-to-end ceiling.

## Native monitor v3 preparation

The native Windows monitor was implemented in C++ and built with the installed Visual Studio optimizing compiler. It preserves the v2 packet checks and JSON fields, raises the requested receive buffer from 32 MiB to 64 MiB, and removes Python object allocation and interpreter dispatch from the per-packet path. The first local build exposed two ordinary Windows SDK integration issues—ICMP header ordering and the `min`/`max` macros—which were corrected with the proper include order and `NOMINMAX`; these are tool-build notes, not FPGA failures.

Before another board run, v3 passed a controlled 300-packet loopback test: `missing=0`, `duplicate=0`, `out_of_order=0`, `malformed=0`, `metadata_errors=0`, `data_error_packets=0` and `data_error_bytes=0`. The machine granted the full requested 64 MiB socket buffer. The JSON result and terminal output are retained as [`v5_monitor_v3_loopback_selftest.json`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_monitor_v3_loopback_selftest.json) and [`v5_monitor_v3_loopback_stdout.txt`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_monitor_v3_loopback_stdout.txt). The next board test will determine whether native receive processing can sustain the FPGA's approximately 680.2 Mb/s payload stream; no FPGA rebuild is required for that test.

## Third continuous board run: synchronous Winsock packet-rate ceiling

The native v3 receiver produced essentially the same result as Python v2, which falsified the narrower hypothesis that Python byte processing was the remaining bottleneck:

- It received 2,383,511 packets at 325.426 Mb/s and reported 2,598,463 skipped sequence positions in 60.001 seconds.
- The received packet rate was approximately 39,725 packets/s, almost identical to v2, despite replacing Python parsing with optimized native C++ and doubling the requested/actual receive buffer to 64 MiB.
- Every delivered packet again passed all checks: malformed, metadata, PRBS, duplicate and out-of-order counts were all zero.
- Received plus skipped positions total 4,981,974 packets, equivalent to 680.200 Mb/s payload and approximately 724.041 Mb/s including estimated Ethernet framing overhead.
- The accounting cross-check remained exact to one burst: transmitted-position bytes plus 262,144 B occupancy modulo 2^32 equal 806,836,224, while the captured committed snapshot was 806,835,200.

The repeatable approximately 39.7 kpacket/s ceiling now points to the one-datagram-per-`recvfrom` Windows/USB receive path rather than PRBS computation or FPGA data corruption. Screenshots [`v5_native_v3_failure_01.png`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_native_v3_failure_01.png) through `_03.png` and [`v5_60s_v3_result.json`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_60s_v3_result.json) preserve this failed run. It remains excluded from final performance claims.

The next host tool uses Windows Registered I/O (RIO): many receive buffers are posted in advance, completion records are dequeued in batches, and packet validation runs over registered memory. This directly targets per-packet kernel transitions. It will also record gap-event count and maximum gap, which distinguishes a steady packet-rate ceiling from isolated bursts. If RIO still reproduces the same ceiling, the next investigation boundary is the USB Ethernet adapter/driver receive path and FPGA MAC FIFO observability, not further socket-buffer growth.

RIO monitor v4 was subsequently built with 4096 pre-posted 2048-byte registered buffers and completion dequeue batches of up to 256. Its controlled 300-packet loopback test passed with zero missing packets, zero gap events, zero completion errors and zero protocol/data errors; the result is retained in [`v5_monitor_v4_rio_loopback_selftest.json`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_monitor_v4_rio_loopback_selftest.json). The attached Realtek USB GbE adapter was also inspected read-only: the link is 1 Gbit/s, flow control is enabled, energy-saving modes are disabled, but the driver exposes only 8 pending receive URBs and a receive-buffer setting of 34. Those relatively small USB receive queues are the next likely constraint only if the RIO board run still shows the same ceiling; they have not been changed automatically.

## Fourth continuous board run: RIO appeared to falsify the host-bottleneck hypothesis

The Windows RIO run received 2,383,334 packets at 325.404 Mb/s and reported 2,598,678 missing sequence positions, 82,179 gap events and a largest gap of 343 packets. It had zero RIO completion errors, duplicates, out-of-order packets, malformed packets, metadata errors and PRBS errors. This is effectively identical to the Python v2 and synchronous native v3 results despite a fundamentally different registered, pre-posted, batched receive engine. The repeated result falsifies the previous host-monitor/USB receive-ceiling hypothesis; the earlier monitor versions remain valuable because they progressively isolated and eliminated PC-side variables rather than being discarded.

The board screenshots are retained as [`v5_rio_v4_failure_01.png`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_rio_v4_failure_01.png) through `_03.png`, and the structured result as [`v5_60s_v4_rio_result.json`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_60s_v4_rio_result.json).

## Confirmed defect and initial root-cause conclusion: stale UDP ready level

Inspection of the [`net21/udp_send.v`](../rtl/vendor/net21/udp_send.v) interface found the deterministic cause. Its `app_tx_ready` is derived from `ready_cnt==0`. On the clock edge that accepts `app_tx_data_last`, the old ready value is still high; only after that edge does `ready_cnt` become nonzero and hold ready low for 50 clocks. The original v5 packetizer returned directly to IDLE after the last byte, observed the stale high level, and started the next packet. Once in SEND it ignored later ready changes, so the UDP block discarded the beginning of that packet while the packetizer still consumed FIFO data and incremented its packet sequence. This exactly predicts the observed signature: all delivered frames and PRBS payloads are correct, but packet sequence numbers contain repeated gaps.

The original unit test tied `app_tx_ready` permanently high and therefore could not expose the protocol mismatch. A targeted regression now models the real high-on-last then 50-cycle-low behavior. Before the RTL fix it reported 40 cycles of data driven while ready was low and only one of two packets arrived intact; this evidence is retained in [`v5_ready_handshake_regression_before_fix.txt`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_ready_handshake_regression_before_fix.txt). The packetizer was changed to pass through explicit WAIT_READY_LOW and WAIT_READY_HIGH states between packets. The same regression now passes with two complete packets and no ready violation, while the ring full/stall/release checks also pass.

## Timing-constraint execution correction and rebuilt image

The investigation also explained the earlier approximately -1.99 ns implementation report. A later diagnostic build showed WNS -2.224 ns, with the failing paths crossing between the 125 MHz acquisition/Ethernet clock and 100 MHz MIG UI clock. These paths use asynchronous FIFO/synchronizer structures and must not be timed as synchronous. The intended XDC conditional was evaluated before the IP-generated clock objects existed, so the exception silently did nothing. A post-link implementation hook now applies the asynchronous clock groups only after both generated clocks are present; the build log confirms `POST_LINK_CDC_CONSTRAINT_APPLIED`.

The corrected instrumented implementation completes with WNS +0.982 ns, TNS 0, WHS +0.052 ns and THS 0. The new BIT/LTX pair was generated at 18:34 and must replace the older programmed image before the next board run. Board validation of this fix is still pending; no success claim is made until the RIO zero-loss run passes.

## Fifth continuous board run: handshake fix improves gap shape but not throughput

The rebuilt handshake-corrected image was programmed and retested with the same Windows RIO v4 receiver. The result remained a board-level failure: 2,383,530 packets were received at 325.429 Mb/s and 2,598,496 sequence positions were missing during 60.001 seconds. All delivered data remained clean: duplicates, out-of-order packets, malformed packets, metadata errors, PRBS errors and RIO completion errors were all zero.

This result corrects the previous root-cause conclusion. The stale-ready defect was real and its regression remains valuable, but it was not the dominant cause of the persistent throughput ceiling. Its repair changed the loss signature materially: the largest gap fell from 343 packets to 36. However, the received packet rate and total missing count remained essentially unchanged. Received plus missing positions total 4,982,026 packets, equivalent to 680.207 Mb/s attempted payload. The 82,174 gap events contain an average of 31.62 missing packets each, which is consistent with repeated bounded receive-queue overflow rather than corrupted FPGA frames.

Screenshots [`v5_post_handshake_failure_01.png`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_post_handshake_failure_01.png) through `_03.png` and [`v5_60s_post_handshake_fix_result.json`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_60s_post_handshake_fix_result.json) preserve this fifth run. The earlier statement that RIO falsified the host/USB bottleneck hypothesis is therefore withdrawn. Python v2, native synchronous Winsock v3 and RIO v4 all converge on approximately 39.7 kpacket/s and 325.4 Mb/s on the same Realtek USB GbE path, while every packet that reaches software is valid. The strongest remaining hypothesis is now the adapter/driver/Windows receive path under a sustained stream of 1048-byte UDP payloads.

## Controlled-rate diagnostic image

Instead of producing another PC receiver variant, the FPGA packetizer now supports an explicit post-ready idle interval. The diagnostic top level inserts 1500 cycles of the 100 MHz UI clock after the UDP block has completed its low-then-high ready handshake. Based on the measured unpaced source rate, the expected payload rate is approximately 302.921 Mb/s, below the repeatable 325.4 Mb/s receive ceiling.

The paced RTL passed the same behavioral ring-flow and realistic UDP-ready regression. A new BIT/LTX pair was generated at 18:55. Final implementation timing is WNS +0.982 ns, TNS 0, WHS +0.054 ns and THS 0; all user timing constraints are met. The next board run is a discriminating experiment: zero missing/gap events at about 303 Mb/s supports the host/adapter ceiling hypothesis, whereas continued loss below that ceiling sends the investigation back to FPGA packet scheduling or physical Ethernet behavior.

## Sixth continuous board run: 315 Mb/s exposes transient, not sustained, loss

The 1500-cycle paced image reduced the failure by more than three orders of magnitude but did not reach the strict zero-loss criterion. In 60.000 seconds, RIO received 2,306,079 packets at 314.856 Mb/s and reported 695 missing sequence positions across only 38 gap events. The largest event contained 589 missing packets; most other events added exactly two packets. All received packets again passed format, metadata and PRBS validation, with zero duplicates, out-of-order packets or RIO completion errors.

This is not the same failure mode as the earlier 325 Mb/s ceiling. The old run lost 2,598,496 positions in 82,174 repeated queue-overflow events; the paced run retained 99.9699% of the observed sequence range and was clean for long intervals. The result supports a transient receive-service interruption in the Realtek USB GbE/Windows path. The adapter exposes only 8 receive URBs and a receive-buffer value of 34, so an occasional USB/DPC scheduling pause can exhaust the device-side queue even though 16 MiB or more remains available above it in the socket/RIO layer. Windows adapter statistics report zero discards, but those counters do not prove that losses before the exposed NDIS counter are absent.

The measured 314.856 Mb/s also corrects the earlier 302.921 Mb/s prediction. Inferring a source rate from the old missing-sequence total was invalid because the old handshake bug could advance packet sequence without producing a corresponding valid frame. The paced hardware itself shows an approximately 2602-cycle packet period at 100 MHz: 1048 application bytes, protocol-ready recovery/state overhead, and the configured 1500 idle cycles.

The monitor's sequence accounting was audited as part of this run. RIO v4 initialized `expected_sequence` to zero and therefore counted the unknown prefix before the first delivered packet as loss; the initial two missing positions in this run are a startup-boundary artifact. RIO v5 now anchors continuity to the first valid packet, records that first sequence, raises the process/thread receive priority, and expands pre-posted registered receive slots from 4096 to 16384. All subsequent gaps remain strict failures.

The four screenshots are retained as [`v5_paced_300m_failure_01.png`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_paced_300m_failure_01.png) through `_04.png`, with the structured result in [`v5_60s_paced_300m_result.json`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_60s_paced_300m_result.json).

## End-to-end flow-control boundary and next diagnostic

The v5 ownership rules provide correct FPGA-internal flow control: DDR space is released only after a complete burst enters the transmit FIFO. They do not provide end-to-end reliability after a UDP frame leaves the FPGA. The UDP stack does not return a PC-consumption acknowledgement to the ring manager, so a host/USB queue overflow cannot stop or replay already released data. Strict indefinite zero loss would require a later acknowledgement/window/retransmission protocol or working Ethernet PAUSE handling; rate limiting can establish a reliable operating point but is not an end-to-end delivery guarantee.

The next image uses a 3000-cycle post-ready interval, corresponding to approximately 199.7 Mb/s from the measured packet period. Combined with RIO v5's deeper posted queue and higher receive priority, this provides a substantially larger transient margin while retaining continuous DDR ring-buffer operation and internal backpressure.

The 200 Mb/s diagnostic BIT/LTX pair was generated at 19:17. Final implementation reports WNS +0.982 ns, TNS 0, WHS +0.056 ns and THS 0, with all user timing constraints met and zero implementation errors. RIO v5 was rebuilt at 19:12. Exact artifact hashes are recorded in [`v5_simulation.txt`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_simulation.txt).

## Seventh continuous board run: deterministic IPv4 checksum boundary defect

The 3000-cycle image was tested for 60.000 seconds at 199.713 Mb/s. RIO v5 received 1,462,744 packets and reported 299 missing positions in 24 gap events; all delivered packets again had zero malformed, metadata, PRBS, duplicate, out-of-order and RIO completion errors. Screenshots are retained as [`v5_paced_200m_failure_01.png`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_paced_200m_failure_01.png) through `_04.png`, with the structured result in [`v5_60s_paced_200m_result.json`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_60s_paced_200m_result.json).

This run changed the diagnosis because most missing increments were exactly two packets and repeated every roughly 2.69 seconds. At 199.7 Mb/s the receiver handles about 24,388 packets/s, so a 16-bit period spans `65536 / 24388 = 2.687` seconds. Inspection of the inherited [`net21/ip_send.v`](../rtl/vendor/net21/ip_send.v) found that its IPv4 one's-complement checksum folded the 32-bit sum into 16 bits only once and immediately complemented it. A first fold can itself generate a carry and therefore requires a second end-around fold.

For the current 1076-byte IP packet, UDP protocol number and `192.168.1.11 -> 192.168.1.100` addresses, the header-word constant before the identification field is `0x28D04`. Exhaustive evaluation of all 65,536 identification values finds exactly two failures: IDs `0x72FA` and `0x72FB` produce raw sums `0x2FFFE` and `0x2FFFF`, whose first folds are `0x10000` and `0x10001`. The old 16-bit assignment discarded the new carry and emitted checksums numerically one greater than required. Windows discarded those invalid IPv4 frames, while the application sequence counter continued, yielding exactly the observed periodic two-packet gap. This proves that the dominant regular loss was FPGA protocol-stack code, not a false report by the PC monitor.

The checksum logic now performs a 17-bit first fold, adds that carry back a second time, and then complements the result. A targeted Vivado regression forces both boundary sums and verifies corrected checksums `0xFFFE` and `0xFFFD`; the existing ring-full, flow-control and UDP-ready regression also remains passing. The larger isolated gap near 10 seconds is not attributed to this defect and may still represent a host/USB service interruption.

RIO monitor v6 now records up to 128 exact gap triples (`expected`, `received`, `missing`) both live and in JSON so any remaining loss can be classified by sequence position rather than inferred from one-second totals. A controlled localhost test deliberately omitted sequences 100 and 101; v6 reported exactly `expected=100`, `received=102`, `missing=2`, with every format, metadata, PRBS and completion-error field remaining zero. The evidence is retained as [`v5_monitor_v6_gap_selftest.json`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_monitor_v6_gap_selftest.json) and [`v5_monitor_v6_gap_selftest_stdout.txt`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_monitor_v6_gap_selftest_stdout.txt).

The checksum-fixed BIT/LTX and validated v6 monitor were rebuilt. Final implementation reports WNS +0.982 ns, TNS 0, WHS +0.057 ns and THS 0, with DRC reporting zero errors. The next board result must use [`v5_60s_ipv4_checksum_fix_result.json`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_60s_ipv4_checksum_fix_result.json); no board-level pass is claimed yet.

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

The run overwrote the older [`v5_60s_paced_200m_result.json`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_60s_paced_200m_result.json) because the old filename was reused. The new contents were preserved verbatim as [`v5_200m_noncapture_zero_gap_prbs_phase_failure.json`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_200m_noncapture_zero_gap_prbs_phase_failure.json), SHA-256 `A60EE5D06148D5F8DFD9FE21557EE67DD6FFE19A4EDB061595659999C9302AA9`. The previous result remains documented by its screenshots and earlier log entry, but its original same-named JSON is no longer present. Future commands must use timestamped filenames.

Before qualifying 315 Mb/s, repeat 200 Mb/s after a deliberate full board reset and wait for MIG calibration. If that run passes, the reset-state hypothesis remains plausible but not proven. The durable RTL correction is to reset/reseed the PRBS source coherently whenever the UI data path resets, then add a mid-stream UI-reset regression. Until that correction is built and tested, this run is retained as a real reset-recovery defect rather than waived as an operator or privilege issue.

## Eleventh board run: clean-reset 200 Mb/s passes without elevation

After a deliberate board RESET and MIG recalibration, the unchanged 200 Mb/s image was tested from a non-elevated PowerShell. The 60.0000781-second run received 1,463,042 packets and 1,498,155,008 payload bytes at 199.753741054 Mb/s. The first sequence was zero and every error field was zero: missing, gaps, duplicate, out-of-order, malformed, metadata, PRBS packet/byte errors and RIO completion errors. The result is preserved as [`v5_200m_clean_reset_nonadmin_20260920.json`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_200m_clean_reset_nonadmin_20260920.json), SHA-256 `6BC1CD621F4035AE25F337DC57F69F3193448D270415F2D18447C4980A631CEC`, with screenshots [`v5_200m_clean_reset_pass_01.png`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_200m_clean_reset_pass_01.png) through `_04.png`.

This controlled result falsifies the claim that administrator elevation is required for a clean 200 Mb/s run. Together with the preceding all-packet PRBS phase failure, it supports the need for a clean reset/reseed boundary before each run and keeps the RTL reset-coherence issue open for a durable fix.

## Twelfth board run: checksum-fixed 315 Mb/s has one 14-packet gap

The separate 1500-cycle pacing candidate produced 314.948837309 Mb/s for 60.0004115 seconds. It delivered 2,306,770 packets and 2,362,132,480 payload bytes. Every received packet passed framing, metadata and PRBS validation, and there were no duplicates, out-of-order packets or RIO completion errors. One gap occurred near 9.7 seconds: expected sequence 373776, received 373790, missing 14. No further gap occurred through 60 seconds. The result is retained as [`v5_315m_checksum_fixed_20260920_234834.json`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_315m_checksum_fixed_20260920_234834.json), SHA-256 `ADACC89877AF4C633BD2255917688DB89AC4C31351A06C911D0F113DF5DE0D90`. This is a strict FAIL, but its isolated 14-packet signature is not sustained-rate saturation.

PktMon had remained active from the earlier `ingress_20260920_230946` session. The attempted second `start` did not redirect the global capture into `ingress_20260920_234803`; therefore that new directory has no ETL and its zero-byte PCAP is invalid. Stopping PktMon finalized the real file in `ingress_20260920_230946`. It converted successfully to `ingress_final.pcapng`: 3,363,237 formatted packets, PktMon drop count zero, SHA-256 `2DCBFAE86A71B1757A2BB9D84F23DF369D9A6585BBB65BF75556DB469A709566`.

Direct parsing of every P2V5 header in the final PCAP found sequences 373770 through 373775 twice each at the captured NIC layers, sequences 373776 through 373789 zero times, and sequence 373790 onward twice each. Thus the same 14 packets missing from RIO were also absent at the PktMon NIC observation point. Adapter before/after statistics reported zero receive errors and zero receive discards, and PktMon reported no capture-event loss. The loss boundary is therefore before delivery to Windows/RIO: FPGA MAC/PHY, physical link, USB adapter/front-end queue, or an earlier unobserved point. This evidence does not distinguish those remaining locations.

The next discriminating run must use the identical 315 Mb/s BIT and a clean full reset, with PktMon confirmed stopped, to test whether capture/system load induced a front-end queue overflow. If a no-capture run passes, repeat it before accepting the speed. If it still fails, instrument the inherited MAC frame/data FIFO full conditions as sticky status/ILA probes before selecting a lower operating point.

## Thirteenth board run: 315 Mb/s fails again without capture

The identical 315 Mb/s image was tested after a clean reset with PktMon stopped. It ran for 60.0000409 seconds, received 2,306,648 packets and 2,362,007,552 payload bytes at 314.934125587 Mb/s, and reported three gaps totaling 123 packets: expected 1088770/received 1088846/missing 76; expected 1280510/received 1280552/missing 42; expected 2121830/received 2121835/missing 5. Every delivered packet again passed all format, metadata and PRBS checks; duplicate, out-of-order and RIO completion errors were zero. The result is [`v5_315m_nocapture_clean_reset_20260921.json`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_315m_nocapture_clean_reset_20260921.json).

An additional retained 315 Mb/s result, [`v5_315m_checksum_fixed_20260920_235323.json`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_315m_checksum_fixed_20260920_235323.json), independently failed with three gaps totaling 509 packets (301, 110 and 98). Together with the captured 14-packet failure, the checksum-fixed 315 Mb/s candidate has now failed three 60-second observations. The failures are intermittent bursts rather than a continuous receive-rate ceiling, but 315 Mb/s is not an acceptable operating point on the current setup.

The next candidate targets approximately 248 Mb/s using 2200 post-ready UI cycles. It also resets the PRBS source with the same ADMA/UI reset used by the ring and packetizer, and exposes sticky inherited-MAC `frame_fifo_overflow` and `data_fifo_overflow` conditions as ILA probes 39 and 40. This diagnostic version is maintained separately so the validated 200 Mb/s baseline remains immutable.

## Approximately 248 Mb/s diagnostic image built

The separate `project2_v5_250m_diagnostic` candidate was completed without modifying the 200 Mb/s baseline or 315 Mb/s candidate. Its post-ready pacing is 2200 UI-clock cycles, predicting approximately 248 Mb/s from the two measured pacing points. The PRBS source now resets from `adma_reset`, matching the ring controller, ADMA path and packetizer and closing the previously observed reset-phase mismatch mechanism.

The inherited Ethernet MAC transmitter now exports two sticky diagnostic flags. `mac_frame_fifo_overflow` latches if a frame-descriptor write is attempted while its FIFO is full; `mac_data_fifo_overflow` latches if a data-byte write is attempted while its FIFO is full. They are carried through the stack to ILA probes 39 and 40 and remain asserted until board reset. A failed board run can therefore distinguish an FPGA MAC FIFO rejection from loss occurring later in the PHY/link/adapter path. The matching LTX contains both named probes.

Behavioral ring/flow regression passed. Implementation completed with WNS +0.380 ns, TNS 0, WHS +0.053 ns and THS 0; all user timing constraints are met. The post-link CDC marker is present, routed bus-skew constraints have positive slack, and DRC reports zero errors. Final SHA-256 hashes are `61965B6466B97F202CC36B33A1B269DCDC579781201707E96AF00FBD69DA0DF9` for the BIT and `7EEBB68F7DF07BC0F406E21123A449CB7B3B8941C15F8F174DD6068AA00CC846` for the LTX. This candidate has not yet been tested on the board.

## Fourteenth board run: 248 Mb/s has one nine-packet gap; MAC FIFO probes remain clear

The approximately 248 Mb/s diagnostic image was tested for 60.0002029 seconds from a non-elevated PowerShell without PktMon. It received 1,817,596 packets and validated 1,861,218,304 payload bytes at 248.161601334 Mb/s. One gap occurred near 43 seconds: expected sequence 1304804, received 1304813, missing 9. All delivered packets passed framing, metadata and PRBS checks; duplicate, out-of-order and RIO completion errors were zero. The result is a strict FAIL and is preserved as [`v5_250m_diagnostic_clean_reset_20260921.json`](../../../v1_v5/project2_v5_ring_buffer/evidence/v5_250m_diagnostic_clean_reset_20260921.json), SHA-256 `78B90B7CAF3664171AD8C55008872A6DC0FF1F7AA8930451F5E8036DBE8FB5D9`.

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

## Seventeenth experiment: host-load correlation found with an independent Ethernet receiver

The transmitter was kept powered and the same original 200 Mb/s FPGA image was exercised through a second host using its Realtek Gaming 2.5GbE controller. Four 60-second observations were supplied from that host. Three clean-environment runs passed at approximately 199.759--199.760 Mb/s with zero missing packets, zero gaps and zero protocol/data errors. One run performed while NetEase Cloud Music, WeChat and other background programs were active failed at 196.424 Mb/s: 1,438,657 packets were received, 24,427 sequence positions were missing in 94 gap events, and the largest gap was 3,539 packets. All packets that did reach the receiver remained structurally and bytewise correct.

A further run on the development machine's Realtek USB GbE path, after selecting the performance power mode and closing background programs, also passed: 60.0001812 s, 1,463,070 packets, 199.757220733 Mb/s, zero missing/gap events and zero format, metadata, PRBS or RIO completion errors. Its structured result is [`Project2_200M_USB_Kit/results/20260921_231519_293/rio_result.json`](../../../v5_v6/Project2_200M_USB_Kit/results/20260921_231519_293/rio_result.json). The supplied comparison screenshots are retained under [`evidence/host_load_comparison_20260921.png`](../../../v5_v6/evidence/host_load_comparison_20260921.png) and [`evidence/development_pc_clean_200m_pass_20260921.png`](../../../v5_v6/evidence/development_pc_clean_200m_pass_20260921.png).

This is a strong controlled correlation between host service conditions and the intermittent 200 Mb/s loss. The failure signature is compatible with a temporary receive-service interruption: the application rate drops slightly, missing packets arrive in bursts, and delivered payloads remain correct. It also explains why changing FPGA pacing alone did not produce a monotonic loss threshold. The evidence does not prove that CPU execution capacity by itself is the sole cause; background applications can affect CPU scheduling, DPC/interrupt latency, USB scheduling, memory pressure, power state and NIC queue service. The defensible conclusion is that the Windows host receive path has limited transient margin and must be treated as part of the tested system configuration.

The earlier statement that the single 200 Mb/s pass was probably accidental is superseded. Multiple clean-host passes on two different receiver paths now establish 200 Mb/s as repeatable for 60 seconds under controlled host conditions. It is still a short-run baseline rather than a long-duration qualification result.

Rate stepping may resume as a controlled experiment. The already built 315 Mb/s candidate is the next useful stress point because it has a much smaller host margin and previously showed isolated gaps. Its next run must use the same clean-host conditions: performance power mode, unnecessary foreground/background applications closed, PktMon stopped, no downloads or cloud synchronization, and the RIO receiver started before KEY0. A 60-second pass is a screening result; repeat it once, then run 5 minutes before making a stability claim.

## Eighteenth experiment: controlled-host 315 Mb/s passes three consecutive 60-second runs

The unchanged 315 Mb/s candidate was retested with the host set to the Windows High performance power plan, unnecessary foreground/background applications closed, and PktMon explicitly stopped. Three complete runs were found in the generated USB-kit result folders; all three passed the strict receiver criteria:

| Run | Duration | Packets | Payload rate | Missing/gaps | All other errors |
| --- | ---: | ---: | ---: | ---: | ---: |
| `20260921_233205_642` | 60.0000506 s | 2,306,780 | 314.952097057 Mb/s | 0 / 0 | 0 |
| `20260921_233858_000` | 60.0002460 s | 2,306,794 | 314.952982826 Mb/s | 0 / 0 | 0 |
| `20260921_234044_030` | 60.0002708 s | 2,306,836 | 314.958587020 Mb/s | 0 / 0 | 0 |

Across 180.0005674 seconds, the receiver accepted 6,920,410 packets and 7,086,499,840 payload bytes at an aggregate 314.954555638 Mb/s. Every run started at sequence zero and reported `missing_packets=0`, `gap_events=0`, `max_gap_packets=0`, `duplicates=0`, `out_of_order=0`, `malformed=0`, `metadata_errors=0`, `data_error_packets=0`, `data_error_bytes=0` and `receive_completion_errors=0`. The Windows adapter counters also remained at zero receive errors and zero receive discards. The three JSON SHA-256 values are respectively `C8BF7020A9F058549C1166DFA5E2A1E04D2861779E545EE880CF4F880C747656`, `7931862FCE337068FECA80DB15E9BE55044259B653CA7091422474160B8F12FD` and `C990FE79056FD88552B6355DB4C5873D47A186F1E653B5AB7BBB1B4755AE4A15`.

This repeatability is a major change in the evidence. The same 315 Mb/s image previously showed isolated gaps under less controlled host conditions, whereas three consecutive clean-host runs are now lossless. The most defensible interpretation is that background activity and the selected Windows power/scheduling state materially affect the receive path's transient service margin. This does not turn UDP into a guaranteed-delivery protocol and does not yet qualify indefinite operation, but it establishes 315 Mb/s as a repeatable 60-second operating point for the recorded host configuration.

The next gate is a five-minute run with the environment held constant. It must retain the same BIT/LTX, High performance plan, stopped PktMon and closed background applications. A five-minute pass will justify moving to a 30-minute qualification run; a failure remains evidence and must be preserved without changing several variables at once. The final screenshot is retained as [`evidence/315m_clean_host_third_pass_20260921.png`](../../../v5_v6/evidence/315m_clean_host_third_pass_20260921.png).

## Nineteenth experiment: controlled-host 315 Mb/s passes the five-minute gate

The unchanged 315 Mb/s image completed the planned 300-second no-capture run under the same controlled host conditions. RIO received 11,533,704 packets and 11,810,512,896 payload bytes in 300.0000249 seconds, for 314.946984419 Mb/s. The complete result is strictly clean: sequence started at zero; missing packets, gap events, maximum gap, duplicates, out-of-order packets, malformed packets, metadata errors, PRBS packet/byte errors and receive completion errors were all zero. The Windows adapter counters also remained at zero receive errors and zero receive discards. The active power plan was High performance.

The structured result is [`Project2_315M_USB_Kit/results/20260921_234944_683/rio_result.json`](../../../v5_v6/Project2_315M_USB_Kit/results/20260921_234944_683/rio_result.json), SHA-256 `6A56F144D884EA7D76B702698E5B962BF53AC2CE12A774F5A36863A220351D45`. The terminal screenshot is retained as [`evidence/315m_clean_host_5min_pass_20260921.png`](../../../v5_v6/evidence/315m_clean_host_5min_pass_20260921.png).

Together with the preceding three consecutive 60-second passes, this establishes 315 Mb/s as a repeatable five-minute operating point for the recorded host configuration. The user elected to characterize maximum throughput before the 30-minute endurance run. Speed exploration will therefore use controlled steps while holding the BIT family, packet format, receiver, cable, adapter, High performance plan and clean-background condition constant. The first step targets approximately 400 Mb/s; a 60-second strict pass advances to the next step, while a failure brackets the boundary and triggers a smaller intermediate step.

## Approximately 400 Mb/s speed-exploration image built

The first upper-bound search candidate reduces `POST_READY_IDLE_CYCLES` from 1500 to 950 while leaving the packet format, DDR ring controller, UDP stack, clocks and host receiver unchanged. From the measured 315 Mb/s packet period, the predicted payload rate is approximately 399.4 Mb/s. This is deliberately a moderate first jump: a pass permits a larger next step, while a failure brackets the operating boundary between 315 and 400 Mb/s.

The behavioral ring/flow and realistic UDP-ready regression passed. Vivado implementation and bitstream generation completed successfully with WNS +0.862 ns, TNS 0, WHS +0.058 ns and THS 0. All user timing constraints and routed bus-skew checks are met. Resource use is 11,438 LUTs, 15,121 registers and 23 BRAM tiles. DRC contains zero errors; the existing IP warnings remain unchanged. The BIT SHA-256 is `0382046942E2A0A369652F0362B1FAF8F713A8FAD533DBACD3177EB8877C688F`; matching LTX SHA-256 is `9C76CD050FE5EC07BB8F57763B124F2F55F324171469F33C22CD040041A01931`.

The board-test package is `Project2_400M_USB_Kit`. Its first gate is one controlled 60-second no-capture run. Board validation is pending and no 400 Mb/s performance claim is made before that result.

## Twentieth experiment: controlled-host 400 Mb/s passes the first board gate

The approximately 400 Mb/s image completed its first 60-second controlled-host, no-capture run successfully. RIO received 2,925,356 packets and 2,995,564,544 payload bytes in 60.0001324 seconds, yielding 399.407724507 Mb/s. Sequence began at zero and every strict error field was zero: missing packets, gap events, maximum gap, duplicates, out-of-order packets, malformed packets, metadata errors, PRBS packet/byte errors and receive completion errors. Windows adapter counters also remained at zero receive errors and zero receive discards; the active power plan was High performance.

The result is [`Project2_400M_USB_Kit/results/20260922_001323_222/rio_result.json`](../../../v5_v6/Project2_400M_USB_Kit/results/20260922_001323_222/rio_result.json), SHA-256 `6F2E3F7A194E7C78D7B3A6623E02B7D8E72666AB5382641AD633323E1B04E428`. The terminal screenshot is retained as [`evidence/400m_clean_host_60s_pass_20260922.png`](../../../v5_v6/evidence/400m_clean_host_60s_pass_20260922.png).

At the user's request, the next experiment jumps directly to the transmitter's unpaced architectural limit instead of continuing small rate steps. `POST_READY_IDLE_CYCLES` will be set to zero. Extrapolating from the measured 400 Mb/s packet period gives approximately 744 Mb/s of UDP payload; this is the current packetizer/UDP-stack ceiling rather than the theoretical payload limit of all possible Gigabit Ethernet designs. The first unpaced run remains a 60-second strict screening test. If it fails, 400 Mb/s remains the last proven point and the observed result will bracket the upper boundary.

## MAX unpaced image built

The unpaced candidate sets `POST_READY_IDLE_CYCLES=0`; no deliberate packet interval remains after the inherited UDP ready handshake. The behavioral ring/flow and realistic ready regression passed. Vivado implementation and bitstream generation completed successfully with WNS +0.982 ns, TNS 0, WHS +0.054 ns and THS 0. All user timing constraints and routed bus-skew checks are met. Resource use is 11,394 LUTs, 15,104 registers and 23 BRAM tiles. DRC contains zero errors, with the same existing IP warnings/advisories retained.

The MAX BIT SHA-256 is `7BA937B17F5B450E63B04513B077CFA848C568416433731A8408434B160296F5`; matching LTX SHA-256 is `9C76CD050FE5EC07BB8F57763B124F2F55F324171469F33C22CD040041A01931`. The board-test package is `Project2_MAX_USB_Kit`. Board validation is pending; approximately 744 Mb/s remains a prediction until the RIO JSON records the actual rate.

## Twenty-first experiment: MAX unpaced image passes at 680.207 Mb/s

The unpaced image completed its first controlled-host 60-second board run successfully. RIO received 4,981,998 packets and 5,101,565,952 payload bytes in 60.0001438 seconds, yielding 680.207163370 Mb/s of verified PRBS payload. Sequence began at zero and every strict error field was zero: missing packets, gap events, maximum gap, duplicates, out-of-order packets, malformed packets, metadata errors, PRBS packet/byte errors and receive completion errors. Windows adapter counters also remained at zero receive errors and zero receive discards; the active power plan was High performance.

The structured result is [`Project2_MAX_USB_Kit/results/20260922_003038_415/rio_result.json`](../../../v5_v6/Project2_MAX_USB_Kit/results/20260922_003038_415/rio_result.json), SHA-256 `E24C93E2B9C49A81BAF0F0953C1714358AF953CAC667254797FF932F17FB3712`. The terminal screenshot is retained as [`evidence/max_unpaced_680m_60s_pass_20260922.png`](../../../v5_v6/evidence/max_unpaced_680m_60s_pass_20260922.png).

The earlier approximately 744 Mb/s prediction is superseded by this measurement. It assumed the 400 Mb/s packet period could be decomposed into a fixed base period plus the configured 950 idle cycles. At zero added idle, internal UDP-ready recovery and state scheduling impose a larger effective minimum interval than that linear extrapolation. Since `POST_READY_IDLE_CYCLES` is already zero, 680.207 Mb/s is the measured throughput ceiling of the current RTL, 1024-byte verified-data payload and inherited UDP-stack configuration. Raising it requires an architectural change such as reducing the inherited inter-packet recovery or increasing payload size; there is no remaining pacing parameter to remove.

The appropriate endurance gate is one hour at the unchanged MAX image. At the measured rate this should verify approximately 306.1 GB of payload and about 299 million packets, while remaining well below the 32-bit packet-sequence wrap time. The long-test script prevents Windows system sleep during the run, keeps PktMon stopped and records the same environment, adapter and JSON evidence. A clean one-hour result is sufficient for the project's primary sustained-throughput claim; an optional later four-hour overnight run can strengthen it further.

## Twenty-second experiment: MAX sustains 680.198 Mb/s for one hour with 2.208 ppm packet loss

The unchanged unpaced image completed the full 3600-second controlled-host run. RIO received 298,914,974 packets and verified 306,088,933,376 payload bytes in 3600.0001469 seconds, yielding 680.197601969 Mb/s of received and byte-checked PRBS payload. The expected sequence span contained 298,915,634 packets; 660 sequence positions were absent in 25 gap events. This corresponds to a packet-loss fraction of 0.000220798% (2.207981 parts per million) and a packet-delivery rate of 99.999779202%. The largest individual gap was 133 packets and the average gap contained 26.4 packets.

Every packet delivered to the application remained correct: duplicates, out-of-order packets, malformed packets, metadata errors, PRBS data-error packets, data-error bytes and RIO completion errors were all zero. Windows reported zero receive packet errors and zero receive discards on the selected adapter. The 25 losses were temporally sparse rather than one terminal collapse: the first occurred after roughly 367 seconds, the final one near 3323 seconds, and the average interval was about 144 seconds. This signature is consistent with brief service-margin exhaustion somewhere before the application sequence checker; the present counters do not prove a single exact component.

This run is a valuable positive endurance result but is not a strict zero-loss pass. The defensible project claims are now separated:

- Peak short-run result: 680.207 Mb/s for 60 seconds with zero missing packets and zero data errors.
- Maximum-rate endurance result: 680.198 Mb/s for one hour, 306.089 GB verified, 99.999779% packet delivery, and zero corruption among delivered packets.
- Strict zero-loss sustained operating rate: not yet qualified for one hour at MAX; it requires a modest pacing margin and a new endurance run.

The result is preserved at [`Project2_MAX_USB_Kit/results/20260922_004730_216/rio_result.json`](../../../v5_v6/Project2_MAX_USB_Kit/results/20260922_004730_216/rio_result.json), SHA-256 `98B9D1467EC659666CC58898028461DEDA202ACF57D5B049BBACE061BD2FF33B`. The supplied terminal image is retained as [`evidence/max_unpaced_680m_1hour_660_missing_20260922.png`](../../../v5_v6/evidence/max_unpaced_680m_1hour_660_missing_20260922.png).

The strict receiver verdict remains FAIL because the test was deliberately configured to reject any missing sequence. That verdict should not be weakened retroactively. Instead, the one-hour MAX result is reported as a high-throughput endurance measurement with its measured loss rate, while a slightly paced image is used to qualify the zero-loss operating point. A first practical target is approximately 640 Mb/s, leaving about 5.9% host-path headroom while retaining most of the measured maximum throughput.

## Final ILA evidence plan uses the validated 400 Mb/s image

The remaining v5 evidence task is the previously specified four-capture ILA set: DDR write commit, DDR read-to-TX-FIFO release, ring-pointer wrap, and stable running state. These captures do not need the MAX image or another endurance run. The 400 Mb/s image is selected because it already has a strict 60-second zero-loss host result, retains the same 39-probe ILA topology as MAX, and provides more receive-path margin while exercising the same DDR ring, AXI and packetization mechanisms.

The matching 400 Mb/s BIT/LTX must be used as a pair. The board may be started once with KEY0 and left transmitting while all four ILA captures are taken; no simultaneous PC receiver is required. Detailed trigger conditions, expected transitions and evidence filenames are recorded in [`ILA_400M_FOUR_CAPTURE_GUIDE.md`](../../../v5_v6/ILA_400M_FOUR_CAPTURE_GUIDE.md).

## Twenty-third experiment: four-part ILA evidence completed; v5 closed

The final four-part ILA evidence set was captured from the validated 400 Mb/s image. The 400 Mb/s image was intentionally used instead of MAX because it preserves the same DDR ring, AXI, packetizer and 39-probe ILA structure while already having a strict zero-loss 60-second host result.

1. **DDR write commit:** the capture shows `BVALID` accepted with `BREADY=1` and `BRESP=00`. `write_pointer` advances from `0x0003C800` to `0x0003CC00`, `committed_bytes` advances from `0x0703C800` to `0x0703CC00`, and occupancy increases from 261,120 to 262,144 bytes. All increments are exactly 1,024 bytes.
2. **DDR read completion and release:** `tx_burst_committed` pulses, `read_pointer` advances from `0x00009000` to `0x00009400`, `released_bytes` advances from `0xB8A09000` to `0xB8A09400`, occupancy decreases from 262,144 to 261,120 bytes, and the complete-packet FIFO count advances from one to two. This proves that ring space is released only after a complete 1,024-byte burst is accepted into the transmit FIFO.
3. **Ring wrap:** the write pointer changes from `0x0003FC00`, the final 1,024-byte slot of the 256 KiB ring, to `0x00000000`. At the same transition, `committed_bytes` advances from `0xD30FFC00` to `0xD3100000` and occupancy rises from 261,120 to 262,144 bytes. The wrap is clean and no fatal or FIFO error is asserted.
4. **Stable running state:** an immediate capture after continued operation shows `init_calib_complete=1`, `ring_started=1`, both logical pointers advancing through the ring, packet sequence at 58,795,992, `fatal_error=0`, and all four ADMA FIFO error flags at zero. The ring reaches its full state and `write_stall_cycles` continues counting, demonstrating deliberate source backpressure rather than buffer overwrite.

The eight full-window screenshots are archived as `evidence/ila_400m_01_write_commit_a.png` through `ila_400m_04_stable_state_b.png`. Together with behavioral regression, successful implementation and timing closure, the 400 Mb/s strict host run, the MAX 60-second zero-loss run, and the MAX one-hour measured-loss endurance run, these captures complete the planned v5 verification record.

**V5 closure status:** the continuous PRBS acquisition/test source, asynchronous FIFO crossings, AXI4/MIG DDR3 ring buffer, occupancy-based backpressure, complete-burst release rule, UDP packetization, host-side sequence/metadata/byte verification, timing reports and board-level ILA evidence are complete. No further v5 board run is required for the current documented claims. A future one-hour zero-loss operating-rate qualification or a real external acquisition source is additional project work and is not required to close the v5 implementation phase.

## V6 implementation: continuous DDR3-to-UDP pipeline

V6 was created in a new `project2_v6_pipeline` directory; the closed V5 sources and evidence were not modified. The data path is now split into three independently advancing stages: a continuous PRBS acquisition stream fills a 4 KiB ingress FIFO, 1,024-byte AXI write and read bursts operate concurrently through the 256 KiB DDR3 ring, and an eight-packet egress FIFO feeds the UDP stack at the validated approximately 400 Mb/s pacing point.

Two hysteresis loops replace single-boundary scheduling. The acquisition source pauses when the ingress FIFO reaches 1,536 16-bit words (3 KiB) and resumes at 512 words (1 KiB). DDR draining starts at 65,536 occupied bytes and remains active until occupancy falls to 16,384 bytes. A DDR write starts only when a complete ingress burst is available and a ring slot is free; a DDR read starts only while the drain loop is active and the egress FIFO has room for a complete burst. These decisions are independent, so write, read and UDP transmission can overlap.

V6 adds separate 32-bit counters for ingress overflow/underflow, ingress burst starvation, DDR ring overflow/underflow, egress overflow/underflow, write stalls and read stalls. AXI response, ADMA FIFO and framing faults retain a fatal status. The ILA was rebuilt around the new FIFO levels, watermarks, concurrent-stage flags and counters. The UDP payload layout deliberately remains `P2V5`/version `0x05`, because no field layout changed and this preserves compatibility with the validated Windows RIO receiver.

The V6 behavioral regression passed. It observed both ingress high-to-low hysteresis and simultaneous pipeline stages, completed 83 UDP packets, committed 1,568 bytes to the reduced simulation ring and released 1,456 bytes without a fatal, framing, overflow or underflow condition. Full Vivado implementation completed with zero errors. Final timing is WNS +0.887 ns, TNS 0, WHS +0.055 ns and THS 0; all user timing constraints and all routed bus-skew constraints are met. Resource use is 14,126 LUTs, 16,434 registers and 36 BRAM tiles. The remaining DRC warnings are inherited MIG/FIFO/UDP IP advisories of the same classes present in V5.

The generated artifacts are [`project2_v6_pipeline/project2_v6_top.bit`](../../../v5_v6/project2_v6_pipeline/project2_v6_top.bit) and the matching [`project2_v6_top.ltx`](../../../v5_v6/project2_v6_pipeline/project2_v6_top.ltx). Their SHA-256 values are respectively `514043C21BB8780886AF774E51BE701DE17FBF2B67611006206BF46BE94E2254` and `84486ADDAB52CD3D26FB2410E629CBD61E271F0ACE1C2CA75D86E0B8ECBBCBE7`. The board-test package is `Project2_V6_400M_USB_Kit`. V6 board validation is pending; the first gate is one controlled 60-second no-capture run, followed by an immediate ILA capture if the host result passes.

The board package was finalized with its matching BIT/LTX pair, the hash-locked validated RIO receiver, a 60-second administrator launch script, Chinese operating instructions, a build-validation summary and a UTF-8 SHA-256 manifest. The distributable archive is `Project2_V6_400M_USB_Kit.zip`, SHA-256 `EE18FAAA1CE55355F940B503F8FF7AF9F1F84FB5A5907DD21CEBA2ADD4574982`. The launcher parses successfully, and the packaged BIT and LTX hashes match the post-route artifacts exactly. This closes the V6 implementation/build stage; board behavior remains the next evidence gate.

## Twenty-fourth experiment: V6 continuous pipeline passes its first board gate

The V6 400 Mb/s image completed its first controlled 60-second board run successfully. The RIO receiver accepted 2,925,356 packets and verified 2,995,564,544 payload bytes in 60.0005534 seconds, yielding 399.404922022 Mb/s. Sequence began at zero. Missing packets, gap events, maximum gap, duplicates, out-of-order packets, malformed packets, metadata errors, PRBS data-error packets, data-error bytes and receive completion errors were all zero. The receiver returned exit code 0.

The Windows adapter was a Realtek USB GbE Family Controller linked at 1 Gbps. Its receive-error and receive-discard counters remained zero before and after the run. The active Windows power plan was High performance, PktMon was stopped, the socket receive buffer was 64 MiB, and the receiver ran with high process priority and highest receive-thread priority.

The complete result is `Project2_V6_400M_USB_Kit/results/20260922_102315_345`; its structured result file `rio_result.json` has SHA-256 `9E01CB3842CA0509411DBFCC5E480F9108FD83BE2B7FAE7AF84D3908DD30E08E`. The terminal screenshot is archived as [`evidence/v6_400m_first_board_pass_20260922.png`](../../../v5_v6/evidence/v6_400m_first_board_pass_20260922.png), SHA-256 `491F65DB08D25BECBC03422F953279CB5077BEE1B6E3AF033C448BFBFCD33435`.

This result closes the first V6 board gate: the new continuous source, ingress FIFO hysteresis, independent DDR write/read scheduling, enlarged packet egress FIFO and UDP path operated together at the validated 400 Mb/s point without any host-visible loss or corruption for 60 seconds. It establishes a strict short-run V6 pass. Longer endurance and V6-specific ILA captures remain separate evidence gates and are not implied by this result.

## V6 ILA evidence plan

The post-pass V6 ILA plan is recorded in [`ILA_V6_FOUR_CAPTURE_GUIDE.md`](../../../v5_v6/ILA_V6_FOUR_CAPTURE_GUIDE.md). It replaces the V5-specific four-capture set with evidence for the new architecture: ingress FIFO 3 KiB/1 KiB hysteresis, DDR drain activation at 64 KiB followed by safe full-ring backpressure, simultaneous `write_inflight` and `read_inflight`, and the complete DDR-read-to-egress-FIFO-to-UDP sequence. Seven full-window screenshots are required. The 16 KiB drain-stop branch is covered by behavioral simulation rather than the continuous-source board run: after the source first fills DDR past 64 KiB, its input rate exceeds the paced 400 Mb/s output, so occupancy does not fall to 16 KiB while the source remains latched on. The completion gate also requires all six overflow/underflow counters and `fatal_error` to remain zero.

The first V6 ILA group is complete. In the high-water capture, `source_run` falls at the trigger while `ingress_level_words` crosses 1,536 words; the UI-clock observation shows the adjacent 1,537-word sample, which is the expected one-word registered/clock-observation offset. In the low-water capture, `source_run` rises at the trigger with `ingress_level_words=511`, immediately below the configured 512-word boundary. Both ingress overflow and underflow counters are zero. The accompanying lower-panel views also show all ring/TX overflow and underflow counters and `fatal_error` at zero. The four archived views are [`evidence/ila_v6_01a_ingress_high_pause_a.png`](../../../v5_v6/evidence/ila_v6_01a_ingress_high_pause_a.png), [`ila_v6_01a_ingress_high_pause_b.png`](../../../v5_v6/evidence/ila_v6_01a_ingress_high_pause_b.png), [`ila_v6_01b_ingress_low_resume_a.png`](../../../v5_v6/evidence/ila_v6_01b_ingress_low_resume_a.png), and [`ila_v6_01b_ingress_low_resume_b.png`](../../../v5_v6/evidence/ila_v6_01b_ingress_low_resume_b.png). Screenshots taken while the ILA displayed `Waiting For Trigger` were excluded because they show the previously captured waveform rather than a completed new acquisition.

## Twenty-fifth experiment: V6 ILA pipeline evidence completed

The remaining five V6 ILA acquisitions were completed with `ILA Status: Idle` and the trigger centered at sample 1,024. Each acquisition is retained as upper and lower probe-panel views, bringing the complete V6 ILA archive to 14 screenshots.

1. **DDR drain activation:** `drain_active` rises when `occupancy_bytes`, `write_pointer` and `committed_bytes` reach `0x00010000` (65,536 bytes). `released_bytes` is still zero at the boundary, and `read_inflight` starts immediately afterward. This directly proves the configured 64 KiB drain-start threshold.
2. **Full-ring backpressure:** `ring_full` rises with `occupancy_bytes=0x00040000` (262,144 bytes). At that point `committed_bytes=0x00052000` and `released_bytes=0x00012000`, whose difference is exactly the full ring size. `write_stall_cycles` begins increasing from zero while `ring_overflow_count` remains zero, proving that the controller stalls producers instead of overwriting unread data. `read_inflight` and `drain_active` remain asserted so output continues.
3. **Concurrent DDR write and read:** the overlap capture shows `write_inflight=1` and `read_inflight=1` simultaneously at the trigger, with `ingress_drain_busy=1` and `drain_active=1`. This is the central board-level proof that V6 no longer serializes the write and read stages.
4. **DDR read completion into the egress FIFO:** `tx_burst_committed` pulses while `read_inflight=1` and the captured pre-commit FIFO byte count is 1,023. The following controller edge releases the completed 1,024-byte slot. Ring/TX overflow and underflow counts remain zero.
5. **UDP completion:** `packet_done` pulses at the trigger, `packet_sequence` advances from 792,800 to 792,801, and `tx_burst_space_available` returns high. This proves continued packet retirement and egress-space recovery.

Across all five new captures, ingress, ring and TX overflow/underflow counters are zero and `fatal_error=0`. Together with the preceding ingress high/low-water captures, the V6 ILA evidence set is complete.

The board evidence also refines the interpretation of the DDR low watermark. With the continuous PRBS producer running faster than the paced 400 Mb/s UDP sink, DDR occupancy does not fall back to the 16 KiB drain-stop threshold after its first 64 KiB activation. Consequently, waiting for a `drain_active` falling edge during this board workload would be invalid test methodology rather than evidence of a fault. The 16 KiB stop branch remains covered by the behavioral regression; the board evidence instead records the operationally reachable full-ring backpressure state. This correction is incorporated into [`ILA_V6_FOUR_CAPTURE_GUIDE.md`](../../../v5_v6/ILA_V6_FOUR_CAPTURE_GUIDE.md).

The new files are archived as [`evidence/ila_v6_02a_ddr_high_start_drain_a.png`](../../../v5_v6/evidence/ila_v6_02a_ddr_high_start_drain_a.png) through [`ila_v6_04b_udp_packet_done_b.png`](../../../v5_v6/evidence/ila_v6_04b_udp_packet_done_b.png). All 14 V6 ILA image hashes are recorded in [`evidence/ila_v6_SHA256.txt`](../../../v5_v6/evidence/ila_v6_SHA256.txt); the manifest SHA-256 is `13973396AD3B8005E2310CA0098E44321CA135C7C4B14592FC9C4C14D40DA8F8`.

**V6 ILA status:** complete. The board evidence now demonstrates both hysteresis-controlled ingress behavior, the reachable DDR water-level transition, safe full-ring backpressure, simultaneous write/read operation, complete-burst release into the egress FIFO, UDP sequence progress, and zero internal fault counters.

## V7 implementation: UART command and status control plane

V7 was created as a separate `project2_v7_uart_control` project without modifying
the closed V6 archive. It retains the V6 continuous ingress-FIFO, concurrent DDR3
ring and paced UDP data path, and adds a UART command/status plane. The UART PHY
uses the established UART hierarchy; framing and CRC-16/MODBUS semantics
reuse the board-verified Project1 definition:
`A5 5A | TYPE | SEQ | LEN | PAYLOAD | CRC_LO | CRC_HI`.

Implemented commands are START, STOP, SOURCE_SELECT, SET_RATE,
SET_PACKET_LENGTH, SET_MODE (finite/continuous), CLEAR_COUNTERS and READ_STATUS.
The fixed DDR transfer remains 1,024 bytes, while one burst can be segmented into
four 256-byte, two 512-byte or one 1,024-byte UDP payload. READ_STATUS uses a
request/acknowledge toggle and a stable UI-clock snapshot before returning DDR,
FIFO, packet and UART diagnostics to the 125 MHz control domain.

Behavioral regressions pass for actual UART receive timing, Project1-compatible
CRC checking, every command path, busy rejection, invalid CRC rejection, finite
auto-stop, exact rate scheduling, status flags and dynamic packetization. Native
Vivado XSim also passes the UART-control regression. Vivado 2018.3 implementation
completed with WNS +0.456 ns, TNS 0, WHS +0.054 ns and THS 0. All specified
timing constraints are met and DRC has zero errors. Final BIT SHA-256 is
`6FD8FF72CE6B2475812380D72DE9ACFB74873E64EA76614117695BAFACC46A5E`.

## Twenty-sixth experiment: V7 UART control-plane board gate passes

The first V7 board interaction successfully completed READ_STATUS over COM4.
The returned frame passed CRC and reported result OK, control version 7,
`mig_calibrated=True`, `run_enable=False`, an empty ingress FIFO and DDR ring,
packet sequence zero, and zero ingress, ring, TX, UART-CRC and command-rejection
counters. This proves the V7 BIT is running, the reused Part 6 UART RX/TX path is
correct on the board, the Project1 frame/CRC protocol interoperates with the host
tool, the UI-clock status snapshot returns coherently, and DDR3 calibration has
completed.

The subsequent stopped-state configuration commands all returned result OK:
CLEAR_COUNTERS, SOURCE_SELECT=0, SET_RATE=25,000,000 words/s,
SET_PACKET_LENGTH=512 bytes and SET_MODE=continuous. Screenshots are archived as
[`evidence/v7_uart_status_initial_pass_20260922.png`](../../project2_v7_uart_control/evidence/v7_uart_status_initial_pass_20260922.png) (SHA-256
`2FF4CC1FE0D664AB064BF9B68911878F39760A90E6DA77D8B0BC40619FE9B7F6`)
and [`evidence/v7_uart_configuration_pass_20260922.png`](../../project2_v7_uart_control/evidence/v7_uart_configuration_pass_20260922.png) (SHA-256
`A3648085135E165F17666C9560B4B992CCAD989B4E4EFBA42482EBA2E43406BF`).

The first UDP receiver invocation is not a data-path failure. The receiver pinged
the FPGA, bound `192.168.1.100:6666`, allocated its RIO buffers and reached
`ARMED`, but no START command was sent from a second terminal before the
first-packet timeout. It therefore received zero packets and exited with the
explicit timeout verdict. This is recorded as a test-procedure interruption,
not as UART, DDR3, packetization or Ethernet evidence. The screenshot is
[`evidence/v7_receiver_start_timeout_20260922.png`](../../project2_v7_uart_control/evidence/v7_receiver_start_timeout_20260922.png), SHA-256
`031B60EE917DCD663AFC944EF31CE60B90A64455656E284D805B85A10420D30D`.
The generated structured result is preserved as
[`evidence/v7_receiver_start_timeout_20260922.json`](../../project2_v7_uart_control/evidence/v7_receiver_start_timeout_20260922.json), SHA-256
`864259D09827F3D9C8CF5CFAF41DD1EE8452A97AB03FA61B6F96916C932E62D9`.

The next unchanged gate is the manually coordinated 60-second run: keep the UART
PowerShell as window A, start the RIO receiver in window B with a 60-second
first-packet timeout, and after window B prints `ARMED`, return to window A and
send START. No RTL, BIT or configuration change is justified by the timeout.

The operator procedure was then consolidated into [`BOARD_TEST_V7.md`](../../project2_v7_uart_control/BOARD_TEST_V7.md) using the
same evidence-first structure as the earlier Project2 board and V6 ILA guides.
It now carries the complete sequence through 512-byte baseline streaming,
256/1024-byte packetization, rate limiting, exact finite transfer, command and
CRC rejection, a 60-second maximum-rate screen and a 300-second final run. Each
stage defines the two-window handoff, exact commands, expected replies, strict
PASS criteria, unique evidence filenames and the rule to preserve state before
any retry.

## Twenty-seventh experiment: V7 continuous baseline and dynamic packet lengths pass

The manually coordinated two-window board procedure closed V7 gates 1, 2A and
2B. In every run the UART START and STOP commands returned result OK. After STOP
and a 500 ms drain, READ_STATUS reported control version 7,
`run_enable=False`, `mig_calibrated=True`, `fatal=False`, an empty ingress FIFO,
zero DDR-ring occupancy, and zero ingress, ring, TX, UART-CRC and
command-rejection counters.

The 512-byte, 25 Mword/s continuous baseline ran for 60.0003887 seconds and
received 3,898,575 packets / 1,996,070,400 payload bytes at 266.140996 Mb/s.
The 256-byte dynamic-packet run lasted 10.0004083 seconds and received 779,493
packets / 199,550,208 bytes at 159.633649 Mb/s. The 1024-byte run lasted
10.0002455 seconds and received 487,592 packets / 499,294,208 bytes at
399.425561 Mb/s. All three JSON results report `passed=true`, first sequence
zero, and zero missing packets, gaps, duplicates, out-of-order packets,
malformed packets, metadata errors, PRBS data errors and receive-completion
errors. The observed UDP payload sizes are exactly 512, 256 and 1024 bytes.

The packet-size-dependent rates are expected for this validation gate: its
acceptance criterion is correct dynamic segmentation with continuous sequence
and PRBS data, not equal throughput for all payload sizes. The results therefore
close the 512-byte baseline and both dynamic packet-length gates without an RTL,
BIT or host-tool change.

All 11 supplied screenshots and the three original JSON files were archived in
`evidence`. Their full filenames, measured values and SHA-256 hashes are recorded
in [`evidence/V7_STAGE1_STAGE2_EVIDENCE_20260922.md`](../../project2_v7_uart_control/evidence/V7_STAGE1_STAGE2_EVIDENCE_20260922.md). The next unchanged step is
gate 3, the 1024-byte, 12.5 Mword/s rate-limit test.

## Twenty-eighth experiment: V7 rate, finite, protection and final endurance gates pass

All remaining V7 board gates were completed on 2026-09-22 and audited against
the original Windows RIO JSON files and UART screenshots.

The SET_RATE gate used a 1,024-byte payload and 12,500,000 accepted 16-bit
words/s. It ran for 10.000138 seconds, received 244,178 packets / 250,038,272
payload bytes at 200.027857 Mb/s, and reported zero packet loss, gaps,
duplicates, reordering, malformed frames, metadata faults, PRBS errors and
receive-completion errors. The measured rate is within the planned 195–205 Mb/s
window and closes the rate-control function.

The finite gate requested exactly 1,048,576 words with a 256-byte payload. It
produced exactly 8,192 packets and 2,097,152 payload bytes with no host-side
error. READ_STATUS then showed `run_enable=False`, `finite_done=True`,
`finite_mode=True`, `finite_words=1048576`, `run_words=1048576`,
`packet_sequence=8192`, empty ingress and DDR occupancy, and zero internal data
path, UART-CRC and reject counters. This closes automatic finite termination and
exact-count accounting.

The command-protection gate also behaved exactly as specified. SOURCE_SELECT=1
returned UNSUPPORTED, a packet-length change while running returned BUSY, and a
deliberately corrupted READ_STATUS frame received no reply. The following valid
status reported `uart_crc_errors=1` and `command_rejects=2`, with the selected
source unchanged and no fatal condition. Restoring source 0, maximum rate,
1,024-byte payload and continuous mode succeeded, and CLEAR_COUNTERS returned
OK before the final data tests.

One diagnostic nuance was resolved during evidence review. The 12.5 Mword/s
rate-limited status contained `tx_underflow=12952`, and the 1000 word/s
command-protection run contained `tx_underflow=1`. Inspection of
[`udp_v7_tx_fifo_packetizer.v`](../rtl/udp_v7_tx_fifo_packetizer.v) shows that this counter increments once when
`stream_expected` remains asserted while the packetizer is idle and has no
complete packet, then latches until data returns. A producer intentionally
paced below the approximately 400 Mb/s egress therefore creates these counted
idle/starvation intervals. They are not truncated-packet events: both related
host runs retained continuous sequence and correct PRBS data. After the
deliberate low-rate work, CLEAR_COUNTERS reset the diagnostic, and both final
maximum-rate runs finished with `tx_underflow=0`. The board-test guide has been
corrected to state this rate-limit exception while retaining the zero-counter
requirement for maximum-rate qualification.

The 60-second maximum-rate screen received 2,925,342 1,024-byte packets /
2,995,550,208 payload bytes in 60.0002045 seconds at 399.405333 Mb/s. The final
300-second endurance run received 14,626,556 packets / 14,977,593,344 payload
bytes in 300.0003589 seconds at 399.402011 Mb/s. Both JSON files report
`passed=true`, first sequence zero and every packet/data/receive error field at
zero. The final UART status reports `run_enable=False`, empty ingress and DDR
occupancy, `fatal=False`, and all ingress, ring, TX, UART-CRC and reject counters
at zero.

The remaining 18 supplied screenshots and four JSON files were archived under
`evidence`. Their exact filenames, metrics and SHA-256 hashes are recorded in
[`evidence/V7_STAGE3_STAGE7_EVIDENCE_20260922.md`](../../project2_v7_uart_control/evidence/V7_STAGE3_STAGE7_EVIDENCE_20260922.md). Together with the earlier
stage 0–2 evidence, this completes Project2 V7 board validation. No retest or
RTL/BIT change is required.

**V7 final status:** complete. UART framing and CRC, all requested commands,
dynamic packet sizes, rate control, finite transfer, rejection/error counters,
60-second screening and 300-second maximum-rate endurance are closed on board.

## Twenty-ninth experiment: V8 integrates the final Project1 internal XADC source

V8 was created as a separate `project2_v8_xadc_acquisition` project so the
completed V7 archive and its board evidence remain unchanged. The acquisition
design integrates the Project1 XADC module with the high-rate deterministic
PRBS16 test source, sharing the DDR3 and UDP data path.

Project1 [`rtl/xadc_multichannel.v`](../rtl/xadc_multichannel.v) was copied without modification; the source
and V8 copies have the same SHA-256,
`EF467DFEA1DC4867C85712CECA18A9C35EA69B958DF6607F58DEC8A45A58F936`.
A new valid/ready wrapper samples the four Project1 channels in fixed order at
an aggregate 1,000 records/s. Each 16-bit record contains a two-bit channel ID,
two zero reserved bits and the original 12-bit XADC value. A pending register
preserves the record under downstream backpressure and a dedicated drop counter
detects any missed sampling instant. Source 0 retains the board-qualified V7
PRBS16 high-rate path; source 1 selects the real internal XADC. Both sources use
the same ingress FIFO, DDR3 ring, packetizer, Ethernet stack and PC receiver.

The V8 UART control plane accepts source 0 and 1, increments its reported
version to 8 and extends READ_STATUS from 61 to 74 bytes. The additional fields
are XADC valid mask, drop count and the latest raw temperature, VCCINT, VCCAUX
and VCCBRAM values. The Python host tool decodes those fields and prints the
standard XADC temperature and voltage conversions. The UDP header is now P2V8
and includes the source ID. The Windows RIO monitor dispatches validation by
source: direct-index PRBS checking for source 0, or record reserved-bit,
channel-order, per-channel count and min/max checking for source 1.

An integration-specific device constraint was found and resolved rather than
hidden. The xc7a35t has one XADC, while the inherited MIG configuration had
also instantiated an internal XADC for DDR temperature compensation. That
initial form could synthesize but could not place because two XADC instances
competed for one site. The final MIG configuration uses external temperature
input, and the Project1 XADC temperature value is connected to MIG
`device_temp_i`. This preserves MIG temperature compensation while the one
physical XADC also supplies all four acquisition channels. The routed
utilization report confirms exactly one XADC is used.

Behavioral tests pass for the XADC wrapper valid/ready and finite-count
contract, source-tagged packetization, and actual UART serial timing with the
V8 status extension. The UART regression also passes native Vivado XSim. The
Windows RIO V8 receiver was compiled successfully.

Vivado 2018.3 completed synthesis, placement, routing and bitstream generation
for `xc7a35tfgg484-2`. Routed timing is WNS +0.544 ns, TNS 0, WHS +0.031 ns and
THS 0; all specified timing constraints are met. All 20 DDR bus-skew checks are
MET, with minimum slack +6.778 ns. Utilization is 14,910 LUTs (71.68%), 18,166
registers (43.67%), 36 BRAM tiles (72.00%), 0 DSPs and 1/1 XADC. Final DRC has
zero errors, 37 inherited-IP warnings and two advisories. BIT SHA-256 is
`DAD9D9AE15C2380DC22ECF348BA5507E48AE659749717C62D5A78C3BD80637A4`.

One inherited timing XDC contained a conditional Tcl statement that Vivado
2018.3 does not support inside XDC files. The asynchronous clock group was
already applied and checked by the implementation pre-opt Tcl hook, so the
duplicate XDC block was removed and the project was rebuilt. The final
opt/place/route/write-bitstream stages report zero critical warnings and zero
errors; the timing and utilization figures above are from that clean rebuild.

The complete board workflow is in [`BOARD_TEST_V8.md`](BOARD_TEST_V8.md). It explicitly uses two
PowerShell windows, starts the receiver and waits for ARMED before UART START,
and covers every remaining stage through the 300-second final test. It also
records the expected approximately 32.8-second first-packet delay for the slow
XADC source: at 2,000 byte/s, the DDR ring needs that long to reach its 65,536
byte drain high-water mark. The delay is expected batching behavior, not a
failure. The board package and pre-board evidence are prepared; V8 board
validation is the only remaining gate, and no V7 result is being presented as
V8 hardware evidence.

## Thirtieth experiment: V8 board validation closes the real-acquisition path

The complete V8 board procedure was executed on 2026-09-22 and audited against
the four original Windows RIO JSON files and the supplied UART/receiver
screenshots. Initial READ_STATUS identified version 8, a calibrated DDR3 MIG,
no fatal state, `xadc_valid_mask=0xF`, `xadc_drop_count=0`, and plausible live
temperature, VCCINT, VCCAUX and VCCBRAM measurements. This confirms that the
single physical XADC is active before either data-source gate is started.

The source 0 regression used the deterministic PRBS16 generator, 1,024-byte
UDP payloads and 25,000,000 accepted words/s. In 10.0003399 seconds the PC
received 487,592 packets / 499,294,208 payload bytes at 399.421790 Mb/s. The
result has `passed=true`, first sequence zero, and zero missing packets, gaps,
duplicates, reordering, malformed packets, metadata errors, PRBS errors and
receive-completion errors. Final UART status showed an empty ingress and DDR
ring with every internal error counter at zero, so the inherited high-rate
path has no V8 regression.

The source 1 continuous 60-second gate carried the real internal-XADC stream
through the same ingress FIFO, DDR3 ring, packetizer, Ethernet stack and PC
receiver. It delivered 144 packets / 147,456 payload bytes containing 73,728
records. The four fixed-order channels each contributed exactly 18,432 records;
all values remained in the 12-bit range and the measured min/max values were
nonzero and physically plausible. Packet continuity, metadata, record format,
channel order, data and receive-completion error fields were all zero.

The finite gate requested exactly 32,768 XADC records and produced exactly 64
1,024-byte packets / 65,536 payload bytes. Each channel contributed exactly
8,192 records. READ_STATUS then reported `finite_done=True`,
`finite_words=32768`, `run_words=32768`, `packet_sequence=64`, empty ingress
and DDR occupancy, and zero internal error counters. This closes automatic
finite termination and proves exact source-1 accounting across DDR3 and UDP.

The final source 1 endurance gate ran for 300.0529577 seconds and received 624
packets / 638,976 payload bytes containing 319,488 XADC records, exactly 79,872
per channel. It completed with `passed=true`; missing, gap, duplicate,
out-of-order, malformed, metadata, data, XADC format/order and receive-completion
errors were all zero. Final status again showed `run_enable=False`, no fatal
state, empty ingress and DDR occupancy, XADC valid mask `0xF`, and no dropped
XADC samples.

The source 1 continuous final statuses contained `tx_underflow=6` after the
60-second gate and `tx_underflow=13` after the 300-second gate. This is the same
packetizer diagnostic semantics established during V7 low-rate validation: the
counter records a bounded idle/starvation interval while the 1,000-record/s
producer waits to accumulate the next DDR output batch. It does not identify a
truncated packet. Both PC runs retained perfect sequence and record integrity,
both pipelines drained to zero occupancy, and the exact finite gate retained
`tx_underflow=0`. The acceptance guide was corrected to state this slow-source
exception explicitly; no RTL/BIT change or retest is required.

The 22 unique supplied screenshots and all four original JSON files were
archived under `evidence/board_20260922`. One submitted screenshot reference
was a duplicate of the same 300-second FINAL image and was stored once. Exact
metrics, filenames and SHA-256 hashes are recorded in
[`evidence/V8_BOARD_VALIDATION_EVIDENCE_20260922.md`](evidence/V8_BOARD_VALIDATION_EVIDENCE_20260922.md).

**V8 final status:** complete. The core implementation remains documented in
experiment 29, and this experiment closes independent board evidence for both
the high-rate deterministic source and the honest real acquisition target:
internal XADC acquisition through DDR3 to the PC.
