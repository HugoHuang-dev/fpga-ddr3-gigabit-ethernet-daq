# Project 2 V8 Protocol

## 1. UART frame

UART operates at 115200 baud, 8N1, without flow control. Multibyte integers are big-endian; the transmitted CRC is low byte first.

```text
A5 5A | TYPE | SEQ | LEN | PAYLOAD[LEN] | CRC16_LO | CRC16_HI
```

CRC-16/MODBUS starts at `0xFFFF` and covers TYPE through the last payload byte, excluding the `A5 5A` sync bytes.

| Command | TYPE | Payload | Behavior |
| --- | --- | --- | --- |
| START | `0x03` | None | Start the selected source |
| STOP | `0x04` | None | Stop production and drain complete bursts |
| SOURCE_SELECT | `0x10` | 1 byte | `0=PRBS16`, `1=internal XADC` |
| SET_RATE | `0x11` | u32 | Source 0 only; zero selects maximum rate |
| SET_PACKET_LENGTH | `0x12` | u16 | Data portion of 256, 512, or 1024 bytes |
| SET_MODE | `0x13` | mode + u32 | `0=continuous`; `1=finite` with a positive word count divisible by 512 |
| CLEAR_COUNTERS | `0x14` | None | Clear run and error counters |
| READ_STATUS | `0x15` | None | Return the 74-byte V8 status payload |

An ordinary reply has TYPE = request TYPE + `0x80` and a one-byte result: `0=OK`, `1=BAD_LENGTH`, `2=BAD_VALUE`, `3=BUSY`, `4=UNSUPPORTED`. Changes to source, rate, packet length, or mode while running return BUSY. A frame with an invalid CRC is silently dropped and increments `uart_crc_errors`.

## 2. READ_STATUS payload

The reply TYPE is `0x95`; payload length is exactly 74 bytes.

| Offset | Length | Field |
| ---: | ---: | --- |
| 0 | 1 | result |
| 1 | 1 | version, fixed at 8 |
| 2 | 1 | flags: bit 0 run, bit 1 finite_done, bit 2 finite_mode, bit 3 MIG calibrated, bit 4 ring_started, bit 5 ring_full, bit 6 fatal |
| 3 | 1 | source: 0 PRBS16, 1 internal XADC |
| 4 | 4 | rate_words_per_sec; applies only to source 0 |
| 8 | 2 | packet_length |
| 10 | 1 | mode |
| 11 | 4 | finite_words |
| 15 | 4 | run_words |
| 19 | 2 | ingress_level_words |
| 21 | 4 | DDR occupancy_bytes |
| 25 | 4 | packet_sequence |
| 29 | 4 | ingress_overflow |
| 33 | 4 | ingress_underflow |
| 37 | 4 | ring_overflow |
| 41 | 4 | ring_underflow |
| 45 | 4 | tx_overflow |
| 49 | 4 | tx_underflow |
| 53 | 4 | uart_crc_errors |
| 57 | 4 | command_rejects |
| 61 | 1 | xadc_valid_mask; low four bits should be `0xF` |
| 62 | 4 | xadc_drop_count |
| 66 | 2 | temperature_raw; low 12 bits valid |
| 68 | 2 | vccint_raw; low 12 bits valid |
| 70 | 2 | vccaux_raw; low 12 bits valid |
| 72 | 2 | vccbram_raw; low 12 bits valid |

Conversions are for display: `temperature_C = raw * 503.975 / 4096 - 273.15`; for each voltage channel, `voltage_V = raw * 3.0 / 4096`.

## 3. P2V8 UDP datagram

A datagram contains a 24-byte header and 256, 512, or 1024 data bytes. Multibyte header fields are big-endian; individual acquisition records are 16-bit little-endian.

| Offset | Length | Field |
| ---: | ---: | --- |
| 0 | 4 | ASCII `P2V8` |
| 4 | 1 | version = 8 |
| 5 | 1 | source ID |
| 6 | 2 | complete UDP datagram length |
| 8 | 4 | packet sequence |
| 12 | 2 | data length |
| 14 | 2 | header length = 24 |
| 16 | 4 | low 32 bits of DDR committed bytes |
| 20 | 4 | DDR occupancy bytes |

Source 0 retains the V7 PRBS16 data format. Each source-1 record is:

```text
bits 15:14  channel: 0=temperature, 1=VCCINT, 2=VCCAUX, 3=VCCBRAM
bits 13:12  reserved, must be zero
bits 11:0   raw XADC code
```

The channel order repeats 0, 1, 2, 3. The PC receiver checks P2V8 metadata, packet sequence, reserved bits, channel order, per-channel counts, and each channel's raw minimum and maximum.
