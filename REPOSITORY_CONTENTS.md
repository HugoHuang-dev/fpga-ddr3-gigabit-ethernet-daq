# Repository contents

This repository tracks the final V9 source and build configuration, versioned RTL and validation records, board-ready BIT/LTX pairs, representative ILA captures, screenshots, and machine-readable test summaries. Its structure follows the development stages described in the [project README](README.md).

| Directory | Contents |
| --- | --- |
| [`rtl/`](rtl/) · [`constraints/`](constraints/) · [`ip/`](ip/) | Final V9 RTL, pin/timing constraints, and compact Vivado IP configurations |
| [`scripts/`](scripts/) · [`sim/`](sim/) | Project generation, implementation, board programming, and testbenches |
| [`host/`](host/) · [`tools/`](tools/) | UART control, Windows RIO receiver source, and build utilities |
| [`board_test_package/`](board_test_package/) · [`releases/`](releases/) | V9 board procedure, bounded samples, JSON results, and versioned programming files |
| [`evidence/`](evidence/) · [`reports/`](reports/) | Cross-version visual evidence and final implementation reports |
| [`versions/`](versions/) | V1–V9 source snapshots, diagnostics, development records, and results |

Vivado project directories and generated IP output are rebuilt locally. The original IP Core Containers were reduced to their embedded `.xci` configurations for the repository; project-generation Tcl files reference those configurations. Large raw PktMon/PCAP traces and generated checkpoints are retained in the separate project archive, while the linked JSON, screenshots, ILA files, and reports needed to inspect the reported outcomes remain here. Host-specific absolute paths in copied diagnostic text were normalized to `archive/` or `repo/`; measured counters and test conclusions were not rewritten.

The repository includes the original versioned results, including the V5 MAX one-hour packet gaps and the V9 Gate 5 `passed=false` JSON. Consult the [V9 board evidence record](versions/v7_v9/project2_v9_full_validation/evidence/board_20260923/V9_BOARD_EVIDENCE_FINAL.md) for the acceptance interpretation.
