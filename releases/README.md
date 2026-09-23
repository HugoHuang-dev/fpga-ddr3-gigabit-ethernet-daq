# Bitstreams and Debug Probes

This directory stores the board implementation files by version. Each `.bit` file is a configuration bitstream; its matching `.ltx` file contains the ILA debug probes. V1 and V2 do not use ILA probes. Each directory corresponds to the project snapshot with the same version under `versions/`. Consult the version record and original test results for the test conditions and conclusions.

| Version | Configuration files | Project and validation |
| --- | --- | --- |
| V1 Network Connectivity | [Bitstream](V1/project2_v1_top.bit) | [V1 project](../versions/v1_v5/project2_v1_udp/README.md) |
| V2 Continuous Test Stream | [Bitstream](V2/project2_v2_top.bit) | [V2 project](../versions/v1_v5/project2_v2_stream/README.md) |
| V3 DDR3 Self-Test | [AXI self-test bitstream](V3/project2_v3_axi.bit) · [AXI probes](V3/project2_v3_axi.ltx) · [Calibration bitstream](V3/project2_v3_calib.bit) · [Calibration probes](V3/project2_v3_calib.ltx) | [V3 project](../versions/v1_v5/project2_v3_ddr3/README.md) |
| V4 Finite Transfer | [Bitstream](V4/project2_v4_top.bit) · [ILA probes](V4/project2_v4_top.ltx) | [V4 project](../versions/v1_v5/project2_v4_ddr3_udp/README.md) |
| V5 Ring-Buffer Baseline | [Baseline bitstream](V5_base/project2_v5_top.bit) · [ILA probes](V5_base/project2_v5_top.ltx) | [V5 project](../versions/v1_v5/project2_v5_ring_buffer/README.md) |
| V5 225M Diagnostic | [Diagnostic bitstream](V5_225m_diagnostic/project2_v5_top.bit) · [ILA probes](V5_225m_diagnostic/project2_v5_top.ltx) | [Diagnostic project](../versions/v5_v6/project2_v5_225m_diagnostic/README.md) |
| V5 250M Diagnostic | [Diagnostic bitstream](V5_250m_diagnostic/project2_v5_top.bit) · [ILA probes](V5_250m_diagnostic/project2_v5_top.ltx) | [Diagnostic project](../versions/v5_v6/project2_v5_250m_diagnostic/README.md) |
| V5 315M | [315M bitstream](V5_315m/project2_v5_top.bit) · [ILA probes](V5_315m/project2_v5_top.ltx) | [Test record](../versions/v5_v6/project2_v5_315m/README.md) |
| V5 400M | [400M bitstream](V5_400m/project2_v5_top.bit) · [ILA probes](V5_400m/project2_v5_top.ltx) | [Test record](../versions/v5_v6/project2_v5_400m/README.md) |
| V5 MAX | [MAX bitstream](V5_max_unpaced/project2_v5_top.bit) · [ILA probes](V5_max_unpaced/project2_v5_top.ltx) | [Test record](../versions/v5_v6/project2_v5_max_unpaced/README.md) |
| V6 Pipeline | [Bitstream](V6/project2_v6_top.bit) · [ILA probes](V6/project2_v6_top.ltx) | [V6 project](../versions/v5_v6/project2_v6_pipeline/README.md) |
| V7 UART Control | [Bitstream](V7/project2_v7_top.bit) · [ILA probes](V7/project2_v7_top.ltx) | [V7 project](../versions/v7_v9/project2_v7_uart_control/README.md) |
| V8 XADC Acquisition | [Bitstream](V8/project2_v8_top.bit) · [ILA probes](V8/project2_v8_top.ltx) | [V8 project](../versions/v7_v9/project2_v8_xadc_acquisition/README.md) |
| V9 Full Validation | [Bitstream](V9/project2_v9_top.bit) · [ILA probes](V9/project2_v9_top.ltx) | [V9 board evidence](../versions/v7_v9/project2_v9_full_validation/evidence/board_20260923/V9_BOARD_EVIDENCE_FINAL.md) |

Several V5 bitstreams share the same filename but belong to different test configurations. Always use the `.bit` and `.ltx` pair from the same directory. Checksums for all 28 configuration and probe files are in the [SHA-256 manifest](SHA256SUMS.csv).
