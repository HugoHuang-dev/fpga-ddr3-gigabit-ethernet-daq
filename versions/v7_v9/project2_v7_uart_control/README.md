# Project 2 V7 — UART Control and Configurable Transfer

[V7 board images](../../../evidence/V7.md) · [V7 pin/timing constraints](../../../constraints/V7.md)

V7 adds a UART control and status path to the V6 concurrent pipeline. Acquisition, DDR writes/reads, and UDP transmission still progress independently. The UART PHY (`uart_dma`, `uart_rx`, `uart_tx`) runs on the 125 MHz control clock at 115200-8N1. The frame format and CRC-16/MODBUS match Project 1.

## Control functions

- `START` / `STOP`.
- `SOURCE_SELECT`: PRBS16 source.
- `SET_RATE`: acquisition rate in 16-bit words/s; zero selects maximum rate.
- `SET_PACKET_LENGTH`: 256, 512, or 1,024 bytes of UDP data.
- `FINITE` / `CONTINUOUS`: finite or continuous mode.
- `CLEAR_COUNTERS`: clear after stopping and draining.
- `READ_STATUS`: atomic snapshot in the MIG UI domain plus control-domain counters.

Each DDR read remains 1,024 bytes. The packetizer divides it into four, two, or one UDP packet according to the selected length; DDR ring space is released only after the complete read burst has entered the transmit FIFO. Byte-level fields are in the [V7 protocol](PROTOCOL_V7.md).

## Simulation, implementation, and board results

Behavioral tests covered UART transmit/receive timing, CRC, all commands, rejection of configuration changes while running, finite-mode automatic stop, atomic status reads, and bad-CRC discard. They also checked rate-limited PRBS data and continuity while splitting a 1,024-byte burst into four 256-byte packets. Three behavioral suites passed in Icarus Verilog; the UART-control suite also passed in Vivado XSim.

Vivado 2018.3 completed synthesis, place-and-route, and bitstream generation with **+0.456 ns WNS**, zero TNS, **+0.054 ns WHS**, zero THS, and zero DRC errors. Board tests covered UART commands/status, three packet lengths, 12.5 Mword/s rate limiting, exact finite counts, and invalid-command handling. The final 300-second maximum-rate test with 1,024-byte packets received **14,626,556 packets** at an average **399.402 Mb/s**. Packet loss, reordering, metadata, PRBS, receive-completion, and FPGA datapath error counts were all zero. [Stages 1–2](evidence/V7_STAGE1_STAGE2_EVIDENCE_20260922.md) and [stages 3–7](evidence/V7_STAGE3_STAGE7_EVIDENCE_20260922.md) retain the gate-by-gate evidence.

## Host command examples

To build and print UART frames without sending them:

```powershell
py -3 host\v7_uart_control.py start
py -3 host\v7_uart_control.py rate 25000000
py -3 host\v7_uart_control.py packet-length 512
py -3 host\v7_uart_control.py mode finite 1048576
py -3 host\v7_uart_control.py status
```

To query the connected board:

```powershell
py -3 host\v7_uart_control.py --port COM4 --seq 1 status
```

The [V7 board procedure](BOARD_TEST_V7.md) covers programming, configuration, execution, and status reads. The Windows RIO receiver, [`tools/udp_v7_monitor_rio.exe`](tools/udp_v7_monitor_rio.exe), supports all three V7 payload sizes and continuous PRBS validation. See the [development log](../../../DEVELOPMENT_LOG.md#v7) for the engineering sequence.

## Rebuilding

With Vivado 2018.3:

```powershell
vivado -mode batch -source scripts\create_project.tcl
vivado -mode batch -source scripts\run_sim.tcl
vivado -mode batch -source scripts\build_bitstream.tcl
```

[`scripts/build_bitstream.tcl`](scripts/build_bitstream.tcl) creates the report directory before writing post-route reports. [`scripts/collect_reports.tcl`](scripts/collect_reports.tcl) can recollect reports and BIT/LTX from an existing completed implementation.
