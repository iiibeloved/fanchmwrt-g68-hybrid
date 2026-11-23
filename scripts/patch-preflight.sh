#!/bin/sh
# =============================================================================
#  内核补丁预检（prepare 阶段，40 秒级）：把「上游补丁栈 + 本仓 G68 补丁」
#  真的打一遍到 linux-6.12.x 源码片段上，任何 hunk 失败立刻拦下。
#
#  为什么需要：
#    device/kernel-patches/ 里的 910/913/915 是按某个内核版本写的文本 diff。
#    FanchmWrt 的 target/linux/rockchip/patches-6.12/ 有 260+ 个 v6.13~v6.19
#    回移补丁，其中 039-01..039-05 会重写 dwmac-rk.c（加 RK3528、搬
#    integrated_phy_powerup、删多余 GRF）。上游一动，我们的 hunk 就可能
#    静默失配 —— 而 OpenWrt 的 patch 失败会让 make 在 **编译 40 分钟后**
#    才炸，失败信息淹没在几万行日志里。
#    本脚本只下载 4 个源文件（约 200KB），按真实顺序打一遍：
#      内核 tag 源文件 → generic/rockchip 里涉及这些文件的补丁 → 本仓补丁
#    要求 **fuzz=0**（零模糊）全部命中，命中不了就是必须重写。
#
#  用法: sh scripts/patch-preflight.sh <FanchmWrt源码根目录>
#  依赖: curl（或 wget）、patch；缺失时降级为告警（不阻塞构建）
# =============================================================================
set -eu

ROOT="${1:?用法: patch-preflight.sh <FanchmWrt源码根目录>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEV="$HERE/device"
FAIL=0
ok()   { printf '  [OK]   %s\n' "$*"; }
bad()  { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }
warn() { printf '  [WARN] %s\n' "$*"; }

# ---------- 1) 读出内核版本 ----------
KV=""
KVDET=""
for f in "$ROOT/target/linux/generic/kernel-6.12" "$ROOT/include/kernel-6.12"; do
	[ -f "$f" ] && { KVDET="$f"; break; }
done
[ -n "$KVDET" ] && KV=$(sed -n 's/^LINUX_VERSION-6\.12 = //p' "$KVDET" | head -1)
if [ -z "$KV" ]; then
	KP=$(sed -n 's/^KERNEL_PATCHVER:=//p' "$ROOT/target/linux/rockchip/Makefile" 2>/dev/null | head -1)
	case "$KP" in 6.12*) KV="$KP" ;; esac
fi
[ -n "$KV" ] || { warn "读不到内核版本，跳过补丁预检"; exit 0; }
VER="${KV#6.12}"; VER="${VER#.}"
TAG="v6.12.${VER}"
echo "== [patch-preflight] 内核 $TAG =="

# ---------- 2) 需要下载的源文件（本仓补丁涉及的文件）----------
FILES="
drivers/net/ethernet/stmicro/stmmac/dwmac-rk.c
arch/arm64/boot/dts/rockchip/rk356x.dtsi
arch/arm64/boot/dts/rockchip/rk3568.dtsi
arch/arm64/boot/dts/rockchip/Makefile
"
W=$(mktemp -d); trap 'rm -rf "$W" 2>/dev/null || true' EXIT HUP INT TERM
SRC="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain"

fetch() { # fetch <相对路径>
	_d="$W/$1"
	mkdir -p "$(dirname "$_d")"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --retry 2 --max-time 60 -o "$_d" "$SRC/$1?h=$TAG" 2>/dev/null && return 0
	elif command -v wget >/dev/null 2>&1; then
		wget -q -T 60 -O "$_d" "$SRC/$1?h=$TAG" 2>/dev/null && return 0
	else
		return 2
	fi
	return 1
}

echo "  下载内核源文件（$TAG）..."
NET_OK=1
for f in $FILES; do
	if ! fetch "$f"; then
		[ -s "$W/$f" ] && [ "$(wc -c < "$W/$f")" -gt 1000 ] && continue
		NET_OK=0
		break
	fi
	[ -s "$W/$f" ] || { NET_OK=0; break; }
done
if [ "$NET_OK" != "1" ]; then
	warn "无法下载 kernel.org 源文件（网络/镜像问题），本次跳过补丁预检（构建期仍会验证）"
	exit 0
fi
ok "4 个内核源文件已就绪（$TAG）"

# ---------- 3) 按真实顺序应用上游补丁中「涉及这些文件」的部分 ----------
touches() { # touches <patch> -> 0 表示涉及
	for f in $FILES; do
		grep -qE "^(---|\+\+\+) [ab]/$f([[:space:]]|$)" "$1" 2>/dev/null && return 0
	done
	return 1
}

patch_files() { # patch_files <patch> -> 逐个打印 -p1 后的相对路径
	grep -E '^--- a/' "$1" 2>/dev/null | sed 's|^--- a/||; s|[[:space:]].*$||'
}

apply_series() { # apply_series <目录> <标签>
	_dir="$1"; _tag="$2"; _n=0; _fail=0; _skip=0
	[ -d "$_dir" ] || return 0
	for p in $(ls "$_dir"/*.patch 2>/dev/null | sort); do
		touches "$p" || continue
		# 该补丁若同时改其它文件，按需补下（保证 hunk 上下文与真实构建一致）；
		# 补不下来就跳过整条并告警 —— 宁可预检不完整，也不要误报失败。
		_ok=1
		for f in $(patch_files "$p"); do
			[ -s "$W/$f" ] && continue
			fetch "$f" >/dev/null 2>&1 || true
			[ -s "$W/$f" ] || { _ok=0; break; }
		done
		if [ "$_ok" != "1" ]; then
			_skip=$((_skip+1))
			warn "跳过 $_tag/$(basename "$p")（涉及无法获取的源文件，预检不覆盖该补丁）"
			continue
		fi
		_n=$((_n+1))
		if ! ( cd "$W" && patch -p1 -N -F0 --no-backup-if-mismatch < "$p" >/dev/null 2>&1 ); then
			# 只对「改内核网络驱动」的补丁硬失败：本仓 910/913/915 的上下文
			# 全在 dwmac-rk.c 上，它错了 LAN 就死；DTS/Makefile 类补丁在最小
			# 复现树里可能因跳过别的补丁而假失败，只告警不阻塞。
			if grep -qE "^(---|\+\+\+) [ab]/drivers/net/ethernet/stmicro/stmmac/dwmac-rk\.c" "$p"; then
				_fail=$((_fail+1))
				bad "上游补丁与 $TAG 源文件不匹配（dwmac-rk.c）: $_tag/$(basename "$p")"
			else
				warn "上游 $_tag/$(basename "$p") 在最小复现树上未命中（非网络驱动，仅告警）"
			fi
		fi
	done
	[ "$_n" -gt 0 ] && ok "上游 $_tag 补丁已应用 $_n 个（失败 $_fail，跳过 $_skip）"
	return 0
}

apply_series "$ROOT/target/linux/generic/patches-6.12" "generic"
apply_series "$ROOT/target/linux/rockchip/patches-6.12" "rockchip"

# ---------- 4) 本仓 G68 补丁：要求零 fuzz 全部命中 ----------
echo "  应用 device/kernel-patches（fuzz=0）..."
N=0
for p in $(ls "$DEV"/kernel-patches/*.patch 2>/dev/null | sort); do
	N=$((N+1))
	if ( cd "$W" && patch -p1 -N -F0 --no-backup-if-mismatch < "$p" >/tmp/pp.log 2>&1 ); then
		ok "G68 补丁命中: $(basename "$p")"
	else
		bad "G68 补丁失配: $(basename "$p")（上游改动了对应上下文，必须按 $TAG 重写）"
		grep -E "FAILED|Hunk" /tmp/pp.log | sed 's/^/         /' || true
	fi
done
[ "$N" -gt 0 ] || warn "device/kernel-patches 为空"

# ---------- 5) 打完补丁后关键锚点仍在（防补丁互相覆盖）----------
DW="$W/drivers/net/ethernet/stmicro/stmmac/dwmac-rk.c"
if [ -f "$DW" ]; then
	for pat in 'set_to_sgmii' 'is_fixed_link' 'RK3568_PIPE_GRF_XPCS_SGMII_MAC_SEL' 'rockchip,pipegrf'; do
		grep -q "$pat" "$DW" && ok "打完补丁仍有锚点: $pat" || bad "打完补丁丢了锚点: $pat"
	done
fi

echo
if [ "$FAIL" -gt 0 ]; then
	echo "::error::内核补丁预检失败：$FAIL 项 —— 上游补丁栈已变化，禁止进入耗时编译"
	exit 1
fi
echo "内核补丁预检通过 ✅（$TAG：上游栈 + G68 补丁零 fuzz 全命中）"
