# Project 2 Continuation Record

Updated September 20, 2026. This record draws on the version projects, V5 test JSON, board screenshots, and implementation reports to document retesting after the checksum repair and the next diagnostic steps. Later results are recorded at the end.

## Project goal and validation workflow

The system on the DaVinci Artix-7 XC7A35T-FGG484-2 follows the path acquisition/test source → clock-crossing FIFO → AXI4/MIG/DDR3 → UDP → PC validation. Development proceeds in stages, with focused simulation, implementation and timing checks, board tests, and evidence capture. Interface behavior and scheduling receive particular attention.

For each stage: define the target, implement RTL and host software, run focused simulation, synthesize and implement in Vivado, verify timing, test the matching BIT/LTX on the board, capture ILA traces, inspect JSON and screenshots, and update the development log. Failed runs and post-fix retests are archived separately.

## Stages completed at this checkpoint

| Version | Scope | Evidence checked at this point |
| --- | --- | --- |
| V1 | ARP, ping, UDP echo, beacon | Board test passed |
| V2 | Incrementing data, packetization, PC continuity check | 30 seconds at approximately 8.125 Mb/s with zero errors; DDR3 not in path |
| V3 | MIG calibration and AXI4 write/read tests with address, walking-bit, and PRBS patterns | Board test and ILA passed |
| V4 | PRBS → DDR3 → UDP, finite 64 KiB / 64-packet transfer | End-to-end board test and ILA passed |
| V5 | 256 KiB DDR3 ring buffer and continuous flow control | Simulation and implementation passed; a zero-loss board run had not yet passed at this checkpoint |

## Architecture and tested configuration

Backpressure-capable PRBS16 source (125 MHz) → ADMA asynchronous write FIFO → AXI4/MIG (100 MHz UI) → 256 KiB DDR3 ring buffer (256 × 1024-byte slots) → AXI4 read → two-packet TX FIFO → UDP/IP/MAC/RGMII → Realtek USB Gigabit NIC → Windows RIO v6.

FPGA: `192.168.1.11:8888`. PC: `192.168.1.100:6666`. Each 1048-byte UDP payload contains a 24-byte P2V5 header and 1024 bytes of PRBS data. The diagnostic image used a 3000-UI-cycle interpacket interval, yielding approximately 199.7 Mb/s of data throughput.

Writes become committed only after a successful AXI B response. A DDR ring slot is released after a complete 1024-byte read reaches the TX FIFO. A full ring stops authorization of new source data. The PRBS source is a test stimulus; the later XADC integration is documented separately.

[V5 project](../v1_v5/project2_v5_ring_buffer/README.md)

The BIT, LTX, and EXE hashes for this run match the corresponding simulation evidence. Implementation reported WNS +0.982 ns, WHS +0.057 ns, TNS/THS 0, 11,424 LUTs, 15,121 registers, and 23 BRAM tiles. The earlier README value of 11,419 LUTs was corrected against the implementation report. Asynchronous-clock exceptions are reviewed alongside, not in place of, the CDC structure.

## Failure observed and diagnostic conclusion

The UDP ready handshake defect between packets and the IPv4 checksum second end-around-carry defect had already been found and repaired. The build also required a correction to when clock constraints were applied. In the earlier checksum-defective image, IP IDs `0x72FA` and `0x72FB` failed once per 16-bit ID cycle, producing a characteristic two-packet gap about every 2.69 seconds.

The latest JSON at this checkpoint recorded 60.0001563 seconds, 1,462,700 received packets, 1,497,804,800 data bytes, and 199.70678643 Mb/s. It reported 345 missing packets in two gaps:

- Sequences 11400–11733: 334 packets; the next received sequence was 11734.
- Sequences 397018–397028: 11 packets; the next received sequence was 397029.

The first packet sequence was zero. Duplicate, out-of-order, format, metadata, PRBS, and RIO completion errors were all zero. The old periodic checksum symptom was absent, but the cause of these two remaining gaps was still unknown. Accordingly, this 199.7 Mb/s run was recorded as a failure, not as zero-loss throughput.

Four screenshots were saved in the original project as `evidence/v5_checksum_fixed_failure_01.png` through `_04.png`, alongside updated V5 development and version records. This directory retains a copy of the latest JSON.

## Diagnostic and acceptance sequence

1. Hold BIT/LTX, rate, and RIO v6 fixed. Capture NIC ingress and the application JSON during the same board run, then compare exact packet sequence numbers. See [next_capture_steps.md](next_capture_steps.md).
2. If NIC ingress has a valid packet that the application lacks, investigate the Windows/filter-driver/socket/RIO path. If neither has it, first exclude capture loss, then investigate the FPGA MAC output, MAC FIFO overflow/underflow, PHY, and USB path.
3. Review of `mac_send.v` identified internal states including `data_wrfull` and `frame_wrfull`. The four current ADMA FIFO error probes do not cover these MAC-side FIFOs. If ingress also misses packets, a diagnostic image should add MAC counters and sticky error indicators with ILA observation.
4. Following repair and validation, increase test duration from 60 seconds to 30 minutes and then several hours; subsequently sweep throughput. Complete the acquisition integration and final resource/timing report.
5. Report durations, data volumes, rates, and zero-error claims only where supported by the corresponding passing evidence.

This process could not access the capture driver at the time: `pktmon status` returned Access Denied. No new packet capture or board run had been started. The next run required administrator PowerShell and board RESET/KEY0 operation.

## Later update: the ninth run passed

The current 200 Mb/s image subsequently received 1,463,042 packets and 1,498,155,008 bytes in 60 seconds at 199.753956455 Mb/s, with every error counter at zero. Details are in [the zero-loss and speed-up record](V5_ZERO_LOSS_AND_RATE_SCALING.md) and [the work log](Project2_work_log.md). “No passing board run yet” above describes the earlier eighth-run checkpoint; long-duration validation was still pending. A separate approximately 315 Mb/s candidate was then built with passing simulation and timing checks. Its files and board-test steps are in the [315M record](project2_v5_315m/README.md); the original 200 Mb/s image was preserved.
