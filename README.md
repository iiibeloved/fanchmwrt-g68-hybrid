# NSY G68-PLUS · FanchmWrt 杂交固件

[![构建状态](https://github.com/iiibeloved/fanchmwrt-g68-hybrid/actions/workflows/build.yml/badge.svg)](https://github.com/iiibeloved/fanchmwrt-g68-hybrid/actions/workflows/build.yml)
[![最新 Release](https://img.shields.io/github/v/release/iiibeloved/fanchmwrt-g68-hybrid)](https://github.com/iiibeloved/fanchmwrt-g68-hybrid/releases/latest)

> 一句话简介：给 **农商云 NSY G68-PLUS（RK3568 / RTL8367S）** 用的 **FanchmWrt 原生**固件，保留 FanchmWrt 的行为管理能力（`fwx` + `shortcut-fe` + 原生主题），并加入**长按 Reset 直接进 MaskROM** 的刷机体验；网络采用久经真机验证的 **RTL8367S / swconfig（4 个 LAN + 1 个 WAN）** 方案。

如果你是第一次接触本固件，建议只看下面四节即可完成刷机：**[固件特点](#二固件特点) → [刷机前注意事项](#四刷机前注意事项) → [刷机方法](#五刷机方法) → [刷机后注意事项](#六刷机后注意事项)**。其余章节是进阶说明。

> 本仓库是**独立产品线**：与 [iStoreOS swconfig 版](https://github.com/iiibeloved/istoreos-hybrid-g68) / [DSA 版](https://github.com/iiibeloved/istoreos-hybrid-g68-dsa) 共用 G68 设备层与刷机方式，但**系统基座、管理地址、软件生态不同**——本固件是 FanchmWrt 原生风格（无商店 / 无向导 / 无 Argon），管理地址 `192.168.1.1`，刷前请分清下载的是哪个仓库的镜像。

---

## 目录

- [一、这是什么](#一这是什么)
- [二、固件特点](#二固件特点)
- [三、包含内容](#三包含内容)
- [四、刷机前注意事项](#四刷机前注意事项)
- [五、刷机方法](#五刷机方法)
- [六、刷机后注意事项](#六刷机后注意事项)
- [七、下载与校验](#七下载与校验)
- [八、已知限制](#八已知限制)
- [九、常见问题](#九常见问题)
- [十、技术实现（进阶）](#十技术实现进阶)
- [十一、本地构建](#十一本地构建)
- [致谢](#致谢)

---

## 一、这是什么

本固件面向 **RK3568 架构的 G68-PLUS 软路由 / NAS 小板**，把三套经过验证的成果合在一起：

| 组成 | 来源 | 带来的好处 |
| --- | --- | --- |
| **系统基座 / 内核 / 行为管理** | [FanchmWrt](https://github.com/fanchmwrt/fanchmwrt) `fanchmwrt-25.12.6`（OpenWrt 25.12 / 内核 **6.12.112** / **apk** / U-Boot **2025.10**） | `fwx.ko` + `fwxd` + `shortcut-fe` + `luci-theme-fanchmwrt`，家长控制 / 上网行为管理等原生能力 |
| **设备适配层（swconfig 双 GMAC）** | [zhoufuli/immortalwrt-rk356x](https://github.com/zhoufuli/immortalwrt-rk356x) 的 `nsy_g68-plus`（真机验证 OK 路线） | DTS / VLAN 映射 / RTL8367S 驱动；**不走 DSA** |
| **长按复位进 MaskROM** | 本仓 `device/uboot/`（按 U-Boot **2025.10** 原版重做） | overlay-only 投递 + 三层断言，长按 Reset 即可刷机 |

它**不是 iStoreOS 风格**：无 QuickStart 初始化向导、无应用商城、无 Argon 主题，默认主题为 FanchmWrt 原生。设备适配以“整文件 overlay”方式注入，不在上游维护长期分叉，因此上游升级时冲突面最小。

> 为什么不能直接刷上游成品：FanchmWrt 上游 rockchip 目标只有 radxa / bpi 等板且走 DSA，没有 G68 设备树，刷入会导致网口全乱（重演“LAN 拿不到 IP”）。

---

## 二、固件特点

- **刷机省心：长按 Reset 就能进 MaskROM。** 上电时按住 Reset 键即可被 RKDevTool 识别，无需拆机短接测试点；刷写方式与 immortalwrt / iStoreOS hybrid 固件一致（USB 双公头 + RKDevTool + **强制按地址写**）。
- **5 口全千兆，开箱就能上网。** RTL8367S 由 `swconfig` 驱动正确初始化，划分为 **4 个 LAN 口 + 1 个 WAN 口**；LAN 口 DHCP、WAN 口 DHCP 客户端默认可用，插上网线即可获取地址。
- **FanchmWrt 原生行为管理。** 内置 `fwx`（内核模块 + 守护进程）、`shortcut-fe`、`nft-fullcone` 与全套 `luci-app-fwx-*` 管理界面；蜂窝能力整体移除、SMSC 以太网 PHY 保留，与 hybrid 的能力边界对齐。
- **原生外观，不给“假商城”。** 无 QuickStart / 商城 / Argon；以 `luci-theme-fanchmwrt` 为默认主题，中文覆盖只改少量定制标题，不替换应用实现。
- **稳定可升级、可重复构建。** 滚动 feed 锁到已验证提交、同名包生效来源统一指定、`make defconfig` 后做依赖版本一致性校验；上游更新时自动触发构建，任一守卫失败即中止、不发 Release。
- **多重自动化守卫。** 编译前做静态自检、内核补丁预检、硬件级交叉审核（DTS ↔ 驱动 / 配置 / 包集），并对 u-boot 做源码 / 投递 / 产物三层断言，防止 MaskROM 与网络生命线被上游改动悄悄破坏。
- **中文到位，不留孤儿菜单。** `g68-i18n` 同时识别 apk / opkg，只在对应应用确实安装时才覆盖其中文界面；版本指纹守卫防止上游换实现后旧覆盖把应用降级。

---

## 三、包含内容

### 3.1 主要软件

| 类别 | 代表组件 |
| --- | --- |
| 行为管理 | `kmod-fwx` + `fwxd`、`kmod-shortcut-fe`、`kmod-nft-fullcone`、`luci-app-fwx-*` 全套（dashboard / network / firewall / session-stat 等） |
| 系统外观 | `luci-theme-fanchmwrt`（默认）、`96-g68-fanchm-theme` 首次启动写默认主题 |
| 网络 / DNS | `dnsmasq-full`（DNS + DHCP）、`firewall4`、`netifd`、`swconfig` |
| 交换芯片 | `kmod-swconfig`、`kmod-switch-rtl8366-smi`、`kmod-switch-rtl8367b` |
| USB 网卡 | `kmod-phy-smsc`、`kmod-usb-net-smsc95xx`、`kmod-usb-net-asix-ax88179`（**保留**，与蜂窝无关） |
| 中文 | 官方 `luci-i18n-*-zh-cn`（含 wolplus / timecontrol / control-webrestriction / control-weburl 等）+ 本仓 16 项定制标题覆盖 |

> 完整且权威的清单是每次 Release 附件中的 **`packages.manifest`**（含依赖展开）。本次构建为 **963 个包**；本文只列代表组件，一律以该 manifest 为准。

> 已整体移除：4G/5G/短信相关应用（`wwan` / `comgt` / `qmi` / `mbim` / `modemmanager` / `sms-tool` / `luci-proto-*` 等 32 项），并由双阶段守卫拦截回流。

### 3.2 网口与网络

| 逻辑接口 | 硬件端口 | 角色 |
| --- | --- | --- |
| `lan`（br-lan） | RTL8367S port 0~3 | 4 个 LAN 口，同一网桥，硬件二层转发，DHCP 服务端 |
| `wan` | RTL8367S port 4 | 1 个 WAN 口，DHCP 客户端（可改 PPPoE） |
| CPU 上联 | port 6u → `eth0`、port 7u → `eth1` | 交换芯片与 SoC 的两条上联（SGMII fixed-link） |

- 物理网口编号与逻辑口（LAN/WAN）的对应以刷机后实测为准（见 [刷机后注意事项](#六刷机后注意事项)）。
- 面板上的 2.5G 标识口实际按 SGMII **1000 Mb/s** fixed-link 工作（与 hybrid 同一硬件，真机实测），不是 2500 Mb/s。

### 3.3 分区布局

| 分区 | 大小 | 用途 |
| --- | --- | --- |
| `uboot` | 16 MiB | u-boot / SPL |
| `kernel` | 16 MiB | 内核 + DTB（FIT 镜像） |
| `rootfs` | 500 MiB | 只读 squashfs 系统 |
| `rootfs_data` | 4096 MiB | 可写 overlay（配置、apk 数据、Docker 数据） |

> 本次镜像约 **187 MiB**（squashfs 压缩后，196,028,129 字节）。`rootfs_data` 在镜像中只写 MBR 分区表标称 **4096 MiB**，文件系统首次启动时自动创建——所以**不要用镜像文件大小判断是否完整**，产物校验是读 MBR 分区表完成的。

---

## 四、刷机前注意事项

1. **准备工具**：双公头 USB 数据线、`RKDevTool_Release_v3.18`、驱动 `Rockchip_DriverAssitant_v5.12`，以及**解压成 `.img` 的固件**（刷机工具不认 `.img.gz`）。
2. **核对文件**：下载后用 `sha256sum -c sha256sums` 校验镜像，不一致请重新下载。
3. **备份配置**：旧系统还能进入时，先在 LuCI「系统 → 备份/升级」导出配置备份。
4. **接对 USB 口**：用靠近网口一侧的 **USB OTG 口**连接电脑。
5. **保证供电**：刷写与首次启动期间**不要断电**，eMMC 写入中断最难恢复。
6. **理清网口角色**：本固件是 **4 LAN + 1 WAN**；刷机后需按实测确认哪个口是 WAN，再把上级路由 / 光猫接到 WAN 口（见第六节）。
7. **管理地址预期**：默认网关为 **`192.168.1.1`**（FanchmWrt / OpenWrt 25.12 基座默认）。**这与 iStoreOS hybrid 的 `192.168.100.1` 不同**——如果电脑上不了 `192.168.100.1`，试试 `192.168.1.1`，或以实际获取到的默认网关为准。

---

## 五、刷机方法

### 5.1 系统还能进 → 在线升级（仅限已刷本固件的设备）

```
LuCI → 系统 → 备份/升级 → 上传 .img.gz → 勾选「保留配置」（如需清空则不勾）→ 执行
```

> 从 iStoreOS / 其它固件**首次**换到本固件，请用下面的 MaskROM 全擦除流程，不要直接在线升级。

### 5.2 首次刷写 / 进不去系统 → MaskROM（USB 刷机）

1. 电脑安装驱动 `Rockchip_DriverAssitant_v5.12`，打开 `RKDevTool_Release_v3.18`。
2. 设备**断电**，双公头 USB 线连接电脑与设备 OTG 口。
3. **按住 Reset 键不松开 → 接通电源 → 待 RKDevTool 提示“发现一个 MaskROM 设备”后松开 Reset。**
   - 若长按无效，可用拆机短接测试点的传统方式兜底（BROM 模式，loader 相同）。
4. 「高级功能」→ 加载 `rk356x_spl_loader_v1.21.113.bin`，点「下载」。
5. 「获取当前存储」→「**擦除所有**」，进度到 100% 才算成功（若“秒擦除”，需检查 eMMC）。
6. 「下载镜像」→ 选择**解压后的 `.img`** → **勾选「强制按地址写」** → 点击「执行」，等到 100% 成功。
7. 完成后断开 USB、重新上电，接好网线。

> **“强制按地址写”必须勾选**，否则可能写入不完整或校验失败。此处的“地址”是 eMMC 扇区写入地址，与内核 FIT 的 RAM 加载地址（`KERNEL_LOADADDR`）是两个不同阶段，互不冲突（见[技术实现](#十技术实现进阶)）。

---

## 六、刷机后注意事项

> 本节是新旧版本差异最容易被忽略的地方，请按序号操作。

1. **耐心等待首次启动（约 1~3 分钟）。** 首次开机会创建 `rootfs_data` 文件系统并执行初始化脚本，期间网口灯可能闪烁、页面暂时打不开，属正常现象；**不要在此阶段断电或反复重启**。
2. **进入管理页并修改密码。** 浏览器访问 **`http://192.168.1.1`**（或在电脑命令行执行 `ipconfig` / `route -n` 查看默认网关；若之前刷过 hybrid 且 dhcp 记录了旧地址，注意区分）→ **第一时间修改 root 密码**。本固件无 QuickStart 向导，直接进 LuCI。
3. **先确认 LAN，再接 WAN。**
   - 电脑接任意 LAN 口，应能自动获取 `192.168.1.x` 地址并打开管理页——**能打开管理页，说明交换机驱动与 LAN/DHCP 已正常工作**（旧版“只能当交换机、拿不到 IP”的问题即出在此环节，新固件已修复）。
   - 再把上级路由 / 光猫的网线接到 **WAN 口**，WAN 默认 DHCP 获取地址；如需 PPPoE，在「网络 → 接口」中改为拨号并填入账号密码。
4. **核对网口物理对应。** 逐一插拔网线，确认哪个口是 WAN、哪些是 LAN，并在网络接口页观察连接状态；LAN 口之间应能互相通信，WAN 口不应出现在 br-lan 网桥中。
5. **验证外网。** 在「系统 → TTYD / SSH」执行 `ping -c3 223.5.5.5`，全通即表示网络正常。本固件用 apk，包管理命令为 `apk add`，不是 `opkg install`。
6. **验证中文界面。** 中文覆盖为条件投递 + 版本指纹守卫；若某应用界面仍是英文，确认对应 `luci-i18n-*-zh-cn` 已安装，并对 `www/luci-static/*.js` 强刷一次浏览器缓存。
7. **验证 MaskROM 能力（可选）。** 下次需要刷机时，用第五节的长按 Reset 流程验证一次即可；平时不必反复进 MaskROM。
8. **完成配置后备份。** 系统 → 备份/升级 → 生成配置备份并妥善保存，便于日后恢复。
9. **常见误区**：
   - 只接了 LAN 口、没接 WAN → 能进管理页但上不了外网，属正常，接好 WAN 即可。
   - 上级路由 LAN 口与本机 LAN 同为 `192.168.1.x` → 地址冲突，先在「网络 → 接口 → LAN」把本机 LAN 改到其它网段。
   - 访问 `192.168.100.1` 打不开 → 本固件默认地址是 `192.168.1.1`（FanchmWrt 基座），不是 hybrid 的地址。

---

## 七、下载与校验

- **最新 Release**：<https://github.com/iiibeloved/fanchmwrt-g68-hybrid/releases/latest>
- 版本号、镜像与校验值**以 Release 页面为准**（本仓库会持续更新，本文不写死版本号与哈希，避免过期）。

| 资产 | 说明 |
| --- | --- |
| `openwrt-rockchip-armv8-nsy_g68-plus-squashfs-sysupgrade.img.gz` | 固件镜像（约 187 MiB，刷机前需解压） |
| `sha256sums` | 镜像校验值 |
| `packages.manifest` | 本次构建完整包清单（含依赖展开，以 Release 附件为准） |

**国内加速**（把 `<tag>` 和 `<file>` 替换为实际版本号与文件名，`https://` 后拼接以下前缀）：

- `https://gh-proxy.com/https://github.com/iiibeloved/fanchmwrt-g68-hybrid/releases/download/<tag>/<file>`
- `https://ghfast.top/https://github.com/iiibeloved/fanchmwrt-g68-hybrid/releases/download/<tag>/<file>`
- `https://ghproxy.net/https://github.com/iiibeloved/fanchmwrt-g68-hybrid/releases/download/<tag>/<file>`

---

## 八、已知限制

- **不使用 WiFi**：G68 的 MT7916 未启用（WiFi 栈整体不选），需要无线请另行方案。
- **DNS/DHCP 用 `dnsmasq-full`**：与 `dnsmasq` 互斥，二者只能选其一。
- **2.5G 口实为 1000 Mb/s**：SGMII fixed-link 真机实测值。
- **无 QuickStart / 商城 / Argon**：这是刻意选择的 FanchmWrt 原生风格，不是缺少功能；需要软件包页面可自行把 config 里 `luci-app-package-manager` 改为 `=y`（它是 LuCI 原生列表页，不是商城）。
- **无蜂窝能力**：4G/5G/短信整体移除，需要请另选固件。
- **家长控制用途限制**：FanchmWrt 上游声明家长控制功能仅供个人使用，不得用于公司或集成进商用产品（见[授权边界](#致谢)）。
- **需真机验收**：LAN/WAN、eMMC/USB、长按 Reset、中文界面与浏览器缓存建议实机逐项确认。

---

## 九、常见问题

| 现象 | 处理 |
| --- | --- |
| 刷机后只能当交换机、拿不到 IP、无 WAN | 确认所用镜像是带 RTL8367S 驱动的新版（见 Release 的 `packages.manifest` 是否含 `kmod-switch-rtl8367b` / `kmod-switch-rtl8366-smi` / `kmod-swconfig`）；旧版无这些驱动，需重刷新版 |
| 能进管理页但上不了外网 | 检查 WAN 口是否接了上级路由 / 光猫；WAN 是否为 DHCP；上级 LAN 是否与本机能正常连通 |
| 访问 `192.168.100.1` 打不开 | 本固件默认地址是 **`192.168.1.1`**（FanchmWrt 基座），不是 iStoreOS hybrid 的地址；用 `ipconfig` / `route -n` 查实际默认网关 |
| 管理页打不开 | 用 `ipconfig` 查电脑默认网关再访问；首次启动请等 1~3 分钟；确认电脑不在 `192.168.1.x` 之外的静态网段 |
| RKDevTool 找不到 MaskROM 设备 | 检查驱动、USB 线（须为数据线）与 OTG 口；长按 Reset 时序或改用短接触点法 |
| 刷机中途报错 / 校验失败 | 重新“擦除所有”后**勾选“强制按地址写”**再刷；核对 sha256 |
| `opkg` 命令不存在 | 25.12 基座用 **apk**，包管理命令是 `apk add` / `apk info`，不是 `opkg` |
| 某应用中文不生效 | 确认对应 `luci-i18n-*-zh-cn` 已安装；中文覆盖有版本指纹守卫，上游换实现时会主动跳过以防降级；强刷浏览器 JS 缓存 |

---

## 十、技术实现（进阶）

### 10.1 为什么叫“杂交”（Hybrid）

不在 FanchmWrt 上游维护长期分叉的内核 / 设备树；设备层以**整文件 overlay** 交付，上游升级时冲突面最小。三个来源各取所长：FanchmWrt 的行为管理与基座、immortalwrt 真机验证的 G68 设备层、本仓自做的 U-Boot 2025.10 MaskROM overlay。

### 10.2 关键机制

- **长按 Reset → MaskROM**：SPL 阶段读 SARADC 通道 0；按住 Reset 上电即写 BROM 下载标志并复位，RKDevTool 直接识别 MaskROM 设备。u-boot 以 overlay-only 覆盖 `src/`，并由三层断言（`download key pressed` / `adc_channel_single_shot` / `BOOT_MODE_REG=0xfdc20200`）守护。2025.10 起 `setup_boot_mode()` 由上游公共 `board.c:board_late_init()` 调用，产物级断言会检查该调用点仍在。
- **网络生命线（swconfig）**：`swconfig` + `kmod-switch-rtl8366-smi` + `kmod-switch-rtl8367b` + `dnsmasq-full` 缺一禁止构建/发布。内核补丁 `910/913/915` 按 FanchmWrt 的 `v6.12.112 + 039-*` 补丁栈重写，`patch -F0`（零 fuzz）全命中；`verify-network.sh source/dts` 按源码锚点验证，hunk 静默失败即拦截。
- **内核加载地址 vs 刷机写入地址**：FIT 镜像内 `KERNEL_LOADADDR=0x03000000` 是**内核在 RAM 中的加载/入口地址**（跟随 FanchmWrt 25.12 上游 `Device/rk3568` 基类）；刷机“强制按地址写”写的是 **eMMC 扇区地址**。U-Boot 的 `CONFIG_SYS_LOAD_ADDR=0xc00800` 与 `kernel_addr_r=0x02000000` 三套固件一致，因此两者不冲突，也不影响 MaskROM 与分区布局。
- **Feed 防漂移（fail-fast）**：滚动 feed 锁到已验证提交（`configs/feeds.lock`），同名包生效来源统一声明（`configs/feed-precedence.txt`，如 `sing-box` 固定取 `small`）；`dep-guard.sh` 在 `make defconfig` 后遍历所有选中包的版本化依赖做秒级校验。
- **只交付 squashfs**：`CONFIG_TARGET_ROOTFS_SQUASHFS=y`、`CONFIG_TARGET_ROOTFS_EXT4FS` 显式关闭并在 `make defconfig` 后二次压回；收集产物时拒绝任何 ext4 镜像。
- **4096 MiB rootfs_data**：上游 `gen_image_generic.sh` 在 25.12 无 `USERDATASIZE` 锚点，`apply-device.sh` 已在 ptgen 的 `rootfs -p` 后插入第三分区 `-p "${USERDATASIZE:-4096}m"`；产物级 `check-partition-table.py` 只读 gzip 流前 512 字节解析 MBR，要求第三分区标称 4096 MiB，防止“镜像看着对、刷进去 data 分区没了”。
- **中文条件投递（apk / opkg 双识别）**：`g68-i18n` 优先读 `/lib/apk/db/installed` 的 `P:<包名>` 固定串匹配，另有 opkg 回退；`compat_ok()` 版本指纹（行数差 > 2 跳过）；投递后清 LuCI 菜单缓存。覆盖只保留 16 项“与锁定 feed 同版、仅换中文”的文件，24.10 / iStoreOS 时代的整应用实现已全部移除。
- **CI 硬件审核**：`hw-audit.sh` 交叉核对 DTS ↔ 内核配置 ↔ 包集（RTL8367S / XPCS / adc-keys / 存储 / WiFi 豁免），缺关键项阻断构建。

### 10.3 构建流水线

```text
FanchmWrt 官方源 (fanchmwrt-25.12.6)
   │ clone
   ▼
apply-device.sh ──► 设备层注入（DTS / u-boot overlay / 内核补丁 / KERNEL_LOADADDR / 分区 / i18n）
   ▼
patch-preflight ──► 内核补丁预检（上游补丁栈 + G68 补丁，fuzz=0）
selftest / hw-audit ──► 静态自检 / 硬件级审核
   ▼
uboot-check ──► 只编译 u-boot + 长按复位进 MaskROM 三层断言
   ▼
build ──► feed-pin 固定提交 → feed-sources 固定同名包来源
          → defconfig → 关闭 ext4 → verify-critical config（含风格守卫）→ dep-guard
          → 全量编译 → 仅收集 squashfs → check-partition-table（4096 MiB）
          → verify-network source/dts → verify-critical manifest → artifact → Release → 回写 upstream.lock
```

| 作业 | 职责 |
| --- | --- |
| `check-upstream` | 对比上游 commit 与 `upstream.lock`，决定是否构建 |
| `prepare` | 应用设备层、补丁预检、静态自检、硬件审核、包集审计 |
| `uboot-check` | 独立编译 u-boot，验证 MaskROM 链路（源码 / 投递 / 产物三层） |
| `build` | 固定 feed、defconfig 归一化、依赖守卫、全量编译、产物校验、发布 Release、回写 `upstream.lock` |

触发方式：
- `upstream-watch`：每小时比对上游 commit，一有更新立即触发全量构建发布（跟随上游的主力机制）。
- `schedule`：**每周三 02:00 CST**（UTC 周二 18:00）定点检查；仅在上游有更新时构建发版，无变化则跳过，不产生空 Release。
- `push`（device/configs/scripts/workflow 变更）、`workflow_dispatch`（手动）。

仓库为 public，CI 免费额度充足。

### 10.4 仓库结构

```text
configs/
  g68-fanchm.config       主配置（FanchmWrt 原生风格 + hybrid 包集 + 6.12 适配 + fcm）
  feed-precedence.txt     同名包生效来源（sing-box → small）；feed-sources.sh 必需
  feeds.lock              滚动 feed 已验证提交
device/
  uboot/                  MaskROM overlay + static（dts/dtsi/defconfig）+ OVERLAY_BASE=2025.10
  kernel-patches/         910/911/913/914/915（按 v6.12.112 + 039-* 补丁栈重写）
  kernel-dts/             rk3568-nsy-g68-plus.dts
  kernel-files/           RTL8367S 驱动 overlay（6 个 .c/.h）
  board.d/02_network_g68  VLAN: 0 1 2 3=LAN / 4=WAN / 6u@eth0 / 7u@eth1
  files/                  LuCI 菜单资产 + 中文覆盖 + uci-defaults（含 96-g68-fanchm-theme）
  i18n-overlay/           16 项定制标题覆盖（条件投递）
scripts/
  apply-device.sh         投递设备层（含 KERNEL_LOADADDR / 分区表 / 核心守卫）
  patch-preflight.sh      内核补丁预检（fuzz=0，40s 级）
  verify-critical.sh      网络生命线 + 蜂窝 + SMSC + FCM + 风格 双阶段守卫
  verify-network.sh       910/913/915 生效守卫（source/dts）
  verify-maskrom.sh       长按复位进 MaskROM 三层守卫（含 board.c 调用点）
  check-partition-table.py  产物 MBR 分区表校验（4096 MiB rootfs_data）
  selftest.sh / hw-audit.sh / dep-guard.sh / package-guard.py / feed-*.sh
.github/workflows/
  build.yml / maskrom-guard.yml / package-guard.yml / upstream-watch.yml
```

### 10.5 不变量（跟随上游更新时同样固定不变）

**跟随上游只拉取 FanchmWrt 官方源码；设备层与全部守卫脚本都来自本仓固定文件，不随上游变动。** 上游一旦改动内核补丁栈 / U-Boot 调用点 / 文件结构而使任一守卫失配，CI 在 `prepare` 阶段就 fail-fast，**绝不产出削弱核心功能的 Release**——即"跟随的是功能更新，不是守卫退化"。任何改动（含上游同步）都不得破坏以下各条：

1. 长按 Reset → MaskROM 链路可用（三层守卫通过，含 2025.10 `board.c` 调用点）；
2. 网络生命线 swconfig / rtl8367b / dnsmasq-full 齐全，910/913/915 补丁零 fuzz 生效；
3. 核心应用能力与 hybrid 对齐：蜂窝 32 包移除、SMSC 驱动保留、FCM 全套在位；
4. FanchmWrt 原生风格：无 QuickStart / 商城 / Argon，主题为 `luci-theme-fanchmwrt`；
5. i18n 双识别 apk / opkg，16 项覆盖仅换中文、不换实现，`selftest §16` 守住；
6. 上游更新守卫挂载点不摘除，`feed-precedence.txt` 必须存在；
7. 镜像分区 `rootfs_data` 标称 4096 MiB，产物级校验不得改成“容错跳过”；
8. `DEVICE_DTS` 不带 `rockchip/` 前缀（上游 `DEVICE_DTS_DIR` 已含），三处（apply-device / build.yml 断言 / selftest）必须一致；
9. `KERNEL_LOADADDR := 0x03000000` 显式赋值，防 `mkits.sh` 空 `-a/-e`。

### 10.6 已修复的构建失败链（不得回退）

历次全量编译在实践中暴露并已闭环的根因，均已加入 prepare 阶段守卫，让同类错误**几秒内**拦截，而不是编译几小时后才炸：

1. 缺 `include/linux/rtl8366.h`（头文件补齐）；
2. `rtl8366_smi` 内部函数缺 `static`（`-Werror=missing-prototypes`）；
3. `rtl8367b_remove` 改 `static void` 并删 `return 0`（6.12 `platform_driver.remove` 签名）；
4. `DEVICE_DTS` 双重 `rockchip/` 前缀，拼成 `rockchip/rockchip/...` 导致 DTB 编译失败（去前缀，三处一致）；
5. `KERNEL_LOADADDR` 空值 → `mkits.sh` 收到空 `-a/-e` 打印 usage 退出（设备块显式 `0x03000000` + 幂等补回 + selftest 守卫）。

---

## 十一、本地构建

```sh
git clone --depth 1 -b fanchmwrt-25.12.6 https://github.com/fanchmwrt/fanchmwrt.git
sh scripts/apply-device.sh fanchmwrt          # 注入设备层（含 KERNEL_LOADADDR / 分区 / i18n）
sh scripts/patch-preflight.sh fanchmwrt       # 内核补丁预检（fuzz=0）
sh scripts/selftest.sh fanchmwrt              # 静态自检（含 §16 i18n / DTS / LOADADDR 守卫）
sh scripts/hw-audit.sh                        # 硬件审核
cd fanchmwrt
./scripts/feeds update -a
sh ../scripts/feed-pin.sh . ../configs/feeds.lock             # 固定滚动 feed
./scripts/feeds install -a
sh ../scripts/feed-sources.sh . ../configs/feed-precedence.txt # 固定同名包来源
cp ../configs/g68-fanchm.config .config
make defconfig
sh ../scripts/verify-critical.sh config .config                # 核心功能守卫（defconfig 后）
sh ../scripts/dep-guard.sh . ../configs/feed-precedence.txt    # 依赖版本守卫
make -j"$(nproc)"
# 产物校验
python3 ../scripts/check-partition-table.py \
  bin/targets/rockchip/armv8/*nsy_g68-plus*squashfs-sysupgrade.img.gz 4096
```

> 注意：`configs/*.config`、`scripts/*.sh`、workflow 与 `device/files/` 下脚本必须保持 **LF** 行尾——CRLF 会让 `grep -qx` 自检、`make defconfig` 与 `/bin/sh` 失效（`selftest` 有扫描守卫）。通过 Git Data API 创建 blob 会绕过行尾规范化，提交前请核对远端真实行尾。

产物：`fanchmwrt/bin/targets/rockchip/armv8/*nsy_g68-plus*squashfs-sysupgrade.img.gz`

---

## 致谢

- [FanchmWrt](https://github.com/fanchmwrt/fanchmwrt) —— 系统基座、行为管理与原生主题
- [immortalwrt / zhoufuli](https://github.com/zhoufuli/immortalwrt-rk356x) —— G68 设备层与真机验证经验
- [iStoreOS hybrid](https://github.com/iiibeloved/istoreos-hybrid-g68) —— 设备层、刷机方式与 CI 守卫体系参考
- 所有上游包维护者

> 本项目仅做设备层移植与 CI 编排，固件内容遵循各上游组件许可证。FanchmWrt 上游声明家长控制功能**仅供个人使用，不得用于公司或集成进商用产品**；本工作区仅供个人家用研究。
