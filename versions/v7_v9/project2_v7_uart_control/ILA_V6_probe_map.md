# V6 ILA probe map

The ILA clock is the DDR UI clock and the capture depth is 2048 samples.

| Probe | Signal | Width | Purpose |
|---:|---|---:|---|
| 0-1 | `init_calib_complete`, `ring_started` | 1 each | Bring-up state |
| 2 | `ingress_level_words` | 12 | 16-bit words buffered at the acquisition input |
| 3-4 | `source_run`, `ingress_has_burst` | 1 each | Ingress high/low-water gate and full-burst eligibility |
| 5-6 | `ingress_overflow_count`, `ingress_underflow_count` | 32 each | Input FIFO fault counters |
| 7-10 | `ingress_drain_busy`, write/read in-flight, `drain_active` | 1 each | Three-stage pipeline concurrency |
| 11-15 | ring pointers, occupancy, committed/released totals | 32 each | DDR ring accounting |
| 16-18 | TX FIFO bytes, packets, burst space | 14/4/1 | Egress capacity |
| 19-20 | packet done and sequence | 1/32 | UDP progress |
| 21-24 | ring full/empty and write/read stalls | 1/1/32/32 | Watermark behavior |
| 25-28 | ring and TX overflow/underflow counters | 32 each | Pipeline fault counters |
| 29 | `fatal_error` | 1 | AXI/ADMA/framing fatal status |
| 30-38 | AXI B/AR/R/AW/W activity and TX commit | 1 each | Bus-level correlation |

For the first board run, use **Run trigger immediate** while traffic is active. A healthy
capture should show `write_inflight` overlapping `read_inflight` or packet activity,
DDR occupancy cycling between the configured 64 KiB and 16 KiB watermarks, and all
overflow/underflow counters remaining zero.
