#!/usr/bin/env python3
"""Wait until a TCP port accepts connections.

Usage: wait-port.py <host> <port> <timeout-seconds>
Exits 0 once the port is open, 1 on timeout.
"""
import socket
import sys
import time

host, port, timeout = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
start = time.time()
while time.time() - start < timeout:
    try:
        with socket.create_connection((host, port), timeout=2):
            print(f"{host}:{port} open after {time.time() - start:.0f}s")
            sys.exit(0)
    except OSError:
        time.sleep(2)
print(f"{host}:{port} still closed after {timeout:.0f}s")
sys.exit(1)
