#!/bin/sh
# 板子重启后依次拉起 WiFi、编码、画面翻转、推流。
# 二进制放在 /youyan（ubifs，重启不丢），推流地址写在 /youyan/push.conf。
BIN=/youyan
CONF=$BIN/push.conf

echo "start $(date)"
if ! ifconfig wlan0 2>/dev/null | grep -q 'inet addr'; then
    rmmod rtl8189fs 2>/dev/null
    insmod /system/wifi/ko/rtl8189fs.ko
    /system/wifi/wifi_start.sh RTL8189FS
fi
ifconfig wlan0 | grep 'inet addr'

# sample_venc 会在当前目录写码流文件，指到 /dev/null 免得写满 flash。
mkdir -p /tmp/vlog
cd /tmp
ln -sf /dev/null /tmp/stream_chn0.h265
ln -sf /dev/null /tmp/stream_chn1.h264
# 标准输入要一直开着：回车两次 sample_venc 就会退出。
setsid sh -c "trap '' HUP; ( printf '0\nc\n'; sleep 999999 ) | $BIN/sample_venc 0 1" </dev/null >/tmp/vlog/venc.log 2>&1 &

# 传感器初始化会把翻转寄存器写回 0，要等编码起来后再写。
sleep 8
$BIN/i2c_flip 0 1

if [ ! -f "$CONF" ]; then
    echo "缺少 $CONF，不推流"
    exit 1
fi
. "$CONF"
killall rtsp_push 2>/dev/null
setsid $BIN/rtsp_push rtsp://127.0.0.1:554/live.h265 "$PUSH_URL" >/tmp/push.log 2>&1 &
echo "push started"
