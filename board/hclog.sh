#!/bin/sh
# 状态记录。写在 flash 上的 /youyan/log，断电、重启后还在。
# 每 30 秒一行状态；出现异常时额外记下推流日志和内核日志。
export TZ=CST-8
DIR=/youyan/log
LOG=$DIR/hc.log
MAX=262144
SRV=101.37.173.146
NTP="-p 203.107.6.88 -p 120.25.115.20"

mkdir -p $DIR
n=$(cat $DIR/bootcnt 2>/dev/null)
n=$((${n:-0} + 1))
echo $n > $DIR/bootcnt

w() {
    echo "$(date '+%m-%d %H:%M:%S') up=$(cut -d' ' -f1 /proc/uptime) $*" >> $LOG
    sync
}

dump() {
    echo "  -- push.log --" >> $LOG
    grep -v '^fwd' /tmp/push.log 2>/dev/null | tail -n 6 | sed 's/^/  /' >> $LOG
    echo "  -- dmesg --" >> $LOG
    dmesg | tail -n 10 | sed 's/^/  /' >> $LOG
    sync
}

s=$(wc -c < $LOG 2>/dev/null)
[ "${s:-0}" -gt $MAX ] && mv -f $LOG $LOG.1
w "=== BOOT $n ==="
# 等 start.sh 连上 WiFi、拉起编码和推流后再开始判断
sleep 60

synced=0
plines=0
bad=0
while true; do
    ip=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
    if [ $synced = 0 ]; then
        if [ "$(date +%Y)" -gt 2020 ]; then
            synced=1
            w "time synced"
        elif [ -n "$ip" ]; then
            killall ntpd 2>/dev/null
            timeout 20 ntpd -n -q $NTP >/dev/null 2>&1 &
        fi
    fi

    st=$(wpa_cli -i wlan0 status 2>/dev/null | sed -n 's/^wpa_state=//p')
    wl=$(tail -n 1 /proc/net/wireless | awk '{print $3+0 "/" $4+0}')
    gw=$(route -n | awk '$1=="0.0.0.0"{print $2; exit}')
    pg=0; [ -n "$gw" ] && ping -c 1 -W 2 $gw >/dev/null 2>&1 && pg=1
    ps_=0; ping -c 1 -W 2 $SRV >/dev/null 2>&1 && ps_=1
    mem=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
    ld=$(cut -d' ' -f1 /proc/loadavg)
    pl=$(ps)
    venc=$(echo "$pl" | awk '$4=="/youyan/sample_venc"' | wc -l)
    push=$(echo "$pl" | awk '$4=="/youyan/rtsp_push"' | wc -l)
    fwd=$(grep '^fwd' /tmp/push.log 2>/dev/null | tail -n 1 | cut -d' ' -f2)
    beg=$(grep -c 'begin' /tmp/push.log 2>/dev/null)

    # 字段：sig=链路质量/信号  gw/srv=能否 ping 通网关/服务器  conn=推流累计连接次数
    w "ip=${ip:-none} wifi=${st:-?} sig=$wl gw=$pg srv=$ps_ mem=${mem}k load=$ld venc=$venc push=$push conn=${beg:-0} fwd=${fwd:-0}"

    total=$(grep -vc '^fwd' /tmp/push.log 2>/dev/null)
    total=${total:-0}
    [ $total -lt $plines ] && plines=0
    if [ $total -gt $plines ]; then
        grep -v '^fwd' /tmp/push.log | tail -n $((total - plines)) | tail -n 20 | sed 's/^/  push: /' >> $LOG
        sync
    fi
    plines=$total

    if [ -z "$ip" ] || [ $pg = 0 ] || [ $venc = 0 ] || [ $push = 0 ]; then
        [ $bad = 0 ] && { w "!! FAULT"; dump; }
        bad=1
    else
        [ $bad = 1 ] && w "recovered"
        bad=0
    fi

    sleep 30
done
