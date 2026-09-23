# Project2 V9 protocol

## UDP payload envelope

All multi-byte header values are big-endian. The acquisition payload remains a
sequence of 16-bit little-endian words.

| Offset | Size | Field | Meaning |
| ---: | ---: | --- | --- |
| 0 | 4 | magic | ASCII `P2V9` |
| 4 | 1 | version | `9` |
| 5 | 1 | source | `0` PRBS16, `1` internal XADC |
| 6 | 2 | packet bytes | header + payload |
| 8 | 4 | packet sequence | increments once per UDP packet |
| 12 | 2 | payload bytes | 256, 512 or 1024 |
| 14 | 2 | header bytes | fixed `32` |
| 16 | 4 | committed bytes low | low 32 bits of DDR committed-byte counter |
| 20 | 4 | occupancy bytes | DDR ring occupancy snapshot |
| 24 | 8 | first word index | first 16-bit acquisition record carried by this packet |
| 32 | N | payload | acquisition words |

`packet_sequence` and `first_word_index` reset on CLEAR_COUNTERS. For every
accepted packet:

```text
next_packet_sequence = packet_sequence + 1
next_first_word_index = first_word_index + payload_bytes / 2
```

The two checks are intentionally independent. A packet can have the expected
sequence but still carry the wrong sample range; V9 must detect that case.

## Source 0 payload

Source 0 is the deterministic PRBS16 stream seeded with `0xACE1`, using taps
15, 13, 12 and 10. Each PRBS word is serialized low byte then high byte. The PC
uses `first_word_index` to address the reference period and compares every
payload byte, so checking remains correct across packet-size changes and
32-bit packet-sequence wrap.

## Source 1 payload

Each XADC record is a 16-bit little-endian word:

```text
[15:14] channel: 0 temperature, 1 VCCINT, 2 VCCAUX, 3 VCCBRAM
[13:12] reserved: must be 0
[11:0]  raw XADC value
```

Records must repeat in strict `0,1,2,3` order. `first_word_index` counts records
across the entire run; it does not reset at channel 0 boundaries.

## UART control

UART framing, CRC16, command IDs, result codes and command payloads remain
compatible with V8. READ_STATUS reports version 9; source selection remains
`0` or `1`. The host must send CLEAR_COUNTERS after configuration and before
START so packet sequence, sample index and error counters share a known origin.

## Long-run storage rule

The receiver validates every byte online but does not save the complete stream.
Only the JSON summary, bounded error detail and explicitly configured datagram
prefix samples are persisted. Each fragment starts at header byte 0, so a
256-byte fragment contains the 32-byte P2V9 header and the first 224 payload
bytes. The JSON has the run's source ID; each manifest entry records packet
sequence, first word index, copied byte count, CRC32 and fragment filename.
