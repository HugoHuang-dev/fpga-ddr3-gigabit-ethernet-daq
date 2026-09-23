#!/usr/bin/env python3
"""Monitor and verify the continuous Project2 v5 DDR3 ring-buffer stream."""

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
MAGIC = b"P2V5"
VERSION = 5
HEADER_BYTES = 24
DATA_BYTES = 1024
PACKET_BYTES = HEADER_BYTES + DATA_BYTES
RING_BYTES = 256 * 1024
PRBS_SEED = 0xACE1
PRBS_WORD_PERIOD = 65535
PRBS_BYTE_PERIOD = PRBS_WORD_PERIOD * 2
MONITOR_VERSION = 2


def prbs_next(value: int) -> int:
    feedback = ((value >> 15) ^ (value >> 13) ^ (value >> 12) ^ (value >> 10)) & 1
    return ((value << 1) & 0xFFFF) | feedback


def build_prbs_period() -> bytes:
    """Build the complete maximal-length PRBS period once at startup."""
    output = bytearray()
    value = PRBS_SEED
    for _ in range(PRBS_WORD_PERIOD):
        output.append(value & 0xFF)
        output.append((value >> 8) & 0xFF)
        value = prbs_next(value)
    if value != PRBS_SEED:
        raise RuntimeError("PRBS generator did not return to its seed")
    return bytes(output)


def expected_payload(period: bytes, sequence: int) -> bytes:
    """Look up one packet directly; runtime is independent of sequence gaps."""
    offset = ((sequence & 0xFFFFFFFF) * DATA_BYTES) % PRBS_BYTE_PERIOD
    end = offset + DATA_BYTES
    if end <= PRBS_BYTE_PERIOD:
        return period[offset:end]
    split = PRBS_BYTE_PERIOD - offset
    return period[offset:] + period[: DATA_BYTES - split]


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
    parser.add_argument("--duration", type=float, default=60.0)
    parser.add_argument("--first-timeout", type=float, default=20.0)
    parser.add_argument("--rcvbuf-mb", type=int, default=32)
    parser.add_argument("--output", type=Path, default=Path("evidence/v5_result.json"))
    args = parser.parse_args()

    if args.duration <= 0:
        parser.error("--duration must be positive")
    if args.rcvbuf_mb <= 0:
        parser.error("--rcvbuf-mb must be positive")

    print(f"Project2 v5 PC monitor v{MONITOR_VERSION}")
    print("Preparing direct-index PRBS reference table ...")
    prbs_period = build_prbs_period()

    print(f"Checking FPGA reachability at {args.fpga_ip} ...")
    if not ping(args.fpga_ip):
        print("FAIL: ping failed; check bitstream, Ethernet link and static IP.")
        return 1
    print("PASS: FPGA ping reply received")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    requested_rcvbuf = args.rcvbuf_mb * 1024 * 1024
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, requested_rcvbuf)
    actual_rcvbuf = sock.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF)
    sock.bind((args.pc_ip, PC_PORT))
    sock.settimeout(0.25)

    print(f"ARMED: listening on {args.pc_ip}:{PC_PORT}")
    print(
        f"Socket receive buffer: requested={requested_rcvbuf} bytes "
        f"actual={actual_rcvbuf} bytes"
    )
    print("Press FPGA KEY0 once to start v5; press RESET after the monitor finishes.")

    first_deadline = time.monotonic() + args.first_timeout
    measurement_start: float | None = None
    expected_sequence = 0
    packets = 0
    payload_bytes = 0
    missing = 0
    duplicates = 0
    out_of_order = 0
    malformed = 0
    metadata_errors = 0
    data_error_packets = 0
    data_error_bytes = 0
    max_occupancy = 0
    last_committed = 0
    last_print = time.monotonic()

    rx_buffer = bytearray(65535)
    rx_view = memoryview(rx_buffer)

    while True:
        now = time.monotonic()
        if measurement_start is None:
            if now >= first_deadline:
                print("FAIL: no v5 packet received before first-packet timeout.")
                break
        elif now - measurement_start >= args.duration:
            break

        try:
            data_length_received, peer = sock.recvfrom_into(rx_buffer)
        except socket.timeout:
            continue
        if peer[0] != args.fpga_ip:
            continue

        try:
            if data_length_received != PACKET_BYTES:
                raise ValueError(
                    f"length={data_length_received}, expected={PACKET_BYTES}"
                )
            if rx_buffer[:4] != MAGIC:
                raise ValueError(f"magic={bytes(rx_buffer[:4])!r}")
            version, flags, total_length = struct.unpack_from(">BBH", rx_buffer, 4)
            sequence, data_length, header_length, committed, occupancy = struct.unpack_from(
                ">IHHII", rx_buffer, 8
            )
            if version != VERSION or flags != 0:
                raise ValueError(f"version={version}, flags={flags}")
            if (total_length, data_length, header_length) != (
                PACKET_BYTES,
                DATA_BYTES,
                HEADER_BYTES,
            ):
                raise ValueError("header length mismatch")
        except (ValueError, struct.error) as exc:
            malformed += 1
            if malformed <= 3:
                print(f"MALFORMED: {exc}")
            continue

        if measurement_start is None:
            measurement_start = time.monotonic()
            last_print = measurement_start

        sequence_delta = (sequence - expected_sequence) & 0xFFFFFFFF
        if sequence_delta == 0:
            pass
        elif sequence_delta < 0x80000000:
            missing += sequence_delta
        elif sequence == ((expected_sequence - 1) & 0xFFFFFFFF):
            duplicates += 1
            continue
        else:
            out_of_order += 1
            continue

        reference = expected_payload(prbs_period, sequence)
        expected_sequence = (sequence + 1) & 0xFFFFFFFF
        payload = rx_view[HEADER_BYTES:PACKET_BYTES]
        errors = 0
        if payload != reference:
            errors = sum(a != b for a, b in zip(payload, reference))
        if errors:
            data_error_packets += 1
            data_error_bytes += errors

        if (
            committed % DATA_BYTES != 0
            or occupancy % DATA_BYTES != 0
            or occupancy > RING_BYTES
        ):
            metadata_errors += 1
        last_committed = committed
        max_occupancy = max(max_occupancy, occupancy)
        packets += 1
        payload_bytes += DATA_BYTES

        now = time.monotonic()
        if now - last_print >= 1.0:
            elapsed = max(now - measurement_start, 1e-9)
            rate = payload_bytes * 8 / elapsed / 1_000_000
            print(
                f"STAT: time={elapsed:7.2f}s packets={packets:8d} "
                f"rate={rate:8.3f} Mb/s missing={missing} duplicate={duplicates} "
                f"out_of_order={out_of_order} malformed={malformed} "
                f"data_error_packets={data_error_packets} metadata_errors={metadata_errors} "
                f"occupancy={occupancy}/{RING_BYTES}"
            )
            last_print = now

    elapsed = 0.0 if measurement_start is None else time.monotonic() - measurement_start
    rate_mbps = 0.0 if elapsed == 0 else payload_bytes * 8 / elapsed / 1_000_000
    passed = (
        packets > 0
        and missing == 0
        and duplicates == 0
        and out_of_order == 0
        and malformed == 0
        and metadata_errors == 0
        and data_error_packets == 0
        and data_error_bytes == 0
    )
    result = {
        "passed": passed,
        "monitor_version": MONITOR_VERSION,
        "duration_seconds": elapsed,
        "packets_received": packets,
        "payload_bytes": payload_bytes,
        "payload_rate_mbps": rate_mbps,
        "missing_packets": missing,
        "duplicates": duplicates,
        "out_of_order": out_of_order,
        "malformed": malformed,
        "metadata_errors": metadata_errors,
        "data_error_packets": data_error_packets,
        "data_error_bytes": data_error_bytes,
        "max_reported_occupancy_bytes": max_occupancy,
        "last_committed_bytes_low": last_committed,
        "socket_receive_buffer_requested_bytes": requested_rcvbuf,
        "socket_receive_buffer_actual_bytes": actual_rcvbuf,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")

    print(
        f"FINAL: time={elapsed:.2f}s packets={packets} rate={rate_mbps:.3f} Mb/s "
        f"missing={missing} duplicate={duplicates} out_of_order={out_of_order} "
        f"malformed={malformed} metadata_errors={metadata_errors} "
        f"data_error_packets={data_error_packets} data_error_bytes={data_error_bytes} "
        f"payload_bytes={payload_bytes} max_occupancy={max_occupancy}"
    )
    print(f"JSON result written to {args.output}")
    print("Press FPGA RESET now to stop/rearm the continuous source.")
    if passed:
        print("V5 DDR3 RING-BUFFER STREAM TEST PASSED")
        return 0
    print("V5 DDR3 RING-BUFFER STREAM TEST FAILED")
    return 2


if __name__ == "__main__":
    sys.exit(main())
