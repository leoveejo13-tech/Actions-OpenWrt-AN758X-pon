#!/bin/bash
# ================================================================
# diy-part1.sh —— 第三方包接入（feeds 安装之后、加载 .config 之前）
# 运行目录: ponwrt 源码根目录
#
# 本仓库与蓝本（qwe-qaq/Actions-OpenWrt-AN758X）的差异：
#   1) pon_userspace feed 已在 feeds.conf 里换源为 naoki66/OpenWrt_ONU_CONFIG
#      （luci-app-pon/luci-app-iptv -> luci-app-onu），这里不再重复处理；
#   2) airoha_luci feed（naoki66/luci-app-airoha）随 feeds.conf 拉入，
#      提供 luci-app-airoha-{npu,fancontrol,recovery,factory,mesh-conf,netmode}；
#   3) 这里负责：
#      a. 把 OpenWrt_ONU_CONFIG 自带的 firewall4 补丁装进 packages feed
#      b. airoha_luci 各 app 的 po 文件改名（luci.mk 按 basename 查 lmo）
#      c. 拉 qwe3017/luci-app 的 luci-app-pon-status / luci-app-natmode
#      d. 重建包索引并校验关键包
# ================================================================

set -uo pipefail

echo "=========================================="
echo "第三方包接入 (diy-part1.sh)"
echo "=========================================="

PKG_DIR="package/custom"
mkdir -p "$PKG_DIR"

# ---------------------------------------------------------
# 插件开关
# ---------------------------------------------------------
ADD_LUCI_APP=true      # qwe3017/luci-app 仓库（monorepo）
                       #   ├─ luci-app-pon-status  PON 光模块卡片（概览页「系统」下一格）
                       #   └─ luci-app-natmode     NAT 类型三选一（网络 → NAT 类型）
ADD_FW4_PATCH=true     # naoki66 firewall4 flowtable 补丁（luci-app-onu 上网页 PPE 卸载需要）

clone() {  # clone <url> <dir> [branch]
  local url="$1" dir="$2" br="$3"
  [ -d "$dir" ] && { echo "已存在，跳过: $dir"; return 0; }
  echo "--- git clone $url -> $dir ---"
  if [ -n "$br" ]; then
    git clone --depth 1 -b "$br" "$url" "$dir" 2>&1 | tail -3
  else
    git clone --depth 1 "$url" "$dir" 2>&1 | tail -3
  fi
  if [ -d "$dir" ]; then
    echo "✅ 克隆成功: $dir"
    return 0
  fi
  echo "::error::克隆失败: $url"
  return 1
}

# =========================================================
# 1. firewall4 补丁：zone device 也参与 flowtable 卸载解析
#
#    naoki66/OpenWrt_ONU_CONFIG 把补丁放在仓库 patches/firewall4/ 下
#    （feed 仓库自身不携带 packages feed 的补丁机制），需要手工拷到
#    feeds/packages/net/firewall4/patches/，编译 firewall4 时由 quilt 应用。
# =========================================================
if [ "$ADD_FW4_PATCH" = "true" ]; then
  FW4_DIR="feeds/packages/net/firewall4"
  FW4_PATCH_SRC=$(ls feeds/pon_userspace/patches/firewall4/*.patch 2>/dev/null | head -1)

  if [ -z "$FW4_PATCH_SRC" ]; then
    echo "::warning::feeds/pon_userspace/patches/firewall4/ 下没有补丁，跳过"
  elif [ ! -d "$FW4_DIR" ]; then
    echo "::warning::未找到 $FW4_DIR，跳过 firewall4 补丁"
  else
    mkdir -p "$FW4_DIR/patches"
    cp -f "$FW4_PATCH_SRC" "$FW4_DIR/patches/"
    echo "✅ firewall4 补丁已就位: $FW4_DIR/patches/$(basename "$FW4_PATCH_SRC")"
  fi
fi

# =========================================================
# 2. qwe3017/luci-app —— pon-status / natmode
#
#    monorepo 结构，必须把子目录拷进 package/custom（目录名 = 包名）。
# =========================================================
if [ "$ADD_LUCI_APP" = "true" ]; then
  LUCI_APP_URL="https://github.com/qwe3017/luci-app"
  LUCI_APP_TMP="$(mktemp -d)/luci-app"

  if ! clone "$LUCI_APP_URL" "$LUCI_APP_TMP" main; then
    echo "::error::qwe3017/luci-app 拉取失败，natmode / pon-status 会被 defconfig 剔除"
    exit 1
  fi

  for p in luci-app-natmode luci-app-pon-status; do
    if [ ! -f "$LUCI_APP_TMP/$p/Makefile" ]; then
      echo "::error::$LUCI_APP_TMP/$p/Makefile 不存在，包无法被索引"
      exit 1
    fi
    rm -rf "$PKG_DIR/$p"
    cp -r "$LUCI_APP_TMP/$p" "$PKG_DIR/"
    echo "✅ 已拷贝: $p  (版本 $(grep -m1 '^PKG_VERSION' "$PKG_DIR/$p/Makefile" 2>/dev/null | sed 's/PKG_VERSION:=//'))"
  done

  rm -rf "$LUCI_APP_TMP"
fi

# =========================================================
# 3. airoha_luci feed 的 po 文件改名
#
#    luci.mk 的 i18n install 规则：
#      po2lmo $(po) → $(LUCI_LIBRARYDIR)/i18n/$(basename $(notdir $(po))).$(lang).lmo
#    即 lmo 名取自 po 文件主名。而运行时按
#      LUCI_BASENAME = $(patsubst luci-app-%,%,luci-app-airoha-npu) = airoha-npu
#    查找 lmo。上游 po 都叫 luci-app-airoha-xxx.po，
#    会生成 luci-app-airoha-xxx.zh-cn.lmo，前端找不到 → 中文不生效。
#    官方 app 都是 basename 命名（firewall.po / package-manager.po / onu.po）。
#    （luci-app-onu 的 po 已是 onu.po，无需处理）
# =========================================================
echo "--- airoha_luci po 改名 ---"
for appdir in feeds/airoha_luci/luci-app-*; do
  [ -d "$appdir/po" ] || continue
  app=$(basename "$appdir")
  base="${app#luci-app-}"
  for langdir in "$appdir"/po/*/; do
    [ -d "$langdir" ] || continue
    for pof in "$langdir"luci-app-*.po; do
      [ -f "$pof" ] || continue
      target="$langdir${base}.po"
      if [ "$pof" != "$target" ]; then
        mv "$pof" "$target"
        echo "✅ po 改名: $app ${pof#$appdir/} -> ${target#$appdir/}"
      fi
      # 确保中文 po 的 Language 头存在（po2lmo 识别语言用）
      if [[ "$target" == */zh_Hans/* ]] && ! grep -q '^"Language:' "$target"; then
        sed -i 's/^msgstr ""$/msgstr ""\n"Language: zh_Hans\\n"/' "$target"
      fi
    done
  done
done

# =========================================================
# 4. 检查重复嵌套目录（防止 feed 索引中断）
# =========================================================
echo "--- 检查重复嵌套目录 ---"
for d in "$PKG_DIR"/*; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  if [ -d "$d/$n" ] && [ -f "$d/$n/Makefile" ]; then
    rm -rf "$d/$n"
    echo "✅ 已移除重复嵌套目录: $n/$n"
  fi
done

# =========================================================
# 5. 强制重建包索引
#
#   package/custom 下的包不需要注册 feed（scan.mk 直接扫 package/ 树），
#   但新增文件后必须清掉扫描 stamp 再跑 prepare-tmpinfo，否则
#   scan_unchanged 优化会跳过扫描，tmp/.packageinfo 不会更新。
# =========================================================
rm -f tmp/.packageinfo tmp/.targetinfo
rm -f tmp/info/.scan-packageinfo.stamp tmp/info/.scan-targetinfo.stamp
rm -f tmp/.config-package.in tmp/.config-target.in

echo ">>> make prepare-tmpinfo（重新扫描 package/ 树）"
make -s prepare-tmpinfo OPENWRT_BUILD= 2>&1 | tail -5 || true

# =========================================================
# 6. 包索引校验
# =========================================================
echo "=========================================="
echo "包索引校验（判据：tmp/.packageinfo）"
echo "=========================================="

# 6a. PON 用户态（来自 pon_userspace feed = naoki66/OpenWrt_ONU_CONFIG）
echo "pon_userspace feed（naoki66/OpenWrt_ONU_CONFIG）："
FEED_MISS=""
for p in airoha-pond airoha-ponctl airoha-pon-debug luci-app-onu; do
  if grep -qx "Package: $p" tmp/.packageinfo 2>/dev/null; then
    echo "  ✅ $p"
  else
    echo "  ❌ $p"
    FEED_MISS="$FEED_MISS $p"
  fi
done

# 6b. airoha_luci feed（naoki66/luci-app-airoha）
echo "airoha_luci feed（naoki66/luci-app-airoha）："
for p in luci-app-airoha-npu luci-app-airoha-fancontrol luci-app-airoha-recovery \
         luci-app-airoha-factory luci-app-mesh-conf luci-app-netmode; do
  if grep -qx "Package: $p" tmp/.packageinfo 2>/dev/null; then
    echo "  ✅ $p"
  else
    echo "  ⚠ $p（未索引，仅当 config 里显式 =y 时才会导致失败）"
  fi
done

# 6c. package/custom
echo "package/custom："
for d in "$PKG_DIR"/*; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  [ -f "$d/Makefile" ] || { echo "  -  $n（无根 Makefile，跳过）"; continue; }
  if grep -qx "Package: $n" tmp/.packageinfo 2>/dev/null; then
    echo "  ✅ $n"
  else
    echo "  ❌ $n —— tmp/.packageinfo 里查不到"
    for f in "logs/package/$n/dump.txt" "logs/package/custom/$n/dump.txt"; do
      [ -f "$f" ] && { echo "===== $f ====="; tail -25 "$f"; }
    done
    FEED_MISS="$FEED_MISS $n"
  fi
done

echo "------------------------------------------"
echo "luci.mk: $([ -f feeds/luci/luci.mk ] && echo '✓' || echo '✗ 缺失（luci app 无法解析）')"
echo "tmp/.packageinfo 包总数: $(grep -c '^Package: ' tmp/.packageinfo 2>/dev/null || echo 0)"
echo "=========================================="

# 必装包（config 里是 =y）必须全部进索引，否则 defconfig 会静默剔除
REQUIRED="airoha-pond airoha-ponctl airoha-pon-debug luci-app-onu luci-app-airoha-npu"
if [ "$ADD_LUCI_APP" = "true" ]; then
  REQUIRED="$REQUIRED luci-app-natmode luci-app-pon-status"
fi
HARD_MISS=""
for r in $REQUIRED; do
  grep -qx "Package: $r" tmp/.packageinfo 2>/dev/null || HARD_MISS="$HARD_MISS $r"
done
if [ -n "$HARD_MISS" ]; then
  echo "::error::以下必装包未进入 tmp/.packageinfo，defconfig 会把 .config 里的 =y 静默剔除:$HARD_MISS"
  exit 1
fi

echo "🎉 diy-part1.sh 执行完毕"
