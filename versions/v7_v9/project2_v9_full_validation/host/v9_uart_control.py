#!/usr/bin/env python3
"""Build, send and decode Project2 V9 UART control frames."""

from __future__ import annotations

import argparse
import struct
import sys
import time


COMMANDS = {
    "start": 0x03,
    "stop": 0x04,
    "source": 0x10,
    "rate": 0x11,
    "packet-length": 0x12,
    "mode": 0x13,
    "clear": 0x14,
    "status": 0x15,
}

RESULTS = {
    0: "OK",
    1: "BAD_LENGTH",
    2: "BAD_VALUE",
    3: "BUSY",
    4: "UNSUPPORTED",
}


def crc16_modbus(data: bytes) -> int:
    crc = 0xFFFF
    for value in data:
        crc ^= value
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc


def build_frame(command_type: int, sequence: int, payload: bytes = b"") -> bytes:
    body = bytes((command_type, sequence, len(payload))) + payload
    crc = crc16_modbus(body)
    return b"\xA5\x5A" + body + struct.pack("<H", crc)


def parse_frame(frame: bytes) -> tuple[int, int, bytes]:
    if len(frame) < 7 or frame[:2] != b"\xA5\x5A":
        raise ValueError("bad frame header")
    length = frame[4]
    expected = 7 + length
    if len(frame) != expected:
        raise ValueError(f"bad frame length: received {len(frame)}, expected {expected}")
    received_crc = struct.unpack_from("<H", frame, 5 + length)[0]
    calculated_crc = crc16_modbus(frame[2 : 5 + length])
    if received_crc != calculated_crc:
        raise ValueError(
            f"bad CRC: received 0x{received_crc:04X}, expected 0x{calculated_crc:04X}"
        )
    return frame[2], frame[3], frame[5 : 5 + length]


def command_payload(args: argparse.Namespace) -> bytes:
    if args.command in {"start", "stop", "clear", "status"}:
        return b""
    if args.command == "source":
        return bytes((args.value,))
    if args.command == "rate":
        return struct.pack(">I", args.value)
    if args.command == "packet-length":
        return struct.pack(">H", args.value)
    if args.command == "mode":
        mode = 0 if args.mode_name == "continuous" else 1
        return bytes((mode,)) + struct.pack(">I", args.words)
    raise AssertionError(args.command)


def read_frame(serial_port, timeout: float) -> bytes:
    deadline = time.monotonic() + timeout
    state = 0
    while time.monotonic() < deadline:
        byte = serial_port.read(1)
        if not byte:
            continue
        if state == 0:
            state = 1 if byte == b"\xA5" else 0
        elif byte == b"\x5A":
            header = serial_port.read(3)
            if len(header) != 3:
                break
            length = header[2]
            tail = serial_port.read(length + 2)
            if len(tail) != length + 2:
                break
            return b"\xA5\x5A" + header + tail
        else:
            state = 1 if byte == b"\xA5" else 0
    raise TimeoutError("timed out waiting for a complete V9 reply")


def u16(data: bytes, offset: int) -> int:
    return struct.unpack_from(">H", data, offset)[0]


def u32(data: bytes, offset: int) -> int:
    return struct.unpack_from(">I", data, offset)[0]


def decode_reply(frame: bytes) -> str:
    frame_type, sequence, payload = parse_frame(frame)
    if not payload:
        return f"TYPE=0x{frame_type:02X} SEQ={sequence} empty payload"
    result = RESULTS.get(payload[0], f"UNKNOWN_{payload[0]}")
    if frame_type != 0x95 or len(payload) != 74:
        return f"TYPE=0x{frame_type:02X} SEQ={sequence} RESULT={result}"
    if payload[1] != 9:
        raise ValueError(
            f"unexpected status version {payload[1]}; program the V9 bitstream"
        )
    flags = payload[2]
    fields = {
        "result": result,
        "version": payload[1],
        "run_enable": bool(flags & 0x01),
        "finite_done": bool(flags & 0x02),
        "finite_mode": bool(flags & 0x04),
        "mig_calibrated": bool(flags & 0x08),
        "ring_started": bool(flags & 0x10),
        "ring_full": bool(flags & 0x20),
        "fatal": bool(flags & 0x40),
        "source": payload[3],
        "source_name": {0: "deterministic_prbs16", 1: "internal_xadc"}.get(
            payload[3], "unknown"
        ),
        "rate_words_per_sec": u32(payload, 4),
        "packet_length": u16(payload, 8),
        "mode": payload[10],
        "finite_words": u32(payload, 11),
        "run_words": u32(payload, 15),
        "ingress_level_words": u16(payload, 19),
        "occupancy_bytes": u32(payload, 21),
        "packet_sequence": u32(payload, 25),
        "ingress_overflow": u32(payload, 29),
        "ingress_underflow": u32(payload, 33),
        "ring_overflow": u32(payload, 37),
        "ring_underflow": u32(payload, 41),
        "tx_overflow": u32(payload, 45),
        "tx_underflow": u32(payload, 49),
        "uart_crc_errors": u32(payload, 53),
        "command_rejects": u32(payload, 57),
        "xadc_valid_mask": f"0x{payload[61] & 0x0F:X}",
        "xadc_drop_count": u32(payload, 62),
        "xadc_temperature_raw": u16(payload, 66) & 0x0FFF,
        "xadc_vccint_raw": u16(payload, 68) & 0x0FFF,
        "xadc_vccaux_raw": u16(payload, 70) & 0x0FFF,
        "xadc_vccbram_raw": u16(payload, 72) & 0x0FFF,
    }
    fields["xadc_temperature_c"] = (
        fields["xadc_temperature_raw"] * 503.975 / 4096.0 - 273.15
    )
    fields["xadc_vccint_v"] = fields["xadc_vccint_raw"] * 3.0 / 4096.0
    fields["xadc_vccaux_v"] = fields["xadc_vccaux_raw"] * 3.0 / 4096.0
    fields["xadc_vccbram_v"] = fields["xadc_vccbram_raw"] * 3.0 / 4096.0
    return "\n".join(f"{key}: {value}" for key, value in fields.items())


def parser() -> argparse.ArgumentParser:
    def bounded_int(minimum: int, maximum: int):
        def parse(value: str) -> int:
            number = int(value, 0)
            if not minimum <= number <= maximum:
                raise argparse.ArgumentTypeError(
                    f"value must be between {minimum} and {maximum}"
                )
            return number
        return parse

    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--port", help="COM port; omit to print the command frame only")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--timeout", type=float, default=2.0)
    p.add_argument("--seq", type=lambda x: int(x, 0), default=0)
    p.add_argument(
        "--corrupt-crc",
        action="store_true",
        help="invert one transmitted CRC bit for the silent-rejection test",
    )
    p.add_argument(
        "--expect-no-reply",
        action="store_true",
        help="treat a reply timeout as success and any reply as failure",
    )
    sub = p.add_subparsers(dest="command", required=True)
    for name in ("start", "stop", "clear", "status"):
        sub.add_parser(name)
    source = sub.add_parser("source")
    source.add_argument("value", type=bounded_int(0, 255))
    rate = sub.add_parser("rate")
    rate.add_argument("value", type=bounded_int(0, 125_000_000))
    length = sub.add_parser("packet-length")
    length.add_argument("value", type=int, choices=(256, 512, 1024))
    mode = sub.add_parser("mode")
    mode.add_argument("mode_name", choices=("continuous", "finite"))
    mode.add_argument("words", type=int, nargs="?", default=0)
    return p


def main() -> int:
    args = parser().parse_args()
    if args.command == "mode" and args.mode_name == "finite":
        if args.words <= 0 or args.words % 512:
            raise SystemExit("finite word count must be a positive multiple of 512")
    frame = build_frame(COMMANDS[args.command], args.seq & 0xFF, command_payload(args))
    if args.corrupt_crc:
        frame = frame[:-1] + bytes((frame[-1] ^ 0x01,))
    print("TX:", frame.hex(" ").upper())
    if not args.port:
        if args.expect_no_reply:
            raise SystemExit("--expect-no-reply requires --port")
        return 0
    try:
        import serial
    except ImportError as exc:
        raise SystemExit("pyserial is required for --port operation") from exc
    with serial.Serial(args.port, args.baud, timeout=0.05) as port:
        port.reset_input_buffer()
        port.write(frame)
        port.flush()
        try:
            reply = read_frame(port, args.timeout)
        except TimeoutError:
            if args.expect_no_reply:
                print("PASS: no reply received, as expected")
                return 0
            raise SystemExit("timed out waiting for a complete V9 reply")
    if args.expect_no_reply:
        print("RX:", reply.hex(" ").upper())
        raise SystemExit("FAIL: received a reply when silence was expected")
    print("RX:", reply.hex(" ").upper())
    print(decode_reply(reply))
    return 0


if __name__ == "__main__":
    sys.exit(main())
