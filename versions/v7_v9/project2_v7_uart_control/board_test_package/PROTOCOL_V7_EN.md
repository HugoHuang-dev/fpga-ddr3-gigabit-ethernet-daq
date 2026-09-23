# Project2 V7 UART control protocol

## Frame format

V7 reuses the verified Project1 frame and CRC definition:

```text
A5 5A | TYPE | SEQ | LEN | PAYLOAD[LEN] | CRC_LO | CRC_HI
```

- UART: 115200 baud, 8 data bits, no parity, 1 stop bit, no flow control.
- CRC: CRC-16/MODBUS, initial value `0xFFFF`, reflected polynomial `0xA001`, no final XOR.
- CRC coverage: `TYPE | SEQ | LEN | PAYLOAD`; the two header bytes and transmitted CRC are excluded.
- CRC byte order: low byte first, then high byte.
- A valid reply uses `TYPE = request TYPE | 0x80` and echoes `SEQ`.
- A request with an invalid CRC is silently discarded and increments the UART CRC-error counter.

## Result codes

Every ordinary reply contains one result byte.

| Code | Meaning |
| ---: | --- |
| `00` | Command accepted |
| `01` | Invalid payload length |
| `02` | Invalid value |
| `03` | Busy; stop and drain the pipeline before changing this setting |
| `04` | Unsupported command or source |

## Commands

| Command | TYPE | Payload | Rules |
| --- | ---: | --- | --- |
| START | `03` | none | Starts the selected source. A finite run resets its per-run accepted-word count. |
| STOP | `04` | none | Stops production immediately; already complete DDR bursts continue draining to UDP. A partial ingress burst is discarded after complete bursts have drained. |
| SOURCE_SELECT | `10` | `SOURCE[7:0]` | `00=PRBS16`. Other values are reserved and return `04`. Only accepted while stopped. |
| SET_RATE | `11` | `WORDS_PER_SECOND[31:0]`, big-endian | `0` selects the V6-compatible maximum rate. Valid non-zero range is 1–125,000,000 accepted 16-bit words/s. Only accepted while stopped. |
| SET_PACKET_LENGTH | `12` | `BYTES[15:0]`, big-endian | Valid values are 256, 512 and 1024. One 1024-byte DDR burst is divided into 4, 2 or 1 UDP packets. Only accepted while stopped and completely drained. |
| SET_MODE | `13` | `MODE[7:0] | WORD_COUNT[31:0]` | `MODE=0` continuous. `MODE=1` finite; count must be non-zero and a multiple of 512 words so no partial DDR burst remains. Only accepted while stopped. |
| CLEAR_COUNTERS | `14` | none | Clears source, packet-sequence and diagnostic counters. Only accepted while stopped and completely drained. It also restores the PRBS seed. |
| READ_STATUS | `15` | none | Returns the atomic status payload below. |

`SET_RATE` limits source production; FIFO and DDR backpressure can reduce the achieved rate. It is not a promise that Ethernet will transmit at the requested rate.

## READ_STATUS payload (`TYPE=95`, `LEN=61`)

All multibyte fields are big-endian.

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 1 | Result (`00`) |
| 1 | 1 | Control version (`07`) |
| 2 | 1 | Flags: bit0 run enable, bit1 finite done, bit2 finite mode, bit3 MIG calibrated, bit4 ring started, bit5 ring full, bit6 fatal |
| 3 | 1 | Selected source |
| 4 | 4 | Configured words/s (`0` means maximum) |
| 8 | 2 | UDP payload bytes |
| 10 | 1 | Mode (`0` continuous, `1` finite) |
| 11 | 4 | Finite target words |
| 15 | 4 | Words accepted in the current run |
| 19 | 2 | Ingress FIFO level in 16-bit words |
| 21 | 4 | DDR ring occupancy in bytes |
| 25 | 4 | UDP packet sequence |
| 29 | 4 | Ingress overflow count |
| 33 | 4 | Ingress underflow count |
| 37 | 4 | DDR ring overflow count |
| 41 | 4 | DDR ring underflow count |
| 45 | 4 | TX FIFO overflow count |
| 49 | 4 | TX FIFO underflow count |
| 53 | 4 | UART CRC-error count |
| 57 | 4 | Rejected-command count |

The UI-clock fields are captured atomically by a request/acknowledge toggle bridge before the response is assembled in the 125 MHz UART/control domain.

## Packet data format

V7 UDP packets keep the 24-byte metadata layout but identify themselves as `P2V7`, version `07`. Header offsets 6–7 and 12–13 report the dynamic full packet and payload lengths. The PRBS payload remains continuous across the 256/512/1024-byte segmentation of each DDR burst.
