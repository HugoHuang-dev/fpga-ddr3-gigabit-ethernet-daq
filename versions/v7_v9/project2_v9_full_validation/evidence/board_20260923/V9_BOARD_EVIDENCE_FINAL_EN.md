# Project2 V9 board evidence — final measured outcome, 2026-09-23

## Verdict and scope

The board validation used the physical FPGA, COM14 UART control, Vivado ILA,
and the Windows RIO receiver. Results below are taken from the archived
JSON, waveforms, screenshots, and status records.

ModelSim 3/3, PC monitor self-test 10/10, and routed Vivado timing/resource
results are documented in [`../V9_PREBOARD_EVIDENCE_20260923.md`](../V9_PREBOARD_EVIDENCE_20260923.md). Board Gates
1, 2 and 3 have passing original JSON and bounded sample files. Four native
ILA acquisitions are archived here. Gate 5 completed its full 3,600 seconds
and produced a valid measured-loss result, but its strict receiver verdict is
`passed=false`. **All planned observations were executed; the planned
one-hour zero-loss acceptance criterion was not met.** This is a legitimate
final project measurement, not a zero-loss qualification.

## Completed board gates

| Gate | Archived original result | Audited result |
| --- | --- | --- |
| Gate 1, source 0 PRBS16, 1,024 B, 25 Mword/s | [`results/v9_gate1_prbs_1024B_25M_60s_manual.json`](results/v9_gate1_prbs_1024B_25M_60s_manual.json) | `passed=true`; 60.000168 s; 2,913,988 packets; 2,983,923,712 payload bytes; 397.855381 Mb/s average; sequence and first-word origins 0; all PC integrity and receive errors 0. Six 256-byte prefix fragments archived in `samples/gate1_manual/`. |
| Gate 2, source 1 XADC finite 32,768 words | [`results/v9_gate2_xadc_finite_32768.json`](results/v9_gate2_xadc_finite_32768.json) | `passed=true`; 64 packets; 65,536 payload bytes; 32,768 records, four channels × 8,192; origins 0; all PC errors 0. One prefix fragment archived in `samples/gate2/`. |
| Gate 3, source 1 XADC continuous | [`results/v9_gate3_xadc_1024B_300s.json`](results/v9_gate3_xadc_1024B_300s.json) | `passed=true`; 300.0674324 s; 624 packets; 638,976 payload bytes; 319,488 records, four channels × 79,872; 0.0170355 Mb/s average; origins 0; all PC errors 0. Five prefix fragments archived in `samples/gate3/`. |
| Gate 5, source 0 PRBS16 endurance | [`results/v9_gate5_prbs_1024B_25M_3600s.json`](results/v9_gate5_prbs_1024B_25M_3600s.json) | **Strict FAIL** after 3600.0000886 s; 174,834,426 received packets; 179,030,452,224 payload bytes; 397.845440 Mb/s average; 1,824 missing packets in 30 gaps; 30 corresponding sample-index discontinuities / 933,888 missing words. Delivered-packet payload corruption, malformed packets, metadata and receive-completion errors all 0. Sixty 256-byte prefix fragments archived in `samples/gate5/`. |

The older [`results/v9_gate1_prbs_1024B_25M_60s_incomplete_attempt.json`](results/v9_gate1_prbs_1024B_25M_60s_incomplete_attempt.json)
is deliberately retained. It has `passed=false`, duration 0 and zero packets;
it is **not** counted as a Gate 1 pass. The later `_manual.json` is the actual
completed passing 60-second run. The incomplete file alone does not establish
why no packets were captured, so no cause is inferred.

The status images show V9, calibrated MIG, no fatal state and
XADC mask `0xF`. Gate 1's post-STOP status shows empty ingress/DDR and zero
listed internal overflow/underflow counters. Gate 2's post-run status has
`finite_done=True`, `run_words=32768`, `packet_sequence=64`, empty ingress/
DDR, `xadc_drop_count=0`, and zero listed internal overflow/underflow counts.
Gate 3's post-STOP status has empty ingress/DDR, `xadc_drop_count=0`, no fatal
state, and `tx_underflow=25`. The latter is recorded explicitly: per the
previously documented slow-source batch/idle interpretation, it is compatible
with zero PC loss/corruption and complete post-STOP drain. It is not silently
converted to zero or used to claim every internal counter was zero.

## Gate 5 interpretation and limits

The receiver's 30 packet gaps and 30 sample-index discontinuities describe
the same missing spans, not two independent loss totals: 1,824 packets × 512
16-bit words per packet = 933,888 missing words. The largest single gap was
173 packets. `gap_records_truncated=false` and
`sample_index_records_truncated=false`; all 30 events are retained in the
JSON. First sequence and first-word origins are 0. The measured payload rate
range was 393.900884–398.100834 Mb/s over one-second windows. All packets
that reached the PC passed the deterministic PRBS16 byte comparison; this
does **not** mean the unreceived packets were verified.

The FINAL screenshot reports `V9 FULL VALIDATION STREAM TEST
FAILED`, matching the archived JSON, not a PASS. The post-STOP UART screenshot
shows version 9, calibrated MIG, `run_enable=False`, `fatal=False`, zero
ingress level and DDR occupancy, and zero listed ingress/ring/TX overflow and
underflow counts. It also shows `command_rejects=1`, whose command and timing
cannot be determined from this status alone. Neither the zero FPGA-side error
counters nor prior experience with host load proves where the missing packets
were lost. FPGA, PHY/link, USB NIC, driver and host scheduling remain possible
contributors without an independent observation at the loss boundary.

This one-hour run may close the *measurement/validation work* with a known
limitation, just as the earlier V5 one-hour maximum-rate run was retained as
a measured-loss endurance result. It cannot satisfy the unchanged Gate 5
zero-loss hard criterion in [`../../board_test_package/VALIDATION_PLAN_V9.md`](../../board_test_package/VALIDATION_PLAN_V9.md),
and should never be described as a V9 full-validation PASS or a guaranteed
lossless 400 Mb/s operating point. No additional rerun is required merely to
preserve and report the honest result; establishing a strict lossless one-hour
operating point or locating the loss boundary is optional future work.

## Four ILA waveform exports

Each `.ila` is a native Vivado archive. Its embedded `waveform.csv` was
extracted to a same-stem `.csv` without changing the native export. Each CSV
has 1,024 samples and `TRIGGER=1` at sample 512. These are independent clock
domains and do not imply cycle-aligned events across ILAs.

| Capture | Archived files under `ila/` | Directly checked at trigger |
| --- | --- | --- |
| Acquisition/control, `clk_125m` | `gate3_acq_handshake.ila/.csv` | source select `0x01`, `source_valid=1`, `source_ready=1`, XADC mask `0xF`, drop 0. |
| PHY RX, `phy_rx_clk` | `gate3_rx_activity.ila/.csv` | `gmii_rx_data_vld=1`, `gmii_rx_data_error=0`. This is RX activity, not FPGA→PC payload proof. |
| DDR/TX, MIG `ui_clk` | `gate3_ui_commit.ila/.csv` | `tx_burst_committed=1`, `fatal_error=0`. |
| DDR/TX packet completion, MIG `ui_clk` | `ui_packet_done_supplement.ila/.csv` | `packet_done=1`, `fatal_error=0`; sequence 0→1 and first-word index 0→512 in the local waveform. |

The packet-completion capture was acquired later as a standalone supplement,
not simultaneously with the 300-second Gate 3 PC monitor. Its local waveform
claim is valid; same-run cross-domain/PC correlation is **not** claimed. The
original supplied file spelling was [`iladatapacketdone_suplenment.ila`](../../iladatapacketdone_suplenment.ila); the
archival copy uses `supplement` in its name. Other original `.ila` files are
[`iladata acq.ila`](ila/gate3_acq_handshake.ila), [`iladatarx.ila`](../../iladatarx.ila) and [`iladataui.ila`](../../iladataui.ila) in the V9 output root. The acquisition link uses the identical no-space evidence copy.

## Board-test screenshots

Twenty board-test PNGs are stored in `screenshots/`; their SHA-256 values
are included in [`SHA256.txt`](SHA256.txt). The Gate 5 FINAL and post-STOP status images
are stored as [`screenshots/gate5_final_failed.png`](screenshots/gate5_final_failed.png) and
[`screenshots/gate5_post_stop_status.png`](screenshots/gate5_post_stop_status.png), with hashes in [`GATE5_SHA256.txt`](GATE5_SHA256.txt).

| Image | Filename stem | Observed role |
| --- | --- | --- |
| 1 | `56b06ca96a14c2398df10530026aeed9` | Initial UART status: version 9, MIG calibrated, XADC mask `0xF`, no fatal state. |
| 2 | `eac43d18de733bb01bae2539b9b9c63a` | PC monitor ten-case self-test PASS. The textual self-test log is separately archived with pre-board evidence. |
| 3 | `f99fc37cf1817ec16c06cf8048e539f5` | Gate 1 source 0, rate 25 Mword/s, 1,024 B, continuous configuration ACKs. |
| 4 | `06797e623ade32412e508e86dd069e3e` | Gate 1 START and STOP ACKs. |
| 5 | `af6c9e1e2b3854e940be60137cc439f2` | Gate 1 60-second receiver FINAL/PASS. |
| 6 | `98f0618af79bbadfc54ec5bb2508ad61` | Gate 1 post-STOP UART status. |
| 7 | `6b1c7f9568e9740b22b601a9f5e17234` | Gate 2 source 1, 1,024 B, finite 32,768 configuration ACKs. |
| 8 | `a92b043b87df5fc2ce4d5f4ea891c93d` | Gate 2 CLEAR and START ACKs. |
| 9 | `3b240555af2996192eee32ac5e169b13` | Gate 2 receiver FINAL/PASS. |
| 10 | `8493dad08c371ca447b56581921e0056` | Gate 2 finite-done UART status. |
| 11 | `282a63e2ace96575005497af0fe6d91e` | Gate 3 CLEAR and START ACKs. |
| 12 | `6461e3eff145288e5061d9632b5a2db3` | Acquisition-domain ILA handshake wave. |
| 13 | `6a479877acae8d96edc19fefd82e1aab` | PHY RX-domain ILA activity wave and trigger setup. |
| 14 | `6d46d7b02fd971f282450afd12effc50` | DDR/TX ILA commit, upper probes. |
| 15 | `abfde643cd6e88ae45ea98584feaf3f5` | DDR/TX ILA commit, lower probes and trigger pulse. |
| 16 | `d504f93876f71aecd4c5691508a75dc6` | Gate 3 post-STOP UART status, including `tx_underflow=25`. |
| 17 | `2099d4880806b525442ed1c2dfba565b` | Gate 3 300-second receiver FINAL/PASS. |
| 18 | `a68e0343d9a39345c7d8b4dc17da458c` | Supplemental UI `packet_done` wave, upper probes. |
| 19 | `88497a3d67f7b59b8068e8c4afb43646` | Supplemental UI `packet_done` wave, lower probes. |
| 20 | `85cf13f15cdb0781b8f934d137ab4acf` | Gate 5 source 0/rate/packet/mode setup only; **not** long-run PASS. |
| 21 | [`gate5_final_failed.png`](screenshots/gate5_final_failed.png) | Gate 5 3600-second receiver FINAL/FAIL. |
| 22 | [`gate5_post_stop_status.png`](screenshots/gate5_post_stop_status.png) | Gate 5 post-STOP UART status. |

## Identity and project disposition

[`SHA256.txt`](SHA256.txt) covers all 44 archived binary/data files: 20 PNG screenshots,
4 native ILA exports, 4 extracted CSVs, 4 JSONs (including the incomplete
attempt), and 12 bounded sample fragments. [`GATE5_SHA256.txt`](GATE5_SHA256.txt) covers the
additional 63 Gate 5 files: final JSON, two PNGs and 60 bounded fragments.
Both manifests were checked against the files. The pre-board evidence file retains the BIT/LTX, software,
RTL and Vivado-report identity hashes. No raw multi-hundred-GB payload stream
was archived; the receiver checked it online and retained only bounded
fragments by design.

**Final wording:** Project2 V9 implementation and planned validation are
complete, with passing local tests, short-run/real-XADC board gates and ILA
evidence, plus a full one-hour high-rate measured-loss endurance result. The
strict one-hour zero-loss qualification failed. Root cause of the sparse
losses is not established. Do not overwrite passing Gate 1–3 or ILA artifacts.
