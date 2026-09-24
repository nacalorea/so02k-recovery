#!/usr/bin/env bash
# ============================================================================
# SO-02K 「不认 SIM / 无 IMEI / 无服务」一键恢复
#
# 把 backup/modemst1.img + modemst2.img 写回 modemst1(sda49) / modemst2(sda50)。
# 这是 2026-09-24 实测修好本机的那条路径（RECOVERY.md 场景 D）。
#
# 用法:  bash restore-modemst.sh
#
# 前置:  手机能开机(或能进 fastboot) + USB 连着 + 驱动已装
# 原理:  Sony 对 modemst 有 fastboot 层写保护,只能 RAM 启动 TWRP 后 dd 直写分区
#
# 安全设计:
#   - 写之前先把当前(坏的)modemst 留底到 probe/modemst-rollback/
#   - 写完读回到独立文件,用 cmp 逐字节比对
#   - **只有比对通过才重启**,否则停在这里不重启,保留现场
# ============================================================================
set -u
export MSYS_NO_PATHCONV=1

ROOT="C:/Users/Administrator/xz1c-flash"
ADB="$ROOT/tools/platform-tools/adb.exe"
FB="$ROOT/tools/platform-tools/fastboot.exe"
TWRP="$ROOT/tools/twrp-3.5.2_9-0-lilac.img"
B="$ROOT/backup"
RB="$ROOT/probe/modemst-rollback"

SRC1="$B/modemst1.img"; SRC2="$B/modemst2.img"
DEV1=/dev/block/sda49;  DEV2=/dev/block/sda50

die() { echo "❌ $*"; exit 1; }

echo "=== 0. 前置检查 ==="
for f in "$ADB" "$FB" "$TWRP" "$SRC1" "$SRC2"; do
  [ -f "$f" ] || die "缺文件: $f"
done
for f in "$SRC1" "$SRC2"; do
  sz=$(stat -c %s "$f")
  [ "$sz" = "2097152" ] || die "$f 大小是 $sz,应为 2097152"
done
mkdir -p "$RB"
echo "源备份:"
sha256sum "$SRC1" "$SRC2"

echo ""
echo "=== 1. 进 bootloader ==="
timeout 60 "$ADB" reboot bootloader 2>&1
FBOK=0
for i in $(seq 1 25); do
  if [ -n "$("$FB" devices 2>/dev/null | head -1)" ]; then
    echo "fastboot 命中(第 $((i*3)) 秒)"; FBOK=1; break
  fi
  sleep 3
done
[ "$FBOK" = "1" ] || die "等不到 fastboot 设备 —— 手机在 Flash/fastboot 模式吗? 驱动装了吗?"

echo ""
echo "=== 2. RAM 启动 TWRP(不写任何分区)==="
# 注意: 可能报 "Booting FAILED (usb_read failed ... (31))" —— 那是假报错,
# TWRP 照样会起。所以这里不看 fastboot 的返回,只轮询 TWRP 是否起来。
timeout 150 "$FB" boot "$TWRP" 2>&1
echo "(上面若报 USB 错误请忽略,继续等)"

echo ""
echo "=== 3. 等 TWRP root shell ==="
ROOTED=0
for i in $(seq 1 40); do
  sleep 5
  if timeout 15 "$ADB" shell id 2>/dev/null | grep -q "uid=0"; then
    echo "root 就绪(第 $((i*5)) 秒)"; ROOTED=1; break
  fi
done
[ "$ROOTED" = "1" ] || die "TWRP 没起来。手动进 TWRP(音量下+Power)后重跑本脚本,或直接从第 4 步开始。"
timeout 15 "$ADB" shell id 2>&1 | head -1

echo ""
echo "=== 4. 留底当前(坏的)modemst,便于回退 ==="
timeout 90 "$ADB" shell "dd if=$DEV1 of=/tmp/rb_m1.img bs=1024 count=2048 2>/dev/null; \
                         dd if=$DEV2 of=/tmp/rb_m2.img bs=1024 count=2048 2>/dev/null; sync; echo done" 2>&1
timeout 120 "$ADB" pull /tmp/rb_m1.img "$RB/modemst1_before_restore.img" 2>&1
timeout 120 "$ADB" pull /tmp/rb_m2.img "$RB/modemst2_before_restore.img" 2>&1

echo ""
echo "=== 5. 推入备份到 /tmp(ramdisk;不用 /data/local/tmp)==="
timeout 120 "$ADB" push "$SRC1" /tmp/rs_m1.img 2>&1
timeout 120 "$ADB" push "$SRC2" /tmp/rs_m2.img 2>&1

echo ""
echo "=== 6. 设备侧确认源文件哈希与 PC 一致 ==="
D1=$(timeout 40 "$ADB" shell "sha256sum /tmp/rs_m1.img" 2>/dev/null | tr -d '\r' | cut -d' ' -f1)
D2=$(timeout 40 "$ADB" shell "sha256sum /tmp/rs_m2.img" 2>/dev/null | tr -d '\r' | cut -d' ' -f1)
L1=$(sha256sum "$SRC1" | cut -d' ' -f1)
L2=$(sha256sum "$SRC2" | cut -d' ' -f1)
echo "设备侧 m1=$D1"; echo "PC  侧 m1=$L1"
echo "设备侧 m2=$D2"; echo "PC  侧 m2=$L2"
[ "$D1" = "$L1" ] || die "modemst1 推送后哈希不一致,中止"
[ "$D2" = "$L2" ] || die "modemst2 推送后哈希不一致,中止"
echo "✅ 推送完整"

echo ""
echo "=== 7. 写回分区 ==="
timeout 120 "$ADB" shell "dd if=/tmp/rs_m1.img of=$DEV1 bs=1024 count=2048 && sync && echo W1_OK" 2>&1 || die "写 modemst1 失败"
timeout 120 "$ADB" shell "dd if=/tmp/rs_m2.img of=$DEV2 bs=1024 count=2048 && sync && echo W2_OK" 2>&1 || die "写 modemst2 失败"

echo ""
echo "=== 8. 读回校验(读到独立文件再 cmp,绝不用 dd | sha256sum)==="
timeout 120 "$ADB" shell "dd if=$DEV1 of=/tmp/v_m1.img bs=1024 count=2048 2>/dev/null; \
                         dd if=$DEV2 of=/tmp/v_m2.img bs=1024 count=2048 2>/dev/null; sync" 2>&1
C1=$(timeout 40 "$ADB" shell "cmp /tmp/v_m1.img /tmp/rs_m1.img >/dev/null 2>&1 && echo OK" 2>/dev/null | tr -d '\r\n ')
C2=$(timeout 40 "$ADB" shell "cmp /tmp/v_m2.img /tmp/rs_m2.img >/dev/null 2>&1 && echo OK" 2>/dev/null | tr -d '\r\n ')
echo "modemst1 比对: ${C1:-失败}"
echo "modemst2 比对: ${C2:-失败}"

if [ "$C1" = "OK" ] && [ "$C2" = "OK" ]; then
  echo "✅ 校验通过,允许重启"
else
  echo "❌ 校验不通过 —— 不重启,保留现场。回退镜像在 $RB/"
  exit 1
fi

echo ""
echo "=== 9. 重启并验收 ==="
timeout 30 "$ADB" shell "umount /mnt/s 2>/dev/null; umount /mnt/t1 2>/dev/null; umount /mnt/t2 2>/dev/null; sync" 2>&1
timeout 30 "$ADB" reboot 2>&1
for i in $(seq 1 90); do
  sleep 10
  st=$(timeout 20 "$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n ')
  if [ "$st" = "1" ]; then echo "✅ 启动完成(第 $((i*10)) 秒)"; break; fi
done

echo "等 90 秒 SIM 注册…"
sleep 90
echo ""
echo "--- 结果 ---"
timeout 30 "$ADB" shell "for p in gsm.sim.state gsm.network.type gsm.operator.alpha gsm.version.baseband; do printf '%-22s = [' \$p; getprop \$p; echo ']'; done" 2>&1
timeout 30 "$ADB" shell "dumpsys telephony.registry 2>/dev/null | grep -m1 -o 'mVoiceRegState=[^,]*'" 2>&1
echo ""
echo "期望: gsm.sim.state=LOADED / network.type=LTE / mVoiceRegState=0(IN_SERVICE)"
echo "若仍是空/UNKNOWN,见 RECOVERY.md 场景 D 的排查与回退说明。"
