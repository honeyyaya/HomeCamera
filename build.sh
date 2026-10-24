#!/bin/sh
# 在 WSL 里交叉编译板上程序，产物在 out/。工具链路径可用 CC 覆盖。
set -e
CC=${CC:-/mnt/d/hisi-toolchain/gcc-20250305-arm-v01c02-linux-musleabi/arm-v01c02-linux-musleabi-gcc/bin/arm-v01c02-linux-musleabi-gcc}
CFLAGS="-mcpu=cortex-a7 -mfloat-abi=softfp -mfpu=neon-vfpv4 -Os -s"

cd "$(dirname "$0")"
mkdir -p out
$CC $CFLAGS -o out/rtsp_push src/rtsp_push.c
$CC $CFLAGS -o out/i2c_flip src/i2c_flip.c
ls -l out
