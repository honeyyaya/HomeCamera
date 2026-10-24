/*
 * 板子上实际改画面方向的程序。编码程序本身没有改。
 *
 * 摄像头是 SC4336P，挂在 /dev/i2c-0，7 位地址 0x30（8 位写地址 0x60）。
 * 寄存器 0x3221：bit[6:5] 是上下翻转，bit[2:1] 是左右镜像。
 * 出厂值 0x00。写成 0x60 只翻上下，左右不动。
 *
 * 幽燕 sample_venc 走在线卷绕，VPSS 的 flip_en 设成 1 会返回 0xa007800d，
 * 通道起不来。所以翻转做在传感器寄存器上，不改 sample_venc。
 *
 * 用法（在板子上）：
 *   ./i2c_flip          读 0、1、2 三条总线的 0x3221
 *   ./i2c_flip 0        读总线 0
 *   ./i2c_flip 0 1      写成 0x60
 *   ./i2c_flip 0 0      写回 0x00
 *
 * 这个寄存器在 sample_venc 启动时会被传感器初始化表写回 0x00。
 * 每次重新跑 ./sample_venc 0 1 之后，要再执行一次 ./i2c_flip 0 1。
 */
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/ioctl.h>

#define I2C_SLAVE_FORCE 0x0706
#define SENSOR_ADDR 0x30
#define FLIP_REG 0x3221
#define FLIP_ON 0x60
#define FLIP_OFF 0x00

static int xfer(int bus, int do_write, int value)
{
    char path[32];
    unsigned char buf[3];
    int fd, n;

    snprintf(path, sizeof(path), "/dev/i2c-%d", bus);
    fd = open(path, O_RDWR);
    if (fd < 0) {
        printf("open %s fail\n", path);
        return -1;
    }
    if (ioctl(fd, I2C_SLAVE_FORCE, SENSOR_ADDR) < 0) {
        printf("slave %s %#x fail\n", path, SENSOR_ADDR);
        close(fd);
        return -1;
    }
    buf[0] = (FLIP_REG >> 8) & 0xff;
    buf[1] = FLIP_REG & 0xff;
    if (do_write) {
        buf[2] = (unsigned char)value;
        n = write(fd, buf, 3);
        printf("write bus %d reg %#x val %#x n %d\n", bus, FLIP_REG, value, n);
    } else {
        n = write(fd, buf, 2);
        buf[0] = 0;
        if (n == 2) {
            n = read(fd, buf, 1);
        }
        printf("read bus %d reg %#x n %d val %#x\n", bus, FLIP_REG, n, buf[0]);
    }
    close(fd);
    return 0;
}

int main(int argc, char **argv)
{
    int bus;

    if (argc == 1) {
        for (bus = 0; bus < 3; bus++) {
            xfer(bus, 0, 0);
        }
        return 0;
    }
    bus = argv[1][0] - '0';
    if (argc == 2) {
        return xfer(bus, 0, 0);
    }
    return xfer(bus, 1, argv[2][0] == '1' ? FLIP_ON : FLIP_OFF);
}
