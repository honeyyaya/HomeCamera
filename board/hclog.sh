#!/bin/sh
# 状态记录。写在 flash 上的 /youyan/log，断电、重启后还在。
# 每 30 秒采一次：状态有变化就写一行，没变化每 5 分钟写一行心跳；出异常时附上推流日志和内核日志。
# alive 文件每 30 秒覆盖一次，开机时记进日志，用来判断上次大概什么时候断的。
# 板上 flash 和内存都小，所有日志都有上限：hc.log 64KB 两份，push.log / venc.log 超 32KB 截到末尾 8KB。
export TZ=CST-8
DIR=/youyan/log
LOG=$DIR/hc.log
MAX=65536
SRV=101.37.173.146
NTP="-p 203.107.6.88 -p 120.25.115.20"
PLOG=/tmp/push.log
VLOG=/tmp/vlog/venc.log

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
    grep -v '^fwd' $PLOG 2>/dev/null | tail -n 6 | sed 's/^/  /' >> $LOG
    echo "  -- dmesg --" >> $LOG
    dmesg | tail -n 10 | sed 's/^/  /' >> $LOG
    sync
}

size() {
    s=$(wc -c < $1 2>/dev/null)
    echo ${s:-0}
}

# 写日志的进程以追加方式打开，原地截短不会留空洞
trim() {
    [ $(size $1) -gt 32768 ] || return 1
    tail -c 8192 $1 > $1.t && cat $1.t > $1
    rm -f $1.t
}

[ $(size $LOG) -gt $MAX ] && mv -f $LOG $LOG.1
w "=== BOOT $n === last alive: $(cat $DIR/alive 2>/dev/null)"
# 等 start.sh 连上 WiFi、拉起编码和推流后再开始判断
sleep 60

synced=0
plines=0
conn=0
bad=0
last=
hb=0
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
    fwd=$(grep '^fwd' $PLOG 2>/dev/null | tail -n 1 | cut -d' ' -f2)

    total=$(grep -vc '^fwd' $PLOG 2>/dev/null)
    total=${total:-0}
    [ $total -lt $plines ] && plines=0
    new=
    if [ $total -gt $plines ]; then
        new=$(grep -v '^fwd' $PLOG | tail -n $((total - plines)) | tail -n 20)
        conn=$((conn + $(echo "$new" | grep -c begin)))
    fi
    plines=$total

    # 字段：sig=链路质量/信号  gw/srv=能否 ping 通网关/服务器  conn=本次开机推流连接次数
    key="$ip $st $pg $ps_ $venc $push $conn"
    up=$(cut -d' ' -f1 /proc/uptime)
    up=${up%.*}
    if [ "$key" != "$last" ] || [ $((up - hb)) -ge 300 ]; then
        w "ip=${ip:-none} wifi=${st:-?} sig=$wl gw=$pg srv=$ps_ mem=${mem}k load=$ld venc=$venc push=$push conn=$conn fwd=${fwd:-0}"
        last=$key
        hb=$up
    fi
    if [ -n "$new" ]; then
        echo "$new" | sed 's/^/  push: /' >> $LOG
        sync
    fi

    if [ -z "$ip" ] || [ $pg = 0 ] || [ $venc = 0 ] || [ $push = 0 ]; then
        [ $bad = 0 ] && { w "!! FAULT"; dump; }
        bad=1
    else
        [ $bad = 1 ] && w "recovered"
        bad=0
    fi

    echo "$(date '+%m-%d %H:%M:%S') up=$up" > $DIR/alive
    sync

    [ $(size $LOG) -gt $MAX ] && mv -f $LOG $LOG.1
    trim $PLOG && plines=$(grep -vc '^fwd' $PLOG)
    trim $VLOG

    sleep 30
done
