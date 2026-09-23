#!/usr/bin/env python3
"""Receive and verify the Project2 v2 continuous UDP stream."""

from __future__ import annotations

import argparse
import json
import socket
import struct
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path

FPGA_DEFAULT = "192.168.1.11"
PC_DEFAULT = "192.168.1.100"
PC_PORT = 6666
MAGIC = b"P2V2"
VERSION = 2
HEADER_BYTES = 16
EXPECTED_PACKET_BYTES = 1024
EXPECTED_DATA_BYTES = EXPECTED_PACKET_BYTES - HEADER_BYTES


@dataclass
class Statistics:
    packets: int = 0
    bytes: int = 0
    first_sequence: int | None = None
    last_sequence: int | None = None
    lost_packets: int = 0
    duplicate_packets: int = 0
    out_of_order_packets: int = 0
    malformed_packets: int = 0
    data_error_packets: int = 0
    data_error_bytes: int = 0


def ping(ip: str) -> bool:
    result = subprocess.run(
        ["ping", "-n", "2", "-w", "1000", ip],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def verify_packet(data: bytes) -> tuple[int, int, int]:
    """Return (sequence, error_bytes, payload_bytes), or raise ValueError."""
    if len(data) < HEADER_BYTES:
        raise ValueError(f"short packet: {len(data)} bytes")
    if data[:4] != MAGIC:
        raise ValueError(f"bad magic: {data[:4].hex()}")

    version = data[4]
    flags = data[5]
    total_length = struct.unpack_from(">H", data, 6)[0]
    sequence = struct.unpack_from(">I", data, 8)[0]
    payload_length = struct.unpack_from(">H", data, 12)[0]
    start_value = data[14]
    reserved = data[15]

    if version != VERSION or flags != 0 or reserved != 0:
        raise ValueError(
            f"bad header: version={version} flags={flags} reserved={reserved}"
        )
    if total_length != len(data):
        raise ValueError(
            f"length mismatch: header={total_length} received={len(data)}"
        )
    if payload_length != len(data) - HEADER_BYTES:
        raise ValueError(
            f"payload length mismatch: header={payload_length} "
            f"received={len(data) - HEADER_BYTES}"
        )

    payload = data[HEADER_BYTES:]
    error_bytes = sum(
        value != ((start_value + index) & 0xFF)
        for index, value in enumerate(payload)
    )
    # The source starts at zero and advances continuously across packet
    # boundaries, so the sequence number also predicts each packet's start.
    if start_value != ((sequence * payload_length) & 0xFF):
        error_bytes += 1
    return sequence, error_bytes, len(payload)


def update_sequence(stats: Statistics, sequence: int) -> None:
    if stats.last_sequence is None:
        stats.first_sequence = sequence
        stats.last_sequence = sequence
        return

    expected = (stats.last_sequence + 1) & 0xFFFFFFFF
    delta = (sequence - expected) & 0xFFFFFFFF
    if delta == 0:
        stats.last_sequence = sequence
    elif sequence == stats.last_sequence:
        stats.duplicate_packets += 1
    elif delta < 0x80000000:
        stats.lost_packets += delta
        stats.last_sequence = sequence
    else:
        stats.out_of_order_packets += 1


def print_status(stats: Statistics, elapsed: float, prefix: str = "STAT") -> None:
    mbps = (stats.bytes * 8 / elapsed / 1_000_000) if elapsed > 0 else 0.0
    print(
        f"{prefix}: time={elapsed:7.2f}s packets={stats.packets:8d} "
        f"rate={mbps:7.3f} Mb/s lost={stats.lost_packets} "
        f"duplicate={stats.duplicate_packets} "
        f"out_of_order={stats.out_of_order_packets} "
        f"malformed={stats.malformed_packets} "
        f"data_error_packets={stats.data_error_packets} "
        f"data_error_bytes={stats.data_error_bytes}"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fpga-ip", default=FPGA_DEFAULT)
    parser.add_argument("--pc-ip", default=PC_DEFAULT)
    parser.add_argument("--duration", type=float, default=30.0)
    parser.add_argument("--report-interval", type=float, default=1.0)
    parser.add_argument("--output", type=Path, help="optional JSON result path")
    args = parser.parse_args()

    if args.duration <= 0 or args.report_interval <= 0:
        parser.error("duration and report interval must be positive")

    print(f"Pinging FPGA {args.fpga_ip} to establish ARP state ...")
    if not ping(args.fpga_ip):
        print("FAIL: ping failed; check bitstream, cable, link and static IP.")
        return 1
    print("PASS: ICMP echo reply received")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
    sock.bind((args.pc_ip, PC_PORT))
    sock.settimeout(0.25)

    stats = Statistics()
    start = time.monotonic()
    deadline = start + args.duration
    next_report = start + args.report_interval
    print(
        f"Receiving {EXPECTED_PACKET_BYTES}-byte v2 packets on "
        f"{args.pc_ip}:{PC_PORT} for {args.duration:g} s ..."
    )

    while time.monotonic() < deadline:
        try:
            data, _peer = sock.recvfrom(65535)
        except socket.timeout:
            data = None

        now = time.monotonic()
        if data is not None:
            stats.bytes += len(data)
            try:
                sequence, error_bytes, payload_bytes = verify_packet(data)
            except ValueError as exc:
                stats.malformed_packets += 1
                if stats.malformed_packets <= 3:
                    print(f"MALFORMED: {exc}")
            else:
                stats.packets += 1
                update_sequence(stats, sequence)
                if error_bytes:
                    stats.data_error_packets += 1
                    stats.data_error_bytes += error_bytes
                    if stats.data_error_packets <= 3:
                        print(
                            f"DATA ERROR: sequence={sequence} "
                            f"bad_bytes={error_bytes}/{payload_bytes}"
                        )

        if now >= next_report:
            print_status(stats, now - start)
            next_report += args.report_interval

    elapsed = time.monotonic() - start
    print_status(stats, elapsed, "FINAL")

    result = asdict(stats)
    result.update(
        {
            "duration_seconds": elapsed,
            "udp_mbps": stats.bytes * 8 / elapsed / 1_000_000,
            "passed": False,
        }
    )
    passed = (
        stats.packets > 0
        and stats.lost_packets == 0
        and stats.duplicate_packets == 0
        and stats.out_of_order_packets == 0
        and stats.malformed_packets == 0
        and stats.data_error_packets == 0
        and stats.data_error_bytes == 0
    )
    result["passed"] = passed

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(f"JSON result written to {args.output}")

    if passed:
        print("V2 STREAM TEST PASSED")
        return 0

    print("V2 STREAM TEST FAILED")
    return 2


if __name__ == "__main__":
    sys.exit(main())
