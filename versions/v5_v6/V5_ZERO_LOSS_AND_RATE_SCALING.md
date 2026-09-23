# V5: First Zero-Loss Run and Throughput Increase

The original JSON confirms a 60.0000134-second run: 1,463,042 packets, 1,498,155,008 bytes of PRBS data, and 199.753956455 Mb/s. The first packet sequence was zero. Missing packets, gaps, duplicates, reordering, format errors, metadata errors, PRBS errors, and RIO errors were all zero.

This run used the existing FPGA image with the checksum fix and RIO v6; no further code fix was introduced. PktMon was enabled and the program ran from an administrator PowerShell window. This single result cannot isolate the effect of administrator privileges, packet capture, or other environment changes on packet loss, nor does it establish the high-throughput limit. The 200 Mb/s configuration is now a 60-second passing baseline; a long-duration run remains to be done.

The passing snapshot is saved under `v5_200m_pass_baseline`; the full historical log is [`Project2_work_log.md`](Project2_work_log.md). Five new screenshots are also saved in the original project's `evidence/v5_first_zero_loss_01.png` through `_05.png`.

For the throughput sweep, first preserve this capture and run the same 200 Mb/s image once without PktMon. Then program the separate 315 Mb/s image and run for 60 seconds. If it passes, extend to five minutes before testing approximately 400/500 Mb/s. Select the final rate from a stable long-duration operating point with margin, rather than treating the highest short-run figure as sustained performance. Preserve gap details for failed runs. The pre-checksum-fix 315 Mb/s result is not the corrected design's rate ceiling.

## Closing out this PktMon capture

In the original administrator window, press RESET first. If this capture is still the one started for the run, execute:

```powershell
pktmon counters | Out-File (Join-Path $run 'pktmon_counters.txt')
```

Then:

```powershell
pktmon stop | Tee-Object -FilePath (Join-Path $run 'pktmon_stop.txt')
```

Do not repeat `stop` if it has already completed. Continue with:

```powershell
Get-NetAdapterStatistics -Name '以太网' | ConvertTo-Json | Set-Content (Join-Path $run 'adapter_after.json')
pktmon etl2pcap (Join-Path $run 'ingress.etl') --out (Join-Path $run 'ingress.pcapng')
pktmon filter remove $filter
```

If that window is closed, do not run commands that depend on `$run` or `$filter`. This run used `evidence/ingress_20260920_230946` and filter `P2V5_230946`.

## 200 Mb/s control run without PktMon

Keep the current FPGA image and run this separately from the original administrator window:

```powershell
& (Join-Path $v5 'tools\udp_v5_monitor_rio.exe') --duration 60 --output (Join-Path $v5 ('evidence\v5_200m_nocapture_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.json'))
```

Press KEY0 once after `ARMED` appears and RESET after completion. All errors must be zero for a pass. The timestamped output name avoids overwriting previous evidence.
