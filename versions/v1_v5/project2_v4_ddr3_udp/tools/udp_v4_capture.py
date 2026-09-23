#!/usr/bin/env python3
"""Receive and verify the finite Project2 v4 DDR3-to-UDP transfer."""

from __future__ import annotations

import argparse
import json
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path

FPGA_DEFAULT = "192.168.1.11"
PC_DEFAULT = "192.168.1.100"
PC_PORT = 6666
MAGIC = b"P2V4"
VERSION = 4
HEADER_BYTES = 16
DATA_BYTES = 1024
PACKET_BYTES = HEADER_BYTES + DATA_BYTES
TOTAL_PACKETS = 64
PRBS_SEED = 0xACE1


def prbs_next(value: int) -> int:
    feedback = ((value >> 15) ^ (value >> 13) ^ (value >> 12) ^ (value >> 10)) & 1
    return ((value << 1) & 0xFFFF) | feedback


def expected_stream() -> bytes:
    output = bytearray()
    value = PRBS_SEED
    for _ in range(TOTAL_PACKETS * DATA_BYTES // 2):
        output.append(value & 0xFF)
        output.append((value >> 8) & 0xFF)
        value = prbs_next(value)
    return bytes(output)


def ping(ip: str) -> bool:
    result = subprocess.run(
        ["ping", "-n", "2", "-w", "1000", ip],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fpga-ip", default=FPGA_DEFAULT)
    parser.add_argument("--pc-ip", default=PC_DEFAULT)
    parser.add_argument("--first-timeout", type=float, default=20.0)
    parser.add_argument("--idle-timeout", type=float, default=3.0)
    parser.add_argument("--output", type=Path, default=Path("evidence/v4_result.json"))
    args = parser.parse_args()

    print(f"Checking FPGA reachability at {args.fpga_ip} ...")
    if not ping(args.fpga_ip):
        print("FAIL: ping failed; check bitstream, Ethernet link and static IP.")
        return 1
    print("PASS: FPGA ping reply received")

    expected = expected_stream()
    received: dict[int, bytes] = {}
    malformed = 0
    duplicates = 0
    out_of_order = 0
    data_error_packets = 0
    data_error_bytes = 0
    arrival_order: list[int] = []

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
    sock.bind((args.pc_ip, PC_PORT))
    sock.settimeout(0.25)

    print(f"ARMED: listening on {args.pc_ip}:{PC_PORT}")
    print("Press FPGA KEY0 once to start the finite v4 transfer (do not press RESET).")
    start = time.monotonic()
    first_deadline = start + args.first_timeout
    last_packet_time: float | None = None

    while True:
        now = time.monotonic()
        if last_packet_time is None and now >= first_deadline:
            print("FAIL: no v4 packet received before first-packet timeout.")
            break
        if last_packet_time is not None and now - last_packet_time >= args.idle_timeout:
            break
        if len(received) == TOTAL_PACKETS:
            break

        try:
            data, peer = sock.recvfrom(65535)
        except socket.timeout:
            continue

        if peer[0] != args.fpga_ip:
            continue
        last_packet_time = time.monotonic()

        try:
            if len(data) != PACKET_BYTES:
                raise ValueError(f"length={len(data)}, expected={PACKET_BYTES}")
            if data[:4] != MAGIC:
                raise ValueError(f"magic={data[:4]!r}")
            version, flags, total_length = struct.unpack_from(">BBH", data, 4)
            sequence = struct.unpack_from(">I", data, 8)[0]
            data_length, total_packets = struct.unpack_from(">HH", data, 12)
            if version != VERSION:
                raise ValueError(f"version={version}")
            if total_length != PACKET_BYTES or data_length != DATA_BYTES:
                raise ValueError("header length mismatch")
            if total_packets != TOTAL_PACKETS:
                raise ValueError(f"total_packets={total_packets}")
            if sequence >= TOTAL_PACKETS:
                raise ValueError(f"sequence={sequence}")
            if flags != (1 if sequence == TOTAL_PACKETS - 1 else 0):
                raise ValueError(f"flags={flags}")
        except ValueError as exc:
            malformed += 1
            if malformed <= 3:
                print(f"MALFORMED: {exc}")
            continue

        if sequence in received:
            duplicates += 1
            continue
        if arrival_order and sequence != arrival_order[-1] + 1:
            out_of_order += 1
        arrival_order.append(sequence)
        payload = data[HEADER_BYTES:]
        received[sequence] = payload

        offset = sequence * DATA_BYTES
        reference = expected[offset : offset + DATA_BYTES]
        errors = sum(a != b for a, b in zip(payload, reference))
        if errors:
            data_error_packets += 1
            data_error_bytes += errors
            print(f"DATA ERROR: packet={sequence} bad_bytes={errors}/{DATA_BYTES}")

        print(
            f"RX: packet={sequence:02d}/{TOTAL_PACKETS-1} "
            f"received={len(received):02d}/{TOTAL_PACKETS} errors={errors}"
        )

    elapsed = time.monotonic() - start
    missing = [seq for seq in range(TOTAL_PACKETS) if seq not in received]
    payload_bytes = len(received) * DATA_BYTES
    udp_bytes = len(received) * PACKET_BYTES
    passed = (
        len(received) == TOTAL_PACKETS
        and not missing
        and malformed == 0
        and duplicates == 0
        and out_of_order == 0
        and data_error_packets == 0
        and data_error_bytes == 0
    )

    result = {
        "passed": passed,
        "packets_received": len(received),
        "packets_expected": TOTAL_PACKETS,
        "missing_sequences": missing,
        "duplicates": duplicates,
        "out_of_order": out_of_order,
        "malformed": malformed,
        "data_error_packets": data_error_packets,
        "data_error_bytes": data_error_bytes,
        "payload_bytes": payload_bytes,
        "udp_bytes": udp_bytes,
        "elapsed_seconds": elapsed,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")

    print(
        f"FINAL: packets={len(received)}/{TOTAL_PACKETS} missing={len(missing)} "
        f"duplicate={duplicates} out_of_order={out_of_order} malformed={malformed} "
        f"data_error_packets={data_error_packets} data_error_bytes={data_error_bytes} "
        f"payload_bytes={payload_bytes}"
    )
    print(f"JSON result written to {args.output}")
    if passed:
        print("V4 FINITE DDR3-TO-UDP TEST PASSED")
        return 0
    print("V4 FINITE DDR3-TO-UDP TEST FAILED")
    return 2


if __name__ == "__main__":
    sys.exit(main())
