#!/usr/bin/env python3
"""Board-level smoke test for Project2 v1."""

from __future__ import annotations

import argparse
import socket
import subprocess
import sys
import time

FPGA_DEFAULT = "192.168.1.11"
PC_DEFAULT = "192.168.1.100"
FPGA_PORT = 8888
PC_PORT = 6666
BEACON = b"FPGA-UDP-V1-BEACON-0123456789ABC"


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
    parser.add_argument("--timeout", type=float, default=5.0)
    args = parser.parse_args()

    print(f"[1/3] Pinging FPGA {args.fpga_ip} ...")
    if not ping(args.fpga_ip):
        print("FAIL: ping failed; check cable, link speed, FPGA bitstream and static IP.")
        return 1
    print("PASS: ICMP echo reply received")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((args.pc_ip, PC_PORT))
    sock.settimeout(args.timeout)

    print(f"[2/3] Waiting for fixed beacon on {args.pc_ip}:{PC_PORT} ...")
    deadline = time.monotonic() + args.timeout
    beacon_ok = False
    while time.monotonic() < deadline:
        try:
            data, peer = sock.recvfrom(2048)
        except socket.timeout:
            break
        if data == BEACON:
            print(f"PASS: fixed 32-byte beacon received from {peer}")
            beacon_ok = True
            break
    if not beacon_ok:
        print("FAIL: fixed beacon not received")
        return 2

    payload = bytes(range(64))
    print(f"[3/3] Sending {len(payload)}-byte UDP echo test ...")
    sock.sendto(payload, (args.fpga_ip, FPGA_PORT))
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        try:
            data, peer = sock.recvfrom(2048)
        except socket.timeout:
            break
        if data == BEACON:
            continue
        if data == payload:
            print(f"PASS: UDP payload echoed byte-for-byte from {peer}")
            print("V1 BOARD TEST PASSED")
            return 0
        print(f"FAIL: unexpected UDP payload ({len(data)} bytes): {data.hex()}")
        return 3

    print("FAIL: UDP echo timed out")
    return 4


if __name__ == "__main__":
    sys.exit(main())
