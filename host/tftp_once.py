"""Serve one TFTP read request on UDP 6969, then exit.

    python tftp_once.py [目录]

Board side: tftp -g -r NAME -l /tmp/NAME <电脑IP> 6969
"""

import os
import socket
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out")
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("0.0.0.0", 6969))
print("tftp on 6969, root", ROOT, flush=True)
data, addr = sock.recvfrom(2048)
name = data[2:].split(b"\x00", 1)[0].decode("ascii", "replace")
path = os.path.join(ROOT, os.path.basename(name))
print("rrq", name, flush=True)
with open(path, "rb") as handle:
    block = 1
    while True:
        chunk = handle.read(512)
        pkt = b"\x00\x03" + (block & 0xFFFF).to_bytes(2, "big") + chunk
        acked = False
        for _ in range(8):
            sock.sendto(pkt, addr)
            sock.settimeout(3)
            try:
                ack, _ = sock.recvfrom(2048)
            except socket.timeout:
                continue
            if ack[:2] == b"\x00\x04" and int.from_bytes(ack[2:4], "big") == (block & 0xFFFF):
                acked = True
                break
        if not acked or len(chunk) < 512:
            print("done" if acked else "fail", block, flush=True)
            break
        block += 1
