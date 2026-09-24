# SO-02K 刷机备份与救砖包

> 目标:手机刷成砖也能回到官方原厂状态。
> 应用数据**不需要**备份(用户已确认),本文只覆盖「系统级恢复能力」。

---

## 一句话结论

**恢复靠的是 Flash Mode + newflasher + 完整原厂固件**,这三样现在都已在本机备好并
逐字节校验通过。只要手机还能进 Flash Mode(绿灯),就能刷回官方 Android 9。

---

## 一、已备好的资产(全部已校验)

### 恢复用固件(救砖的核心)

| 文件 | 大小 | 校验 |
|---|---|---|
| `firmware/SO-02K_47.2.B.5.38_1311-8845_R11C.ftf` | 2,932,330,297 | md5 `e2e143b681be5b8fe675cc912f2ab1f9` = archive.org ✅ |
| `firmware/SO-02K_47.1.F.1.105_1311-8845_R14B.ftf` | 2,758,530,892 | md5 `d24ac9977d66e193f6a8cd0c5d885063` = archive.org ✅ |

两个 .ftf 都另外过了**全成员 CRC-32 校验**(`probe/ftf-crc.log`),不是只看下载完成。

> 实测修正:指南 01/03 说「47.1 是 zip,47.2 是 tar」——**实际两个都是 ZIP**
> (magic 均为 `PK\x03\x04`),用同一条 `unzip` / `ftf-unpack.py` 路径解包即可。

### 已解包成 newflasher 可直接用的目录

| 目录 | 内容 |
|---|---|
| `restore/stock-9.0-47.2.B.5.38/` | 官方 Android 9 整包 + `newflasher.exe`(35 项) |
| `restore/stock-8.0-47.1.F.1.105/` | 官方 Android 8 整包 + `newflasher.exe`(35 项) |
| `restore/p114-bootloader-only/` | 只刷 bootloader 的包(`boot/` + `newflasher.exe`) |

> **`boot_delivery.xml` 放在哪一层,直接决定 bootloader 刷不刷 —— 已对源码逐行确认。**
>
> newflasher 只在 **`<当前目录>\boot\boot_delivery.xml`** 这一个位置找 boot delivery
> (源码 `newflasher.c:4814`,`working_path` 就是 CWD,**没有回退到顶层的分支**)。
> 找不到就整段跳过,**一个字节都不写 bootloader 分区**。
> 主循环也只在 CWD **顶层**扫 `.sin`(`opendir(working_path)`,不递归),
> 所以 `boot/` 里的 `.sin` 只能靠 boot delivery 触达。
>
> - `restore/p114-bootloader-only/boot/boot_delivery.xml` → 在 `boot/` **里面** → **会刷**。
>   内含 `VERSION="1306-5035-X-BOOT-MSM8998-LA2.0-P-114"`,与指南阶段 3 预期一致。
> - 两个 `restore/stock-*/` → 保持 `.ftf` 原样:`boot_delivery.xml` 在**顶层**,
>   `boot/` 里只有 `.sin` → **不会刷** bootloader。
>
> 后者是**故意保持的**:降级到 Android 8 时保留出厂自带的 P_114,就能整段跳过
> 全流程里风险最高的阶段 3。(`Platform ID` 也不需要担心 —— newflasher 匹配前会把
> 平台号前两位强制改写成 `"00"`,手机报的 `2005E0E1` 会被规范化成 `0005E0E1`,
> 与 xml 里的 `PLATFORM_ID="0005E0E1"` 天然一致;root key hash 也已核对相符。)

### 解锁工具链(全部校验过)

| 文件 | 大小 | sha256 |
|---|---|---|
| `tools/xperable.exe` | 6,917,742 | `c7217b49b995b63515007d385c50c1ca5b747a1b0813f747d0956c7d705baeb0` |
| `tools/xfl-o77.mbn` | 13,153,250 | `c745a32721d68bb7499a0e929bd9bcfec307cb922d0c17c22f064a51e6e1a7c7` |
| `tools/LinuxLoader-p114.pe` | 1,052,672 | `e8919094432714805980fd113806faaa65648dc9fabd7ae5912540579ef1e51b` |

**`xperable.exe` 是我们自己从 j4nn 上游源码编译的**,不是下载的第三方二进制:

- 源码:`tools/src/xperable-master/`(j4nn/xperable 1.1)
- 交叉编译脚本:`tools/build-xperable.sh`(WSL + mingw-w64)
- 只编入 `TARGET_ABL_P114` 一个目标 —— `xperable.exe -h` 可验证;编译产物里的
  ABL 版本字符串只有 `X_Boot_MSM8998_LA2.0_P_114`
- 静态链接,只依赖 `KERNEL32.dll` / `msvcrt.dll`,不会在关键时刻弹缺 DLL

**`LinuxLoader-p114.pe` 是我们自己从 SO-02K 的 P_114 bootloader 里提取的**:
`bootloader_X_BOOT_MSM8998_LA2_0_P_114_X-FLASH-ALL-99C3.sin`
→ `bootloader.000` → `abl_..._P_114.mbn` → `section1.pe`。
提取结果 1,052,672 字节,与第三方包里的同名文件**大小完全一致**。

**`xfl-o77.mbn` 的来源链已闭合**:XDA 的 SO-02K 实战帖里,手机上 `dd` 出来的
分区 dump 和被 push 进去的文件 sha256 **都是 `c745a327…`**,与本文件一致。
j4nn 的 Makefile 接受两个哈希,另一个 `41867a4f…`(13,112,290 字节,来自另一个
来源目录 `old/xperable-blobs-xz1`)也留在 `kit/xfl-copies/new-xfl-o77.mbn` 以备核对。
**本次要用的是 `c745a327…` 那一份**(与实战帖 dd 结果逐字节一致),
`41867a4f…` 只是旁证,别刷错。

### 刷机工具

| 文件 | 说明 |
|---|---|
| `kit/newflasher.exe` | 3,560,462 字节,已复制进各 `restore/` 目录 |
| `kit/bindershell` | 23,016 字节,CVE-2019-2215 临时 root(Android 8 专用) |
| `kit/platform-tools/` | adb.exe / fastboot.exe + 依赖 DLL |
| `tools/twrp-3.5.2_9-0-lilac.img` | 34,496,512 字节,`ANDROID!` 魔数正常 |

### ROM 与 GApps

| 文件 | 校验 |
|---|---|
| `firmware/lineage-22.2-20260522-UNOFFICIAL-lilac-DCM-KSU.zip` | 1,043,421,503 字节;sha256 `2b44624558ea4cfc3b9c13bf00b76604da688124d336214e47e001711e37a7be` = 指南记录值 ✅,zip 全成员 CRC OK |
| `gapps/MindTheGapps-15.0.0-arm64-20260915_032013.zip` | 507,472,816 字节;sha256 `e979601ef70b03d9214ea24ca7a103cb408ab102718fff38ec170a6ca03e263d` = 官方 `.sha256sum` ✅ |

> LineageOS **不自带** GApps。要谷歌商店就必须自己刷 MindTheGapps,
> 而且**必须在 ROM 第一次开机之前**刷进去(详见阶段 6 末的 GApps 硬约束)。

---

## 二、三种故障场景的恢复流程

### 场景 A:系统起不来 / 无限重启 / 刷坏 system、kernel、userdata

最常见,也是最容易恢复的。

```
1. 手机关机
2. 按住【音量下】不松,插 USB
3. 绿灯亮 = 进入 Flash Mode
4. 进入 restore/stock-9.0-47.2.B.5.38/
5. 运行 newflasher.exe,交互回答:**全部 `n`**(v20 实测只问 4 个可选项)
6. 刷完**不会自动重启**,手动开机 → 回到官方 Android 9 出厂状态
```

想回到 Android 8,把第 4 步换成 `restore/stock-8.0-47.1.F.1.105/`。

脚本化写法(等价,省得手敲):

```bash
printf 'n\nn\nn\nn\nn\nn\n' | newflasher.exe
```

> **v20 实际只问 4 个问题,而且全是「可选项」,答案一律 `n`:**
>
> | # | 问题 | 答 |
> |---|---|---|
> | 1 | 生成 GordonGate 驱动包? | `n` |
> | 2 | dump trim area? | `n` |
> | 3 | 把 bootloader/bluetooth/dsp/modem/rdimage 刷到 **a、b 双槽**? | `n` |
> | 4 | 刷 persist 分区? | `n` ← **别答错,见下** |
>
> ⚠ **第 4 问答 `n` 是有实质后果的,不是走过场。** newflasher 在这一问旁边会打印
> `More info .../android-attest-key-lost-bootloader-t3829945` —— 刷 `persist`
> 会覆盖 **attest key** 和传感器校准。实测答 `n` 后日志显示:
>
> ```
> Skipping persist.sin
> ```
>
> persist 分区(`/dev/block/sda33`,32 MB)**全程未动**。
>
> 指南 doc 01 写的 `n / y / n / y / n / a`(6 个)是**另一个版本**的 newflasher
> 才有的提问。照抄那串会**在第 3 个问题答 `y`** 去动双槽 —— 别用。
>
> ⚠ v20 **没有**「是否保留 userdata」这个提问,所以 `userdata.sin` 会被直接刷入,
> **手机数据会清空**。降级场景下可以接受(本来也该清干净)。

> ⚠ **救砖时看到这一行,不要以为刷失败了:**
>
> ```
> boot_delivery.xml not exist in boot folder or no boot folder.
> ```
>
> 这是**正常的、预期的** —— 原厂 `.ftf` 的 `boot_delivery.xml` 就在顶层,newflasher
> 只认 `boot/` 里的那份(原因见上文),于是它在最后一步跳过 bootloader。
> **此时 system / kernel / modem 等该刷的都已经刷完了**,开机就是正常的官方系统。
>
> 2026-09-23 实测(v20)完整刷写 Android 8 整包:写入 20 个分区、195 个 `OKAY`、
> **0 错误**,打印了这句话后**以退出码 0 结束**。判断成功的依据是那些
> `flash:xxx OKAY.`,不是这行字。
>
> **实测确认:写入清单里没有 `bootloader` / `abl` / `xfl`** —— 整个原厂整包刷写
> 确实一个字节都没碰引导链。

### 场景 A2:只想单独刷 bootloader(阶段 3)

**交互回答不一样,别照抄场景 A 的那串。**

```bash
cd restore/p114-bootloader-only/
printf 'n\na\nn\ny\n' | newflasher.exe
```

期望日志出现:

```
Processing bootloader_X_BOOT_MSM8998_LA2_0_P_114_X-FLASH-ALL-99C3.sin
 - Uploading signature ... OKAY.
 - erase:bootloader OKAY.
 - flash:bootloader OKAY.
```

> ⚠ **刷完这个包,XFL 会变成 P_114 版。** xperable 要求 XFL 必须是 **O_77**
> (Sony ABL 会校验 XFL,新 XFL 体积更大、会把 bootloader 内存布局顶偏,溢出就打不到
> ABL 代码区了)。所以进系统后必须用 bindershell 把 O_77 XFL 刷回去,否则 `-4`
> 永远是 `no luck`:
>
> ```bash
> adb push tools/xfl-o77.mbn /sdcard/
> adb shell "cd /data/local/tmp && printf 'dd if=/sdcard/xfl-o77.mbn of=/dev/block/bootdevice/by-name/xfl\nsync\nexit\n' | ./bindershell"
> ```
>
> 期望输出 `13153250 bytes transferred`。详见 `so02k-guide/docs/03-bootloader.md`。

### 场景 B:解锁后「双锁闪烁 + 反复重启」

这不是砖,是 FBE 加密元数据失效的预期现象:

```
fastboot format userdata     # 必须 format,erase 不够
fastboot format cache
```

### 场景 C:bootloader 刷坏了(最坏情况)

**这一层没有可靠的公开恢复手段,必须提前避免,而不是事后补救。**

Flash Mode 本身是由 bootloader 分区里的 S1 loader 提供的。如果 bootloader 分区
被写坏,Flash Mode 可能直接进不去,那就只剩 EDL(9008)模式 —— 而 EDL 需要高通
签名的 firehose programmer,零售版 Xperia 拿不到。**这就是本方案的最大风险点。**

风险集中在**阶段 3(只刷 `boot/` 子目录)**,因为那是唯一会动 bootloader 分区的
步骤。所以刷之前必须做完下面第三节的检查。

### 场景 D:系统正常但**不认 SIM / 无服务 / 无 IMEI**(2026-09-24 实测修复)

**症状**:系统能开机、Wi-Fi 正常,但

- `gsm.sim.state` 空或 `ABSENT`,`gsm.network.type=Unknown`
- ServiceState = `OUT_OF_SERVICE`
- `service call iphonesubinfo 1 s16 com.android.shell` 返回 `ffffffff`(读不到 IMEI)
- 插着卡也完全没反应

**根因:`modemst1` / `modemst2`(EFS/NV 分区)内容被改写。** 基带固件本身是好的
(`gsm.version.baseband` 能显示 `8998-8998.gen.prodQ-00278-47`),坏的是 EFS 数据。

**修复 = 把 `backup/modemst1.img` / `modemst2.img` 写回去。** 完整原理见
`so02k-guide/docs/06-efs-restore.md`。

> ✅ **一键脚本:`xz1c-flash/restore-modemst.sh`** —— 手机连着 USB、能进 fastboot 或
> 手动进 TWRP,跑 `bash restore-modemst.sh` 即可。脚本已内置本页所有教训:
> 自动留底当前状态、push 到 `/tmp`、`cmp` 逐字节校验、**校验不过就不重启**。
> 下面是它等价的手工步骤(脚本失效时照这个敲)。

```
1. adb reboot bootloader                       # 蓝灯
2. fastboot boot tools/twrp-3.5.2_9-0-lilac.img   # 内存启动,不写任何分区
3. 等 adb devices 显示 recovery、adb shell id 是 uid=0(root)

   # 写之前先留底当前(坏的)状态,便于回退
4. adb shell "dd if=/dev/block/sda49 of=/tmp/m1_now.img bs=1024 count=2048"
   adb shell "dd if=/dev/block/sda50 of=/tmp/m2_now.img bs=1024 count=2048"
   adb pull /tmp/m1_now.img ./  ;  adb pull /tmp/m2_now.img ./

   # push 到 /tmp(ramdisk),别用 /data/local/tmp
5. adb push backup/modemst1.img /tmp/modemst1_restore.img
   adb push backup/modemst2.img /tmp/modemst2_restore.img

   # 写回
6. adb shell "dd if=/tmp/modemst1_restore.img of=/dev/block/sda49 bs=1024 count=2048 && sync"
   adb shell "dd if=/tmp/modemst2_restore.img of=/dev/block/sda50 bs=1024 count=2048 && sync"

   # 读回到独立文件再比,不要 dd | sha256sum
7. adb shell "dd if=/dev/block/sda49 of=/tmp/v1.img bs=1024 count=2048"
   adb shell "cmp /tmp/v1.img /tmp/modemst1_restore.img && echo IDENTICAL"
   adb shell "cmp /tmp/v2.img /tmp/modemst2_restore.img && echo IDENTICAL"

8. adb reboot
   # 等 ~40 秒开机 + 90 秒注册,然后:
   adb shell getprop gsm.sim.state      # 期望 LOADED
   adb shell getprop gsm.network.type   # 期望 LTE
```

**本机实测结果(2026-09-24)**:修复后 `gsm.sim.state=LOADED`、`gsm.network.type=LTE`、
`gsm.operator.alpha=CMCC`、ServiceState `IN_SERVICE`、LTE `rsrp=-90 level=4`、
IMEI 15 位可读;**重启一次后依然正常(持久)**。

> ⚠ **两个必须避开的坑(都是本次实测踩到的):**
>
> 1. **TWRP 的 busybox `dd` 不支持 `conv=notrunc`**(报 `dd: conv option disabled`),
>    而且失败时**不写任何字节**。别用 `dd ... conv=notrunc` 去写分区。
> 2. **不要用 `dd if=分区 | md5sum` / `| sha256sum` 校验** —— busybox `dd` 会把
>    `2048+0 records in/out` 这类状态摘要打到 **stdout**,混进哈希,算出来的值
>    永远是错的。必须 `dd of=独立文件` 再对文件算哈希,或干脆 `adb pull` 到电脑上算。
>
> 另外:`fastboot boot` 有时会报
> `Booting FAILED (usb_read failed: ... (31))` —— **这是假报错**,TWRP 照样会在
> ~15 秒后起来,别据此重试(重试第二次会卡在 `< waiting for any device >`)。

#### 防止复发:`com.sonymobile.customizationselector`(2026-09-24)

**那个「Sony Modem」弹窗就是它发的,而它确实有能力写 modemst。** 反编译
`/system/system_ext/priv-app/CustomizationSelector/CustomizationSelector.apk`,dex 里直接有:

```
reset_modemst1 / reset_modemst2 / modemST1Name / modemST2Name
amss_fsg_lilac_tar.mbn
writeModemToMiscTA / clearMiscTaConfigId / "Clear MiscTa value for Config Id"
"isNewConfigurationNeeded - Modem:"  "setConfiguration - modem configuration ="
"reApplyModem - Modem Switcher 2404 cleared"  "reApplyModem - Re-writing 2405 with modem"
"Configuration changed - rebooting device..."
```

即:**检测到 SIM 需要换 modem 配置 → 写 MiscTA(2404/2405)→ 可能重置 modemst → 自己重启
手机**。所以它不是无害的通知,别去点它。

**禁用它(已实测,可逆):**

```
adb shell pm disable-user --user 0 com.sonymobile.customizationselector
# 复核
adb shell "dumpsys package com.sonymobile.customizationselector | grep -oE 'enabled=[0-9]+'"
#   enabled=3 = DISABLED_USER ✅   （enabled=0 = 已启用）
adb shell pm list packages -d | grep sonymobile
```

恢复:`adb shell pm enable com.sonymobile.customizationselector`。

> ⚠ **几条走不通的路(别再试)**:
> - `pm disable` 单个组件(`.EventReceiver` / `.ModemSwitcherActivity`)→
>   `SecurityException: Shell cannot change component state ... to 2`。
> - `pm revoke ... POST_NOTIFICATIONS` → 返回 0 但**无效**,该权限是
>   `SYSTEM_FIXED|GRANTED_BY_DEFAULT`,系统会重新授回。
> - `appops set ... POST_NOTIFICATION ignore` → 回读仍是 `allow`,不生效。
> - **在设置里手动关它的通知也不行** —— dumpsys 显示该 App `fixedImportance=true`。
>
> 原因是这个包 `sharedUser=android.uid.phone/1001`、`SYSTEM_EXT|PRIVILEGED`。
> **整包禁用要重启后才见分晓**(第一次试时曾被还原,第二次及以后稳定保持),
> 所以**务必跨一次重启复核 `enabled=3`** 再认为搞定。
>
> ⚠ **首次 `pm disable-user` 后一定要重启复核。** 实测有一次重启后被还原成 `enabled=0`。

**已排除的错误假设(留档,别再走一遍)**:`fsg` 分区、`misc` 分区、`/data` 都不是病因。
`fsg` 写过签名正确的 `amss_fsg_lilac_tar.mbn` 并验证重启后未被覆盖,SIM 依然不认;
`misc` 除 BCB 全零外只有两条 64 字节记录,结构正常;`/data` 全清 + `/system` 重装
也毫无影响。**只有 modemst 写回才修好。**

---

## 三、动手机之前必做的检查(只读,无风险)

### 1. 确认 Flash Mode 通(最重要)

先**不要刷任何东西**,只验证能不能进 Flash Mode、newflasher 能不能认到设备。
Flash Mode 通 = 救砖路径存在。这一步没验证过就刷 bootloader,等于赌。

### 2. 记录当前状态

```
fastboot getvar version-bootloader     # 期望最终= P_114;出厂/降级后常见 P_110
fastboot getvar unlocked
fastboot getvar all                    # 留一份完整底稿
```

指南反复强调:**排查起点永远是 `getvar version-bootloader`**。不要假设刷了固件
就一致 —— 实测降级到 Android 8 后,机器上仍可能是 P_110 而不是固件自带的 O_82。

### 3. 备份 modemst(EFS)

`modemst1` / `modemst2` = `/dev/block/sda49` / `sda50`,各 2MB,存射频校准数据和
加密的 IMEI。它是「手机能打电话」的根,**有 root 的时候顺手备份一份**
(Android 8 + bindershell 阶段即可做):

> **实测订正(2026-09-23)**:原先写的「刷机本身不会动它们(官方固件里没有 modemst
> 镜像)」**是错的**。原厂整包里 `amss_fs_1.sin` / `amss_fs_2.sin`(各约 1.3 KB)
> 刷的**就是** `modemst1` / `modemst2`,实测日志里明确有
> `flash:modemst1 OKAY` / `flash:modemst2 OKAY`。
> 那只是写 fs 头部的小配置块、不是整份 EFS,也属于正常官方刷机流程,
> 但「刷机完全不碰 modemst」这个说法必须收回 —— 所以这份备份要在**动手机之前**
> 就做好,而不是指望它没被改过。

```
dd if=/dev/block/bootdevice/by-name/modemst1 of=/sdcard/modemst1.img
dd if=/dev/block/bootdevice/by-name/modemst2 of=/sdcard/modemst2.img
```

备份有效性判断:大小必须是 2,097,152 字节,且文件里有 `IMGEFS` 魔数、非 FF 比例
高(实测 99.6%)。详细校验与写回流程见 `so02k-guide/docs/06-efs-restore.md`。

> ✅ **这份备份不是「以防万一」,它已经救过机了(2026-09-24)。** 本机刷完后出现
> 「系统正常但完全不认 SIM / 无 IMEI」,把 `backup/modemst1.img` / `modemst2.img`
> 写回后立刻恢复 `LOADED` + `IN_SERVICE (LTE)`,重启后持久。完整流程见
> **场景 D**。当天实测当前(坏的)modemst 与这份备份**逐字节差异达
> 2,088,475 / 2,097,152(99.6%)**,即整份内容已被改写。

> **2026-09-24 实测补全**:
>
> - **魔数不在文件开头,而在字节偏移 40**(前面有 40 字节头)。用 `od -c | head -1`
>   只看开头会以为没有魔数 —— 要用 `grep -abo "IMGEFS" file` 才找得到。
> - 已备份到 `backup/` 的三份实测值:
>
> | 文件 | 大小 | 非 FF 字节 | 占比 |
> |---|---|---|---|
> | `modemst1.img` | 2,097,152 | 2,088,953 | 99.58% |
> | `modemst2.img` | 2,097,152 | 2,088,891 | 99.59% |
> | `TA.img` | 2,097,152 | 2,094,289 | 99.85% |
>
> ⚠ **踩坑记录**:在 `/data/local/tmp` 里用 root `dd` 出来的文件是 **`root:root` 且
> 权限 `600`**,而 `adb pull` 是以 `shell`(uid 2000)身份跑的,**读不了** ——
> 报 `remote open failed: Permission denied`,本地会留下 **0 字节空壳**
> (sha256 是 `e3b0c442…`,即空文件的哈希)。
> 所以 root 侧 dd 完必须补一句 `chmod 644`,或者干脆写到 `/sdcard/`。

> 注意:fastboot 层对 modemst 有额外写保护(报 `Flashing is not allowed`),
> 与解锁状态无关。写回要绕到 TWRP 里 `dd`,不能用 `fastboot flash`。

### 4. TA / DRM

解锁会永久失效 DRM 密钥(Widevine L1 等)。TA 分区的读取同样需要 root,**要留就
在 bindershell 阶段一起 dd 出来**。这是「不后悔」性质的备份,不影响救砖。

---

## 四、进度与待办

### 已经做完的

| 项目 | 状态 |
|---|---|
| Flash Mode 驱动 `VID_0FCE&PID_B00B` | ✅ 已装(`oem23.inf`) |
| fastboot 驱动 `VID_0FCE&PID_0DDE` | ✅ 已装(`oem30.inf` → WinUSB) |
| **Flash Mode 连通性实测** | ✅ **已用 newflasher 实测认到设备、读到型号/序列号**,写入 0 字节 |
| 只读状态留档 | ✅ `probe/device-state-2026-09-23.md` |
| 当前系统 | ✅ Android 9 `47.2.B.5.38` |
| 当前 bootloader | ✅ **`LA2.0_P_114`** —— 正是 xperable 需要的那版,**已出厂自带** |

Flash Mode 这一项是「救砖路径存在」的实证,不是推断:手机进 Flash Mode 后
newflasher 能正常握手并读出 `SO-02K / BH90****** / Secure: yes`(序列号后段已隐去)。

### 各阶段状态(按顺序)

| 阶段 | 状态 |
|---|---|
| **1. 降级到 Android 8 `47.1.F.1.105`** | ✅ **2026-09-23 完成** —— 23 个 `.sin`、20 个分区、195 个 `OKAY`、0 错误 |
| **2. bindershell → 刷 O_77 XFL → 备份** | ✅ **2026-09-24 完成**(见下) |
| **3. 刷 P_114 bootloader** | 🚫 **已永久取消**(见下) |
| **4. xperable 解锁** | ✅ **2026-09-24 完成**(见下) |
| **5. TWRP + LineageOS 22.2** | ✅ **2026-09-24 完成**(见下) |
| **6. 重装 ROM + GApps(修 user 误 wipe)** | ✅ **2026-09-24 完成**(见下) |
| **7. 修复「不认 SIM / 无 IMEI」** | ✅ **2026-09-24 完成** —— 写回 `backup/modemst1/2.img`,见 **场景 D** |

**阶段 1 实测结论(这条是整份文档最重要的实测):**

降级刷完后 `fastboot getvar version-bootloader` 仍是

```
1306-5035_X_Boot_MSM8998_LA2.0_P_114
```

即 **P_114 完整保住**。写入清单里也确实没有 `bootloader` / `abl` / `xfl`。
源码推出的「原厂整包刷写够不着引导链」在真机上坐实了。

→ **阶段 3 永久划掉。** 整条链上唯一会动 bootloader 分区、唯一不可恢复的一步,
现在不存在了。**从这一刻起本流程的所有操作都是可恢复的。**

**阶段 2 实测结论(2026-09-24):**

bindershell(CVE-2019-2215)**第一次尝试即成功**,拿到临时 root。设备状态
`Android 8.0 / SDK 26 / 安全补丁 2018-11-01 / 内核 4.4.78-perf+` ——
补丁日期早于该漏洞 2019-10 的修复,漏洞窗口对得上。

⚠ **临时 root 只在那一条 shell 会话内有效**,bindershell 一退出就打回 `shell`。
所以所有动作必须在**同一次 bindershell 会话**里连着做完(做法:把命令写成脚本
push 上去,再 `./bindershell < 脚本`)。同样地,root 建的产物是 `600 root:root`,
**拉取前要 `chmod 644`**。

O_77 XFL 写入 `xfl` 分区(`/dev/block/sda25`),实测:

```
dd if=/data/local/tmp/xfl-o77.mbn of=/dev/block/bootdevice/by-name/xfl bs=4096
→ 13153250 bytes transferred
```

**回读校验(手机上算 + PC 上复核,两边一致):**

```
dd if=/dev/block/bootdevice/by-name/xfl bs=13153250 count=1 | sha256sum
→ c745a32721d68bb7499a0e929bd9bcfec307cb922d0c17c22f064a51e6e1a7c7
```

与 `tools/xfl-o77.mbn` 逐字节相同 ✅ —— **XFL 现在确实是 O_77。**

覆盖前的 xfl 整份已存为 `backup/xfl-p114-backup.img`(31,457,280 字节)。
`xflbak`(`/dev/block/sda26`)**全程未动** —— 保留索尼自己的备份槽。

**注**:`dd` 用的 `bs=13153250 count=1` 是刻意的 —— 设备上的 toybox `head`
**不认 `-c` 参数**(报 `head: not integer: c`),所以回读校验不能靠 `head -c`。

**阶段 4 实测结论(2026-09-24):解锁成功,DRM 保住。**

```
xperable.exe -v -V -B -U -s 0xf49880 -4
```

`-4` 把 LinuxLoader 补丁打进 ABL **内存**(不写 flash):patch 落在 `0x98db9000`,
距离 `0x00f45000` —— 与上游 j4nn 的 XZ1 日志逐字一致。

```
xperable.exe -c "oem unlock Y" -1 -c reboot -1
→ OKAY
```

⚠ **`oem unlock Y` 只是个「待生效标志」** —— 命令返回 `OKAY` 之后 `getvar unlocked`
仍然是 `no`,**必须重启一次才落地**。`fastboot reboot-bootloader` 之后:

```
unlocked: yes
secure:   no
version-bootloader: 1306-5035_X_Boot_MSM8998_LA2.0_P_114   ← 没变
```

✅ 解锁成功,且按上游 README 第 26 行,**这条路径解锁不会抹掉索尼 DRM 设备密钥**
(和官方解锁码路径不同)。

⚠ **解锁的代价:开机会多一屏「解锁警告」**(Sony logo 之后、LineageOS 动画之前,
带开锁小图标 + 警告文字)。这一屏是**签名的 bootloader(ABL)自己画的,不是 Android 画的**
—— 所以**在解锁状态下无法删除、无法改样式**,每台解锁的 Xperia 都有。
**唯一**的消除办法是重新锁上 bootloader,而**当前配置下绝对不要那么做**:
装了 LineageOS + 自编译内核之后 `fastboot oem lock` 有硬砖风险,而且锁上就起不来了
(自编译内核过不了 verified boot)。

已核实这屏**不是刷机刷出来的**:

- 两版原厂 .ftf 解出的 `restore/` 目录里**都没有 `splash.sin`** → newflasher 从没写过 `splash`
  (`splash` = `/dev/block/sda43`,`0x20A4000` = 34,225,152 字节,**原厂内容未动**)
- ABL 是原厂 `LA2.0_P_114`(阶段 3 永久取消,`-4` 只改内存)→ **bootloader 未被修改**

⚠ **该屏在本机上还有显示异常(2026-09-24,用户报告)**:
警告屏会**连续闪烁多次并出现重影**,但**只在开机这一段**;进 Android 后显示完全正常
(`720x1280@60Hz`,无异常)。判断:

- **不是硬件故障** —— 面板在 Android 下正常;硬件坏会一直重影
- **不是刷机造成的** —— 见上面两条核实(`splash` 未动、ABL 未改)
- 位置在 **ABL → 内核的显示交接**:面板在内核起来时被重新初始化,上一帧残留 → 重影;
  反复重初始化 → 闪烁。**自编译内核(`4.4.302-JustinLin099`)是最可能的变量**
- ⚠ **不建议为此换内核**:DCM-KSU 变体的内核带 FeliCa(cxd224x)驱动,换通用 lilac 内核
  很可能把**おサイフケータイ 弄坏** —— 而那正是当初选这个 ROM 的理由。**代价不对等。**
- 纯外观问题,**不影响系统、不影响数据、也不影响救砖**(`boot` 分区随时可重刷)

**阶段 5 实测结论(2026-09-24):TWRP + LineageOS 22.2 已刷入。**

⚠ **三条与指南不符的实测**,记下来:

1. **`fastboot format userdata` / `format cache` 在本机不可用** —— platform-tools 30.0.5
   里没有 `make_ext4fs`,报 `CreateProcess failed: 系统找不到指定的文件。 (2)` /
   `Cannot generate image for userdata`。改用**设备上的 `twrp format data`** 做真正的
   格式化(FBE 死循环要的是 format,**不是 erase**)。
2. **`fastboot reboot recovery` 在这台索尼 ABL 上是空操作** —— 打印
   `Rebooting into recovery OKAY`,但 55 秒后设备以 `PID_01F4`(MTP = 普通 Android)
   回来,不是 TWRP(`PID_71F4`)。**进 recovery 只能靠按键组合**
   (先 Power + 音量上 强制关机,再 音量下 + Power)。
3. **指南 5.2 的结论是错的** —— 它断言写 FOTAKernel 只能靠 bindershell `dd`,
   但它只试过 `fastboot flash recovery`,而 Yoshino **根本没有 recovery 分区**。实测:

```
fastboot flash FOTAKernel twrp-3.5.2_9-0-lilac.img
→ Sending 'FOTAKernel' (33688 KB) OKAY
→ Writing 'FOTAKernel' OKAY
```

(33688 × 1024 = 34,496,512 = TWRP 镜像精确大小。)

解锁之后 `fastboot flash FOTAKernel` 直接可用,**省掉一整轮「回 Android 8 + bindershell」**。
TWRP 版本必须是 **3.5.2_9-0**(3.7.x 会崩)。

安装 ROM:没用 `adb sideload`,而是先 `adb push` 到 `/data`(21 GB 空间够),
**在设备上再核一次 sha256**,确认无误后用 `twrp install` 安装。结果:

```
script succeeded: result was [1.000000]
I:Updater process ended with RC=0
bytes_written_vendor: 465244160
```

⚠ **「日志里没有写 boot 的那一行」是虚惊。** `updater-script` 的最后一步确实是

```
package_extract_file("boot.img", "/dev/block/bootdevice/by-name/boot");
```

但它**不打印任何东西**,所以日志里看不见。实测比对:

| | sha256 |
|---|---|
| zip 里 `boot.img`(17,608,704 字节) | `43917d758a4a85281bdbc9713d4c578a0d193527e9cd4bde0f49a1d752b3cbb2` |
| 手机 `boot` 分区前 17,608,704 字节 | `43917d758a4a85281bdbc9713d4c578a0d193527e9cd4bde0f49a1d752b3cbb2` |

**逐字节一致 ⇒ 内核确实写进去了**,头部魔数 `ANDROID!` 正常。

(ROM 里还带了个 `recovery.img` 29 MB,但**脚本不写它** —— FOTAKernel 里的 TWRP 原样保留。)

**阶段 5.4 验收(2026-09-24,全部通过):**

重启后**第 100 秒**进入系统。逐项对照指南 5.4:

| 检查项 | 期望 | 实测 | |
|---|---|---|---|
| `ro.build.version.release` | `15` | **15** | ✅ |
| `ro.lineage.version` | `…lilac_dcm` | **`22.2-20260522-UNOFFICIAL-lilac_dcm`** | ✅ |
| `ro.product.model` | `SO-02K` | **SO-02K** | ✅ |
| `dumpsys nfc \| grep mState` | `on` | **`mState=on`** | ✅ |
| `ro.boot.flash.locked` | `0` | **0** | ✅ |

补充实测值:

```
内核                4.4.302-JustinLin099  (#110 SMP PREEMPT Sat May 23 01:42:43 CST 2026)
SELinux             Enforcing
ro.build.type       userdebug            (ro.debuggable=1)
verifiedbootstate   orange               ← 已解锁
ro.build.id         BP1A.250505.005      ← Android 15 的 build id
```

⚠ **`ro.build.fingerprint` 是刻意伪装的**:

```
Sony/G8441/G8441:9/47.2.A.11.228/3311891731:user/release-keys
```

这是**原厂 Android 9 的指纹**,而 `ro.build.id` 是 Android 15 的 —— 两者对不上,
是 DCM 变体**故意保留原厂指纹**(日版 FeliCa / おサイフケータイ 一类服务会校验设备指纹)。
**别把它当成「没刷干净」。**

**KernelSU(选 DCM-KSU 变体的理由)—— 内核里有,管理器没装:**

```
zcat /proc/config.gz | grep -i ksu
→ CONFIG_KSU=y
  CONFIG_KSU_MANUAL_HOOK=y
  # CONFIG_KSU_DISABLE_MANAGER is not set
```

内核确实编入了 KernelSU,`/data/adb/ksu/` 也已由内核建立(以 shell 访问报
`Permission denied` 而非 `No such file or directory`)。但**系统里没有 KernelSU
管理器 App**(`pm list packages | grep -i ksu` 为空),`su` 也不在任何 PATH 里 ——
所以**现在还不能真正提权**,要装管理器才能授权。

**另注**:`adb root` 默认被关,报
`ADB Root access is disabled by system setting`;要在
*设置 → 系统 → 开发者选项 → Rooted debugging* 里打开。打开后 `adb shell dd`
就能读裸分区,可用来做只读校验(例如核对 FOTAKernel 里的 TWRP 是否还在)。

**遗留**:`/data/lineage.zip`(1,043,421,503 字节 ≈ 995 MB)还在设备上。
确认系统没问题后可以删掉回收空间 —— PC 上的原始 zip 与 sha256 都在,随时能重新 push。

---

**阶段 6 实测结论(2026-09-24):固件底包不匹配导致「SIM 不认」—— 已修复。**

首次装完 LineageOS 后冒出两个问题:**识别不到 SIM 卡**、**没有谷歌商店**。

**「没有谷歌商店」是预期现象**,不是故障 —— LineageOS 不带 GApps,必须自己刷
(见本节末的 GApps 硬约束)。

**「SIM 不认」的根因是固件底包不匹配**,不是硬件问题,也不是解锁造成的:

| | 首次装 LineageOS 时 | 修复后 |
|---|---|---|
| `gsm.version.baseband` | **空** ❌ | **`8998-8998.gen.prodQ-00278-47`** ✅ |
| `gsm.sim.state` | — | `LOADED` ✅ |
| `simSlotIndex` | **-1** ❌ | **0** ✅ |
| `gsm.network.type` | — | `LTE` ✅ |
| ServiceState | — | `mVoiceRegState=0(IN_SERVICE)` / `mDataRegState=0(IN_SERVICE)`;CS/PS 均 `registrationState=HOME`;可用业务 `[VOICE,SMS,VIDEO]` + `[DATA,MMS]`;`mIsEmergencyOnly=false` ✅ |

**机理**:阶段 1 为了拿到漏洞窗口把整机降级到 Android 8,于是 `modem` / `dsp` /
`fsg` / `bluetooth` / `amss_fs_*` 等**固件分区全变成了 Android 8 版本**;而
LineageOS 22.2 的 lilac 构建是**针对 Android 9 固件编译的**(ROM 自带的
`updater-script` 里就写着 `Target: Sony/G8441/G8441:9/47.2.A.11.228/3311891731`)。
底包对不上 → **modem 固件加载不起来**(`gsm.version.baseband` 为空就是直接证据),
SIM 自然认不到。

**决定性验证**:刷回原厂 Android 9 后 SIM 立刻正常(`baseband` 有版本号、
`simSlotIndex=0`、`registrationState=HOME`)。**前后对比成立 ⇒ 根因确认。**

**修复流程(实测,可复用):**

```
① newflasher 刷原厂 Android 9 整包(CWD = restore/stock-9.0-47.2.B.5.38)
   199 个 OKAY、0 错误、退出码 0;写入 20 个分区
   bootloader / xfl 未写   → P_114 与 O_77 XFL 都保住
   第 4 问 persist 答 n    → 跳过 persist,attest key 与传感器校准保住
   ⚠ 代价:FOTAKernel 被原厂覆盖(TWRP 没了)、userdata + cache 清空
② 开机进原厂 Android 9,确认 SIM 正常        ← 决定性验证,已通过
③ fastboot flash FOTAKernel twrp-3.5.2_9-0-lilac.img    ← 重刷 TWRP
④ 按键组合进 TWRP(这台 ABL 不认 fastboot reboot recovery,见阶段 5 第 2 条)
⑤ twrp format data
⑥ adb push 两个 zip 到 /sdcard + 设备上核 sha256
⑦ twrp install ROM → 紧接着 twrp install MindTheGapps(**中间不重启**)
⑧ 重启
```

**三条本轮新增的实测经验:**

1. ⚠ **没有外置 SD 卡时,`format data` 必须在 push 之前做。**
   实测 `/dev/block/mmcblk*` 不存在(本机只有 UFS 的 `sda*`),`/storage` 为空,
   `/sdcard1` 是个没挂载的空挂载点。而 `format data` 会连 `/sdcard`
   (= `/data/media`)一起清掉 —— **先 push 再 format,文件会白推。**

2. ✅ **TWRP 里有 root,可以直接 `dd` 读裸分区做校验。**
   阶段 5 时 `adb root` 被系统设置挡着(`ADB Root access is disabled by system
   setting`),核对 `boot` 分区只能靠**推论**(因为 `package_extract_file` 不打印日志)。
   这次在 TWRP 里直接读,**推论变成了实证**:

   | | sha256 |
   |---|---|
   | zip 里 `boot.img`(17,608,704 字节) | `43917d758a4a85281bdbc9713d4c578a0d193527e9cd4bde0f49a1d752b3cbb2` |
   | 设备 `boot` 分区前 17,608,704 字节 | `43917d758a4a85281bdbc9713d4c578a0d193527e9cd4bde0f49a1d752b3cbb2` |

   同一方法核了 FOTAKernel,**确认 ROM 没有覆盖 TWRP**:

   ```
   69483df57d8d37d631a13b8204d4dee269f7d952f6f2e469eb18ab04bd73d4ee  ← 设备 FOTAKernel
   69483df57d8d37d631a13b8204d4dee269f7d952f6f2e469eb18ab04bd73d4ee  ← tools/twrp-3.5.2_9-0-lilac.img
   ```

   读法:`dd if=/dev/block/bootdevice/by-name/boot bs=4096 count=4299`
   (4299 × 4096 = 17,608,704);分区名换成 `FOTAKernel`、`bs` 换成 TWRP 字节数即可。

3. ⚠ **开机后 SIM 注册要 30~120 秒,采样太早会看到假的「只能拨打紧急呼叫电话」。**
   本轮第一次采样正好落在瞬态窗口里,差点误判。telephony 的状态流水记下了完整过程:

   ```
   17:49:01  OUT_OF_SERVICE
   17:49:03  mIsEmergencyOnly=true, availableServices=[EMERGENCY]        ← 采样点
   01:49:28  IN_SERVICE, registrationState=HOME, [VOICE,SMS,VIDEO]/[DATA,MMS]  ← 注册完成
   ```

   (中间的时间跳变是设备时钟拿到网络时间后校正 —— 开机时 RTC 还停在 ROM 编译日期。)

   → **判断 SIM 是否真的可用,要看 `dumpsys telephony.registry` 里的 `mServiceState`
   和 `registrationState`,不要只看 `dumpsys isub` 里的 `carrierName`。**

   ```
   mVoiceRegState=0(IN_SERVICE), mDataRegState=0(IN_SERVICE)
   CS/PS: registrationState=HOME    mIsEmergencyOnly=false
   ```

**🔴 一条必须记住的规则:**

> **`boot` / `modem` / `dsp` / `fsg` / `bluetooth` / `amss_fs_*` / `rdimage` 这些
> 固件分区,一旦被 Android 8 整包刷过,就必须再刷一遍 Android 9 整包才能回到与
> LineageOS 匹配的状态。**
>
> **只重刷 LineageOS 没用 —— ROM 完全不碰固件分区。**

**⚠ GApps 的硬约束:**

MindTheGapps **必须在 ROM 第一次开机之前**刷进去(`format data` → 刷 ROM →
**紧接着**刷 GApps,**中间不重启**)。一旦先开机,Play Services 会崩,只能重来一遍
`format data`。

| 文件 | 大小 | sha256 |
|---|---|---|
| `gapps/MindTheGapps-15.0.0-arm64-20260915_032013.zip` | 507,472,816 | `e979601ef70b03d9214ea24ca7a103cb408ab102718fff38ec170a6ca03e263d` = 官方 `.sha256sum` ✅ |

装完的验收:`pm list packages` 里应有 `com.android.vending`(Play 商店本体)、
`com.google.android.gms`(Play 服务)、`com.google.android.gsf`。

**遗留**:`/data` 已被 format,阶段 5 留下的 `/data/lineage.zip` 一并清掉了。
现在设备上只有本轮 push 的两个 zip(确认系统稳定后可删,
PC 上的原始文件与 sha256 都在,随时能重新 push):

```
/sdcard/lineage-22.2-20260522-UNOFFICIAL-lilac-DCM-KSU.zip   1,043,421,503 字节
/sdcard/MindTheGapps-15.0.0-arm64-20260915_032013.zip          507,472,816 字节
```

---

## 五、目录速查

```
xz1c-flash/
├── RECOVERY.md                    ← 本文
├── firmware/                      ← 原始 .ftf + LineageOS ROM(已校验)
├── restore/                       ← 解包好、带 newflasher.exe,可直接刷
│   ├── stock-9.0-47.2.B.5.38/          救砖主力
│   ├── stock-8.0-47.1.F.1.105/         降级用
│   └── p114-bootloader-only/           阶段 3 只刷 bootloader
├── tools/                         ← xperable.exe(自建)+ XFL + LinuxLoader + TWRP
├── kit/                           ← newflasher / bindershell / busybox / platform-tools
│   └── xfl-copies/                     XFL 的两个来源副本(互为交叉验证)
├── blobs/                         ← 提取出的 P_114 bootloader 等中间产物
├── backup/                        ← 空目录,modemst / TA 的 dump 放这里
├── so02k-guide/                   ← 参考指南原文
├── probe/                         ← 各种校验日志与抓取内容
├── x/  y/                         ← 解包 bootloader 的临时产物,可忽略
└── bootloader-p114-99C3.sin       ← blobs/ 里同名文件的顶层副本,可忽略
```

### ⚠ 刷机前务必确认

**`tools/` 目录里放的就是要刷进手机的东西。只认下面这三个哈希,别的文件一律不要刷:**

```
c745a32721d68bb7499a0e929bd9bcfec307cb922d0c17c22f064a51e6e1a7c7  xfl-o77.mbn
e8919094432714805980fd113806faaa65648dc9fabd7ae5912540579ef1e51b  LinuxLoader-p114.pe
c7217b49b995b63515007d385c50c1ca5b747a1b0813f747d0956c7d705baeb0  xperable.exe
```

> 本次整理时删掉了一个 `blobs/xfl-o77_new.mbn.part`(12,582,912 字节,是个没下完的
> 残片,完整版应为 13,112,290)。**`.part` 后缀的一律是未完成下载,绝不能刷。**
