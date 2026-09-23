# Next Capture: Correlate NIC Ingress and RIO

The purpose of this diagnostic run is to locate the loss boundary using P2V5 packet sequence numbers from the same execution. Keep the BIT/LTX with the corrected IPv4 checksum and RIO v6. Run performance comparisons separately without PktMon. Execute the commands below from the Project 2 archive root.

1. Press FPGA RESET and wait for the MIG calibration LED0. Open PowerShell as administrator and run `pktmon status`. If another capture is active, leave it intact and do not use the start/stop commands below. On this machine, a non-administrator invocation returned Access Denied, consistent with the driver's privilege requirement.
2. In that window, run the following commands in order. The timestamped directory avoids overwriting evidence. Do not delete existing filters; other filters may widen the capture scope.

```powershell
$v5 = (Resolve-Path -LiteralPath '.\versions\v1_v5\project2_v5_ring_buffer').Path
$run = Join-Path $v5 ('evidence\ingress_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $run
$filter = 'P2V5_' + (Get-Date -Format 'HHmmss')
pktmon filter add $filter -i 192.168.1.11 -t UDP -p 6666
Get-NetAdapterStatistics -Name '以太网' | ConvertTo-Json | Set-Content (Join-Path $run 'adapter_before.json')
pktmon start --capture --comp nics --pkt-size 128 --file-size 1024 --log-mode circular --file-name (Join-Path $run 'ingress.etl')
```

Confirm that capture started before proceeding. A 128-byte snap length covers Ethernet, IPv4, UDP, the P2V5 header, and the sequence number, but not the entire PRBS payload. RIO still performs packet-by-packet payload validation.

3. Start the monitor in the same window; press KEY0 after `ARMED`. Keep the diagnostic evidence even if the program reports FAILED. The original record did not retain a command line for this step.
4. After the monitor ends, press RESET and execute the following. Stop only the capture started above.

```powershell
pktmon counters | Out-File (Join-Path $run 'pktmon_counters.txt')
pktmon stop | Tee-Object -FilePath (Join-Path $run 'pktmon_stop.txt')
Get-NetAdapterStatistics -Name '以太网' | ConvertTo-Json | Set-Content (Join-Path $run 'adapter_after.json')
pktmon etl2pcap (Join-Path $run 'ingress.etl') --out (Join-Path $run 'ingress.pcapng')
pktmon filter remove $filter
$run
```

Retain the displayed directory, original ETL, stop output, counters, and JSON. The PCAPNG can contain duplicate records from multiple observation components; distinguish component and direction. First check that the capture spans the run and that events were neither dropped nor overwritten by circular logging. Only then compare gaps from the same run; sequence numbers from different runs are not directly comparable.

A valid packet present at NIC ingress but absent from RIO points to loss after ingress. If both lack it, possible causes include FPGA output, cable, PHY/NIC/USB, or a capture omission and require another observation point. NIC drivers often do not deliver CRC-failed frames to capture tools, so the absence of recorded bad frames alone is inconclusive.

At the time of this note, command options had been checked against the local PktMon help, but this board-test procedure had not yet been run because the current process lacked the required privileges.
