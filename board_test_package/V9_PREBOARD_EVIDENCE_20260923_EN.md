# Project2 V9 pre-board evidence — 2026-09-23

## Verdict

Local gates PASS; V9 hardware gates PENDING. This record does not substitute
V8 screenshots or V8 JSON for V9 board evidence.

At package handoff, this PC did not list the board's COM4 port (only Bluetooth
serial ports were present), and a one-packet ping to 192.168.1.11 timed out.
No V9 bitstream was programmed on the board and no V9 live-stream result is
claimed. Reconnect/power the board and verify its current UART port and network
addresses before following the board guide; replace COM4 in the commands if
Windows assigns another port.

| Gate | Result | Evidence |
| --- | --- | --- |
| ModelSim DE-64 10.6c | 3/3 PASS | [`modelsim/MODELSIM_V9_SUMMARY.md`](../versions/v7_v9/project2_v9_full_validation/evidence/modelsim/MODELSIM_V9_SUMMARY.md) and three transcripts |
| PC Windows RIO self-test | 10/10 PASS | [`modelsim/udp_v9_monitor_self_test.log`](../versions/v7_v9/project2_v9_full_validation/evidence/modelsim/udp_v9_monitor_self_test.log) |
| Vivado 2018.3 routed design | PASS | [`vivado/timing_summary.rpt`](../versions/v7_v9/project2_v9_full_validation/evidence/vivado/timing_summary.rpt), `utilization.rpt`, `drc.rpt`, `bus_skew.rpt` |
| BIT / LTX generation | PASS | [`../project2_v9_top.bit`](../releases/V9/project2_v9_top.bit), [`../project2_v9_top.ltx`](../releases/V9/project2_v9_top.ltx) |
| V9 source-0/1 board streams | PENDING | Run [`../BOARD_TEST_V9.md`](../versions/v7_v9/project2_v9_full_validation/BOARD_TEST_V9.md); preserve new JSON, samples and screenshots |
| Three on-board ILA cores | PENDING | Save acquisition handshake, UI commit, UI packet-done and RX activity captures |

Routed timing: WNS +0.292 ns, TNS 0.000 ns, WHS +0.014 ns, THS
0.000 ns; all user timing constraints met. LUT 16,976/20,800 (81.62%);
registers 21,459/41,600 (51.58%); BRAM tiles 26/50 (52%);
DSP 0/90; XADC 1/1. DRC: 0 errors, 37 warnings, 2 advisories. The warnings
remain visible in the raw DRC report; they are not silently represented as
zero warnings. Bus-skew constraints: 19 rows, minimum slack +6.870 ns.

The ILA clocks in the implemented top are `u_ila_acq.clk=clk_125m`,
`u_ila_ui.clk=ui_clk`, and `u_ila_rx.clk=phy_rx_clk`. Their existence in
the BIT/LTX is implementation evidence, not evidence of captured board waves.

## SHA-256 artifact identity

```text
project2_v9_top.bit                     DC2E2860E6474051FDF051CBAA845E03F0E8F82A78970D391E4011BB351F67D7
project2_v9_top.ltx                     70647F428343BCB41EB218879AEF35A045BF76B2C3F5C17228BEE98F4A3419E9
rtl/project2_v9_top.v                   944ADE677FD55C1D2D6EC9AA9B45AAFF46EA928D6605633444F019EC3351A244
rtl/udp_v9_tx_fifo_packetizer.v         03675F23128CCAC0D5661A76845840053973197F9C416F8F442CC709B041FF90
rtl/v9_uart_control.v                   EE563E0A101C95EDC8177DA6F450E89CCE2AC2A911CEC483A4F1F0FA7F3294E7
tools/udp_v9_monitor_rio.exe            B9A71E1C5D3A3CA1E2EC6FCA4A6DE2DB7E423E675CB3D3CE222722074FC63E72
tools/udp_v9_monitor_rio.cpp            19A610F5FEB3EA33B26ED21CDCB1F0F3A4E9232046E752BA7E388E104DE9A94E
host/v9_uart_control.py                 E0DBA01D22CA36146143EEC65793F6276A6D7D6F06FD2988516AEE75F414F948
reports/timing_summary.rpt              810B6BB09F5D4744A24BFD2CFCE361E20CCD6935E6729765911518F61F5C5B8B
reports/utilization.rpt                 EF91504761A16EA2256961075DAA36DA64DE508100E554254E94C30FA85BD6E8
reports/drc.rpt                         4F11E02B89ABCF93F0AEE232D89F5CFC0A24209756C5C191C8A4E816E7716639
reports/bus_skew.rpt                    69EDF4EBB61C2EEBBB548B561F4113152497E90B086AA2A53A68F7ACC390E62A
```

## Board evidence to add before final V9 closure

Save the four V9 JSON files and their bounded samples from Gates 1/2/3/5,
the initial/configuration/START/FINAL/STOP/status screenshots, and four
independent .ila/.csv exports with screenshots (acquisition handshake,
UI commit, UI packet-done and RX activity). Check JSON
`passed=true`, zero sequence/sample-index/payload/metadata/receive errors,
the exact finite XADC record count, nonzero live XADC data, DDR/MIG status,
and empty post-STOP pipeline. Record any slow-source tx-underflow with the
full continuity and drop-counter context. Only then append final board
metrics and change the V9 verdict to complete.
