# Project 2 V8 Board-Validation Procedure

## Scope

V8 acquires four internal XADC monitoring channels—temperature, VCCINT, VCCAUX, and VCCBRAM—and transports their records through the common ingress FIFO, DDR3 ring buffer, UDP link, and PC receiver. The board sequence checks initial DDR3/UART/XADC status, regresses the source-0 PRBS path, verifies live source-1 acquisition, checks exact finite-run accounting, and ends with a 300-second XADC run.

## Fixed setup and operating sequence

FPGA `192.168.1.11`; PC `192.168.1.100`; UDP port `6666`; UART `COM4` at 115200 8N1 without flow control. Use the matching [BIT](project2_v8_top.bit) and [LTX](project2_v8_top.ltx), `v8_uart_control.py`, and `udp_v8_monitor_rio.exe`. Replace COM4 consistently if the serial port changes. From the project archive root, enter the board-test package:

```powershell
Set-Location .\versions\v7_v9\project2_v8_xadc_acquisition\board_test_package
New-Item -ItemType Directory -Force .\results | Out-Null
```

Use two PowerShell windows in that directory. Window A issues UART configuration/START/STOP/status; window B runs the UDP receiver. Start B, wait for `ARMED: listening on 192.168.1.100:6666`, then send START from A while B remains running. ARMED means the receiver is waiting for data.

Source 1 produces 1,000 16-bit XADC records/s across the four channels, approximately 2,000 bytes/s. DDR starts draining at 65,536 bytes, so the first UDP output batch may take about 32.8 seconds to accumulate. Source-1 commands therefore use `--first-timeout 90`; `--duration` starts on the first received packet. Packets arrive in DDR-drain batches. The `rate` UART setting applies to source 0; a retained `rate_words_per_sec` status value does not describe XADC's fixed acquisition rate.

## Common acceptance and failure handling

The receiver must print:

```text
V8 ACQUISITION STREAM TEST PASSED
```

JSON must show `passed=true`, at least one packet, and zero missing/gap/max-gap, duplicate/out-of-order, malformed/metadata, data-error, source-mismatch, and receive-completion counts. Source 0 must identify `deterministic_prbs16` and have zero PRBS errors. Source 1 must identify `internal_xadc`, contain XADC records, have zero invalid-record and channel-order errors, and balanced per-channel counts (at most one difference at a continuous-run boundary). All four raw min/max values must lie in the 0–4095 12-bit range, with nonzero supply channels. Stable readings over a short interval are acceptable if format, order, count, values, and continuity are correct.

Wait 500 ms after each run and read FPGA status. Require V8, stopped state, MIG calibrated, no fatal error, empty ingress and DDR, zero ingress/ring overflow/underflow and TX overflow, zero UART CRC errors and command rejects, `xadc_valid_mask=0xF`, `xadc_drop_count=0`, and plausible 12-bit raw readings. Source 0 at maximum rate requires `tx_underflow=0`. Sparse source-1 batches can increment `tx_underflow` while the packetizer waits for another complete batch; record this idle diagnostic only when host continuity/data checks pass, no partial packet or occupancy remains, and XADC drops are zero. The finite-count gate still expects `tx_underflow=0`. Temperature and voltage conversion formulas are in [the V8 protocol](PROTOCOL_V8.md).

On FAIL, timeout, abnormal counters, or implausible readings, preserve the state before retesting: STOP once in A, wait 500 ms, read status, and save both full-window screenshots and that run's JSON. Do not reset, reprogram, or overwrite previous output while diagnosing.

## Gate 0: Program and inspect initial status

Program the matching BIT/LTX in Vivado Hardware Manager, wait approximately three seconds for DDR3 calibration, then run:

```powershell
py -3 .\v8_uart_control.py --port COM4 --seq 1 status
```

Require `result: OK`, `version: 8`, `run_enable: False`, `mig_calibrated: True`, `fatal: False`, source 0 / `deterministic_prbs16`, `xadc_valid_mask: 0xF`, `xadc_drop_count: 0`, visible XADC raw/converted values, and zero path/UART errors. If the mask is not yet `0xF`, wait one second and read status once more; stop and capture a screenshot if it remains incomplete.

## Gate 1: 10-second high-rate source-0 regression

Configure in A, start B, then START in A after ARMED:

```powershell
py -3 .\v8_uart_control.py --port COM4 --seq 2 stop
Start-Sleep -Milliseconds 500
py -3 .\v8_uart_control.py --port COM4 --seq 3 clear
py -3 .\v8_uart_control.py --port COM4 --seq 4 source 0
py -3 .\v8_uart_control.py --port COM4 --seq 5 rate 25000000
py -3 .\v8_uart_control.py --port COM4 --seq 6 packet-length 1024
py -3 .\v8_uart_control.py --port COM4 --seq 7 mode continuous
```

```powershell
.\udp_v8_monitor_rio.exe --duration 10 --first-timeout 60 --output .\results\v8_gate1_source0_1024B_25M_10s.json
```

```powershell
py -3 .\v8_uart_control.py --port COM4 --seq 8 start
```

Once B reports PASS, stop and inspect status:

```powershell
py -3 .\v8_uart_control.py --port COM4 --seq 9 stop
Start-Sleep -Milliseconds 500
py -3 .\v8_uart_control.py --port COM4 --seq 10 status
```

Require the common conditions, `udp_payload_bytes=1024`, source 0, and zero PRBS errors. The expected throughput is near the approximately 399 Mb/s V7 configuration. Preserve evidence for an unexpectedly low rate rather than changing parameters mid-run.

## Gate 2: 60-second continuous live XADC

Configure source 1 and inspect its status in A:

```powershell
py -3 .\v8_uart_control.py --port COM4 --seq 11 clear
py -3 .\v8_uart_control.py --port COM4 --seq 12 source 1
py -3 .\v8_uart_control.py --port COM4 --seq 13 packet-length 1024
py -3 .\v8_uart_control.py --port COM4 --seq 14 mode continuous
py -3 .\v8_uart_control.py --port COM4 --seq 15 status
```

All five commands must return OK; status must show source 1 / `internal_xadc`, mask `0xF`, and zero drops. Start B, then START after ARMED:

```powershell
.\udp_v8_monitor_rio.exe --duration 60 --first-timeout 90 --output .\results\v8_gate2_xadc_1024B_60s.json
```

```powershell
py -3 .\v8_uart_control.py --port COM4 --seq 16 start
```

Allow approximately 33 seconds for the initial batch. After B finishes and passes, stop and inspect status:

```powershell
py -3 .\v8_uart_control.py --port COM4 --seq 17 stop
Start-Sleep -Milliseconds 500
py -3 .\v8_uart_control.py --port COM4 --seq 18 status
```

Apply all source-1 acceptance conditions. Average data throughput is approximately 0.016 Mb/s; instantaneous readouts fluctuate because DDR emits batches.

## Gate 3: Finite XADC run with exact counts

Request 32,768 live XADC records, exactly 65,536 bytes, 64 UDP packets at 1024 data bytes each, and 8,192 records per channel. Configure A, arm B, then START:

```powershell
py -3 .\v8_uart_control.py --port COM4 --seq 20 clear
py -3 .\v8_uart_control.py --port COM4 --seq 21 source 1
py -3 .\v8_uart_control.py --port COM4 --seq 22 packet-length 1024
py -3 .\v8_uart_control.py --port COM4 --seq 23 mode finite 32768
```

```powershell
.\udp_v8_monitor_rio.exe --duration 5 --first-timeout 90 --output .\results\v8_gate3_xadc_finite_32768.json
```

```powershell
py -3 .\v8_uart_control.py --port COM4 --seq 24 start
```

Finite mode drops run enable automatically; do **not** send STOP for this gate. After B completes, read status:

```powershell
Start-Sleep -Milliseconds 500
py -3 .\v8_uart_control.py --port COM4 --seq 25 status
```

Besides the common checks, require exactly `packets_received=64`, `payload_bytes=65536`, `xadc_records=32768`, and `xadc_records_by_channel=[8192,8192,8192,8192]`. Status must show `finite_done=True`, `finite_mode=True`, `finite_words=run_words=32768`, and `packet_sequence=64`. A generic receiver PASS does not override a count mismatch.

## Gate 4: 300-second live XADC run

Proceed only after Gates 1–3 pass. Restore continuous source 1 and clear counters in A, arm B, then START:

```powershell
py -3 .\v8_uart_control.py --port COM4 --seq 30 source 1
py -3 .\v8_uart_control.py --port COM4 --seq 31 packet-length 1024
py -3 .\v8_uart_control.py --port COM4 --seq 32 mode continuous
py -3 .\v8_uart_control.py --port COM4 --seq 33 clear
```

```powershell
.\udp_v8_monitor_rio.exe --duration 300 --first-timeout 90 --output .\results\v8_gate4_xadc_1024B_300s.json
```

```powershell
py -3 .\v8_uart_control.py --port COM4 --seq 34 start
```

Do not reset the FPGA, switch networks, or send other UART commands during the run. After B reports PASS, stop and inspect status:

```powershell
py -3 .\v8_uart_control.py --port COM4 --seq 35 stop
Start-Sleep -Milliseconds 500
py -3 .\v8_uart_control.py --port COM4 --seq 36 status
```

Require approximately 300 seconds of valid source-1 data, balanced channel counts, empty ingress and DDR after STOP, and zero FPGA path, XADC-drop, UART CRC, and command-reject errors.

## Recorded results and evidence

| Gate | Configuration | Result | Status |
| --- | --- | --- | --- |
| 0 | Initial V8 status | DDR calibrated, XADC mask `0xF` | Passed, Sep 22 |
| 1 | Source 0, 1024 B, 25 Mword/s, 10 s | 487,592 packets, 399.422 Mb/s, zero errors | Passed, Sep 22 |
| 2 | Source 1, continuous, 60 s | 73,728 real XADC records, 18,432/channel | Passed, Sep 22 |
| 3 | Source 1, finite 32,768 | Exactly 64 packets, 8,192/channel | Passed, Sep 22 |
| 4 | Source 1, continuous, 300 s | 319,488 records, 79,872/channel, zero host-data errors | Passed, Sep 22 |

All five gates passed. The source-1 continuous status snapshots recorded `tx_underflow=6` after 60 seconds and `13` after 300 seconds. These correspond to idle intervals between slow, high-watermark DDR batches: both receiver runs had zero loss, reordering, format/data/channel-order errors; ingress and DDR drained; `xadc_drop_count=0`; and the exact finite gate completed with `tx_underflow=0`. They were retained as expected idle diagnostics, not grounds for retest.

Keep the four original JSON files:
[Gate 1](evidence/board_20260922/v8_gate1_source0_1024B_25M_10s.json),
[Gate 2](evidence/board_20260922/v8_gate2_xadc_1024B_60s.json),
[Gate 3](evidence/board_20260922/v8_gate3_xadc_finite_32768.json), and
[Gate 4](evidence/board_20260922/v8_gate4_xadc_1024B_300s.json).
For each gate, retain B's FINAL/PASS and A's configuration, START, STOP, and final status with commands and output visible. The 22 unique screenshots and JSON files are archived under `evidence/board_20260922/`; a repeated reference to one 300-second FINAL screenshot was deduplicated. Per-file hashes and quantitative checks are in the [V8 board evidence record](evidence/V8_BOARD_VALIDATION_EVIDENCE_20260922.md).

V6 ILA and V7 UART/UDP already have separate board evidence. V8's passing run does not repeat those ILA captures. For an unresolved failure, preserve its UART/JSON evidence first, then use the matching [V8 LTX](project2_v8_top.ltx) to localize ingress, DDR, or TX behavior.
