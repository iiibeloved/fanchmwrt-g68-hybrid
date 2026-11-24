# G68 PLUS · FanchmWrt 杂交固件

NSY G68-PLUS（RK3568 / RTL8367S）杂交固件工作区。目标是把 **FanchmWrt 的行为管理能力** 与 **已真机验证的 G68 网络栈 + 长按复位进 MaskROM** 结合，保持 FanchmWrt 原生外观，并固化上游更新守卫。

> 本工作区是**独立产品线**，不改动、不发布、不影响现有 hybrid / DSA 固件。

## 一、杂交构成（三源）

| 组件 | 来源 | 作用 |
|---|---|---|
| 基座 / 内核 / 行为管理 | `fanchmwrt/fanchmwrt` `fanchmwrt-25.12.6`（OpenWrt 25.12 / 内核 **6.12** / apk / U-Boot **2025.10**） | `fwx.ko` + `fwxd` + `shortcut-fe` + `luci-theme-fanchmwrt`；950/952 netfilter 内核补丁随基座自带 |
| G68 设备层（swconfig 双 GMAC） | `zhoufuli/immortalwrt-rk356x` 的 `nsy_g68-plus`（真机验证 OK 路线） | DTS / VLAN 映射 / RTL8367S 驱动；**不走 DSA** |
| 长按复位进 MaskROM | 本仓 `device/uboot/`（按 U-Boot **2025.10** 原版重做） | overlay-only 投递，`verify-maskrom.sh` 三层断言 |

为什么不能直接刷成品：上游 rockchip 目标只有 radxa/bpi 等板，且走 DSA；没有 G68 设备树，刷入会导致网口全乱（重演 LAN 拿不到 IP）。

## 二、外观与风格：FanchmWrt 原生

本固件**不使用 iStoreOS 风格**：

- **无 QuickStart 首页**：`quickstart`、`luci-app-quickstart`、`luci-i18n-quickstart-zh-cn` 一律 `is not set`
- **无应用商城**：`luci-app-store` `is not set`；FanchmWrt 自家的云端商城 `luci-app-fwx-app-center`（从 `cloud.fanchmwrt.com` 下载安装包）同样 `is not set` —— 上游 `DEFAULT_PACKAGES.router` 也不含它，去掉它才是真正的“默认 FanchmWrt 风格”
- **无 Argon 主题**：`luci-theme-argon` / `luci-app-argon-config` / `luci-i18n-argon-config-zh-cn` `is not set`
- **默认主题**：`luci-theme-fanchmwrt`；`96-g68-fanchm-theme` 在首次启动把 `luci.main.mediaurlbase` 指向 `/luci-static/fanchmwrt`（目录存在时才写，避免写坏 LuCI），并在上游 `31_luci-theme-fanchmwrt` 缺失时补回 `luci.themes.FanchmWrt`
- **fwx 界面清单**：与上游 `include/target.mk` 的 `DEFAULT_PACKAGES.router` 逐项对齐（16 个 `luci-app-fwx-*` + `traffic-stat` + `fastnat`）
- **守卫**：`verify-critical.sh` 的 `STYLE_FORBIDDEN` 清单在 **defconfig 后 + manifest** 双阶段拦截，任一风格包回流即 fail-fast
- **中文覆盖**：`g68-i18n` 同时识别 **apk / opkg**（25.12 为 apk），否则会把已安装应用误判为“未安装”；详见第六节「24.10 → 25.12 的 i18n 适配」
- **软件包页面**：24.10 的 `luci-app-opkg` 已关（apk 基座上失效）。25.12 用 `luci-app-package-manager`（`PKG_PROVIDES:=luci-app-opkg`，FanchmWrt 另补了 apk 版 `package-manager-call`）；它是 LuCI 原生软件包列表页、**不是商城**，按“无商城”决策暂不启用，需要时把 config 里该行改成 `=y`

## 三、长期不变目标（守卫固化，上游更新不得削弱）

这三条是**硬约束**，任何修改若削弱其一，CI 守卫必须 fail-fast：

### 目标 1 · 长按复位键进 MaskROM
- `device/uboot/OVERLAY_BASE` 锁定 U-Boot 基准版本（**2025.10**），版本漂移即失败
- `device/uboot/overlay/` 4 个文件：`boot_mode.c`（MaskROM 逻辑本体）、`Makefile`、`rk3568.c`、`dts/Makefile`
  - 2025.10 起 `setup_boot_mode()` 由上游公共 `board.c:board_late_init()` 原生调用，`rk3568.c` 不再含 `spl_board_init`
  - `boot_mode.c` 保留：去空桩、`0xfdc20200` 寄存器兜底、`RK_DNL_ADC_CHAN`、`do_reset`
- `scripts/verify-maskrom.sh` 三层断言：源码层 / 投递层 / 产物层（`--built`，`strings` 查 `download key pressed` + `adc_channel_single_shot`）
- 刷机：断电 → **按住 Reset** 上电 → 显示 MaskROM 设备 → RKDevTool 写镜像

### 目标 2 · 网络正常（swconfig 生命线）
- 关键包（缺一禁止构建/发布）：`swconfig`、`kmod-swconfig`、`kmod-switch-rtl8366-smi`、`kmod-switch-rtl8367b`、`dnsmasq-full`；`dnsmasq` 必须未选（互斥）
- 内核补丁 `910` / `913` / `915` 必须真正生效，`scripts/verify-network.sh source` 按**源码锚点**验证（`set_to_sgmii`、`is_fixed_link`、`RK3568_PIPE_GRF_XPCS_SGMII_MAC_SEL`、`rockchip,pipegrf`），hunk 静默失败即拦截
- 板级 DTS 由 `verify-network.sh dts` 验证 `sgmii-mac-sel` / `pipegrf` / `phy-mode=sgmii` / `rtl8367s`，并拦住**重复 label**（`gmac0_xpcsclk`/`gmac1_xpcsclk` 由 911 提供，板级再定义会 `duplicate_label` 编译失败）
- ✅ **已按 FanchmWrt 的 6.12 补丁栈重写并实证**：上游 `target/linux/rockchip/patches-6.12/` 里有 260+ 个 v6.13~v6.19 回移补丁，其中 `039-01..039-05` 会重写 `dwmac-rk.c`（加 RK3528、搬 `integrated_phy_powerup`、删多余 GRF）。910/913/915 已按「内核 `v6.12.112` + 008/039 系列」的真实上下文重新生成，`patch -F0`（零 fuzz）全部命中
- 🛡️ `scripts/patch-preflight.sh`：prepare 阶段只下载 4 个内核源文件（~200KB），按真实顺序打「上游补丁栈 → 本仓补丁」，**40 秒**内判定 hunk 是否失配，避免编译 40 分钟后才炸在日志深处

### 目标 3 · 核心应用能力与 hybrid 对齐（除非不兼容）
- 蜂窝能力整体移除：`verify-critical.sh` 的 32 包 `CELLULAR` 清单双阶段拦截
- SMSC 以太网 PHY（`kmod-phy-smsc`、`kmod-usb-net-smsc95xx`）必须保留（名字含 sms 但与蜂窝无关）
- 菜单资产：`zz-hide-modem.json`（隐藏 Modem）、`91-g68-hide-modem-entry`（注释 sms.lua 父菜单）、`zz-samba4-label.json`（Samba4 → “网络共享++”）
- FCM 行为管理包（`kmod-fwx`/`fwxd`/`libfwx_common`/`kmod-shortcut-fe`/`kmod-nft-fullcone`/`luci-theme-fanchmwrt`/`luci-app-fwx-dashboard`）为杂交新增，双阶段断言缺失即失败
  - ⚠️ 包名坑：Kconfig 里是 `KernelPackage/fwx`、`KernelPackage/shortcut-fe`、`KernelPackage/fullconenat-nft`，但**最终包名**是 `kmod-fwx`、`kmod-shortcut-fe`、`kmod-nft-fullcone`；写错会被 defconfig 静默丢弃（模块永远编不出来）
- 与 hybrid 的差异：**25.12 / apk 不兼容项** + **iStoreOS 风格组件（QuickStart / 商城 / Argon）**

### 附加 · 上游更新守卫
- `build.yml` 守卫挂载点：`patch-preflight`、`selftest`×3、`hw-audit`、`dep-guard`、`verify-critical`×2（含风格守卫）、`verify-network` source/dts、`verify-maskrom`×2
- `upstream-watch.yml`：每小时比对 FanchmWrt 分支 commit 与 `upstream.lock`，变化自动触发构建
- `package-guard.yml`：以上游默认包清单为基准去重（手动/复用通道，`builtin-list.txt` 可选）
- `configs/feed-precedence.txt`：同名包来源（`sing-box → small`）；缺失会让 `feed-sources.sh` 直接 exit 1，因此必须保留
- `configs/feeds.lock`：固定 small feed 提交，防 main 漂移

## 四、目录结构

```
configs/
  g68-fanchm.config       主配置（FanchmWrt 原生风格 + hybrid 包集 + 6.12 适配 + fcm）
  feed-precedence.txt     同名包来源（sing-box → small）；feed-sources.sh 必需
  feeds.lock              滚动 feed 提交锁（small）
device/
  uboot/                  MaskROM overlay（4 文件）+ static（dts/dtsi/defconfig）+ OVERLAY_BASE=2025.10
  kernel-patches/         910/911/913/914/915（需 6.12 编译期验证）
  kernel-dts/             rk3568-nsy-g68-plus.dts
  kernel-files/           RTL8367S 驱动 overlay
  board.d/02_network_g68  VLAN: 0 1 2 3=LAN / 4=WAN / 6u@eth0 / 7u@eth1
  files/                  LuCI 菜单资产 + 中文覆盖 + uci-defaults（含 96-g68-fanchm-theme）
scripts/
  apply-device.sh         投递设备层（含 u-boot / 内核版本守卫）
  patch-preflight.sh      内核补丁预检（上游补丁栈 + G68 补丁，fuzz=0，40s 级）
  verify-critical.sh      网络生命线 + 蜂窝 + SMSC + FCM + 风格 双阶段守卫
  verify-network.sh       source/dts 补丁生效守卫
  verify-maskrom.sh       长按复位进 MaskROM 三层守卫
  selftest.sh / hw-audit.sh / dep-guard.sh / package-guard.py / feed-*.sh
.github/workflows/
  build.yml               check-upstream / prepare / uboot-check / build / Release
  maskrom-guard.yml / package-guard.yml / upstream-watch.yml
```

## 五、构建与发布

- **触发**：push 到 main / `workflow_dispatch` / `upstream-watch` 检测到上游 commit 变化
- **流程**：浅克隆 FanchmWrt `fanchmwrt-25.12.6` → `apply-device.sh` → `selftest` / `hw-audit` → u-boot 单独编译并校验 MaskROM → `make defconfig` 后 `verify-critical config`（含风格）→ 全量编译 → `verify-network source/dts` + `verify-critical manifest` → 发布 Release
- **Release 标签**：`g68-fanchm-YYYY.MM.DD`（重名追加 `-rN`）
- **不一致即停**：任一守卫失败则中止，不发 Release，自动开 issue

## 六、i18n / apk 迁移适配（24.10 → 25.12）

### 后缀到底变了什么

| 项 | 24.10 | 25.12 | 对中文覆盖的影响 |
| --- | --- | --- | --- |
| 包归档 | `.ipk`（opkg） | `.apk`（apk-tools 3.x） | **无**：只换归档格式，包内文件清单与 rootfs 路径不变 |
| 安装库 | `/usr/lib/opkg/info/*.control` | `/lib/apk/db/installed` 的 `P:<包名>` 行 | **有**：`pkg_installed` 必须两边都认 |
| LuCI po 目录 | `po/zh-cn/` | `po/zh_Hans/`（small feed 用 symlink 双向兼容） | **有**：上游目录改名 |
| i18n 包名 | `luci-i18n-<app>-zh-cn` | **同左** | 无：`luci.mk` 的 `LUCI_LC_ALIAS.zh_Hans=zh-cn` 保证 |
| 翻译产物 | `.lmo` → `/usr/lib/lua/luci/i18n/` | 同左 | 无 |

本仓的中文覆盖走 `files/` 注入 + `g68-i18n` 运行时 `cp`，**完全不经过包管理器**，
所以 `.ipk → .apk` 本身不会让覆盖失效；会失效的是「判定已安装」这一步（已修）。

### 覆盖文件的边界（2026-11-23 全量审查）

官方 `.lmo`（config 里 `luci-i18n-*-zh-cn=y`）负责应用内部可翻译字符串，
本仓覆盖只负责少量定制标题（"网络唤醒++"、"上网时间控制" 等）。两者互补。

审查发现 **9 个覆盖其实是 24.10 / iStoreOS 时代的整应用实现**，已从两处 manifest
移除并删除文件：

- `luci-app-filetransfer` 全套 5 个：本仓是 DustReliant 2024 的 iStoreOS 版
  （controller **777 行**，`ALLOWED_EXTENSIONS` 只列 `ipk` 不列 `apk`）；
  25.12 锁定的 small feed 是 lean 版（**13 行**）。投递会把文件传输功能整体换掉，
  而且用户上传 `.apk` 固件包会被上传白名单直接拒绝。
- `luci-app-timecontrol` 的 `basic.js` / `log.js`：压缩过的另一版实现（17/46 行）
  vs 上游 sirpdboy 版（334/238 行），RPC / UCI 字段不保证一致。
- `emmc-health.js` / `lan-scanner.js`：锁定的 small feed 里根本没有这两个包，
  是 24.10 遗留死条目（`lan-scanner.js` 还带 UTF-8 BOM）。

保留的 **16 项**已逐文件与锁定 feed 版本 diff 核验：行数一致、只替换中文字符串
（相似度 0.83~1.0，`model/cbi/*.lua` 的低相似度来自中文译文长度，非逻辑改动）。

### 运行时三道防线

1. `pkg_installed` 优先读 `/lib/apk/db/installed`，用 `grep -qxF "P:<包名>"`
   固定串匹配（包名里的 `.` 不再被当成正则通配），另有 `apk info/query/list`
   与 opkg 多重兜底 —— apk-tools 3.x 把 `info` 改名 `query` 也不会再静默失效。
2. `compat_ok()` 版本指纹：目标文件行数与覆盖文件差 > 2 行即跳过并告警，
   防止上游换实现后旧覆盖把应用降级；被拦截时中文仍由官方 `.lmo` 兜底。
3. 投递后清 `/tmp/luci-indexcache.<hash>.json` 与 `/tmp/luci-modulecache/`
   （LuCI 25.12 的菜单树缓存），否则开机重投递后看到的仍是旧英文菜单。

`selftest §16` 守住：两处 manifest 一致、引用完整、每个应用有官方中文包兜底、
无 24.10 特征回流、`luci-app-opkg` 已关闭。

> 真机仍需确认：官方 `.lmo` 是否覆盖全部可见文案；`www/luci-static/*.js`
> 的浏览器缓存需强刷一次。二者都不影响刷机与网络。

## 七、刷机

1. USB 双公头线连接电脑与设备（OTG/靠网口 USB）
2. RKDevTool v3.18 + 驱动 v5.12
3. 断电 → **按住 Reset** 上电 → 松开 → 显示 MaskROM 设备
4. 高级功能 → Boot 选 `rk356x_spl_loader_v1.21.113.bin` → 下载
5. 获取当前存储 / **擦除所有**
6. 下载解压后的 `.img` → **勾选「强制按地址写」** → 执行

> 若长按无效，可用短接触点法兜底（BROM 模式，loader 相同）。

## 八、状态与已知风险

- **当前阶段**：`prepare`（设备层投递 + 补丁预检 + 静态自检 + 硬件审核）已通过，进入 `uboot-check`；`build` 全量编译待启动
- **首要风险（已消除）**：910/913/915 原本是 6.6 时代补丁；对齐到 FanchmWrt 的 `v6.12.112 + 039-*` 补丁栈后**在本机实证零 fuzz 全命中**，并新增 `patch-preflight.sh` 把这个判定提前到 prepare（上游再动会 40s 内报出来）
- **次要风险**：`kmod-usb-serial-option` 等蜂窝反向依赖在 25.12 的 select 链可能与 6.6 不同（沿用 hybrid 的 32 包清单 + 全 feed 反向依赖扫描方法处理）
- **i18n 剩余风险**：官方 `.lmo` 的译文完整度、LuCI 静态 JS 的浏览器缓存（见第六节），需真机确认；编译期已由 `selftest §16` + 版本指纹守卫兜住
- **已修（本轮审计）**：
  - 缺失 `configs/feed-precedence.txt`（会让 build job 在 defconfig 后直接 exit 1）
  - `g68-i18n` 不识别 apk（25.12 基座上中文覆盖永不投递、还会误删已有覆盖）
  - `hw-audit` 仍读 `kernel-6.6`（改为 `kernel-6.12` + `KERNEL_PATCHVER` 兜底）
  - selftest 旧 §8/§9 仍要求 QuickStart/商城（与风格约束自相矛盾）
  - `luci-app-fwx-app-center` 是 FanchmWrt 云端商城，已按“无商城”移除并入 `STYLE_FORBIDDEN`
  - **可执行位丢失**：仓库在 Windows 上开发，`core.filemode=false` 使 `device/files/**` 全存成 100644；CI 在 Linux 上 `cp -a` 保留 644 → `/etc/init.d/g68-i18n` 无法 `enable`、`/usr/bin/g68-i18n` 的 `[ -x ]` 判假，中文整链静默失效。已两处修：git 索引 `--chmod=+x` + `apply-device.sh` 显式 `chmod 0755` 并断言
  - `upstream-watch` 用 `-f 'inputs[stage]=full'` 派发（gh api 不会展开括号键，实际靠默认值歪打正着）→ 改为显式 JSON `--input -`
  - **内核补丁失配**：910/913/915 在「FanchmWrt 补丁栈（v6.12.112 + 039-*）」上分别有 1~2 个 hunk FAILED（`make` 会在编译 40 分钟后才炸）→ 已按真实上下文重写，`patch -F0` 全命中；新增 `patch-preflight.sh` 提前到 prepare
  - **DTS 重复 label**：板级 DTS 里的 `gmac0_xpcsclk`/`gmac1_xpcsclk` 与 911 注入的同名 label 冲突（dtc `duplicate_label` 直接编译失败）→ 已删除板级定义，并在 `verify-network.sh dts` 加反向断言
  - 注释残留 iStoreOS 字样（`02_network_g68`、`915-*.patch` 头），内容不变

## 九、授权边界

FanchmWrt 源码 README 声明家长控制功能**仅供个人使用，不得用于公司或集成进商用产品**。本工作区仅供个人家用研究。
