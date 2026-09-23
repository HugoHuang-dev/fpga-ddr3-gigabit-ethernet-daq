# V6 at 400 Mb/s: Four-Group ILA Capture Guide

## Purpose and fixed setup

This evidence set validates the concurrent pipeline introduced in V6; it does not repeat the V5 ring-buffer captures. The four groups establish:

1. The ingress FIFO's 3 KiB/1 KiB high/low-watermark hysteresis.
2. DDR drain starting at 64 KiB and safe backpressure when the ring is full.
3. Actual overlap between DDR writes and reads.
4. Acceptance of a complete DDR read burst into the TX FIFO, followed by UDP packet transmission.

Use this matching pair:

- [`Project2_V6_400M_USB_Kit/fpga/project2_v6_400m.bit`](Project2_V6_400M_USB_Kit/fpga/project2_v6_400m.bit)
- [`Project2_V6_400M_USB_Kit/fpga/project2_v6_400m.ltx`](Project2_V6_400M_USB_Kit/fpga/project2_v6_400m.ltx)

The ILA uses the DDR UI clock and has a depth of 2048. Set Capture Mode to BASIC, Number of Windows to 1, and Trigger Position to 1024. Remove every condition from the previous group before setting a new trigger; otherwise Vivado may AND them together.

The Windows receiver is unnecessary during ILA captures. The Ethernet cable may stay connected, but do not run packet capture concurrently. After programming the BIT/LTX, press RESET once and wait for `init_calib_complete=1`. Arm the first trigger, then press KEY0 once to start the continuous source. Unless a step explicitly says otherwise, neither RESET nor another KEY0 press is needed between groups.

## Recommended radix

| Signal | Radix |
| --- | --- |
| Single-bit status and handshake signals | Binary |
| `ingress_level_words` | Unsigned Decimal |
| `write_pointer`, `read_pointer`, `occupancy_bytes`, `committed_bytes`, `released_bytes` | Hex |
| `tx_fifo_byte_count`, `tx_fifo_packet_count`, `packet_sequence` | Unsigned Decimal |
| All overflow, underflow, and stall counters | Unsigned Decimal |

Relevant thresholds:

- Ingress high watermark: 1536 words = `0x600` words = 3072 bytes.
- Ingress low watermark: 512 words = `0x200` words = 1024 bytes.
- DDR high watermark: 65,536 bytes = `0x00010000`.
- DDR low watermark: 16,384 bytes = `0x00004000`.
- One DDR burst: 1024 bytes = `0x400`.

## Group 1: Ingress FIFO watermark hysteresis

### 1A: Pause at the high watermark

1. Add only `source_run` to Trigger Setup.
2. Select the falling-edge operator (1→0, usually displayed as F).
3. Click **Run Trigger** and confirm that the ILA is Waiting for Trigger.
4. If the source has not started, press KEY0 once. If it is already running, do not press KEY0 again.
5. At the trigger, check that `source_run` changes from 1 to 0, `ingress_level_words` is near 1536, and `ingress_has_burst=1`. Both `ingress_overflow_count` and `ingress_underflow_count` must be zero.

Save a full-window screenshot as `ila_v6_01a_ingress_high_pause.png`.

### 1B: Resume at the low watermark

1. Without resetting, remove the 1A condition.
2. Keep `source_run` and change the operator to rising edge (0→1).
3. Click **Run Trigger** again.
4. Confirm that `source_run` changes from 0 to 1 when `ingress_level_words` has fallen near 512. Check both ingress error counters again.

Save as `ila_v6_01b_ingress_low_resume.png`. The two transitions must occur at different thresholds; a static zero or one is not sufficient evidence of hysteresis.

## Group 2: DDR drain startup and full-ring backpressure

### 2A: Start draining at the high watermark

1. Remove the previous condition and add only a rising-edge trigger on `drain_active`.
2. Click **Run Trigger** while the source continues running.
3. Confirm `drain_active` changes from 0 to 1 near `occupancy_bytes=0x00010000`. `read_inflight` should follow. Both ring overflow and underflow counters must remain zero.

Save as `ila_v6_02a_ddr_high_start_drain.png`.

### 2B: Apply safe backpressure when the ring fills

The sustained PRBS input rate exceeds the 400 Mb/s UDP output rate. Once `drain_active` first rises, it generally remains asserted during continuous operation. Do not wait for its falling edge: behavioral simulation covers the 16 KiB stop branch.

1. Without resetting, replace the 2A trigger with a rising-edge trigger on `ring_full`.
2. Click **Run Trigger**.
3. Confirm that `ring_full` rises at `occupancy_bytes=0x00040000` (256 KiB), while `drain_active=1` and the read/UDP path continues. `write_stall_cycles` should increase under backpressure, while `ring_overflow_count=0`.

Save as `ila_v6_02b_ring_full_backpressure.png`. Group 2A establishes the 64 KiB drain threshold; group 2B shows that a full ring stops new writes without overwriting unread data. The 16 KiB stop threshold is not reached in this continuously driven board scenario, so the absence of a falling edge is expected.

## Group 3: Concurrent DDR write and read

1. Remove the previous trigger.
2. Add `write_inflight == 1` and `read_inflight == 1`, combined with AND. Set both values to 1 with Binary radix.
3. Click **Run Trigger** and wait until both are asserted simultaneously.
4. At and around the trigger, check for activity on `ingress_drain_busy`, the AXI write channels (`awvalid`, `wvalid`), and the read channels (`arvalid`, `rvalid`, `rlast`). Both pointers and both committed/released byte counters should advance; `fatal_error` must remain zero.

Save as `ila_v6_03_write_read_overlap.png`. Include the Trigger Setup panel to show that the two conditions were ANDed. This overlap is the central V6 distinction from V5. If it does not trigger for an extended period, verify that draining is active and all old conditions were removed before changing any BIT or threshold.

## Group 4: DDR readout through TX FIFO to UDP

### 4A: Commit a complete DDR burst into the TX FIFO

1. Replace the trigger with a rising edge on `tx_burst_committed` and click **Run Trigger**.
2. Verify the `tx_burst_committed` pulse, followed by release of `read_inflight`. `released_bytes` and `read_pointer` should each advance by `0x400` (the pointer may wrap to zero); `occupancy_bytes` should fall by `0x400`.
3. `tx_fifo_packet_count` should rise by one, or remain nonzero and continue changing if transmission overlaps the commit. Both TX overflow and underflow counters must remain zero.

Save as `ila_v6_04a_read_to_tx_fifo.png`.

### 4B: Complete a UDP packet

1. Without resetting, change the trigger to a rising edge on `packet_done`.
2. Click **Run Trigger**.
3. Check the single-cycle `packet_done` pulse and subsequent increment of `packet_sequence`. TX FIFO byte and packet counts should continue changing.
4. Confirm that all six ingress/ring/TX overflow and underflow counters, plus `fatal_error`, remain zero.

Save as `ila_v6_04b_udp_packet_done.png`.

## Completion criteria

V6 ILA validation is complete when the captures jointly show ingress pause/resume at two distinct watermarks; DDR drain beginning at 64 KiB and full-ring backpressure without overflow; `write_inflight=1 && read_inflight=1`; and complete-burst release followed by UDP sequence advancement. All six overflow/underflow counters and `fatal_error` must stay at zero.

There are seven captures (01a, 01b, 02a, 02b, 03, 04a, 04b). Because the 39 probes do not fit on one screen, retain upper and lower views for each capture: 14 screenshots in total. Each screenshot should include the Name/Value columns, waveform, trigger line, and `ILA Status: Idle` at the top. Interpret transitions around the trigger line, not just the single value beneath the mouse cursor.
