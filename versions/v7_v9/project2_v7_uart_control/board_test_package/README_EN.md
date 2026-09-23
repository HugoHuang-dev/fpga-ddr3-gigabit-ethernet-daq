# Project2 V7 UART-controlled DDR3-to-UDP pipeline

V7 starts from the closed V6 400 Mb/s pipeline without modifying the V6 archive. It adds a UART control and status plane while retaining the independently advancing acquisition, DDR write, DDR read and UDP transmit stages.

## Reused foundations

- UART PHY hierarchy (`uart_dma` → `uart_rx` / `uart_tx`) is taken from `adc_udp_v3` and parameterized for the 125 MHz control clock and 115200-8N1.
- Frame parsing and CRC-16/MODBUS semantics are taken from the board-verified Project1 protocol.
- DDR3/MIG, ADMA, ring management, ingress FIFO hysteresis and UDP stack start from the closed V6 sources.

## V7 functions

- START / STOP;
- SOURCE_SELECT (`0=PRBS16`; other sources are reserved);
- SET_RATE in accepted 16-bit words per second (`0=maximum`);
- SET_PACKET_LENGTH with 256/512/1024-byte UDP payloads;
- FINITE or CONTINUOUS mode;
- CLEAR_COUNTERS while stopped and drained;
- READ_STATUS with an atomic UI-clock snapshot and control-domain counters.

The DDR burst remains 1024 bytes. Dynamic UDP packet size is implemented by dividing one complete burst into 4, 2 or 1 packets; DDR ring space is still released only after the full burst has entered the TX FIFO.

See [PROTOCOL_V7.md](PROTOCOL_V7.md) for the byte-level interface and safety rules.

## Verification status

Behavioral tests cover:

- real UART receive timing through the Part 6 PHY;
- Project1-compatible CRC request validation and response generation;
- all control commands, busy rejection, finite auto-stop, atomic READ_STATUS and corrupt-CRC rejection;
- rate-controlled PRBS finite count and reset behavior;
- dynamic packetization of one 1024-byte DDR burst into four 256-byte UDP payloads with continuous data and one burst release.

Vivado 2018.3 synthesis, placement, routing and bitstream generation pass for
`xc7a35tfgg484-2`. The routed timing report has WNS `+0.456 ns`, TNS `0`, WHS
`+0.054 ns` and THS `0`; all specified timing constraints are met. Routed DRC
has no errors. Its warnings are inherited MIG/UDP-IP structural warnings (RAM
asynchronous control, clock buffering and unroutable unused loads), and the
timing methodology report retains the baseline UDP CRC clock/input-output-delay
warnings.

Hardware validation is complete. UART commands and atomic status passed on the
board; 256/512/1024-byte packetization, 12.5 Mword/s rate control and exact
finite transfer passed; unsupported, busy and bad-CRC handling matched the
protocol; and the final 1,024-byte maximum-rate run sustained 399.402 Mb/s for
300 seconds with 14,626,556 packets and zero loss, ordering, metadata, PRBS,
receive or FPGA data-path errors. See the two V7 evidence manifests under
`evidence` and the cumulative work log for the complete audited record.

The three behavioral tests can also be run independently with Icarus Verilog;
the UART-control test additionally passes native Vivado XSim.

## Host examples

Print frames without opening a serial port:

```powershell
py -3 host\v7_uart_control.py start
py -3 host\v7_uart_control.py rate 25000000
py -3 host\v7_uart_control.py packet-length 512
py -3 host\v7_uart_control.py mode finite 1048576
py -3 host\v7_uart_control.py status
```

Send a command to the board:

```powershell
py -3 host\v7_uart_control.py --port COM4 --seq 1 status
```

For the complete program/configure/run/status sequence, use
[BOARD_TEST_V7.md](BOARD_TEST_V7.md). A V7-aware high-rate Windows RIO receiver
is included as [`tools\udp_v7_monitor_rio.exe`](../tools/udp_v7_monitor_rio.exe); unlike the V5 receiver it accepts
all three V7 payload sizes and checks the continuous PRBS stream.

The cumulative Project2 development and board-evidence record is maintained in
[`Project2_work_log.md`](Project2_work_log.md).

## Build

Use Vivado 2018.3:

```powershell
vivado -mode batch -source scripts\create_project.tcl
vivado -mode batch -source scripts\run_sim.tcl
vivado -mode batch -source scripts\build_bitstream.tcl
```

[`scripts\build_bitstream.tcl`](../scripts/build_bitstream.tcl) creates the report directory before writing the
post-route reports. [`scripts\collect_reports.tcl`](../scripts/collect_reports.tcl) regenerates reports and copies
BIT/LTX from an already completed implementation run without rerunning place and
route.
