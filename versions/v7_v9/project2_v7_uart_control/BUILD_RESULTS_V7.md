# Project2 V7 build results

- Tool: Vivado 2018.3
- Device: `xc7a35tfgg484-2`
- Top: `project2_v7_top`
- Implementation: synthesis, placement, routing and bitstream generation passed
- Routed timing: WNS `+0.456 ns`, TNS `0 ns`, WHS `+0.054 ns`, THS `0 ns`
- Timing verdict: all user-specified timing constraints met
- DRC: 0 errors; 37 warnings and 2 advisories reported during bitstream generation
- Utilization: 14,791 LUTs (71.11%), 17,969 registers (43.19%), 36 BRAM tiles
  (72.00%), 0 DSPs

The DRC warnings are in the inherited MIG/UDP IP (buffer connections, RAM
asynchronous control, clock buffering and unused/no-load nets). The timing
methodology section also reports the inherited UDP CRC derived-clock and
top-level input/output-delay coverage warnings. These are recorded, not silently
treated as clean. V7 board validation is still required.

## SHA-256

- [`project2_v7_top.bit`](project2_v7_top.bit): `6FD8FF72CE6B2475812380D72DE9ACFB74873E64EA76614117695BAFACC46A5E`
- [`project2_v7_top.ltx`](project2_v7_top.ltx): `84486ADDAB52CD3D26FB2410E629CBD61E271F0ACE1C2CA75D86E0B8ECBBCBE7`
- [`tools/udp_v7_monitor_rio.exe`](tools/udp_v7_monitor_rio.exe): `2FDA2F3C6BF66A3ABC2F3C6ED4AF9B65F0C35F664A70C8D82DED2F1A3B095794`
