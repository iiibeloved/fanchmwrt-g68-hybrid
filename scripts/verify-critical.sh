#!/bin/sh
# =============================================================================
#  核心网络功能包守卫（defconfig 后 + 最终 manifest，双阶段 fail-fast）
#
#  为什么需要两阶段：
#    selftest.sh / hw-audit.sh 只检查 configs/g68-fanchm.config 这个"输入"，
#    但真正的包集由 make defconfig 展开，上游 feed 漂移可能让关键包被静默丢弃。
#    历史上的 LAN 拿不到 IP 就是因为用户态 swconfig 未进入最终镜像。
#    因此：
#      config  <defconfig文件>   —— build 作业 make defconfig 之后立即断言，
#                                   缺关键包则秒级失败，不浪费 5 小时编译；
#      manifest <manifest文件>  —— 编译产物阶段再断言一次，确保最终镜像确实含包，
#                                   缺任一包则禁止发布 Release。
#
#  关键包清单（网络生命线，缺一不可）：
#    swconfig                 用户态工具，安装 /lib/network/switch.sh 应用 UCI VLAN
#    kmod-swconfig            内核 swconfig 框架
#    kmod-switch-rtl8366-smi  MDIO 总线驱动（与 RTL8367S 通信）
#    kmod-switch-rtl8367b     RTL8367S 交换机芯片驱动
#    dnsmasq-full             LAN DHCP 服务端（与 dnsmasq 互斥）
#
#  用法：verify-critical.sh config <.config> | verify-critical.sh manifest <manifest>
# =============================================================================
set -eu
MODE="${1:?用法: verify-critical.sh config|<manifest> <文件>}"
FILE="${2:?用法: verify-critical.sh config|<manifest> <文件>}"
[ -f "$FILE" ] || { echo "::error::关键包守卫: 文件不存在 $FILE"; exit 1; }

CRIT="swconfig kmod-swconfig kmod-switch-rtl8366-smi kmod-switch-rtl8367b dnsmasq-full"
# 蜂窝能力整体移除（用户决策 2026-11-22）：固件不含任何 4G/5G/短信应用，
# 但保留 kmod-phy-smsc / kmod-usb-net-smsc95xx（SMSC 以太网 PHY 驱动，名字含 sms 但与蜂窝无关）。
# 上游 feed 漂移或 package-guard 去重可能把这些包重新带入，必须在两阶段拦截。
# 2026-11-23 补 10 个"反向依赖源"：comgt-ncm 上游 DEPENDS:=+wwan，
# kmod-usb-serial-option/ipw/qualcomm 上游 AddDepends(...,+kmod-usb-serial-wwan)，
# luci-proto-ncm 上游 LUCI_DEPENDS:=+comgt-ncm，quectel-timesync 依赖 +kmod-usb-serial-option，
# make defconfig 会把已禁用的末端蜂窝包强制 select 回 y。只禁用末端包无效，
# 必须连同这些源包一起关闭并纳入清单。已对全部 feed 做反向依赖全量扫描。
CELLULAR="adb-enablemodem comgt comgt-directip comgt-ncm kmod-qmi_wwan_m kmod-qmi_wwan_q kmod-usb-net-cdc-mbim kmod-usb-net-qmi-wwan kmod-usb-serial-ipw kmod-usb-serial-option kmod-usb-serial-qualcomm kmod-usb-serial-wwan libmbim libqmi libqrtr-glib luci-app-3ginfo-lite luci-app-modem luci-app-sms-tool luci-i18n-modem-zh-cn luci-proto-3g luci-proto-mbim luci-proto-modemmanager luci-proto-ncm luci-proto-qmi modemmanager qmi-utils quectel-CM-5G quectel-timesync sms-tool umbim uqmi wwan"
SMSC_NET="kmod-phy-smsc kmod-usb-net-smsc95xx"
# 杂交新增目标：FanchmWrt 行为管理（用户要求的杂交价值）。缺失则杂交失去意义，两阶段都断言。
# 注意包名：KernelPackage/fwx → kmod-fwx；KernelPackage/shortcut-fe → kmod-shortcut-fe；
#           KernelPackage/nft-fullcone → kmod-nft-fullcone（写错会被 defconfig 静默丢弃）。
# luci-app-fwx-dashboard 是 UI 入口，缺它则内核模块在但界面不可见。
FCM="kmod-fwx fwxd libfwx_common kmod-shortcut-fe kmod-nft-fullcone luci-theme-fanchmwrt luci-app-fwx-dashboard"
# 风格约束（用户决策 2026-11-23）：本固件使用 FanchmWrt 原生风格，
# 不使用 iStoreOS 的 QuickStart 首页 / 应用商城 / Argon 主题。
# 这些包多来自 small/store feed，上游漂移或 package-guard 去重都可能把它们带回，
# 因此与蜂窝清单同级做双阶段拦截（config 出现 =y 或 manifest 出现即失败）。
# luci-app-fwx-app-center 是 FanchmWrt 自家的云端应用商城（cloud.fanchmwrt.com
# 下载并安装 ipk/apk），上游 DEFAULT_PACKAGES.router 同样不含它，一并禁止。
STYLE_FORBIDDEN="quickstart luci-app-quickstart luci-i18n-quickstart-zh-cn luci-app-store luci-app-fwx-app-center luci-i18n-fwx-app-center-zh-cn luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
FAIL=0
ok()  { printf '  [OK]   %s\n' "$*"; }
bad() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }

echo "== [guard] 核心网络功能包（$MODE: $FILE）=="
for p in $CRIT; do
	case "$MODE" in
		config)   pat="^CONFIG_PACKAGE_${p}=y$" ;;
		manifest) pat="^${p} - " ;;
		*) echo "::error::未知模式 $MODE（应为 config 或 manifest）" >&2; exit 2 ;;
	esac
	if grep -qE "$pat" "$FILE"; then
		ok "$p"
	else
		bad "缺关键包 $p（网络/DHCP 将不可用，禁止继续）"
	fi
done

if [ "$MODE" = "config" ]; then
	if grep -qE '^CONFIG_PACKAGE_dnsmasq=y$' "$FILE"; then
		bad "dnsmasq 与 dnsmasq-full 同时选中（PROVIDES 同名，必须互斥）"
	else
		ok "dnsmasq 未与 dnsmasq-full 冲突"
	fi
fi

echo
echo "== [guard] 蜂窝能力已整体移除（$MODE: $FILE）=="
# 任何蜂窝包被重新选中/进入产物即失败
for p in $CELLULAR; do
	case "$MODE" in
		config)   pat="^CONFIG_PACKAGE_${p}=y$" ;;
		manifest) pat="^${p} - " ;;
	esac
	if grep -qE "$pat" "$FILE"; then
		bad "蜂窝包 $p 被重新引入（用户要求整体移除蜂窝能力）"
	fi
done
# 反向守卫：SMSC 以太网 PHY 绝不能被误禁（名字含 sms 但是网络驱动）
for p in $SMSC_NET; do
	case "$MODE" in
		config)   pat="^CONFIG_PACKAGE_${p}=y$" ;;
		manifest) pat="^${p} - " ;;
	esac
	if grep -qE "$pat" "$FILE"; then
		ok "SMSC 网络驱动 $p 保留"
	else
		bad "SMSC 网络驱动 $p 缺失（误禁会破坏网络，与蜂窝无关）"
	fi
done

echo
echo "== [guard] FanchmWrt 行为管理包（$MODE: $FILE）=="
for p in $FCM; do
	case "$MODE" in
		config)   pat="^CONFIG_PACKAGE_${p}=y$" ;;
		manifest) pat="^${p} - " ;;
	esac
	if grep -qE "$pat" "$FILE"; then
		ok "行为管理包 $p"
	else
		bad "行为管理包 $p 缺失（FanchmWrt 杂交功能不完整，禁止构建/发布）"
	fi
done

echo
echo "== [guard] 风格约束：FanchmWrt 原生（无 QuickStart / 商城 / Argon）=="
# 与蜂窝守卫同语义：出现即失败（本项目明确不采用 iStoreOS 风格）
for p in $STYLE_FORBIDDEN; do
	case "$MODE" in
		config)   pat="^CONFIG_PACKAGE_${p}=y$" ;;
		manifest) pat="^${p} - " ;;
	esac
	if grep -qE "$pat" "$FILE"; then
		bad "iStoreOS 风格包 $p 被引入（本固件使用 FanchmWrt 原生风格）"
	else
		ok "$p 未引入"
	fi
done
# 正向：FanchmWrt 主题必须在（已在 FCM 清单断言，这里再确认风格落地）
case "$MODE" in
	config)   grep -qE '^CONFIG_PACKAGE_luci-theme-fanchmwrt=y$' "$FILE" && ok "默认主题 luci-theme-fanchmwrt" || bad "缺默认主题 luci-theme-fanchmwrt" ;;
	manifest) grep -qE '^luci-theme-fanchmwrt - ' "$FILE" && ok "默认主题 luci-theme-fanchmwrt" || bad "产物缺默认主题 luci-theme-fanchmwrt" ;;
esac

echo
if [ "$FAIL" -gt 0 ]; then
	echo "::error::核心网络包守卫失败：$FAIL 项 —— 禁止继续构建/发布"
	exit 1
fi
echo "核心网络包守卫通过 ✅（LAN/WAN/DHCP 生命线齐全）"
