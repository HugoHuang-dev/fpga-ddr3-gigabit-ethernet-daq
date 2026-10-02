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
| ModelSim DE-64 10.6c | 3/3 PASS | [`modelsim/MODELSIM_V9_SUMMARY.md`](../evidence/modelsim/MODELSIM_V9_SUMMARY.md) and three transcripts |
| PC Windows RIO self-test | 10/10 PASS | [`modelsim/udp_v9_monitor_self_test.log`](../evidence/modelsim/udp_v9_monitor_self_test.log) |
| Vivado 2018.3 routed design | PASS | [`vivado/timing_summary.rpt`](../evidence/vivado/timing_summary.rpt), `utilization.rpt`, `drc.rpt`, `bus_skew.rpt` |
| BIT / LTX generation | PASS | [`../project2_v9_top.bit`](../project2_v9_top.bit), [`../project2_v9_top.ltx`](../project2_v9_top.ltx) |
| V9 source-0/1 board streams | PENDING | Run [`../BOARD_TEST_V9.md`](../BOARD_TEST_V9.md); preserve new JSON, samples and screenshots |
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
