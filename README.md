# G68 PLUS · FanchmWrt 杂交固件

NSY G68-PLUS（RK3568 / RTL8367S）杂交固件工作区。目标是把 **FanchmWrt 的行为管理能力** 与 **已真机验证的 G68 网络栈 + 长按复位进 MaskROM** 结合，并保持与 `istoreos-hybrid-g68` 一致的长期不变量。

> 本工作区是**独立产品线**，不改动、不发布、不影响现有 hybrid / DSA 固件。

## 一、杂交构成（三源）

| 组件 | 来源 | 作用 |
|---|---|---|
| 基座 / 内核 / 行为管理 | `fanchmwrt/fanchmwrt` `fanchmwrt-25.12.6`（OpenWrt 25.12 / 内核 **6.12** / apk） | `fwx.ko` + `fwxd` + `shortcut-fe` + 主题；950/952 netfilter 内核补丁随基座自带 |
| G68 设备层（swconfig 双 GMAC） | `zhoufuli/immortalwrt-rk356x` 的 `nsy_g68-plus`（真机验证 OK 路线） | DTS / VLAN 映射 / RTL8367S 驱动；**不走 DSA** |
| 长按复位进 MaskROM | 本仓 `device/uboot/`（与 hybrid 同源，U-Boot 2024.10） | overlay-only 投递，`verify-maskrom.sh` 三层断言 |

为什么不直接刷成品：上游没有 G68 设备树；FanchmWrt 25.12 主线 rockchip 仅 radxa/bpi 等板，且走 DSA，刷入会导致网口全乱（重演 LAN 拿不到 IP）。

## 二、长期不变目标（守卫固化，上游更新不得削弱）

这三条是**硬约束**，任何修改若削弱其一，CI 守卫必须 fail-fast：

### 目标 1 · 长按复位键进 MaskROM
- `device/uboot/OVERLAY_BASE` 锁定 U-Boot 基准版本（2024.10），版本漂移即失败
- `device/uboot/overlay/` 4 个完整替换文件（Makefile / boot_mode.c / rk3568.c / dts Makefile）
- `scripts/verify-maskrom.sh` 三层断言：源码层 / 投递层 / 产物层（`--built`）
- 刷机：断电 → **按住 Reset** 上电 → 显示 MaskROM 设备 → RKDevTool 写镜像

### 目标 2 · 网络正常（swconfig 生命线）
- 关键包（缺一禁止构建/发布）：`swconfig`、`kmod-swconfig`、`kmod-switch-rtl8366-smi`、`kmod-switch-rtl8367b`、`dnsmasq-full`；`dnsmasq` 必须未选（互斥）
- 内核补丁 `910` / `913` / `915` 必须真正生效，`scripts/verify-network.sh source` 按**源码锚点**验证（`set_to_sgmii`、`is_fixed_link`、`RK3568_PIPE_GRF_XPCS_SGMII_MAC_SEL`、`rockchip,pipegrf`），hunk 静默失败即拦截
- 板级 DTS `scripts/verify-network.sh dts` 验证 `sgmii-mac-sel` / `pipegrf` / `phy-mode=sgmii` / `rtl8367s` 节点
- ⚠️ 910/913/915 为 6.6 时代补丁，移植到 6.12 需重新验证 hunk；首次 CI 的 `verify-network source` 会暴露真实结果，失败即按 6.12 源码重写补丁（**不得删除该守卫来"过关"**）

### 目标 3 · 应用包与 hybrid 尽量一致（除非不兼容）
- 蜂窝能力整体移除：`scripts/verify-critical.sh` 的 32 包 `CELLULAR` 清单双阶段拦截（defconfig 后 + manifest）
- SMSC 以太网 PHY（`kmod-phy-smsc`、`kmod-usb-net-smsc95xx`）必须保留（名字含 sms 但与蜂窝无关）
- 菜单资产：`zz-hide-modem.json`（隐藏 Modem）、`91-g68-hide-modem-entry`（注释 sms.lua 父菜单）、`zz-samba4-label.json`（Samba4 → "网络共享++"）
- 与 hybrid 的差异**仅来自 25.12 / apk 不兼容项**，逐项在 `configs/g68-fanchm.config` 注释说明
- FCM 行为管理包（`fwx`/`fwxd`/`libfwx_common`/`shortcut-fe`/`luci-theme-fanchmwrt`/`fullconenat-nft`）为杂交新增，双阶段断言缺失即失败

### 附加 · 上游更新守卫
- `build.yml` 守卫挂载点：`selftest`×3、`hw-audit`、`dep-guard`、`verify-critical`×2、`verify-network` source/dts、`verify-maskrom`×2
- `upstream-watch.yml`：每小时比对 FanchmWrt 分支 commit 与 `upstream.lock`，变化自动触发构建
- `package-guard.yml`：以上游默认包清单为基准去重，防重复/冲突包

## 三、目录结构

```
configs/
  g68-fanchm.config      主配置（hybrid 包集 + 6.12 适配 + fcm 段）
  feeds.lock / builtin-list.txt / feed-precedence.txt
device/
  uboot/                 MaskROM overlay（6 文件）+ OVERLAY_BASE=2024.10
  kernel-patches/        910/911/913/914/915（需 6.12 移植验证）
  kernel-dts/            rk3568-nsy-g68-plus.dts
  kernel-files/          RTL8367S 驱动 overlay
  board.d/02_network_g68  VLAN: 0 1 2 3=LAN / 4=WAN / 6u@eth0 / 7u@eth1
  files/                 LuCI 菜单资产 + 中文覆盖 + uci-defaults
scripts/
  apply-device.sh        投递设备层（含版本守卫）
  verify-critical.sh     网络生命线 + 蜂窝 + SMSC + FCM 双阶段守卫
  verify-network.sh      source/dts 补丁生效守卫
  verify-maskrom.sh      长按复位进 MaskROM 三层守卫
  selftest.sh / hw-audit.sh / dep-guard.sh / package-guard.py / feed-*.sh
.github/workflows/
  build.yml              check-upstream / prepare / uboot-check / build / Release
  maskrom-guard.yml / package-guard.yml / upstream-watch.yml
```

## 四、构建与发布

- **触发**：push 到 main / `workflow_dispatch` / `upstream-watch` 检测到上游 commit 变化
- **流程**：浅克隆 FanchmWrt `fanchmwrt-25.12.6` → `apply-device.sh` 投递设备层 → `selftest/hw-audit` → u-boot 单独编译并校验 MaskROM → `make defconfig` 后 `verify-critical config` → 全量编译 → `verify-network source/dts` + `verify-critical manifest` → 发布 Release
- **Release 标签**：`g68-fanchm-YYYY.MM.DD`（重名追加 `-rN`）
- **不一致即停**：任一守卫失败则中止，不发 Release，自动开 issue

## 五、刷机

1. USB 双公头线连接电脑与设备（OTG/靠网口 USB）
2. RKDevTool v3.18 + 驱动 v5.12
3. 断电 → **按住 Reset** 上电 → 松开 → 显示 MaskROM 设备
4. 高级功能 → Boot 选 `rk356x_spl_loader_v1.21.113.bin` → 下载
5. 获取当前存储 / **擦除所有**
6. 下载解压后的 `.img` → **勾选「强制按地址写」** → 执行

> 若长按无效，可用短接触点法兜底（BROM 模式，loader 相同）。

## 六、状态与已知风险

- **当前阶段**：工作区初始化完成，配方落地，首次全量构建待触发
- **首要风险**：910/913/915 从 6.6 移植到 6.12 的 hunk 适配（由 `verify-network source` 实证，失败即按 6.12 源码重写，**不降级守卫**）
- **次要风险**：`kmod-usb-serial-option` 等蜂窝反向依赖在 25.12 的 select 链可能与 6.6 不同（沿用 hybrid 的 32 包清单 + 全 feed 反向依赖扫描方法处理）

## 七、授权边界

FanchmWrt 源码 README 声明家长控制功能**仅供个人使用，不得用于公司或集成进商用产品**。本工作区仅供个人家用研究。
