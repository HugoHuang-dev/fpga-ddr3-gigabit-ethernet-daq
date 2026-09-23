# Project 2 V7 Board-Validation Procedure

## Objectives

V7 adds a UART control plane while retaining the V6 DDR3 ring buffer and UDP data path. The board sequence covers initial status and configuration; START/STOP at 512-byte packets and 25 Mword/s; dynamic 256/512/1024-byte packet lengths; SET_RATE; finite-run auto-stop; rejection of invalid source/configuration/CRC; and 60- and 300-second full-rate runs. Completion requires consistent command replies, final FPGA status, host packet-by-packet validation, and error counters.

## Setup and two-window sequence

FPGA `192.168.1.11`; PC `192.168.1.100`; UDP port `6666`; UART `COM4`, 115200 8N1 without flow control; source 0 (PRBS16). Use the matching [BIT](project2_v7_top.bit) and [LTX](project2_v7_top.ltx), `v7_uart_control.py`, and `udp_v7_monitor_rio.exe`. If Windows changes the serial port, substitute the new port for COM4 in each command. From the project archive root, prepare the board-test directory:

```powershell
Set-Location .\versions\v7_v9\project2_v7_uart_control\board_test_package
New-Item -ItemType Directory -Force .\results | Out-Null
```

Keep two PowerShell windows in that directory. Window A sends UART `status`, configuration, `start`, and `stop`; window B runs only the UDP receiver. For each data test, start B, wait for `ARMED: listening on 192.168.1.100:6666`, then switch to A and issue START. ARMED means the receiver is waiting for the first packet; B remains occupied during the run.

## Common pass and failure rules

The receiver must report:

```text
V7 UART-CONTROLLED STREAM TEST PASSED
```

Its JSON must have `passed=true`, `packets_received>0`, and zero missing/gap, duplicate, out-of-order, malformed, metadata, data-error, and receive-completion fields. After STOP and drain, UART status must show `run_enable=False`, `fatal=False`, zero ingress and DDR occupancy, and zero ingress/ring/TX overflow and underflow counters.

For intentionally rate-limited tests below the approximately 400 Mb/s sender capacity, `tx_underflow` may count idle periods while the packetizer waits for a complete packet. This is accepted only when host sequence, format, and PRBS checks pass and other internal errors are zero. Clear counters after restoring maximum rate; final tests require `tx_underflow=0`.

On any FAIL, timeout, nonzero counter, or abnormal state, do not immediately rerun, reprogram, reset, power-cycle, or change several settings. Issue STOP, wait 500 ms, read status, and preserve both full-window screenshots and the run's JSON. Record the first anomaly, then vary one factor at a time. Use a unique JSON name for every gate.

## Gate 0: Programming and baseline status

If the board has neither reset nor been reprogrammed since the passing baseline check, proceed directly to Gate 1. Otherwise, program the matching BIT/LTX in Hardware Manager, wait roughly three seconds for DDR3 calibration, then read status:

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 1 status
```

Require `result: OK`, `version: 7`, `run_enable: False`, `mig_calibrated: True`, `fatal: False`, `source: 0`, and zero error counters. After a fresh download/reset, establish the Gate 1 configuration:

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 2 clear
py -3 .\v7_uart_control.py --port COM4 --seq 3 source 0
py -3 .\v7_uart_control.py --port COM4 --seq 4 rate 25000000
py -3 .\v7_uart_control.py --port COM4 --seq 5 packet-length 512
py -3 .\v7_uart_control.py --port COM4 --seq 6 mode continuous
```

All five commands must return `RESULT=OK`. The board record confirms that initial READ_STATUS, CLEAR_COUNTERS, source 0, rate 25,000,000, 512-byte packets, and continuous mode all succeeded. An earlier first-packet timeout occurred because START was not sent from a second window while the receiver occupied the only window; it was not a data-path failure.

## Gate 1: 512 bytes, 25 Mword/s, continuous, 60 seconds

25 million 16-bit words/s corresponds to about 400 Mb/s of payload. Run in B, then START in A after ARMED:

```powershell
.\udp_v7_monitor_rio.exe --duration 60 --first-timeout 60 --output .\results\v7_gate1_512B_25M_60s.json
```

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 7 start
```

Require `TYPE=0x83 SEQ=7 RESULT=OK`. After the receiver completes its 60-second run:

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 8 stop
Start-Sleep -Milliseconds 500
py -3 .\v7_uart_control.py --port COM4 --seq 9 status
```

STOP must return `TYPE=0x84 SEQ=8 RESULT=OK`. Apply the common pass criteria and preserve the windows plus [Gate 1 JSON](board_test_package/results/v7_gate1_512B_25M_60s.json).

## Gate 2: Dynamic 256- and 1024-byte packets

Gate 1 covered 512 bytes. Leave rate at 25 Mword/s and continuous mode, changing only packet length. After the previous run has stopped and drained, configure 256-byte packets in A, run B, start in A after ARMED, then stop and inspect status:

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 10 clear
py -3 .\v7_uart_control.py --port COM4 --seq 11 packet-length 256
py -3 .\v7_uart_control.py --port COM4 --seq 12 rate 25000000
py -3 .\v7_uart_control.py --port COM4 --seq 13 mode continuous
```

```powershell
.\udp_v7_monitor_rio.exe --duration 10 --first-timeout 60 --output .\results\v7_gate2_256B_25M_10s.json
```

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 14 start
```

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 15 stop
Start-Sleep -Milliseconds 500
py -3 .\v7_uart_control.py --port COM4 --seq 16 status
```

All configuration replies must be OK. In addition to the common pass criteria, JSON must report `udp_payload_bytes=256`.

For 1024 bytes, repeat with the following commands and require `udp_payload_bytes=1024`:

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 17 clear
py -3 .\v7_uart_control.py --port COM4 --seq 18 packet-length 1024
py -3 .\v7_uart_control.py --port COM4 --seq 19 rate 25000000
py -3 .\v7_uart_control.py --port COM4 --seq 20 mode continuous
```

```powershell
.\udp_v7_monitor_rio.exe --duration 10 --first-timeout 60 --output .\results\v7_gate2_1024B_25M_10s.json
```

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 21 start
```

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 22 stop
Start-Sleep -Milliseconds 500
py -3 .\v7_uart_control.py --port COM4 --seq 23 status
```

## Gate 3: SET_RATE at approximately 200 Mb/s

Keep 1024-byte packets and set 12,500,000 16-bit words/s. In A configure, in B arm the receiver, then START in A and STOP/status after completion:

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 24 clear
py -3 .\v7_uart_control.py --port COM4 --seq 25 packet-length 1024
py -3 .\v7_uart_control.py --port COM4 --seq 26 rate 12500000
py -3 .\v7_uart_control.py --port COM4 --seq 27 mode continuous
```

```powershell
.\udp_v7_monitor_rio.exe --duration 10 --first-timeout 60 --output .\results\v7_gate3_1024B_12M5_10s.json
```

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 28 start
```

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 29 stop
Start-Sleep -Milliseconds 500
py -3 .\v7_uart_control.py --port COM4 --seq 30 status
```

Require `rate_words_per_sec: 12500000`, `udp_payload_bytes=1024`, the common host checks, and no internal errors other than the rate-limiting `tx_underflow` described above. An observed `payload_rate_mbps` near 200 (suggested 195–205) is expected. Preserve small deviations for analysis before changing timing parameters.

## Gate 4: Finite run with exact accounting

Configure 256-byte packets, `rate 0` (maximum), and 1,048,576 finite 16-bit words. This is 2,097,152 payload bytes or exactly 8,192 packets. Configure A, arm B, START after ARMED, and **do not send STOP** when the finite source completes automatically:

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 31 clear
py -3 .\v7_uart_control.py --port COM4 --seq 32 packet-length 256
py -3 .\v7_uart_control.py --port COM4 --seq 33 rate 0
py -3 .\v7_uart_control.py --port COM4 --seq 34 mode finite 1048576
```

```powershell
.\udp_v7_monitor_rio.exe --duration 10 --first-timeout 60 --output .\results\v7_gate4_finite_1Mwords_256B.json
```

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 35 start
```

After the receiver exits, wait 500 ms and read status:

```powershell
Start-Sleep -Milliseconds 500
py -3 .\v7_uart_control.py --port COM4 --seq 36 status
```

Require the common host checks plus exactly `packets_received=8192`, `payload_bytes=2097152`, and `udp_payload_bytes=256`. Status must show `run_enable=False`, `finite_done=True`, `finite_mode=True`, `finite_words=run_words=1048576`, `packet_sequence=8192`, zero ingress/DDR occupancy, and zero data-path errors. A generic receiver PASS without exact counts does not pass this gate.

## Gate 5: Command protection and diagnostic counters

Do not run the UDP receiver for this gate. After preserving finite-run results, clear counters and request unsupported source 1:

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 40 clear
py -3 .\v7_uart_control.py --port COM4 --seq 41 source 1
```

The expected reply is:

```text
TYPE=0x90 SEQ=41 RESULT=UNSUPPORTED
```

The source selection must remain zero. Next, start a slow continuous run and attempt to change packet length while running:

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 42 rate 1000
py -3 .\v7_uart_control.py --port COM4 --seq 43 mode continuous
py -3 .\v7_uart_control.py --port COM4 --seq 44 start
py -3 .\v7_uart_control.py --port COM4 --seq 45 packet-length 256
```

The first three replies must be OK; the final reply must be:

```text
TYPE=0x92 SEQ=45 RESULT=BUSY
```

Stop and allow the pipeline to drain:

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 46 stop
Start-Sleep -Milliseconds 500
```

Send a bad-CRC status request and require no reply:

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 47 --corrupt-crc --expect-no-reply status
```

The utility must print `PASS: no reply received, as expected`. Read valid status:

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 48 status
```

Require `run_enable=False`, `source=0`, `uart_crc_errors=1`, `command_rejects=2`, and `fatal=False`. The rejects come from unsupported source 1 and the in-run packet-length change; bad CRC increments only the UART CRC counter. At 1000 words/s, sparse packets may produce the rate-limiting `tx_underflow`; other data-path errors must be zero. Restore the final configuration:

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 49 source 0
py -3 .\v7_uart_control.py --port COM4 --seq 50 rate 0
py -3 .\v7_uart_control.py --port COM4 --seq 51 packet-length 1024
py -3 .\v7_uart_control.py --port COM4 --seq 52 mode continuous
py -3 .\v7_uart_control.py --port COM4 --seq 53 clear
```

All replies must be OK. Save full-window command and reply screenshots.

## Gate 6: Full-rate 1024-byte screening run, 60 seconds

Gate 5 restored source 0, rate 0, 1024-byte packets, continuous mode, and cleared counters. Arm B, START in A, then STOP/status:

```powershell
.\udp_v7_monitor_rio.exe --duration 60 --first-timeout 60 --output .\results\v7_gate6_1024B_max_60s.json
```

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 54 start
```

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 55 stop
Start-Sleep -Milliseconds 500
py -3 .\v7_uart_control.py --port COM4 --seq 56 status
```

Require the common strict pass criteria and `udp_payload_bytes=1024`. Rate 0 requests the fastest source production compatible with backpressure; the decisive evidence is continuous sequence, correct PRBS, and zero errors.

## Gate 7: Full-rate 1024-byte final run, 300 seconds

Proceed only after Gate 6 passes. Reconfirm and clear the configuration in A, arm B, START after ARMED, and allow the uninterrupted five-minute run:

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 60 source 0
py -3 .\v7_uart_control.py --port COM4 --seq 61 rate 0
py -3 .\v7_uart_control.py --port COM4 --seq 62 packet-length 1024
py -3 .\v7_uart_control.py --port COM4 --seq 63 mode continuous
py -3 .\v7_uart_control.py --port COM4 --seq 64 clear
```

```powershell
.\udp_v7_monitor_rio.exe --duration 300 --first-timeout 60 --output .\results\v7_gate7_1024B_max_300s.json
```

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 65 start
```

Do not switch networks, launch other heavy traffic, reset the FPGA, or send other UART commands during the run. After B completes:

```powershell
py -3 .\v7_uart_control.py --port COM4 --seq 66 stop
Start-Sleep -Milliseconds 500
py -3 .\v7_uart_control.py --port COM4 --seq 67 status
```

Require receiver PASS; roughly 300 seconds of JSON with all error fields zero; 1024-byte payloads; empty FIFOs and DDR after STOP; zero FPGA overflow/underflow; `fatal=False`, `uart_crc_errors=0`, and `command_rejects=0`.

## Acceptance and evidence

| Gate | Configuration | Principal check | Recorded status |
| --- | --- | --- | --- |
| 0 | Initial UART status and configuration | Calibration and OK replies | Passed; archived |
| 1 | 512 B, 25 Mword/s, 60 s | START/STOP and strict zero-error data | Passed; archived |
| 2A/2B | 256/1024 B, 25 Mword/s, 10 s each | Dynamic packetization and PRBS continuity | Passed; archived |
| 3 | 1024 B, 12.5 Mword/s, 10 s | Approx. 200 Mb/s rate control | Passed; archived |
| 4 | 256 B, finite 1,048,576 words | 8,192 packets and exact auto-stop accounting | Passed; archived |
| 5 | Unsupported source, BUSY, bad CRC | Reply codes and counters | Passed; archived |
| 6 | 1024 B, max rate, 60 s | Strict zero-error screening | Passed; archived |
| 7 | 1024 B, max rate, 300 s | Final stability check | Passed; archived |

Retain all seven JSON files under `results`:
[Gate 1](board_test_package/results/v7_gate1_512B_25M_60s.json),
[Gate 2A](board_test_package/results/v7_gate2_256B_25M_10s.json),
[Gate 2B](board_test_package/results/v7_gate2_1024B_25M_10s.json),
[Gate 3](board_test_package/results/v7_gate3_1024B_12M5_10s.json),
[Gate 4](board_test_package/results/v7_gate4_finite_1Mwords_256B.json),
[Gate 6](board_test_package/results/v7_gate6_1024B_max_60s.json), and
[Gate 7](board_test_package/results/v7_gate7_1024B_max_300s.json).
For each data gate, retain B's FINAL and PASS/FAIL and A's STOP and final status. For Gate 5, retain complete UNSUPPORTED, BUSY, bad-CRC no-reply, and final-counter screenshots with commands visible.

V6 already closed its data-path ILA evidence. Successful V7 validation rests on UART commands/replies, READ_STATUS, JSON, and screenshots; the V6 four-group ILA set is not repeated. If a data gate fails and these records cannot distinguish ingress, DDR ring, or TX faults, investigate with the matching [V7 LTX](project2_v7_top.ltx) after preserving the failed evidence.
