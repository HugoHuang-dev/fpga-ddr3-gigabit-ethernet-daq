# Project 2 V9 Board-Validation Procedure

## 1. Fixed conditions

- FPGA: `192.168.1.11`; PC: `192.168.1.100`
- UDP: FPGA port `8888` → PC port `6666`
- UART: 115200 8N1, currently `COM14`; substitute the new port throughout if Windows renumbers it
- UDP data payload: 1024 bytes, preceded by a separate 32-byte P2V9 header
- Source 0: PRBS16 at 25,000,000 words/s
- Source 1: four on-board XADC channels, 1,000 records/s in aggregate

Confirm power, JTAG visibility in Vivado Hardware Manager, the serial port, and connectivity to `192.168.1.11`. Run all commands from `board_test_package`. Keep two PowerShell windows: A for UART control, B for the Windows RIO receiver. In every run, wait for **ARMED** in B before issuing CLEAR_COUNTERS and START in A. The first packet and sample indices should then both be zero. This procedure uses fresh UART request sequences 100–134.

`--first-timeout` begins when the receiver reports ARMED, not when START is sent. Allow time for manual window switching. Source 1 may also need roughly 33 seconds to accumulate its first 64 KiB DDR output batch. The earlier [Gate 1 JSON](board_test_package/results/v9_gate1_prbs_1024B_25M_60s.json) records a **zero-packet timeout before START**; retain it as a failed attempt, not acceptance evidence. The retest uses `*_manual.json` and `gate1_manual`.

## 2. Program and check initial status

The previous check had already programmed the V9 BIT/LTX over JTAG and identified all three ILAs. The board was stopped with source 0, 25,000,000 words/s, 1024-byte packets, `ring_started=True`, and zero ingress/DDR occupancy. A monitor timeout before START left historical `run_words` and `packet_sequence` values; do not use those as initial-state evidence.

After power cycling or reprogramming, use the matching [BIT](project2_v9_top.bit) and [LTX](project2_v9_top.ltx), then allow about three seconds for DDR3 calibration. In either case, read status:

```powershell
py -3 .\v9_uart_control.py --port COM14 --seq 100 status
```

Require `version: 9`, `mig_calibrated: True`, `fatal: False`, `xadc_valid_mask: 0xF`, and `xadc_drop_count: 0`. The network check received ICMP replies, although Windows ping sometimes reported `MISCOMPARE at offset 0`. UDP acceptance is determined by the receiver's byte-by-byte validation and JSON results.

## 3. Offline PC self-test

```powershell
.\udp_v9_monitor_rio.exe --self-test
```

All ten checks must pass: normal PRBS and XADC streams, plus injected packet-sequence, sample-index, payload, header, XADC format/order, and nonzero-origin faults.

## 4. Gate 1: 60-second source-0 regression

Configure in window A without starting:

```powershell
py -3 .\v9_uart_control.py --port COM14 --seq 101 stop
Start-Sleep -Milliseconds 500
py -3 .\v9_uart_control.py --port COM14 --seq 102 source 0
py -3 .\v9_uart_control.py --port COM14 --seq 103 rate 25000000
py -3 .\v9_uart_control.py --port COM14 --seq 104 packet-length 1024
py -3 .\v9_uart_control.py --port COM14 --seq 105 mode continuous
```

Start the receiver in B:

```powershell
.\udp_v9_monitor_rio.exe --duration 60 --first-timeout 180 `
  --output .\results\v9_gate1_prbs_1024B_25M_60s_manual.json `
  --sample-dir .\samples\gate1_manual --sample-interval 10 `
  --sample-bytes 256 --max-fragments 8
```

After **ARMED**, issue in A:

```powershell
py -3 .\v9_uart_control.py --port COM14 --seq 106 clear
py -3 .\v9_uart_control.py --port COM14 --seq 107 start
```

The receiver must print `V9 FULL VALIDATION STREAM TEST PASSED`, with approximately 385–405 Mb/s average payload rate and zero origin, sequence, sample-index, metadata, payload, and receive errors. Stop, wait 500 ms, and check status. Source 0 requires `tx_underflow: 0`.

```powershell
py -3 .\v9_uart_control.py --port COM14 --seq 108 stop
Start-Sleep -Milliseconds 500
py -3 .\v9_uart_control.py --port COM14 --seq 109 status
```

## 5. Gate 2: finite source-1 run of 32,768 records

Configure in A:

```powershell
py -3 .\v9_uart_control.py --port COM14 --seq 110 stop
Start-Sleep -Milliseconds 500
py -3 .\v9_uart_control.py --port COM14 --seq 111 source 1
py -3 .\v9_uart_control.py --port COM14 --seq 112 packet-length 1024
py -3 .\v9_uart_control.py --port COM14 --seq 113 mode finite 32768
```

Start B:

```powershell
.\udp_v9_monitor_rio.exe --duration 5 --first-timeout 240 `
  --output .\results\v9_gate2_xadc_finite_32768.json `
  --sample-dir .\samples\gate2 --sample-interval 1 `
  --sample-bytes 256 --max-fragments 4
```

After **ARMED**:

```powershell
py -3 .\v9_uart_control.py --port COM14 --seq 114 clear
py -3 .\v9_uart_control.py --port COM14 --seq 115 start
```

Require exactly 64 packets, 65,536 payload bytes, 32,768 XADC records, and 8,192 records per channel. Both first indices and every error counter must be zero. Final status must show `finite_done: True`, `run_words: 32768`, `packet_sequence: 64`, and zero occupancy.

```powershell
py -3 .\v9_uart_control.py --port COM14 --seq 116 status
py -3 .\v9_uart_control.py --port COM14 --seq 117 stop
```

## 6. Gate 4: arm the ILAs before Gate 3

After Gate 2 has stopped, configure the ILAs **before** starting the 300-second Gate 3. The ILAs retain only a short window around each trigger; arming after Gate 3 stops cannot recover the events. Create `board_test_package\results\ila` and use a distinct filename for each capture.

1. In Vivado 2018.3, open Hardware Manager, auto-connect to `xc7a35t_0`, and use the matching [LTX](project2_v9_top.ltx) if requested. Identify `u_ila_acq`, `u_ila_ui`, and `u_ila_rx` by their **Cell Name** properties. Do not rely on the order of `hw_ila_1/2/3`.
2. In each Basic Trigger Setup, drag in only the trigger probes below, select `==`, and enter the value. Use the generated 1024-sample capture window and approximately 50% trigger position. Disable **Auto Re-Trigger** so later events do not replace unsaved data.

   | Core / clock | Initial trigger | Signals to inspect in waveform |
   | --- | --- | --- |
   | `u_ila_acq` / `clk_125m` | `probe1 control_source_select == 1` **AND** `probe2 source_valid == 1` **AND** `probe3 source_ready == 1` | `probe4 source_data`, `probe5 ingress_level_words`, `probe15 xadc_valid_mask`, `probe16 xadc_drop_count` |
   | `u_ila_ui` / MIG `ui_clk` | `probe34 tx_burst_committed == 1` | `probe5/6` ring pointers, `probe7 occupancy_bytes`, `probe8/9` committed/released bytes, `probe22 fatal_error` |
   | `u_ila_rx` / `phy_rx_clk` | `probe0 gmii_rx_data_vld == 1` | `probe1 gmii_rx_data_error`, `probe2 gmii_rx_data` |

   Confirm that the three acquisition conditions use global **AND**. Other probes belong in the Waveform display, not Trigger Setup. The UI core must later be rearmed separately on `probe15 packet_done == 1`; do not require probes 34 and 15 to be high together.
3. Click **Run Trigger**, not Immediate, for all three cores before issuing Gate 3's receiver command. Verify Waiting for Trigger. Then configure UART, start B, wait for ARMED, CLEAR, and START. The receiver's reachability test usually triggers RX. Otherwise, while RX remains armed, run `ping -n 1 192.168.1.11` from the PC. An ICMP reply can still exercise the RX domain even if Windows reports MISCOMPARE.
4. Acquisition should trigger on a valid XADC handshake. UI commit may take tens of seconds while data accumulates in DDR. When each upload completes, **save its waveform before changing that core's trigger**.
5. After saving the UI commit waveform, replace its trigger with **only** `probe15 packet_done == 1` and click **Run Trigger** again. Wait for the next batch. Inspect `probe16 packet_sequence`, `probe17 packet_first_word_index`, `probe7 occupancy_bytes`, and `probe22 fatal_error`. The two UI captures separately establish DDR batch commit and UDP progress; one 1024-sample window may not contain both events.
6. Capture full-window screenshots showing core name, trigger marker, signals, and values. Export native `.ila` files and separate `.csv` files. Suggested shared prefixes for PNG/ILA/CSV: `gate3_acq_handshake`, `gate3_ui_commit`, `gate3_ui_packet_done`, and `gate3_rx_ping`.

Judge each core within its own clock domain. Acquisition requires `source_valid=source_ready=1`, source 1, XADC mask `0xF`, and zero drop/overflow. UI requires separate commit and packet-done triggers, advancing indices, and zero fatal error. RX requires incoming `gmii_rx_data_vld=1` and `gmii_rx_data_error=0`. RX activity is not a substitute for the receiver's FPGA-to-PC UDP payload check. If a core does not trigger, inspect its clock and exact condition first. Immediate Trigger can confirm that a core is alive, but is not evidence of the target event.

## 7. Gate 3: 300-second live source-1 acquisition

Restore source 1 continuous mode and 1024-byte packets in A:

```powershell
py -3 .\v9_uart_control.py --port COM14 --seq 118 stop
Start-Sleep -Milliseconds 500
py -3 .\v9_uart_control.py --port COM14 --seq 119 source 1
py -3 .\v9_uart_control.py --port COM14 --seq 120 packet-length 1024
py -3 .\v9_uart_control.py --port COM14 --seq 121 mode continuous
```

Start B:

```powershell
.\udp_v9_monitor_rio.exe --duration 300 --first-timeout 240 `
  --output .\results\v9_gate3_xadc_1024B_300s.json `
  --sample-dir .\samples\gate3 --sample-interval 60 `
  --sample-bytes 256 --max-fragments 8
```

After **ARMED**:

```powershell
py -3 .\v9_uart_control.py --port COM14 --seq 122 clear
py -3 .\v9_uart_control.py --port COM14 --seq 123 start
```

XADC reserved bits, channel order, sample indices, packet sequence, and all receive errors must be zero. Per-channel counts should match, or differ by at most one at the stop boundary. V8 established that sparse source-1 batches can increment `tx_underflow` during idle intervals. Record it as such only if host continuity/data errors are zero, `xadc_drop_count=0`, and ingress/DDR are empty after STOP.

```powershell
py -3 .\v9_uart_control.py --port COM14 --seq 124 stop
Start-Sleep -Milliseconds 500
py -3 .\v9_uart_control.py --port COM14 --seq 125 status
```

## 8. Gate 5: 3600-second source-0 long run

Configure source 0, 25,000,000 words/s, 1024-byte packets, continuous mode in A:

```powershell
py -3 .\v9_uart_control.py --port COM14 --seq 126 stop
Start-Sleep -Milliseconds 500
py -3 .\v9_uart_control.py --port COM14 --seq 127 source 0
py -3 .\v9_uart_control.py --port COM14 --seq 128 rate 25000000
py -3 .\v9_uart_control.py --port COM14 --seq 129 packet-length 1024
py -3 .\v9_uart_control.py --port COM14 --seq 130 mode continuous
```

Start B:

```powershell
.\udp_v9_monitor_rio.exe --duration 3600 --first-timeout 180 `
  --output .\results\v9_gate5_prbs_1024B_25M_3600s.json `
  --sample-dir .\samples\gate5 --sample-interval 60 `
  --sample-bytes 256 --max-fragments 64
```

After **ARMED**:

```powershell
py -3 .\v9_uart_control.py --port COM14 --seq 131 clear
py -3 .\v9_uart_control.py --port COM14 --seq 132 start
```

The receiver compares roughly 180 GB of payload online, writing only the JSON and at most 16 KiB of sampled datagram prefixes. The strict acceptance target is PASS at 385–405 Mb/s, with all origin, sequence, sample-index, payload, and receive errors equal to zero. After STOP, require an empty pipeline, `fatal=False`, and zero internal source-0 overflow/underflow counters.

```powershell
py -3 .\v9_uart_control.py --port COM14 --seq 133 stop
Start-Sleep -Milliseconds 500
py -3 .\v9_uart_control.py --port COM14 --seq 134 status
```

## 9. Evidence archive and result

Retain, without overwriting earlier runs: four raw Gate 1/2/3/5 JSON files; each run's samples directory and manifest; initial/configuration/START/live/FINAL/STOP/status screenshots; four triggers across three ILAs as PNG/ILA/CSV; three ModelSim transcripts and summary; Vivado timing/utilization/DRC reports; and SHA-256 hashes for BIT, LTX, EXE, UART utility, and key RTL.

The [board-validation record](evidence/board_20260923/V9_BOARD_EVIDENCE_FINAL.md) reports the actual outcome: Gates 1–3 passed. Gate 5 completed the full 3600 seconds, but receiver-detected missing packets failed the strict zero-loss criterion. Each gate is assessed against its own V9 result.
