#!/usr/bin/env python3
"""Stop U-Boot's autoboot on a serial console and run commands at its prompt.

Usage: uboot-console.py <tty> <banner> <log-file> <timeout-s> <command>...

Waits for <banner> (for example "U-Boot 2020.04") followed by the autoboot
countdown, interrupts it, then runs each <command> and waits for the prompt
again before the next one. Everything received is appended to <log-file>.
"""
import os
import sys
import termios
import time

tty, banner, log_path, timeout = sys.argv[1], sys.argv[2].encode(), sys.argv[3], float(sys.argv[4])
commands = sys.argv[5:]
PROMPT = b"# "

fd = os.open(tty, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
attrs = termios.tcgetattr(fd)
attrs[0] = 0
attrs[1] = 0
attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
attrs[3] = 0
attrs[4] = attrs[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, attrs)
termios.tcflush(fd, termios.TCIOFLUSH)
log = open(log_path, "ab")
buf = b""
deadline = time.time() + timeout


def pump(wait=0.02):
    global buf
    try:
        chunk = os.read(fd, 4096)
    except BlockingIOError:
        chunk = b""
    if chunk:
        buf += chunk
        log.write(chunk)
        log.flush()
    else:
        time.sleep(wait)


def wait_for(token, until):
    start = len(buf)
    while time.time() < until:
        if token in buf[start:]:
            return True
        pump()
    return False


# Wait for the banner, then the countdown, then interrupt it
if not wait_for(banner, deadline):
    sys.exit("banner not seen")
mark = len(buf)
while time.time() < deadline and b"Hit any key" not in buf[mark:]:
    pump()
for _ in range(20):
    os.write(fd, b" ")
    time.sleep(0.05)
    pump()
os.write(fd, b"\r")
if not wait_for(PROMPT, time.time() + 5):
    sys.exit("prompt not seen after interrupting autoboot")

for cmd in commands:
    time.sleep(0.2)
    start = len(buf)
    os.write(fd, cmd.encode() + b"\r")
    end = time.time() + 60
    # "boot" never returns to the prompt
    if cmd == "boot":
        break
    while time.time() < end:
        tail = buf[start:]
        if tail.rstrip().endswith(b"#") and len(tail) > len(cmd) + 2:
            break
        pump()
    print(buf[start:].decode(errors="replace").replace("\r", ""))
log.close()
