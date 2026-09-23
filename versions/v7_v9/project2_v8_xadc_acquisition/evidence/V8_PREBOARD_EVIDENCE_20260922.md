# V8 pre-board evidence — 2026-09-22

## Scope

This directory records reproducible evidence completed before programming the
new V8 image. It does not claim board validation.

## Implementation evidence

- [`build/timing_summary.rpt`](build/timing_summary.rpt): routed WNS +0.544 ns, TNS 0, WHS +0.031 ns, THS 0.
- [`build/bus_skew.rpt`](build/bus_skew.rpt): all 20 bus-skew checks MET; minimum slack +6.778 ns.
- [`build/utilization.rpt`](build/utilization.rpt): 14,910 LUT, 18,166 registers, 36 BRAM tiles, 0 DSP,
  exactly one XADC.
- [`build/drc.rpt`](build/drc.rpt): zero errors; 37 warnings and two advisories.
- [`build/implementation_runme_clean.log`](build/implementation_runme_clean.log): final implementation through
  bitstream with zero critical warnings and zero errors.

## Simulation evidence

[`simulation/simulation_summary.txt`](simulation/simulation_summary.txt) records the final behavioral verdicts. The
Vivado XSim transcript is preserved as [`simulation/run_sim_v8.log`](simulation/run_sim_v8.log).

## Source provenance

Project1 source: `rtl/xadc_multichannel.v`. The project copy is available as
[`../rtl/xadc_multichannel.v`](../rtl/xadc_multichannel.v).

Project1 and V8 copies both have SHA-256:
`EF467DFEA1DC4867C85712CECA18A9C35EA69B958DF6607F58DEC8A45A58F936`.

## Deliverable hashes

- BIT: `DAD9D9AE15C2380DC22ECF348BA5507E48AE659749717C62D5A78C3BD80637A4`
- LTX: `84486ADDAB52CD3D26FB2410E629CBD61E271F0ACE1C2CA75D86E0B8ECBBCBE7`
- RIO monitor EXE: `194E6BCA54DF2DD3E8B8C8C7A5FF3BC902DFFC0A632BCE676467245A7D88826A`
- UART Python tool: `E05B69AB79AB1A808ECFA4542B3741F9F61D2767014B0B39501B3C4CB8CA0B8E`

The corresponding V8 board runs were subsequently completed. Their screenshots,
four original JSON files, measured results and hashes are preserved separately
in `board_20260922/` and [`V8_BOARD_VALIDATION_EVIDENCE_20260922.md`](V8_BOARD_VALIDATION_EVIDENCE_20260922.md); this file
remains the pre-board build/simulation record and does not retroactively mix the
two evidence phases.
