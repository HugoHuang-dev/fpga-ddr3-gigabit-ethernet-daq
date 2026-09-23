# Project 2 V5 — Approximately 400 Mb/s Validation

This image derives from the stable 315 Mb/s version, which passed three consecutive 60-second runs and a 300-second run. Its only functional change is `POST_READY_IDLE_CYCLES` from 1500 to 950. The 315 Mb/s packet period suggested roughly 399.4 Mb/s of payload throughput; the board JSON gives the final measured rate.

The purpose was to find the highest strict zero-loss speed for this FPGA, link, NIC, and controlled Windows host combination. The 315 Mb/s result is not counted as a result for this image.

## Initial test gate

1. Program the FPGA using this directory's matched BIT/LTX.
2. Press RESET once, wait at least five seconds, and do not press KEY0.
3. Keep Windows in high-performance mode, close WeChat, music playback, downloads, cloud synchronization, and other unnecessary applications, and stop PktMon.
4. Start the matched no-capture RIO test. Press KEY0 once after `ARMED` appears.
5. Run 60 seconds first. Strict PASS requires every error field to be zero.
6. On success, repeat the 60-second run. On failure, retain the result and narrow the boundary between 315 and 400 Mb/s.

## Build parameters

| Parameter | Value |
| --- | --- |
| FPGA | XC7A35TFGG484-2 |
| `POST_READY_IDLE_CYCLES` | 950 |
| Expected payload rate | about 399.4 Mb/s |
| Payload per packet | 1,024 bytes |
| UDP receive port | 6666 |
| FPGA / PC IP | 192.168.1.11 / 192.168.1.100 |

## Board and ILA results

The image passed a strict 60.0001324-second host test: **2,925,356 packets**, **2,995,564,544 payload bytes**, and **399.407724507 Mb/s** measured. Missing, out-of-order, duplicate, malformed, metadata, PRBS, and RIO-completion errors were all zero.

Four final ILA groups also passed:

1. After a successful AXI write response, write pointer, committed bytes, and occupancy increased together by 1,024 bytes.
2. After a complete read burst entered the transmit FIFO, read pointer and released bytes increased together by 1,024 bytes while occupancy fell by 1,024 bytes.
3. The 256 KiB ring write pointer wrapped correctly from `0x0003FC00` to `0x00000000`.
4. MIG calibration and ring control remained active under continuous operation. `fatal_error` and all four ADMA FIFO error flags remained zero. Write-stall count rose when the ring filled, demonstrating backpressure protection of unreleased data.

Screenshots are retained in the parent `evidence` directory from `ila_400m_01_write_commit_a.png` through `ila_400m_04_stable_state_b.png`. Board-level functional validation of this 400 Mb/s image is complete.
