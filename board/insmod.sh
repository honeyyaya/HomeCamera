#!/bin/sh

# 板上路径 /youyan/insmod.sh。MMZ 从 0x44000000 起 64M，配合 U-Boot 的 mem=64m。
# 两处要一起改，否则 Linux 内存和 MMZ 会重叠。
cd /komod/load3516cv610

./load3516cv610_20s_debug  -i -sensor0 sc4336p -mmz_start 0x44000000 -mmz_size 64M
