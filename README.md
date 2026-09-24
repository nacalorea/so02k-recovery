# SO-02K 救砖手册与「不认 SIM」修复

日版 **Xperia XZ1 Compact（SO-02K / 代号 `lilac`）** 刷 LineageOS 22.2 的过程记录，以及一份**可执行的救砖手册**。

解锁与刷机的主体流程不在这里，在上游指南：
**[makegogo-Gu/so02k-unlock-guide](https://github.com/makegogo-Gu/so02k-unlock-guide)**

本仓库补的是上游没覆盖的那一块：**刷完之后手机坏了怎么救回来**。

---

## 仓库内容

| 文件 | 说明 |
|---|---|
| `RECOVERY.md` | 救砖手册。四种故障场景的分步恢复流程、动手前的只读检查、备份清单与哈希、进度记录 |
| `restore-modemst.sh` | 一键脚本：把 `modemst1/2` 备份写回分区，修复「不认 SIM / 无服务」 |

---

## 核心发现：「不认 SIM」的原因是 `modemst` 被改写

刷完 LineageOS 后手机出现 **系统正常但完全不认 SIM、读不到 IMEI**。定位方式仍是**单变量对照实验**——写回刷机前备份的 `modemst1` / `modemst2`（EFS/NV 分区）后：

| 指标 | 修复前 | 修复后 |
|---|---|---|
| `gsm.sim.state` | 缺失（ABSENT） | `LOADED` |
| `gsm.network.type` | 空 | `LTE` |
| `gsm.operator.alpha` | 空 | `CMCC` |
| `mVoiceRegState` | 非 0 | `0`（IN_SERVICE） |

重启一次后依然正常，即**持久**。

当前（坏掉的）`modemst` 与备份**逐字节差异 2,088,475 / 2,097,152 字节（99.6%）**——内容被整体替换，而非局部损坏。`IMGEFS1` / `IMGEFS2` 魔数（偏移 40）仍然完好。

### 被证伪的四条假设

每一条都做了受控实验，都不是靠猜排除的：

- **`fsg`** —— 写入正确签名的 `amss_fsg_lilac_tar.mbn` 并确认它熬过了一次开机（`sony-modem-switcher` 没有覆盖它），SIM 依旧不通。**注意**：第一次做这个实验时写入其实失败了（见下方 `dd` 陷阱），分区是全零的，那一轮结论**无效**；重做并校验后才构成有效证伪。
- **`misc`** —— 内容结构正常，只有 BCB 全零区加两条 64 字节记录。
- **`/data` 与 `/system`** —— 完整 wipe 加重装，无变化。

---

## 为什么需要 `restore-modemst.sh`

Sony 对 `modemst` 有 **fastboot 层写保护**：

```
fastboot flash modemst1 modemst1.img
FAILED (remote: 'Flashing is not allowed')
```

只能 RAM 启动 TWRP 后直接 `dd` 写分区（`/dev/block/sda49` / `sda50`）。

脚本的安全设计：

1. 写之前先把当前（坏的）`modemst` 留底到 `probe/modemst-rollback/`，任何时候都能退回去
2. 推入后**先在设备侧核对 sha256** 与 PC 侧一致，再动分区
3. 写完**读回到独立文件**，用 `cmp` 逐字节比对
4. **只有比对通过才重启**；不通过就停在 TWRP 里保留现场，不带着写坏的分区重启

---

## 复现时会踩到的环境陷阱

这些是实际卡住过、且下次一定还会再遇到的东西：

**TWRP 的 busybox `dd` 有两个坑**

- **不支持 `conv=notrunc`** —— 报 `dd: conv option disabled`，而且**失败时一个字节都不写**。最坑的是拿 `;` 串联时，后续命令照常执行并打印成功，制造假象。→ 一律用 `cat SRC > DEV` 写块设备，并用 `&&` 串联，让失败无法伪装成成功。
- **状态摘要走 stdout** —— `2048+0 records in/out` 会混进 `dd | sha256sum` 的管道，污染哈希。→ 永远 `dd of=<独立文件>` 后再对文件求哈希，或者 `adb pull` 回 PC 再算。

**`fastboot boot` 会假报错**

```
Booting    FAILED (usb_read failed: 连到系统上的设备没有发挥作用。 (31))
```

这是**假报错**，TWRP 照常会在 10~15 秒后起来。有时则报 `Booting OKAY`，两者都正常。**不要因此重试** —— 第二次会挂在 `< waiting for any device >`，因为设备此时在 recovery 而不是 fastboot。

**`pm disable-user` 会被重启还原**

第一次禁用报成功、`pm list packages -d` 也列出来了，但重启后 `enabled=0`、通知又回来了。判据必须是**重启后复核 `enabled=3`**，而不是命令的返回码。

---

## 关于那个会弹「更新网络配置」的 Sony 组件 —— 诚实边界

`com.sonymobile.customizationselector`（`CustomizationSelector`）是 Sony Modem 通知的来源。它的 dex 里确实含有 `reset_modemst1` / `reset_modemst2` / `writeModemToMiscTA` 以及 `Configuration changed - rebooting device...`，**即它真的有能力改写 `modemst` 并重启设备**，所以做了禁用：

```bash
pm disable-user --user 0 com.sonymobile.customizationselector
```

**但因果链没有被证明。** 该弹窗的 `contentIntent=null`，唯一动作是「关闭通知」，从「点弹窗」到「modemst 被改写」之间缺少直接证据。这里记录的是**相关性加能力**，不是已证实的机制。禁用它的成本很低（`modem_switcher` 是 `init` 服务，独立于这个 APK，禁用不影响开机流程），所以做了。

顺带记录三条走不通的路：组件级禁用被 `SecurityException: Shell cannot change component state` 挡回；`pm revoke POST_NOTIFICATIONS` 无效（该权限是 `SYSTEM_FIXED|GRANTED_BY_DEFAULT`）；`appops set POST_NOTIFICATION ignore` 读回来仍是 `allow`。

---

## 适用范围与免责

- 文档里的分区号、哈希、固件版本**都只针对 SO-02K（`lilac`）**，其他机型不要照搬。
- 上游文档里给出的 `modemst` 参考哈希是**别人机器的**，正常情况下**不应该**和你的对上；对上反而说明有问题。
- 刷机有变砖风险。**动手前先备份 `modemst` 和 TA**，详见 `RECOVERY.md` 第三节。
- 本仓库不含任何厂商固件、Sony 专有二进制或设备唯一数据（见 `.gitignore` 的白名单说明）。

## 贡献

如果你的 SO-02K 出现了别的故障模式，或者上面某条结论在你的机器上不成立，欢迎开 issue —— **尤其是推翻性的证据**。
