# Actions-OpenWrt-AN758X · naoki66 ONU 增强版

以 [qwe-qaq/Actions-OpenWrt-AN758X](https://github.com/qwe-qaq/Actions-OpenWrt-AN758X) 为蓝本，
云编译 [pbs05/ponwrt](https://github.com/pbs05/ponwrt)（ImmortalWrt + Airoha AN758x，内核 6.18）固件，
并集成 **naoki66** 的两个仓库：

| 仓库 | 接入方式 | 提供 |
|------|---------|------|
| [naoki66/OpenWrt_ONU_CONFIG](https://github.com/naoki66/OpenWrt_ONU_CONFIG) | 替换 `pon_userspace` feed（feeds.conf） | `airoha-pond`（OMCI/OAM 代理）、`airoha-ponctl`（线路控制，Rust）、`airoha-pon-debug`（抓包诊断）、`luci-app-onu`（顶级 ONU 菜单：状态/硬件身份/认证/上网/IPTV/语音/诊断）+ firewall4 flowtable 补丁 |
| [naoki66/luci-app-airoha](https://github.com/naoki66/luci-app-airoha) | 新增 `airoha_luci` feed（feeds.conf） | `luci-app-airoha-npu`（SoC/NPU 状态页）、`luci-app-airoha-fancontrol`、`luci-app-airoha-recovery`、`luci-app-airoha-factory`、`luci-app-mesh-conf`、`luci-app-netmode` |

## 与蓝本的关键差异

1. **feeds.conf 换源**：`pon_userspace` 从 `pbs05/openwrt-pon-userspace` 换成
   `naoki66/OpenWrt_ONU_CONFIG`（该仓库是其重构 fork）。包名 `airoha-pond` /
   `airoha-ponctl` / `airoha-pon-debug` 不变；`luci-app-pon` + `luci-app-iptv`
   合并为顶级菜单 `luci-app-onu`。
2. **全部机型配置已同步**：`configs/*.config` 中
   - `CONFIG_PACKAGE_luci-app-pon=y` → `CONFIG_PACKAGE_luci-app-onu=y`
   - `luci-i18n-pon-zh-cn` → `luci-i18n-onu-zh-cn`
   - 删除独立的 `luci-app-iptv` / `luci-i18n-iptv-zh-cn`（已并入 onu）
   - 新增 `CONFIG_BUSYBOX_CONFIG_DEVMEM=y` + `CONFIG_KERNEL_DEVMEM=y`
     （naoki66 版 airoha-npu 状态页的 Frame Engine 寄存器读取依赖 devmem）
   - 追加 naoki66 luci-app-airoha 其余 5 个插件的注释行，按需取消注释
3. **diy-part1.sh 重写**：
   - 把 OpenWrt_ONU_CONFIG 自带的 `patches/firewall4/010-fw4-zone-device-flowtable.patch`
     拷到 `feeds/packages/net/firewall4/patches/`（zone device 也参与 flowtable
     卸载解析，PPPoE 会话下物理网口才能命中硬件卸载）；
   - airoha_luci 全部 6 个 app 的 `po/zh_Hans/luci-app-xxx.po` 改名为
     `xxx.po`（luci.mk 按 LUCI_BASENAME 查找 lmo，不改名中文不生效）；
   - 继续拉取 qwe3017/luci-app 的 `luci-app-pon-status`（PON 光模块卡片）与
     `luci-app-natmode`（NAT 类型三选一）到 `package/custom`；
   - 重建包索引并强校验：`airoha-pond` `airoha-ponctl` `airoha-pon-debug`
     `luci-app-onu` `luci-app-airoha-npu` `luci-app-pon-status` `luci-app-natmode`
     任一缺失直接失败，避免 defconfig 静默剔除。
4. **workflow 校验同步**：关键包校验列表换成 onu 系（含 `airoha-pon-debug`），
   并对 `luci-i18n-onu-zh-cn` 做中文包警告检查。
5. **固件版本后缀**：作者名改为 `maple`（workflow env `FW_AUTHOR` 唯一真相源，
   触发时也可用 `fw_author` 输入临时覆盖）。
6. **fiberhome 身份布局注入**（`diy-part1.sh` 开关 `ADD_FH_IDENTITY`，默认开）：
   ponwrt 的 `03_pon_data` 只给 gemtek/nokia/h3c 声明了 identity，fiberhome 三机型
   的 ONU→硬件身份页会报「读不到板载身份布局」。本仓库按 **pbs05/fiberhome-factory**
   的权威布局注入（HG5382A 镜像验证，volume 内偏移）：

   | 偏移 | 大小 | 内容 | 声明 |
   |------|------|------|------|
   | 0x2000 (8192) | 6B | Base MAC，二进制 | `pon_mac` / `mac-binary6` |
   | 0x2010 (8208) | 8B | PON SN：4 厂商字符 + 4 字节二进制（FHTT+C0D74532 → FHTTC0D74532） | `pon_sn` / `pon-binary8` |
   | 0x2020 (8224) | 32B | 整机序列号，ASCII | `device_sn` / `serial-text` |
   | 0x0000-0x1FFF | — | APONCAL 校准 + MT7916 EEPROM | 不开放编辑，勿动 |

## 支持的机型

| SoC | profile |
|-----|---------|
| AN7581 | `fiberhome_hg5382a` `fiberhome_hg5585f-ct` `fiberhome_hg5585f-cu` `gemtek_xg2010g` `nokia_xg-040g-md-ubi` `nokia_xg-040g-tf-ubi` `unionman_ung00a` `znxt_zn504xg-d` `znxt_zn515xg-d` |
| AN7583 | `nokia_xg-040g-mf` `nokia_xg-040g-mf-ubi` |

机型名写错会在 `Generate toolchain cache key` 步骤直接 `::error::` 退出，不会静默全机型编译。

## 使用方法

1. 把本目录推到一个 GitHub 仓库（Actions 默认关闭的话，到 Actions 页启用）。
2. **首次先跑一次预热**：Actions → Build PonWrt → Run workflow →
   `scope = toolchain-only`（建工具链缓存，不发 Release）。
3. 再跑一次 `scope = firmware` 出固件；产物进 Artifact，`upload_release=true`
   时同时发到 Release（按机型滚动保留最近 10 个）。
4. 机型 / SoC / 分支 / 编译源（fork 或 pbs05/ponwrt）都在 Run workflow 表单里选。

> 免费 runner 单次 6 小时上限，首次全量编译（工具链 + 内核 + 全包）大概率超时，
> 务必先 toolchain-only 预热。dl / ccache 缓存按「年+周」滚动，同周复用。

## 刷完怎么验

```sh
# ONU 菜单（LuCI 顶级）是否在位
ls /usr/share/luci/menu.d/luci-app-onu.json
# firewall4 补丁生效（zone device flowtable）
grep -c zone_offload_devices /usr/share/ucode/fw4.uc
# NPU 状态页
dmesg | grep -i npu
```

## 风险提示

- `luci-app-airoha-factory` 可就地改写 factory 分区（SN/MAC），默认关闭，慎开。
- XG-040G 系列刷 OpenWrt 后 XG-PON 拨号可能失效（变纯路由），部分 NAND 需 UART 救砖，请备 USB-TTL。
- 刷机前用 AN758x-Stock2UBI 备份原厂 flash，刷完恢复 PON/校准数据。

## 目录结构

```
.github/workflows/build-ponwrt.yml   # 主编译流水线（缓存/校验/发布）
.github/workflows/cache-keepalive.yml# 缓存保活
configs/*.config                     # 每机型精简配置（14 份，已同步 onu 系包名）
feeds.conf                           # feed 清单（pon_userspace 换源 naoki66 + airoha_luci）
diy-part1.sh                         # 第三方包接入（fw4 补丁 / po 改名 / pon-status+natmode / 索引校验）
diy-part2.sh                         # 默认值定制（时区 / 5G WiFi / CPU 占用率 / 版本后缀）
files/                               # rootfs 覆盖（tempinfo / cpuusage / uci-defaults）
scripts/patch-luci-cpuusage.sh       # 概览页 CPU 使用率行补丁
```
