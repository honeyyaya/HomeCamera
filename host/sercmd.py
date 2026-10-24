"""Run one shell command on the board over the serial console.

    python sercmd.py "命令" [等待秒数]

Port defaults to COM3; set HC_PORT to change it.
"""

import os
import sys
import time

import serial

cmd = sys.argv[1]
wait = float(sys.argv[2]) if len(sys.argv) > 2 else 20
mark = "ZZ%d" % int(time.time() * 1000 % 100000)
s = serial.Serial(os.environ.get("HC_PORT", "COM3"), 115200, timeout=0.2)
s.write(b"\n")
time.sleep(0.3)
s.reset_input_buffer()
s.write((cmd + "; echo " + mark + "\n").encode())
buf = b""
end = time.time() + wait
while time.time() < end:
    buf += s.read(4096)
    # 标记出现两次：一次是命令回显，一次是真正的输出。
    if buf.decode("utf-8", "replace").count(mark) >= 2:
        break
s.close()
print(buf.decode("utf-8", "replace"))
