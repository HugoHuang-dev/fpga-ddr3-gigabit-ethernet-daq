# Project 2 V5 — MAX Image Without Additional Throttling

This image derives from the 400 Mb/s version that passed a strict 60-second run at 399.407724507 Mb/s. Its only functional change is `POST_READY_IDLE_CYCLES` from 950 to zero, removing the deliberately added inter-packet wait.

The board-measured unpaced throughput of the current packetizer/UDP combination was **680.207163370 Mb/s** over 60.0001438 seconds: **4,981,998 packets** and **5,101,565,952 bytes**, with every receiver error counter at zero. This measurement supersedes an earlier linear estimate near 744 Mb/s. “MAX” denotes the measured rate limit of this RTL and 1,024-byte packet configuration.

## Endurance procedure

1. Program the matched BIT/LTX from this directory.
2. Press RESET, wait at least five seconds, and leave KEY0 untouched.
3. Keep the host in high-performance mode, close unnecessary background programs, and stop PktMon.
4. Start the MAX no-capture RIO script. Press KEY0 once after `ARMED` appears.
5. After a passing 60-second screening run, use `02_Run_MAX_1hour_NoCapture.cmd` in the test kit for a one-hour run.
6. The original strict one-hour acceptance gate required every error field to remain zero; approximately 306 GB of payload was expected to be checked.

## Measured one-hour result

MAX completed a **3600.0001469-second** continuous run. The receiver obtained **298,914,974 packets**, verified **306,088,933,376 bytes** byte-for-byte, and measured **680.197601969 Mb/s** of payload throughput. Twenty-five sparse gaps totaled **660 missing packets**, a **0.000220798%** loss rate (2.207981 ppm) and **99.999779202%** packet delivery. The largest gap was 133 packets.

Every received packet passed format, metadata, and PRBS checks. Out-of-order, duplicate, malformed, corrupt-data, and RIO-completion error counts were zero; Windows NIC receive-error and discard counters were also zero. The result is therefore a **680.198 Mb/s one-hour maximum-rate endurance measurement, 306.089 GB verified, 99.999779% packet delivery, and zero corruption in delivered packets**, not a strict zero-loss pass. The earlier zero-loss 60-second MAX run remains a short-term peak demonstration; a paced image with more headroom would be required for a zero-loss one-hour qualification.

## Parameters

| Parameter | Value |
| --- | --- |
| FPGA | XC7A35TFGG484-2 |
| `POST_READY_IDLE_CYCLES` | 0 |
| Earlier predicted payload rate | about 744 Mb/s |
| Payload per packet | 1,024 bytes |
| UDP receive port | 6666 |
| FPGA / PC IP | 192.168.1.11 / 192.168.1.100 |
