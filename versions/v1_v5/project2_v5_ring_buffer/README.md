# Project 2 V5 — DDR3 Ring Buffer and Flow Control

This page documents V5 ring-buffer implementation and its early diagnostic runs. The subsequent 315M, 400M, and MAX throughput steps and final ILA evidence appear in the [V5 development-log section](../../../DEVELOPMENT_LOG.md#v5); together they form the complete version record.

[V5 image and waveform index](../../../evidence/V5.md) · [V5 constraints index](../../../constraints/V5.md)

V5 turns V4's finite transfer into a continuous data path:

```text
Continuous PRBS16 source
  -> ADMA write FIFO / AXI4 writes
  -> 256 KiB DDR3 ring buffer (256 × 1,024-byte slots)
  -> ADMA AXI4 reads
  -> two-packet transmit FIFO
  -> UDP (24-byte header + 1,024 data bytes)
  -> continuous PC validation and statistics
```

V5 retains `axi_adma_v1`, MIG, and the `net21` UDP modules. Its upper-level controller establishes ownership of ring slots and schedules reads/writes. A DDR read request now depends jointly on committed data and enough space for a complete packet in the transmit FIFO; it is no longer directly tied to the final beat of a write burst.

## Flow-control invariants

- Advance the write pointer and `committed_bytes` only when `BVALID && BREADY && BRESP==OKAY`.
- Latch `fatal_error` immediately on a non-OKAY `BRESP` and stop further scheduling.
- Start a read only when committed DDR data exists and the transmit FIFO can accept the entire 1,024-byte burst.
- Release ring space only after the final byte marked by `user_rd_last` has actually entered the transmit FIFO.
- Count ring occupancy in 1,024-byte slots, accounting for a write commitment and read release in the same cycle; occupancy must remain within 0–256 KiB.
- Limit V5 to at most one in-flight write burst and one in-flight read burst. Establish exact ownership and counter behavior first; later versions increase concurrency.

## Simulation and implementation

Behavioral simulation passed. Its 4 KiB miniature ring was deliberately filled to exercise write backpressure, and the testbench modeled the actual `net21/udp_send` `ready` timing. Final simulation counters were `committed=76800`, `released=73728`, occupancy `3072 B`, and `17` write-stall cycles; two consecutive complete packets passed.

Vivado 2018.3 generated a bitstream. The current 200 Mb/s image with the IPv4 checksum correction met timing: WNS `+0.982 ns`, TNS `0.000 ns`, WHS `+0.057 ns`, and THS `0.000 ns`. Diagnostic-image utilization was 11,424 LUTs, 15,121 registers, and 23 BRAM tiles. DRC had zero errors; FIFO/MIG/UDP asynchronous-reset REQP warnings remain in the implementation report, with post-reset behavior also checked on the board.

These results, the PC reception tests, and the ILA captures jointly form the V5 validation record.

## Rebuilding the project

From this directory in the Vivado 2018.3 Tcl Shell:

```tcl
source scripts/create_project.tcl
source scripts/run_sim.tcl
source scripts/build_bitstream.tcl
```

Equivalent PowerShell commands:

```powershell
& 'C:\Xilinx\Vivado\2018.3\bin\vivado.bat' -mode batch -source scripts/create_project.tcl
& 'C:\Xilinx\Vivado\2018.3\bin\vivado.bat' -mode batch -source scripts/run_sim.tcl
& 'C:\Xilinx\Vivado\2018.3\bin\vivado.bat' -mode batch -source scripts/build_bitstream.tcl
```

The build generates `build/project2_v5_ring_buffer.xpr` locally. The [bitstream](project2_v5_top.bit), [ILA probes](project2_v5_top.ltx), and timing/utilization reports under `reports/` are retained here.

## Continuous board test

1. Keep the external Type-C Gigabit adapter at static address `192.168.1.100/24`; the FPGA is `192.168.1.11`.
2. Program [`project2_v5_top.bit`](project2_v5_top.bit) and confirm LED0 is on (MIG calibrated).
3. The compiled Windows RIO batch receiver is [`tools/udp_v5_monitor_rio.exe`](tools/udp_v5_monitor_rio.exe). To rebuild it, run `powershell -ExecutionPolicy Bypass -File tools\build_udp_v5_monitor_rio.ps1`.
4. Run `tools\udp_v5_monitor_rio.exe --duration 60 --output evidence\v5_60s_ipv4_checksum_fix_result.json` from this directory. When the receiver displays `ARMED`, press KEY0 once. LED1 means streaming has started without a latched fatal error.
5. Wait for `V5 DDR3 RING-BUFFER STREAM TEST PASSED`.
6. After the test, press RESET to stop and rearm; the continuous V5 source does not stop on its own.

This run used the BIT/LTX regenerated in this directory. The image includes the UDP `ready` handshake correction, second carry fold in the IPv4 checksum, and a diagnostic inter-packet gap of 3,000 cycles of the 100 MHz UI clock. Payload throughput is about 199.7 Mb/s. RIO v6 anchors sequence checking at the first valid packet, pre-posts 16,384 receive buffers, raises receive-thread priority, and saves `expected/received/missing` details for the first 128 gaps. The 60-second verdict checks missing packets, gap events, format, metadata, PRBS data, duplicates, out-of-order packets, and RIO completion errors. The throughput ladder and endurance testing followed.

RIO v6 precomputes a full PRBS period, indexes it directly by packet sequence, and recycles up to 256 registered-buffer completions per batch. It checks every packet's sequence, 1,024-byte PRBS data, frame format, and ring-occupancy metadata. JSON retains first sequence, rate, loss and gap details, reordering, duplication, content errors, and maximum occupancy. Python v2, synchronous Winsock v3, and RIO v4/v5 remain as diagnostic references.

One 200 Mb/s retest received `1,462,744` packets in 60 seconds but reported `299` missing sequence positions, most as a fixed increase of two roughly every 2.69 seconds. Inspection of [`net21/ip_send.v`](rtl/vendor/net21/ip_send.v) showed that the IPv4 one's-complement sum folded its carry only once. For the current addresses, 1,076-byte IP total length, and UDP protocol number, IP IDs `0x72FA` and `0x72FB` produced incorrect checksums once per 16-bit ID cycle, so Windows discarded those frames. `65536 / 24388 packets/s ≈ 2.69 s` matched the screenshot period. A second carry fold and boundary regression removed the recurring two-packet gaps; remaining intermittent gaps were investigated with synchronized capture and host-load comparisons.

## UDP V5 format

Each application payload is 1,048 bytes. All multi-byte header fields are big-endian:

| Offset | Field | Length |
| ---: | --- | ---: |
| 0 | `P2V5` | 4 B |
| 4 | version = 5 | 1 B |
| 5 | flags = 0 | 1 B |
| 6 | total length = 1048 | 2 B |
| 8 | packet sequence | 4 B |
| 12 | data length = 1024 | 2 B |
| 14 | header length = 24 | 2 B |
| 16 | committed bytes, low 32 bits | 4 B |
| 20 | occupancy bytes | 4 B |
| 24 | continuous PRBS16 data | 1,024 B |

## ILA probe map

ILA depth is 2,048 samples in MIG `ui_clk`. All probes are listed at once so the capture layout need not be repeatedly edited:

| Probe | Signal | Probe | Signal |
| ---: | --- | ---: | --- |
| 0 | `init_calib_complete` | 20 | `packet_done` |
| 1 | `ring_started` | 21 | `packet_sequence[31:0]` |
| 2 | `write_pointer[31:0]` | 22 | `fatal_error` |
| 3 | `read_pointer[31:0]` | 23–26 | four ADMA FIFO error flags |
| 4 | `occupancy_bytes[31:0]` | 27 | `ring_full` |
| 5 | `committed_bytes[31:0]` | 28 | `ring_empty` |
| 6 | `released_bytes[31:0]` | 29 | `write_stall_cycles[31:0]` |
| 7 | `write_inflight` | 30–31 | `ARVALID / ARREADY` |
| 8 | `read_inflight` | 32–33 | `RVALID / RLAST` |
| 9 | `write_grant_toggle` | 34–35 | `AWVALID / AWREADY` |
| 10 | `user_wr_en` | 36–37 | `WVALID / WREADY` |
| 11–13 | `BVALID / BREADY / BRESP[1:0]` | 38 | `tx_burst_committed` |
| 14 | `user_rd_req` | | |
| 15–16 | `user_rd_valid / user_rd_last` | | |
| 17 | `tx_fifo_byte_count[11:0]` | | |
| 18 | `tx_fifo_packet_count[1:0]` | | |
| 19 | `tx_burst_space_available` | | |

Display pointers and cumulative byte counters in hexadecimal or unsigned radix; occupancy, FIFO counts, sequence, and stall cycles in unsigned; and one-bit handshakes in binary.

### Four ILA checks

1. **Write commitment:** trigger on `probe11 BVALID == 1`. `BREADY=1` and `BRESP=0` should accompany the response, followed by 1,024-byte increments in `committed_bytes`, write pointer, and occupancy.
2. **Read into transmit FIFO and release:** trigger on `probe38 tx_burst_committed == 1`. Observe `user_rd_last=1`, followed by 1,024-byte increments in `released_bytes` and read pointer and a 1,024-byte occupancy decrease.
3. **Ring wraparound or backpressure:** after sustained operation, trigger on `write_pointer==0` for wraparound or `ring_full==1` when transmission is blocked. Wraparound is normal; a full ring must suspend write grants and resume after release.
4. **Steady-state capture:** use Immediate Trigger. Confirm `fatal_error=0`, all four FIFO errors are zero, commitment/release counts keep rising, and packet sequence advances.

For an error-specific capture, trigger on `fatal_error==1`; it remains zero in normal operation.

## Evidence inventory

- [Behavioral simulation](evidence/v5_simulation.txt) and [architecture/validation log](evidence/development_log.md).
- First PC receiver bottleneck: [image 01](evidence/v5_pc_monitor_bottleneck_01.png) · [02](evidence/v5_pc_monitor_bottleneck_02.png) · [03](evidence/v5_pc_monitor_bottleneck_03.png) · [04](evidence/v5_pc_monitor_bottleneck_04.png). The [first 60-second JSON](evidence/v5_60s_result.json) is retained as a failed diagnostic run, not final performance evidence.
- [Python v2 local loopback self-test](evidence/v5_monitor_v2_loopback_selftest.json); receive-limit images [01](evidence/v5_pc_monitor_v2_limit_01.png) · [02](evidence/v5_pc_monitor_v2_limit_02.png) · [03](evidence/v5_pc_monitor_v2_limit_03.png) · [04](evidence/v5_pc_monitor_v2_limit_04.png). The [second 60-second JSON](evidence/v5_60s_v2_result.json) is another retained failed diagnostic.
- [Native v3 local 300-packet loopback self-test](evidence/v5_monitor_v3_loopback_selftest.json), with zero errors, and its [full stdout](evidence/v5_monitor_v3_loopback_stdout.txt). Winsock v3's approximately 39.7 kpackets/s ceiling appears in [01](evidence/v5_native_v3_failure_01.png) · [02](evidence/v5_native_v3_failure_02.png) · [03](evidence/v5_native_v3_failure_03.png); the [third failed result](evidence/v5_60s_v3_result.json) is retained.
- [RIO v4 local 300-packet loopback self-test](evidence/v5_monitor_v4_rio_loopback_selftest.json) and [stdout](evidence/v5_monitor_v4_rio_loopback_stdout.txt) have zero errors/gaps. Its [board retest JSON](evidence/v5_60s_v4_rio_result.json) and screenshots [01](evidence/v5_rio_v4_failure_01.png) · [02](evidence/v5_rio_v4_failure_02.png) · [03](evidence/v5_rio_v4_failure_03.png) show that changing receiver engines alone did not eliminate sequence gaps.
- The [UDP `ready` regression before the fix](evidence/v5_ready_handshake_regression_before_fix.txt) fails reliably; the [post-fix simulation](evidence/v5_simulation.txt) passes. The [fifth board-test JSON](evidence/v5_60s_post_handshake_fix_result.json) and images [01](evidence/v5_post_handshake_failure_01.png) · [02](evidence/v5_post_handshake_failure_02.png) · [03](evidence/v5_post_handshake_failure_03.png) show an improved gap pattern but unchanged aggregate throughput ceiling.
- The [approximately 315 Mb/s diagnostic JSON](evidence/v5_60s_paced_300m_result.json) shows that sustained loss disappeared, although 38 intermittent gaps remained. Screenshots: [01](evidence/v5_paced_300m_failure_01.png) · [02](evidence/v5_paced_300m_failure_02.png) · [03](evidence/v5_paced_300m_failure_03.png) · [04](evidence/v5_paced_300m_failure_04.png).
- The [seventh, approximately 200 Mb/s failed run](evidence/v5_60s_paced_200m_result.json) led to the IPv4 checksum root cause. Screenshots: [01](evidence/v5_paced_200m_failure_01.png) · [02](evidence/v5_paced_200m_failure_02.png) · [03](evidence/v5_paced_200m_failure_03.png) · [04](evidence/v5_paced_200m_failure_04.png). The [checksum analysis](evidence/v5_ipv4_checksum_analysis.txt) preserves constants, failing IP IDs, observed period, and corrected boundary values.
- The [RIO v6 deliberate-gap self-test](evidence/v5_monitor_v6_gap_selftest.json) and [stdout](evidence/v5_monitor_v6_gap_selftest_stdout.txt) skip sequences 100 and 101 and verify `expected=100, received=102, missing=2` with all other checks at zero.
- PC results and four critical ILA groups were copied into `evidence/`. Write commitment, complete-read release, pointer wraparound, and steady-state captures passed, completing the planned V5 board-function checks.

## Eighth board run: retest after the checksum fix

After correcting the IPv4 checksum, a 60-second run received 1,462,700 packets at 199.70678643 Mb/s. Two gaps remained, totaling 345 packets (334 + 11); all other validation errors were zero. The periodic two-packet gaps had disappeared, but this run did not meet the zero-loss criterion. [Screenshots](../../../evidence/V5.md) retain this diagnosis. The image was then held fixed while NIC-ingress captures and RIO sequences were compared to isolate the intermittent gaps.

## Ninth board run: first zero-loss 60-second pass

With the checksum-corrected image and RIO v6, a run with PktMon enabled received 1,463,042 packets and 1,498,155,008 bytes of PRBS data in 60.0000134 seconds, averaging 199.753956455 Mb/s. Every error item was zero. The [raw result](evidence/ingress_20260920_230946/rio_result.json) and [image index](../../../evidence/V5.md) preserve this first 60-second pass. Host-load comparisons, rate steps, and endurance testing followed in the [development log](../../../DEVELOPMENT_LOG.md#v5).

## Final V5 state · September 22, 2026

The later 315M, 400M, and MAX steps, receive-path comparisons, and endurance run are documented in the [V5 development log](../../../DEVELOPMENT_LOG.md#v5). Formal ILA evidence used the approximately 400 Mb/s image: it retained the same DDR ring, AXI path, packetizer, and 39 probes as MAX and had already passed a zero-loss 60-second PC run. Four waveforms confirmed:

1. After successful AXI `BVALID/BREADY` with `BRESP=00`, write pointer, committed bytes, and occupancy each increased by 1,024 bytes.
2. Once an entire 1,024-byte read burst entered the transmit FIFO, `tx_burst_committed` asserted; read pointer and released bytes increased by 1,024 bytes and occupancy fell by 1,024 bytes.
3. The 256 KiB ring write pointer wrapped from `0x0003FC00` to `0x00000000`.
4. During continuous operation MIG remained calibrated, the ring was active, and fatal/ADMA FIFO errors stayed at zero. Writes paused when the ring filled and resumed after space was released.

The [V5 ILA image index](../../../evidence/V5.md) links all four groups. V5 completed RTL, simulation, implementation, timing, packet/byte-level PC checks, and internal ILA checks. Its MAX 60-second run reached 680.207 Mb/s with zero loss; its one-hour run averaged 680.198 Mb/s with 25 gaps totaling 660 packets. The two outcomes are retained separately with their respective durations and criteria.
