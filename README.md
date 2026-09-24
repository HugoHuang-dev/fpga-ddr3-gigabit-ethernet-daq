# Project 2 — FPGA DDR3-Buffered Gigabit Ethernet Data Acquisition and Streaming System

**Architecture, module development, and simulation test planning: July 19–September 17, 2026 · Integration, regression, and board validation: September 19–23, 2026**  
**Hardware: Davinci V2.1 / Xilinx Artix-7 XC7A35T · Tools: Vivado 2018.3, Verilog, ModelSim, Python, Windows RIO, and ILA**

## Highlights

- **Multi-clock RTL architecture:** asynchronous CDC, flow control, and continuous FPGA streaming
- **DDR3 memory subsystem:** AXI4/MIG-controlled 256 KiB ring buffer with concurrent reads/writes and backpressure
- **Digital design flow:** ModelSim → synthesis → static timing analysis → implementation → multi-domain ILA
- **Hardware validation:** sustained 397.845 Mb/s UDP payload throughput over a 1-hour endurance run

The project began with a UDP loopback, brought up Ethernet and DDR3 independently, and then moved a finite PRBS16 data set through DDR3 to a PC. It evolved into a continuous acquisition and streaming system with a DDR3 ring buffer, a concurrent pipeline, UART control, and on-chip XADC acquisition. After the board arrived in September, the versions were validated on hardware in succession. V5 board bring-up led to improvements in the receiver, UDP transmit timing, IPv4 checksum logic, and reset boundaries; the final V6–V9 implementations incorporated these changes. The result is a traceable evidence set spanning RTL, simulation, timing, on-board signals, and PC-side reception statistics.

The system has two data sources. **PRBS16** provides repeatable, byte-for-byte verification at high throughput. The **on-chip XADC** samples temperature, VCCINT, VCCAUX, and VCCBRAM in sequence. Both sources share the FIFO, DDR3 ring-buffer, UDP, and PC verification path.

## System architecture

```text
PRBS16 high-speed test source ─┐
                               ├─► valid/ready ─► ingress FIFO ─► AXI4 / MIG ─► DDR3 ring buffer
Project 1 on-chip XADC ────────┘                                           │
                                                                            ▼
PC: packet/sample/content checks ◄─ Gigabit Ethernet / UDP ◄─ packet FIFO ◄─ DDR3 read bursts
             ▲
             └──────── UART: START / STOP / source / rate / packet length / status
```

The FPGA and PC use a direct Gigabit Ethernet connection: FPGA `192.168.1.11`, PC `192.168.1.100`, receiver port `6666`. The DDR3 path crosses the 125 MHz acquisition/network domain and the MIG `ui_clk` domain through asynchronous FIFOs and synchronizers. ILA captures are separated by clock domain. From V5 onward, the ring buffer is 256 KiB, divided into 1,024-byte slots. A successful AXI `B` response commits a write; a complete read burst releases DDR space only after it has entered the transmit FIFO. Occupancy and backpressure protect buffer ownership during continuous operation.

## Development timeline · July 19–September 17, 2026

Development proceeded from isolated network and memory functions to an end-to-end path, then to continuous streaming, control, and system-level validation. The dates below describe each version's architecture, interfaces, and planned verification cases. The actual September implementation and board results follow in the next section.

| Period | Version | Design and development |
| --- | --- | --- |
| Jul 19–21 | **V1 — network connectivity** | Adapted the ARP/ICMP/UDP/RGMII stack; defined pin assignments, PHY reset, and clocks; designed UDP loopback, a fixed beacon, and an application-level self-test. This established the bidirectional network path independently. |
| Jul 22–25 | **V2 — continuous test stream** | Defined a 1,024-byte UDP payload, a 32-bit packet sequence, and incrementing bytes continuous across packets. Planned PC checks for missing, duplicate, out-of-order, malformed, and corrupted packets, with JSON statistics. |
| Jul 26–Aug 1 | **V3 — standalone DDR3 self-test** | Designed MIG/AXI4 calibration and write/readback tests using address data, walking-bit data, and PRBS patterns, with LED and ILA observation points. |
| Aug 2–10 | **V4 — finite end-to-end transfer** | Designed a 32,768-word, 16-bit PRBS path through an asynchronous FIFO, AXI4/DDR3, UDP, and the PC. Defined source/packetizer simulation cases, 64-packet transfer, byte-level PC checks, and write/read/completion ILA captures. |
| Aug 11–24 | **V5 — continuous ring buffer** | Extended the one-shot transfer architecture to a 256 KiB DDR3 ring and a continuous source. Defined occupancy, backpressure, AXI write commitment, complete-read release, and full-ring/recovery simulation cases. |
| Aug 25–Sep 1 | **V6 — concurrent pipeline** | Separated the ingress FIFO, DDR write/read operations, and transmit FIFO. Designed overlapping reads and writes plus ingress/DDR high- and low-watermark scheduling, with throughput and backpressure checks. |
| Sep 2–7 | **V7 — UART control** | Used the Project 1 frame format and CRC-16 to define START/STOP, source selection, rate control, variable packet lengths, finite/continuous modes, and atomic status snapshots. Planned dual-terminal operation and invalid-command tests. |
| Sep 8–13 | **V8 — four-channel acquisition** | Designed the on-chip XADC connection, shared source 0/1 path, channel encoding, dropped-sample counter, and PC-side XADC record checks. |
| Sep 14–17 | **V9 — layered validation** | Defined independent checks of packet sequence and 64-bit sample index, ILAs in three clock domains, ModelSim self-tests, receiver fault injection, and staged PRBS/XADC/endurance gates. |

September board bring-up further refined the V5 protocol, reset, and reception paths. The final V6–V9 projects incorporated those revisions and were validated version by version. The [V1–V3 development-record index](versions/v1_v5/V1-V3_DEVELOPMENT_RECORD_INDEX.md) links their development, offline, and board evidence. The [V4 development record](versions/v1_v5/project2_v4_ddr3_udp/evidence/development_log.md) distinguishes the August design/test cases from the September regression, implementation, and board results. V5–V9 integration and board work are collected in the [development log](DEVELOPMENT_LOG.md).

## Key engineering issues

**Clock-domain boundaries and timing constraints.** The first complete V4 implementation had WNS of approximately **−1.986 ns**. The worst path crossed the 125 MHz domain and the MIG clock domain through an asynchronous FIFO/synchronizer structure, but the clocks were analyzed as synchronous. Declaring the asynchronous clock relationship brought WNS to **+0.982 ns**. V5 also moved the cross-domain constraint application to post-link, when the generated clock objects exist. See the [V4 development record](versions/v1_v5/project2_v4_ddr3_udp/evidence/development_log.md) and [V5 log](versions/v5_v6/Project2_work_log.md).

**Continuous transmission and receiver performance.** During the first V5 board tests, the Python receiver generated a new PRBS reference for each packet gap. That made a gap increasingly expensive to process. Precomputing the PRBS period and indexing it directly by sequence restored stable reception; a native Winsock receiver and batched RIO reception later improved receive efficiency and statistics. RTL review also found that the UDP transmit interface briefly retained an old high `ready` value at the edge accepting a packet's last byte, allowing the next packet to start early. The packetizer was changed to wait for `ready` to go low and then high, and this behavior was covered by a timing-aware simulation regression. Retesting separated protocol timing issues from host receive-path limits.

**IPv4 checksum and reset consistency.** A roughly 200 Mb/s diagnostic run showed a recurring two-packet gap once per 16-bit IP-ID cycle. Inspection of the transmit logic identified an IPv4 one's-complement carry-fold boundary error; the periodic gaps disappeared after correction. A separate run had continuous packet sequence numbers but a PRBS phase mismatch. That led to a consistent reset boundary for the PRBS source and MIG/UI data path, plus MAC FIFO sticky probes. The successive JSON results and reasoning are preserved in the [V5 version record](versions/v1_v5/project2_v5_ring_buffer/README.md) and [cumulative log](versions/v5_v6/Project2_work_log.md).

**Receive path and operating conditions.** Paired PktMon and RIO sequence traces helped locate where packet gaps appeared; MAC FIFO sticky probes exposed the transmit queue state. Tests with a separate receive host and different system loads showed how the PC power profile, background load, and NIC receive scheduling affected high-packet-rate headroom. With the host in high-performance mode, packet capture stopped, and background load controlled, 315 Mb/s passed three consecutive 60-second runs and one 300-second run. These conditions provided a repeatable baseline for higher-rate testing. See the [comparative test log](versions/v5_v6/Project2_work_log.md).

**XADC and MIG resource sharing.** V8 used one on-chip XADC for both four-channel monitoring data and the MIG temperature input. The routed utilization report confirmed **1/1 XADC**. At the low acquisition rate, filling the first 64 KiB DDR drain batch takes about 32.8 seconds. Packet continuity, final drain state, and the `tx_underflow` count were assessed together for this slow source. See the [V8 implementation and validation record](versions/v7_v9/project2_v8_xadc_acquisition/README.md).

## Board bring-up and version completion · September 19–23, 2026

After the board arrived, V1–V4 were validated in dependency order, followed by intensive V5 continuous-stream debugging. V6–V9 incorporated the resulting protocol and receiver revisions and completed their own simulation, implementation, and board checks.

### Base path and finite transfer: V1–V4

V1 passed ARP, ping, fixed-beacon, and 64-byte UDP echo checks over a direct cable and Type-C Gigabit Ethernet adapter; see the [board result](versions/v1_v5/project2_v1_udp/README.md). V2 received **29,755 packets** in a 30-second continuous run at about **8.125 Mb/s**, with zero missing, out-of-order, or corrupt packets; see the [raw JSON](versions/v1_v5/project2_v2_stream/evidence/v2_30s_result.json). On September 19, V3 completed DDR3 calibration and three AXI write/readback modes; LEDs and ILA showed `error_count=0` and matching 128-bit readback data; see the [V3 evidence](versions/v1_v5/project2_v3_ddr3/README.md). V4 used KEY0 to launch a finite 64 KiB transfer. The PC received **64/64 packets** and passed byte-level PRBS, sequence, and format checks. AXI write, read, and completion ILAs confirmed the internal path; see the [raw result](versions/v1_v5/project2_v4_ddr3_udp/evidence/v4_result.json) and [development/ILA record](versions/v1_v5/project2_v4_ddr3_udp/evidence/development_log.md).

### Continuous streaming and throughput ladder: V5

V5 established a staged performance curve. Approximately **200 Mb/s** passed multiple short runs. **315 Mb/s** passed three consecutive 60-second runs and a 300-second run with zero loss. A 60-second run at approximately **399.408 Mb/s** had zero receiver-check errors. With additional inter-packet throttling removed, the MAX image reached **680.207 Mb/s** for 60 seconds with zero loss. The MAX one-hour run received **298,914,974 packets** and verified **306,088,933,376 bytes** byte-for-byte at an average **680.198 Mb/s**. Packet delivery was **99.999779%**, with 25 gaps totaling 660 packets. Short-term peak and one-hour endurance results are retained separately. See the [V5 full log](versions/v5_v6/Project2_work_log.md), [400M image record](versions/v5_v6/project2_v5_400m/README.md), and [MAX raw JSON](versions/v5_v6/Project2_MAX_USB_Kit/results/20260922_004730_216/rio_result.json).

Four formal V5 ILA capture types used the approximately 400 Mb/s image: commitment after a successful AXI write response, release after a complete read burst, 256 KiB ring-pointer wraparound, and full-ring backpressure/steady operation. PC packet-by-packet checks and FPGA buffer state corroborate one another. See the [V5 ILA record](versions/v1_v5/project2_v5_ring_buffer/README.md).

### Pipeline, command control, and measured acquisition: V6–V8

The final V6 design added a 4 KiB ingress FIFO, independently overlapped DDR reads and writes, an eight-packet output FIFO, and hysteretic watermarks. Its 60-second board run reached **399.405 Mb/s** and **2,925,356 packets**, with all PC error counters at zero. Fourteen ILA images cover high/low watermarks, the start of a 64 KiB drain, write suspension at a full ring, concurrent DDR reads/writes, complete-packet commitment, and UDP packet completion. See the [V6 result and evidence](versions/v5_v6/project2_v6_pipeline/README.md).

The final V7 design added UART START/STOP, source selection, rate limiting, 256/512/1,024-byte packet lengths, finite/continuous modes, counter clear, and atomic READ_STATUS. Simulation and board tests covered UART CRC, busy-state rejection, dynamic packetization, and exact finite counts. A final 300-second, 1,024-byte run received **14,626,556 packets** at approximately **399.402 Mb/s**, with zero loss and PRBS content errors. See the [V7 entry](versions/v7_v9/project2_v7_uart_control/README.md), [stages 1–2](versions/v7_v9/project2_v7_uart_control/evidence/V7_STAGE1_STAGE2_EVIDENCE_20260922.md), and [stages 3–7](versions/v7_v9/project2_v7_uart_control/evidence/V7_STAGE3_STAGE7_EVIDENCE_20260922.md).

The final V8 design made source 0 PRBS16 and source 1 on-chip XADC share the DDR3→UDP→PC path. The source 0 short run reached approximately **399.422 Mb/s**. XADC passed a 60-second continuous run, a **32,768-record** finite run, and a **300-second** continuous run, with correct channel order and record format and no dropped XADC samples. See the [V8 README](versions/v7_v9/project2_v8_xadc_acquisition/README.md) and [board evidence](versions/v7_v9/project2_v8_xadc_acquisition/evidence/V8_BOARD_VALIDATION_EVIDENCE_20260922.md).

### Full validation and one-hour measurement: V9

V9 focused on system-level validation and metrics. P2V9 added a **64-bit first-sample index**. The Windows RIO receiver independently checked packet sequence, sample index, PRBS content or XADC records. ILAs covered the acquisition, MIG UI, and PHY RX clock domains. ModelSim **3/3** self-tests, receiver **10/10** self-tests, routed timing (WNS **+0.292 ns**), and zero DRC errors completed; see the [implementation and simulation evidence](versions/v7_v9/project2_v9_full_validation/evidence/V9_PREBOARD_EVIDENCE_20260923.md).

On September 23, Gate 1 passed a 60-second PRBS16 board run at approximately **397.855 Mb/s**, with every check satisfied. Gate 2 passed a finite 32,768-record XADC run, and Gate 3 passed a 300-second XADC run. Four native ILA captures documented acquisition handshakes, PHY RX activity, DDR commitment, and a separate `packet_done` capture. See the [V9 board evidence index](versions/v7_v9/project2_v9_full_validation/evidence/board_20260923/V9_BOARD_EVIDENCE_FINAL.md).

Gate 5 ran for the full **3,600 seconds** and received **174,834,426 packets** and **179,030,452,224 bytes** at an average UDP payload rate of **397.845 Mb/s**, a packet delivery rate of approximately **99.998957%**. The receiver recorded 30 gaps totaling **1,824 packets**. All received data passed PRBS byte, format, and metadata checks. This is a one-hour high-load throughput and integrity measurement; the planned zero-loss acceptance item was **not passed**. The [raw Gate 5 JSON](versions/v7_v9/project2_v9_full_validation/evidence/board_20260923/results/v9_gate5_prbs_1024B_25M_3600s.json) and [screenshot, waveform, and hash index](versions/v7_v9/project2_v9_full_validation/evidence/board_20260923/V9_BOARD_EVIDENCE_FINAL.md) preserve the measured outcome.

## Rebuild and verify

The final V9 implementation is organized as a reproducible Vivado 2018.3 project. From the repository root on Windows, with Vivado available on `PATH`:

```powershell
vivado -mode batch -source scripts/create_project.tcl
vivado -mode batch -source scripts/build_bitstream.tcl
```

The first command creates `build/project2_v9_full_validation.xpr`; the second writes the local BIT/LTX pair and timing, utilization, and DRC reports. The checked-in `ip/` directory contains the compact `.xci` configurations for the clock, FIFO, and MIG cores; Vivado regenerates their implementation products. For the three focused V9 ModelSim regressions, run `powershell -ExecutionPolicy Bypass -File scripts/run_modelsim_v9.ps1`. The receiver source, build command, UART controller, and board-test procedure are in [tools/](tools/), [host/](host/), and the [V9 board package](board_test_package/README.md). A matching V9 [BIT/LTX release pair](releases/README.md) is also retained for direct board programming.

Earlier version snapshots under `versions/` retain their own RTL, constraints, IP configurations, and project scripts for stage-specific reconstruction. Test data, ILA captures, and implementation reports remain beside the corresponding version records.

## Conclusion

Project 2 progressed from network connectivity to a measurable data stream, standalone DDR3 correctness, finite end-to-end transfer, continuous ring buffering, a concurrent pipeline, UART control, on-chip XADC, and layered validation. RTL, simulation, timing, board JSON, and ILA evidence are retained for each stage. The V5 MAX **680.207 Mb/s zero-loss short run** demonstrates peak capability; the V9 **397.845 Mb/s one-hour run** documents sustained operation. Gaps in the endurance result remain part of the original record and provide a quantitative baseline for future optimization.

## Project and evidence index

Projects, results, and development records are archived by stage. The [V1–V9 image and waveform index](evidence/README.md) and [constraints index](constraints/README.md) cover screenshots, native ILA files, and pin/timing constraints.

The top-level `rtl/`, `ip/`, `constraints/`, `sim/`, `scripts/`, `host/`, `board_test_package/`, and `reports/` directories contain the finalized V9 project. The top-level [V9 bitstream](project2_v9_top.bit) and [ILA probe file](project2_v9_top.ltx) are used directly by the programming script. The [release index](releases/README.md) preserves bitstreams and probe files by version. Build scripts use paths relative to this project root and generate `build/` locally. `versions/` retains stage-specific source snapshots, diagnostic variants, and their validation evidence. The [repository contents note](REPOSITORY_CONTENTS.md) distinguishes tracked evidence from larger capture traces kept in the project archive.

Project-authored RTL, simulation, Vivado Tcl, and constraint files carry project headers. The protocol-stack code, generated IP, base UART/CRC modules, and reused XADC module retain their original attribution. The [source-header manifest](tools/source_header_manifest.csv) records SHA-256 values before and after header additions.

| Material | Entry points |
| --- | --- |
| V1–V5 projects | [V1 network](versions/v1_v5/project2_v1_udp/README.md) · [V2 stream](versions/v1_v5/project2_v2_stream/README.md) · [V3 DDR3](versions/v1_v5/project2_v3_ddr3/README.md) · [V4 finite transfer](versions/v1_v5/project2_v4_ddr3_udp/README.md) · [V5 ring buffer](versions/v1_v5/project2_v5_ring_buffer/README.md) |
| V5 diagnostics and V6 | [V5–V9 development log](DEVELOPMENT_LOG.md) · [V5 200M result](versions/v5_v6/v5_200m_pass_baseline/rio_result.json) · [V5 315M](versions/v5_v6/project2_v5_315m/README.md) · [V5 400M](versions/v5_v6/project2_v5_400m/README.md) · [V5 MAX](versions/v5_v6/project2_v5_max_unpaced/README.md) · [V6](versions/v5_v6/project2_v6_pipeline/README.md) |
| V7–V9 projects and validation | [V7](versions/v7_v9/project2_v7_uart_control/README.md) · [V8](versions/v7_v9/project2_v8_xadc_acquisition/README.md) · [V9 development and validation](DEVELOPMENT_LOG.md#v9) · [V9 board evidence](versions/v7_v9/project2_v9_full_validation/evidence/board_20260923/V9_BOARD_EVIDENCE_FINAL.md) |
| V9 project and retest procedure | [V9 project notes](versions/v7_v9/project2_v9_full_validation/README.md) · [board procedure](versions/v7_v9/project2_v9_full_validation/BOARD_TEST_V9.md) · [acceptance criteria](versions/v7_v9/project2_v9_full_validation/VALIDATION_PLAN_V9.md) |
