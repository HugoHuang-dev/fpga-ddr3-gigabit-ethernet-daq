# V1–V3 Development and Validation Records

The version documents contain the design work, offline verification, and board-test results for the first three releases. This page brings their entry points together in development order.

| Version | Development and validation record | Key evidence |
| --- | --- | --- |
| V1 Network Connectivity | [V1 record](project2_v1_udp/README.md): ARP/ICMP/UDP echo, beacon, RGMII/PHY clocks and pins, application-layer simulation, implementation timing, board ping, and 64-byte echo | [Board-test screenshot](project2_v1_udp/evidence/v1_board_test_passed.png) · [V1 image index](../../evidence/V1.md) |
| V2 Continuous Test Stream | [V2 record](project2_v2_stream/README.md): packet sequence numbers, incrementing payload, RTL source self-test, PC parser self-test, and a 30-second continuous stream | [30-second JSON](project2_v2_stream/evidence/v2_30s_result.json) · [V2 image index](../../evidence/V2.md) |
| V3 DDR3 Self-Test | [V3 record](project2_v3_ddr3/README.md): MIG calibration, three AXI4 data patterns, XSim, timing, LED status, and ILA readback comparison | [Final ILA status](project2_v3_ddr3/evidence/v3_ila_final_status_pass.png) · [ILA readback comparison](project2_v3_ddr3/evidence/v3_ila_data_compare_pass.png) · [V3 image index](../../evidence/V3.md) |

[Project overview](../../README.md) · [V4 development record](project2_v4_ddr3_udp/evidence/development_log.md) · [V5–V9 development log](../../DEVELOPMENT_LOG.md)
