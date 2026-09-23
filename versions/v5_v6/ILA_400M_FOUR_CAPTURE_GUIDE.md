# Project 2 V5: Four ILA Evidence Captures at 400 Mb/s

## Why use the 400 Mb/s image?

The 400 Mb/s image passed the strict 60-second zero-loss board test and retains the same 39 ILA probes as the MAX image. It leaves more headroom for the host and link while still exercising continuous DDR3 writes, reads, TX FIFO operation, UDP packetization, and ring wraparound. Use this image for all four captures; another one-hour run is unnecessary.

Program the matching pair below. Do not combine the MAX `.ltx` with the 400M `.bit`:

- BIT: [`project2_v5_400m/project2_v5_top.bit`](project2_v5_400m/project2_v5_top.bit)
- LTX: [`project2_v5_400m/project2_v5_top.ltx`](project2_v5_400m/project2_v5_top.ltx)

## Setup

1. In Vivado Hardware Manager, program the device with the 400M BIT and matching LTX.
2. Press RESET once and wait for MIG calibration.
3. Set the ILA trigger position near the middle of the capture window, preferably 1024/2048.
4. Display pointers and cumulative byte counts as Hex or Unsigned; display `occupancy_bytes`, FIFO counts, packet sequence, and stall cycles as Unsigned. Keep single-bit signals in Binary.
5. Press KEY0 once to start the continuous stream. Do not press it again between captures. Press RESET after all four groups are complete.

The PC receiver need not run during ILA capture. The FPGA continues transmitting, so the ILA can be rearmed repeatedly during one board run.

## Group 1: DDR3 write commit

1. Add `bvalid == 1` in Trigger Setup.
2. Click **Run Trigger** (the ordinary triangle), not Immediate Trigger.
3. Around the trigger, confirm `bvalid=1`, `bready=1`, and `bresp=0`. Then `committed_bytes` and `write_pointer` should each advance by 1024, with a corresponding increase in `occupancy_bytes`.
4. Save the screenshot as `ila_400m_01_write_commit.png`.

## Group 2: DDR3 readout and ring-slot release

1. Remove the previous trigger.
2. Set `tx_burst_committed == 1` and click **Run Trigger**.
3. Around the trigger, confirm `user_rd_last=1` and `tx_burst_committed=1`. Then `released_bytes` and `read_pointer` should each advance by 1024, with a corresponding decrease in `occupancy_bytes`.
4. Save as `ila_400m_02_read_release.png`.

## Group 3: Ring write-pointer wraparound

1. Confirm that the stream is running and `write_pointer` is nonzero. If it is momentarily zero, wait for the next refresh before arming.
2. Remove the previous trigger and set `write_pointer == 0`.
3. Click **Run Trigger**. At 400 Mb/s the write pointer wraps approximately every 5 ms.
4. Verify that the pointer was at the end of the ring immediately before returning to zero. `fatal_error` and all four ADMA FIFO error indicators must remain zero.
5. Save as `ila_400m_03_ring_wrap.png`.

If the condition catches the initial zero immediately upon arming, restart the stream, wait until the pointer is nonzero, and rearm.

## Group 4: Stable operating state

1. Remove all Trigger Setup conditions and let the board run for several seconds.
2. Click **Run Trigger Immediate** (the double-arrow button).
3. Confirm `init_calib_complete=1`, `ring_started=1`, `fatal_error=0`, and all four ADMA FIFO errors (`wr_cmd_fifo_err`, `wr_data_fifo_err`, `rd_cmd_fifo_err`, `rd_data_fifo_err`) equal zero. `committed_bytes`, `released_bytes`, and `packet_sequence` should have continued advancing.
4. Save as `ila_400m_04_stable_state.png`.

## Completion and evidence

After saving the four captures, press RESET once. Retain the original Vivado ILA waveform files or CSV exports where available, as well as full-window screenshots that show signal names, values, waveforms, and trigger positions.

All four groups were captured and checked on September 22, 2026:

- [`evidence/ila_400m_01_write_commit_a.png`](evidence/ila_400m_01_write_commit_a.png) and `_b.png`
- [`evidence/ila_400m_02_read_release_a.png`](evidence/ila_400m_02_read_release_a.png) and `_b.png`
- [`evidence/ila_400m_03_ring_wrap_a.png`](evidence/ila_400m_03_ring_wrap_a.png) and `_b.png`
- [`evidence/ila_400m_04_stable_state_a.png`](evidence/ila_400m_04_stable_state_a.png) and `_b.png`

Together these captures cover write commit, complete-burst release, 256 KiB ring wraparound, and steady operation without internal errors. The planned V5 ILA evidence set is complete.
