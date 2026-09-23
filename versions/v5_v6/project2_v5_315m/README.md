# Project 2 V5 — Stable 315 Mb/s Operating Point

This image derives from the IPv4-checksum-corrected baseline that had passed a 60-second run at 199.753956455 Mb/s. The only functional change is `POST_READY_IDLE_CYCLES` from 3000 to 1500 in the 100 MHz UI domain. Expected PRBS throughput was about 315 Mb/s; the board JSON provides the measured value. Packet format remains compatible with RIO v6.

Earlier 315 Mb/s runs showed isolated gaps under heavier host load. On September 21, 2026, Windows was switched to high-performance mode, background load was controlled, and PktMon was stopped. The same BIT then passed three consecutive strict 60-second tests and a 300-second test. The five-minute run reached **314.946984419 Mb/s**, **11,533,704 packets**, and **11,810,512,896 payload bytes**, with every error counter at zero. This established a repeatable five-minute operating point before the higher-rate boundary was explored.

The original 200 Mb/s baseline remains in the neighboring `v5_200m_pass_baseline` directory; its project was not altered.

## Board procedure

Before testing, set Windows to its high-performance profile, close unnecessary background downloads/sync applications, and verify that PktMon is stopped. Do not capture packets in this run, reducing additional host and USB/NIC receive-path load.

1. In Vivado Hardware Manager, program the FPGA with this directory's matching `project2_v5_top.bit` and `project2_v5_top.ltx`.
2. Wait for LED0 to remain on; do not press KEY0 yet.
3. The adjacent `Project2_315M_USB_Kit` includes the matching BIT/LTX, RIO v6, and no-capture scripts. For a manual run with the same port/IP settings, execute:

```powershell
& (Join-Path $v5 'tools\udp_v5_monitor_rio.exe') --duration 60 --output (Join-Path $v5 ('evidence\v5_315m_checksum_fixed_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.json'))
```

4. Press KEY0 after `ARMED` appears. Expect approximately 315 Mb/s and zero errors after 60 seconds; then press RESET.
5. After three passing 60-second runs, use `02_Run_315M_5min_NoCapture.cmd` in the USB kit for the five-minute run. Archive its JSON and console output.

## Build note

To avoid Vivado 2018.3 long-path issues on Windows, the build temporarily mapped `Q:` to the archived project directory. The project may retain internal `Q:` references; direct board programming with BIT/LTX accepts full physical paths and needs no mapping. Before a rebuild, confirm `Q:` is free, map it to the current project, and run the create-project, simulation, and bitstream scripts in order. Detailed build output is in `validation.txt` after generation.
