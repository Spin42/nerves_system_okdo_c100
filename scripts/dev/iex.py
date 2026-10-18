#!/usr/bin/env python3
"""Type one line into an IEx session on a serial console and print what
comes back within a fixed time.

Usage: iex.py <tty> <seconds> <elixir expression>
"""
import os
import re
import sys
import termios
import time

dev, seconds = sys.argv[1], float(sys.argv[2])
expr = " ".join(sys.argv[3:])

fd = os.open(dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
attrs = termios.tcgetattr(fd)
attrs[0] = 0
attrs[1] = 0
attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
attrs[3] = 0
attrs[4] = attrs[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, attrs)
termios.tcflush(fd, termios.TCIOFLUSH)

os.write(fd, (expr + "\r").encode())
buf = b""
end = time.time() + seconds
while time.time() < end:
    try:
        chunk = os.read(fd, 4096)
    except BlockingIOError:
        chunk = b""
    if chunk:
        buf += chunk
    else:
        time.sleep(0.02)
os.close(fd)

text = buf.decode(errors="replace").replace("\r", "")
text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", text)
print(text)
