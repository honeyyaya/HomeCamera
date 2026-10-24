# camera-board

幽燕 Hi3516CV610（SC4336P）板上用到的程序。板子自己把 H.265 画面推到云上的 MediaMTX，家里电脑和代理都不参与。

```text
镜头 -> sample_venc 编码 H.265 -> 板内 rtsp://127.0.0.1:554/live.h265
     -> rtsp_push 原样转发（TCP）-> 云上 MediaMTX :8554/cam -> 手机 VLC
```

## 目录

| 路径 | 作用 |
| --- | --- |
| `src/rtsp_push.c` | 板上推流。从本机 RTSP 拉一路，ANNOUNCE/RECORD 推到远端，不重新编码，断开 3 秒后重连。支持 Basic 和 Digest 鉴权。 |
| `src/i2c_flip.c` | 画面上下翻转。直接写 SC4336P 寄存器 `0x3221=0x60`。 |
| `board/start.sh` | 重启后依次拉起 WiFi、编码、翻转、推流。 |
| `board/push.conf.example` | 推流地址模板。复制成板上的 `/youyan/push.conf`，填好密码。 |
| `board/insmod.sh` | 板上 `/youyan/insmod.sh`，MMZ 改为 `0x44000000` 起 64M。 |
| `host/tftp_once.py` | 电脑上的一次性 TFTP 服务，给板子传文件。 |
| `host/sercmd.py` | 通过串口在板上执行一条命令。 |
| `build.sh` | WSL 里交叉编译，产物在 `out/`。 |

`sample_venc` 不在这里。它来自幽燕 SDK 的 `mpp/sample/venc`，带 RTSP 输出（`./sample_venc 0 1`）。

## 编译

WSL 里执行：

```text
./build.sh
```

工具链是 `arm-v01c02-linux-musleabi-gcc`，参数 `-mcpu=cortex-a7 -mfloat-abi=softfp -mfpu=neon-vfpv4`。路径不同时用 `CC=... ./build.sh`。

## 上板

板子和电脑在同一个局域网。电脑每传一个文件，先跑一次 `python host/tftp_once.py`，再在板上取：

```text
tftp -g -r rtsp_push -l /youyan/rtsp_push <电脑IP> 6969
tftp -g -r i2c_flip  -l /youyan/i2c_flip  <电脑IP> 6969
chmod +x /youyan/rtsp_push /youyan/i2c_flip
```

`sample_venc` 也放到 `/youyan/sample_venc`。再把 `board/start.sh` 放到 `/youyan/start.sh`，按模板写好 `/youyan/push.conf`。

重启后执行 `sh /youyan/start.sh`。推流日志在 `/tmp/push.log`，出现 `pushing /live.h265 -> ...` 且后面 `fwd N` 持续增长，就是在推。编码日志在 `/tmp/vlog/venc.log`。

## 内存划分

板子总共 128MB。U-Boot 里 `mem=64m`，`/youyan/insmod.sh` 的 MMZ 从 `0x44000000` 起 64M，两处要一起改。原来是 `mem=32m`，MMZ `0x42000000` 起 96M，Linux 只剩 2MB 左右可用，推流程序跑不起来。

## 踩过的坑

- MediaMTX 的鉴权是 Basic，401 的头是 `WWW-Authenticate: Basic realm="ipcam"`。
- 往 MediaMTX 推流，SETUP 的 `Transport` 必须带 `mode=record`，否则回 `400 Bad Request`。
- 板上 stderr 重定向到文件时，日志要走 `write()`，只用 `fprintf` 可能一直缓冲不落盘。
- `sample_venc` 异常退出后 ISP 不会释放，再启动报 `OT_MPI_ISP_MemInit failed with 0xa01c800c`，只能重启板子。不要在内存紧张时跑 `pidof` 这类扫 `/proc` 的命令，曾经把编码进程挤掉。
- 不要再对板子的 554 开额外的拉流客户端，电脑上的 ffprobe 短连接曾经把 `sample_venc` 弄退出。
- VPSS 的 `flip_en` 在在线卷绕模式下返回 `0xa007800d`，所以翻转做在传感器寄存器上。
