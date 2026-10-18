#!/usr/bin/env python3
"""Capture raw serial output at 115200 8N1 to a file for a fixed time.

Usage: serial-capture.py <tty> <output-file> <seconds>
"""
import os
import sys
import termios
import time

dev, out, seconds = sys.argv[1], sys.argv[2], float(sys.argv[3])
fd = os.open(dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
attrs = termios.tcgetattr(fd)
attrs[0] = 0                                              # iflag
attrs[1] = 0                                              # oflag
attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL   # cflag
attrs[3] = 0                                              # lflag
attrs[4] = attrs[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, attrs)
termios.tcflush(fd, termios.TCIFLUSH)

end = time.time() + seconds
with open(out, "wb") as f:
    while time.time() < end:
        try:
            data = os.read(fd, 4096)
        except BlockingIOError:
            data = b""
        if data:
            f.write(data)
            f.flush()
        else:
            time.sleep(0.02)
os.close(fd)
