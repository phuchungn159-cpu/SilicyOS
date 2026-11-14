<div align="center">

<img src="../silicyos-build/branding/mark-128.png" width="88" height="88" alt="silicyOS Mark">

# silicyOS

**专为 Apple Silicon 打造的 Arch Linux ARM64 — 16KB 页、CachyOS BORE、LLVM ThinLTO 与 Titanium Wayland**

![Audit](https://img.shields.io/badge/Audit-205%20Checks%20Pass-0A84FF?style=flat-square&labelColor=141418)
![Architecture](https://img.shields.io/badge/Arch-ARM64%20(16KB%20Pages)-0A84FF?style=flat-square&labelColor=141418)
![Hardware](https://img.shields.io/badge/Target-Apple%20M1%20%7C%20M2%20%7C%20M3-141418?style=flat-square&labelColor=0B0B0E)
![Wayland](https://img.shields.io/badge/Wayland-Niri%20%7C%20Hyprland-141418?style=flat-square&labelColor=0B0B0E)
[![License: MIT](https://img.shields.io/badge/License-MIT-141418?style=flat-square&labelColor=0B0B0E)](../LICENSE)

[English](../README.md) · [Tiếng Việt](README.vi.md) · [日本語](README.ja.md) · **简体中文**

</div>

`silicyOS` 是专为 Apple Silicon Mac（M1、M2、M3 系列）设计的 Arch Linux ARM64（`aarch64`）发行版。它将上游 Asahi Linux 16KB 页大小内核与 CachyOS BORE 交互式调度器、LLVM/Clang ThinLTO 编译、Btrfs 透明压缩以及遵循 **Apple Industrial Titanium** 视觉规范的 Wayland 桌面环境深度整合。

仓库根目录快捷命令：`make verify`（8 阶段审计） | `make build-macos`（Lima Apple VZ 构建） | `make install-macos`（双系统安装）。

---

## 目录

- [1. 设计理念与硬件目标](#1-设计理念与硬件目标)
- [2. 内核、调度器与网络协议栈](#2-内核调度器与网络协议栈)
- [3. 统一内存、ZRAM、I/O 与服务精简](#3-统一内存zramio-与服务精简)
- [4. 存储布局与 Btrfs 快照 (`silicy-capsule`)](#4-存储布局与-btrfs-快照-silicy-capsule)
- [5. 纯 C 硬件控制器 (`silicy-ctl`)](#5-纯-c-硬件控制器-silicy-ctl)
- [6. 交互式控制中心 (`silicy-center`)](#6-交互式控制中心-silicy-center)
- [7. 安全只读 macOS APFS 数据桥接 (`silicy-macos-bridge`)](#7-安全只读-macos-apfs-数据桥接-silicy-macos-bridge)
- [8. 智能 `Command` 键同步与毛玻璃 HUD (`keyd` + `swayosd`)](#8-智能-command-键同步与毛玻璃-hud-keyd--swayosd)
- [9. 桌面环境、视觉规范与快捷键](#9-桌面环境视觉规范与快捷键)
- [10. 仓库架构](#10-仓库架构)
- [11. 构建、安装与首次启动向导](#11-构建安装与首次启动向导)
- [12. 自动化验证与审计 (`verify-silicyos.sh`)](#12-自动化验证与审计-verify-silicyossh)
- [13. 故障排查与测试边界](#13-故障排查与测试边界)

---

## 1. 设计理念与硬件目标

Apple Silicon 在内存页大小、异构大小核集群、NVMe 提交队列及固件加载机制方面与传统 x86_64 笔记本存在本质区别。`silicyOS` 围绕这些硬件特性构建：

- **严格对齐 16KB 页大小**：Apple Silicon 的 IOMMU 与 Dart 硬件原生运行于 16KB 内存页（`CONFIG_ARM64_16K_PAGES=y`, `CONFIG_ARM64_PAGE_SHIFT=14`）。Swap、ZRAM 与 NVMe 预读均按 16KB 边界优化，避免缺页放大效应。
- **E-Core / P-Core 异构感知**：遥测读取与后台索引进程隔离至能效核（E-core：Icestorm/Blizzard/Sawtooth），Wayland 合成器与前台交互窗口则根据电源配置优先调度至性能核（P-core：Firestorm/Avalanche/Everest）。
- **零 Shell 轮询**：避免 `while true; do cat /sys/...; sleep 1; done` 造成的 P-core 频繁唤醒与耗电。持续传感器读取全部采用纯 C11（`silicy-ctl`）基于栈缓冲区与原生系统调用实现。
- **零冗余占用**：通过纯内存 `journald`、禁用核心转储、带 Apple 固件白名单的 pacman `NoExtract` 规则及事务后自动清理包缓存，将目标占用控制在 `< 2.8 GB` 磁盘空间与 `< 420 MB` 空闲内存。

---

## 2. 内核、调度器与网络协议栈

源码：[`silicyos-build/kernel/PKGBUILD`](../silicyos-build/kernel/PKGBUILD) | [`config.silicy`](../silicyos-build/kernel/config.silicy) | [`99-silicy-cachyos.conf`](../silicyos-build/cachy-arm64/silicy-core-tuning/99-silicy-cachyos.conf)

### 内核构建配置 (`linux-silicy-asahi`)
- **上游基线**：`AsahiLinux/linux` 标签 `asahi-6.12.12-1`（`pkgver=6.12.12.asahi1`）。
- **集成补丁**：CachyOS `0001-bore-cachy.patch`（BORE 调度器）与 `0002-bbr3.patch`（TCP BBRv3）。
- **编译工具链**：全 LLVM/Clang 构建（`LLVM=1`, `LLVM_IAS=1`, `CC=clang`, `LD=ld.lld`），使用 `-O3 -mcpu=apple-m1 -mtune=apple-m1` 及 `KRUSTFLAGS="-C opt-level=3 -C target-cpu=apple-m1"`。
- **强制内核选项**：`CONFIG_ARM64_16K_PAGES=y`, `CONFIG_ARM64_PAGE_SHIFT=14`, `CONFIG_SCHED_BORE=y`, `CONFIG_LTO_CLANG_THIN=y`, `CONFIG_HZ_1000=y`。

### 核心 Sysctl 调优 (`/etc/sysctl.d/99-silicy-cachyos.conf`)

| 子系统 | 参数 | 取值 | 技术依据 |
| --- | --- | --- | --- |
| ZRAM / Swap | `vm.page-cluster` | `0` | 防止每次换页读取 `2^3 * 16KB = 128KB`，严格解压单个 16KB 页 |
| ZRAM / Swap | `vm.swappiness` | `150` | 优先使用内存 `zstd` ZRAM 压缩，减少 SSD NAND 写入磨损 |
| Btrfs 缓存 | `vm.vfs_cache_pressure` | `50` | 延长 Btrfs dentry/inode 驻留时间，减少 ANS2 NVMe 唤醒 |
| 脏页回写 | `vm.dirty_ratio` / `dirty_background_ratio` | `10` / `5` | 限制脏页比例，防止 `zstd:3` Btrfs 挂载产生 I/O 卡顿 |
| BORE 调度 | `kernel.sched_bore` | `1` | 优先响应突发型的 Wayland 合成与 PipeWire 音频线程 |
| BORE 调度 | `kernel.sched_burst_penalty_offset` | `22`（默认） | 由 `silicy-ctl` 动态调整（`28` eco / `22` balanced / `16` burst） |
| 网络 | `net.core.default_qdisc` / `tcp_congestion_control` | `fq` / `bbr` | 启用 TCP BBRv3、TCP Fast Open (`3`) 与带回退的 ECN (`1`) |

---

## 3. 统一内存、ZRAM、I/O 与服务精简

源码：[`memory/zram-generator.conf`](../silicyos-build/memory/zram-generator.conf) | [`memory/earlyoom.conf`](../silicyos-build/memory/earlyoom.conf) | [`70-silicy-io.rules`](../silicyos-build/cachy-arm64/silicy-core-tuning/70-silicy-io.rules) | [`services/systemd-diet.sh`](../silicyos-build/services/systemd-diet.sh)

### 统一内存保护 (`zram` + `earlyoom`)
Apple Silicon 的 CPU 与 Asahi AGX GPU 共享 LPDDR 物理内存，内存耗尽时合成器往往先于内核 OOM 卡死：
- **`zram0`**：设置 `zram-size = ram`、`compression-algorithm = zstd`、`swap-priority = 100`。
- **`earlyoom`**：可用内存 `<= 4%` / 可用 ZRAM `<= 10%` 发送 `SIGTERM`，`<= 2%` / `<= 5%` 发送 `SIGKILL`。通过 `--avoid` 保护系统核心进程（`niri`, `Hyprland`, `kitty`, `greetd`, `seatd`, `dbus-broker`, `pipewire`, `speakersafetyd`, `tiny-dfr`, `keyd`, `swayosd-server`），通过 `--prefer` 优先回收大型浏览器与编译器（`chromium`, `firefox`, `rustc`, `clang`, `node`）。

### 块设备 I/O 与 Udev 规则 (`70-silicy-io.rules`)
- **内置 Apple ANS2 NVMe (`nvme*n*`)**：`scheduler="none"`, `read_ahead_kb="256"` (`16 x 16KB`), `nr_requests="1024"`, `rq_affinity="2"`, `iostats="0"`, `wbt_lat_usec="2000"`。
- **ZRAM (`zram*`)**：`read_ahead_kb="0"`, `nomerges="2"`, `iostats="0"`。
- **外接 USB/Thunderbolt SSD (`sd[a-z]`)**：`scheduler="kyber"`, `read_ahead_kb="512"`。
- **音频与 Wayland DRM**：为 `audio` 组授予 `rtc0`/`hpet` `0660` 权限，为 `video` 组授予 `UDMABUF`/`dma_heap` `0660` 权限。

### Cgroup 分级调度 (`ananicy-cpp` + `silicy-pe-enforcer.sh`)
- `00-cgroups.cgroups` 定义四级配额：`pcores_rt` (`CPUQuota: 100`)、`pcores_interactive` (`95`)、`ecores_background` (`40`)、`ecores_idle` (`20`)。
- `silicy-pe-enforcer.sh` 通过 `/sys/devices/system/cpu/cpu*/cpu_capacity`（`< 650` 为 E-core，`1024` 为 P-core）动态探测核心拓扑，授予 `wheel` 组对 cpufreq 与 BORE sysctl 节点的写权限，将合成器与 PipeWire 绑定到 P-core，并将后台进程（`pacman`, `makepkg`, `btrfs`, `systemd-journald`）限制在 E-core。

### Systemd 服务精简 (`systemd-diet.sh`)
- **屏蔽服务**：`ModemManager`, `systemd-networkd-wait-online`, `cups` (`.service`/`.socket`/`.path`), `avahi-daemon`, `lvm2-monitor`, `ldconfig`, `systemd-FirstBoot`, `remote-fs.target`。
- **启用服务**：`dbus-broker`, `iwd`, `seatd`, `earlyoom`, `ananicy-cpp`, `speakersafetyd`, `tiny-dfr`, `keyd`, `swayosd-libinput-backend`, `greetd`。
- **SSD 寿命保护**：`journald` 限制为纯内存模式（`Storage=volatile`, `RuntimeMaxUse=16M`），完全禁用核心转储（`Storage=none`, `ProcessSizeMax=0`）。

---

## 4. 存储布局与 Btrfs 快照 (`silicy-capsule`)

源码：[`storage/setup-btrfs-silicy.sh`](../silicyos-build/storage/setup-btrfs-silicy.sh) | [`storage/silicy-capsule`](../silicyos-build/storage/silicy-capsule) | [`00-silicy-capsule-pre.hook`](../silicyos-build/storage/00-silicy-capsule-pre.hook) | [`99-clean-cache-and-recompress.hook`](../silicyos-build/storage/99-clean-cache-and-recompress.hook)

### Btrfs 子卷规划
所有子卷均使用 `compress-force=zstd:3,noatime,space_cache=v2` 挂载（`fstab` 中配合 `ssd,discard=async`）：

| 子卷 | 挂载点 | 用途 |
| --- | --- | --- |
| `@` | `/` | 根文件系统（快照与回滚目标） |
| `@home` | `/home` | 用户数据（`@` 回滚时保留） |
| `@pkg` | `/var/cache/pacman/pkg` | Pacman 软件包暂存 |
| `@log` | `/var/log` | 系统日志 |
| `@snapshots` | `/.snapshots` | 只读系统快照目录 |

### `silicy-capsule` CLI 与自动化
- **零空间快照**：在 `/.snapshots/` 中基于写时复制即时创建只读快照。
- **升级前自动钩子**：`00-silicy-capsule-pre.hook` 在每次 `pacman` `Upgrade` 的 `PreTransaction` 阶段触发 `silicy-capsule auto-pre-upgrade`。
- **自动保留策略**：自动清理旧快照，最多保留最近 **3 份**（支持 `create`, `auto-pre-upgrade`, `prune`, `list`, `rollback`）。
- **事务后清理**：`99-clean-cache-and-recompress.hook` 在安装/升级/卸载后自动清理 `.pkg.tar*` 归档及 `/tmp`、`/var/tmp` 残留。

---

## 5. 纯 C 硬件控制器 (`silicy-ctl`)

源码：[`silicyos-build/silicy-ctl/silicy-ctl.c`](../silicyos-build/silicy-ctl/silicy-ctl.c) | [`Makefile`](../silicyos-build/silicy-ctl/Makefile) | [`71-silicy-macsmc.rules`](../silicyos-build/silicy-ctl/71-silicy-macsmc.rules)

`silicy-ctl` 采用严格 C11 标准（`-Wall -Wextra -Werror -O3 -mcpu=apple-m1 -flto=thin`）编写，零堆内存分配（不使用 `malloc`/`calloc`/`realloc`），全部 I/O 基于 `open()`, `pread()`, `pwrite()`，亲和性绑定调用 `sched_setaffinity()`。

### 子命令参考

| 命令 | 行为说明 |
| --- | --- |
| `silicy-ctl telemetry` | 绑定至 E-core，读取 `macsmc-battery`（`power_now`、回退 `current_now`*`voltage_now`、`capacity`、`status`、`charge_control_end_threshold`、`cycle_count`）与 `/sys/class/hwmon/` SoC 温度，输出单行 Waybar JSON |
| `silicy-ctl telemetry --power\|--temp\|--memory` | 输出简洁功耗（`%.1fW`）、温度（`%.0f°C`）或 RAM/ZRAM 摘要 |
| `silicy-ctl battery-guard <60\|80\|100\|status>` | 校验阈值（`60`, `80`, `100`），写入 `charge_control_end_threshold` 并保存至 `/etc/silicy-battery.conf` |
| `silicy-ctl power-profile <eco\|balanced\|burst\|status>` | 更新 CPU 调速器、频率上限、进程亲和性、`cpuset.cpus`、BORE sysctl、`dirty_writeback_centisecs` 及 Hyprland 模糊状态（`toggle_compositor_blur`） |
| `silicy-ctl keyboard-mode <mac\|pc\|status>` | 从 `/usr/share/silicyos/keyd/{mac,pc}-mode.conf` 复制配置至 `/etc/keyd/default.conf` 并写入 `/etc/silicy-kb-mode` |

### Waybar JSON 输出格式
```json
{
  "text": "4.2W · 38°C",
  "alt": "balanced",
  "tooltip": "Apple SMC Telemetry | Profile: balanced | Power: 4.2W (Discharging) | SoC: 38.5C | Battery: 86% (Limit: 80%, Cycles: 24)",
  "class": "balanced",
  "percentage": 86,
  "power_watts": 4.20,
  "temp_c": 38.5,
  "capacity": 86,
  "status": "Discharging",
  "charge_threshold": 80,
  "cycle_count": 24,
  "profile": "balanced"
}
```

### `wheel` 用户组免 `sudo` 权限 (`71-silicy-macsmc.rules`)
- 为 `wheel` 组授予 `macsmc-battery/charge_control_end_threshold`、`cpufreq/scaling_{governor,max_freq,min_freq}`、`*kbd_backlight*/brightness` 与 `backlight/*/brightness` 的 `0664` 写权限。
- 在 udev `add|change` 事件时自动恢复 `/etc/silicy-battery.conf` 中的充电上限。
- `/etc/sudoers.d/20-silicy-nopasswd` 允许 `wheel` 成员免密执行 `systemctl restart keyd`、`silicy-capsule` 与 `silicy-macos-bridge`。

---

## 6. 交互式控制中心 (`silicy-center`)

源码：[`silicyos-build/scripts/silicy-center`](../silicyos-build/scripts/silicy-center)

按 `Super + Ctrl + Space` 或点击 Waybar 系统模块打开，使用 Apple Industrial Titanium 配色的 `fuzzel --dmenu` 渲染：

| 模块 | 交互操作 | CLI 快捷调用 |
| --- | --- | --- |
| `[Power Profile]` | 切换 `eco` / `balanced` / `burst` 并显示实时功耗 | `silicy-center --power [eco\|balanced\|burst]` |
| `[Battery Care]` | 设置 `60%`、`80%`、`100%` MacSMC 充电上限 | `silicy-center --battery [60\|80\|100]` |
| `[Display Comfort]` | 开关 `wlsunset -t 4200 -T 4201`，切换 `120Hz ProMotion` <-> `60Hz Battery Saver` | `silicy-center --display` |
| `[Keyboard Mode]` | 切换 `Mac (Command)` <-> `PC (Ctrl)` 并重启 `keyd` / `keyd-application-mapper` | `silicy-center --keyboard [mac\|pc]` |
| `[macOS Shared Drive]` | 挂载/卸载 APFS 只读分区或在 `kitty` 中打开 `~/macOS-Shared` | `silicy-center --macos` |
| `[System Capsule]` | 创建快照、清理旧快照或在 `kitty` 中启动交互式回滚 | `silicy-center --capsule` |
| `[Shortcut Guide]` | 显示完整快捷键说明（支持 TTY 降级输出） | `silicy-center --shortcuts` |

### 动态合成器与合盖外接显示器检测
- 先检查会话环境变量（`NIRI_SOCKET`, `HYPRLAND_INSTANCE_SIGNATURE`），再回退至 `pgrep`，避免后台无关进程干扰当前会话判断。
- **Niri**：通过 `detect_niri_internal_output` 动态识别内置屏幕接口，并从 `niri msg --json outputs` 匹配可用刷新率模式。
- **Hyprland**：通过 `detect_hyprland_internal_output`（解析 `hyprctl monitors -j`，跳过禁用或空名称条目）识别活动显示器，并在外接屏幕场景（如合盖 4K 显示器）下保留原有分辨率与缩放比例。

---

## 7. 安全只读 macOS APFS ブリッジ (`silicy-macos-bridge`)

源码：[`silicyos-build/storage/silicy-macos-bridge`](../silicyos-build/storage/silicy-macos-bridge)

- **严格只读保护**：绝不以读写模式挂载 macOS APFS 容器，彻底杜绝 APFS 元数据损坏风险。
- **Data 卷识别**：通过 `lsblk`（`PARTLABEL` / `FSTYPE=apfs`）并调用 `apfsutil`（`detect_apfs_volume_id`）自动优先选择 `Data` 卷（`* - Data`），同时支持 `--vol N` 手动指定卷编号。
- **挂载路径**：在 `/etc/fuse.conf` 启用 `user_allow_other` 后，通过 `apfs-fuse` 或 `fsapfsmount` 挂载至 `/run/media/$USER/macOS`。
- **共享交换目录 (`~/macOS-Shared`)**：挂载共享分区前先探测 `FSTYPE`，仅对 `vfat|msdos|exfat|ntfs|ntfs3` 传递 `uid`/`gid`/`umask`，保护 Linux POSIX 文件系统（`ext4`, `btrfs`, `xfs`, `f2fs`）权限。
- **FileVault 提示**：若 macOS Data 卷启用了 FileVault 加密，`silicy-center` 会提示在 `kitty` 终端中交互式解锁。

---

## 8. 智能 `Command` 键同步与毛玻璃 HUD (`keyd` + `swayosd`)

源码：[`input/keyd/default.conf`](../silicyos-build/input/keyd/default.conf) | [`mac-mode.conf`](../silicyos-build/input/keyd/mac-mode.conf) | [`pc-mode.conf`](../silicyos-build/input/keyd/pc-mode.conf) | [`skel/.config/keyd/app.conf`](../silicyos-build/skel/.config/keyd/app.conf) | [`skel/.config/swayosd/`](../silicyos-build/skel/.config/swayosd/config.toml)

### 键盘映射架构 (`keyd`)
- `/etc/keyd/` 目录下仅保留唯一活动配置 `default.conf`（预设隔离存放于 `/usr/share/silicyos/keyd/`），避免重复加载。
- `default.conf` 定义 `[meta:M]`（`leftmeta`/`rightmeta = layer(meta)`）与 `capslock = overload(control, esc)`。
- `app.conf` 将 `[*]` 置于 `[kitty]` 与 `[org-wezfurlong-wezterm]` 之前：
  - **GUI 与浏览器 (`[*]`)**：`meta.c/v/x/z/a/w/t/s/n` 映射为 `C-*`，而 `meta.f/r/l/q` 保留 `M-*` 以避免与合成器快捷键冲突。
  - **终端 (`[kitty]`)**：物理 `Ctrl+C` 保持 POSIX `SIGINT`；`meta.c/v/t/w` 映射为 `C-S-*`，且 `meta.z = M-z`（配合 `kitty.conf` 中的 `no_op`）防止误触 `SIGTSTP`。
- **PC 模式**：交换 `leftmeta`/`rightmeta` 与 `leftcontrol`，并在会话启动时跳过 `keyd-application-mapper -d`。

### 毛玻璃 HUD (`swayosd`)
- Niri 与 Hyprland 会话均自启 `swayosd-server`。
- `swayosd/config.toml` 配置 `show_percentage = true` 与 `max_volume = 100`，遵循 `speakersafetyd` 扬声器保护限制。
- 硬件功能键（`XF86MonBrightness*`, `XF86KbdBrightness*`, `XF86Audio*`）直接驱动 `swayosd-client`，并保留 `brightnessctl` / `wpctl` 回退路径。

---

## 9. 桌面环境、视觉规范与快捷键

### Apple Industrial Titanium 调色板

| 用途 | Hex | RGB（终端 / Fastfetch / `os-release`） |
| --- | --- | --- |
| 主背景 (Background) | `#0B0B0E` | `11, 11, 14` |
| 毛玻璃表面 (Glass) | `#141418` | `20, 20, 24` |
| 边框 (Border) | `#26262E` | `38, 38, 46` |
| 主文本 (Primary) | `#F2F2F7` | `38;2;242;242;247` |
| 次要文本 (Secondary) | `#8E8E93` | `142, 142, 147` |
| 强调色 (Accent) | `#0A84FF` | `38;2;10;132;255` |

### 核心快捷键 (Niri & Hyprland)

| 快捷键 | 功能 |
| --- | --- |
| `Super + Ctrl + Space` | 打开 `silicy-center` |
| `Super + /` | 打开快捷键指南 (`silicy-center --shortcuts`) |
| `Super + Space` | 打开 `fuzzel` 应用启动器 |
| `Super + Return` | 打开 `kitty` 终端 |
| `Super + Q` | 关闭当前窗口 |
| `Super + Shift + 3` / `4` | 全屏 / 区域截图 (`grim` + `slurp` + `wl-copy`) |
| `Super + 1..6` | 切换至工作区 `1..6` |
| `Super + Shift + 1..6` | 将窗口/列移至工作区 `1..6` |
| `Super + H/J/K/L` 或方向键 | 移动焦点 |
| `Super + Shift + H/J/K/L` 或方向键 | 移动窗口/列 |
| `Super + F` / `Super + Shift + F` | 最大化列 (Niri) / 全屏 |
| `Super + Shift + V` | 切换浮动状态 |
| `Super + Shift + E` | 退出合成器会话 |

---

## 10. 仓库架构

```text
silicyos-build/
├── build-silicyos.sh                  # Arch ARM64 + Asahi rootfs 与 ESP 镜像主构建脚本
├── verify-silicyos.sh                 # 8 阶段自动化 QA 与模拟 sysroot 审计套件
├── macos-build-and-install.sh         # macOS 宿主机 Lima Apple VZ ARM64 构建编排脚本
├── install-silicyos-macos.sh          # 本地 HTTP 服务 (127.0.0.1:8765) + Asahi 安装器
├── kernel/
│   ├── PKGBUILD                       # linux-silicy-asahi (6.12.12 + BORE + BBRv3 + Clang ThinLTO)
│   └── config.silicy                  # 16KB 页大小内核配置
├── cachy-arm64/
│   ├── makepkg-silicy.conf            # ARM64 Apple M1 makepkg 编译参数
│   └── silicy-core-tuning/
│       ├── 99-silicy-cachyos.conf     # Sysctl: ZRAM 16KB, BORE, BBRv3
│       ├── 70-silicy-io.rules         # Udev: ANS2 NVMe, ZRAM, USB SSD, DRM/audio
│       ├── ananicy-silicy.rules       # 进程优先级规则 (99-silicy-overrides.rules)
│       └── ananicy-cpp/               # 00-cgroups.cgroups, 00-types.types, silicy-pe-enforcer.{sh,service}
├── silicy-ctl/
│   ├── silicy-ctl.c                   # 纯 C 硬件控制器
│   ├── Makefile
│   ├── 71-silicy-macsmc.rules         # wheel 写权限 + 开机电池阈值恢复
│   └── silicy-battery.conf            # 默认 80% 充电上限
├── scripts/
│   └── silicy-center                  # fuzzel 控制中心
├── storage/
│   ├── setup-btrfs-silicy.sh          # Btrfs 子卷创建与 fstab 生成
│   ├── silicy-capsule                 # 快照与回滚 CLI
│   ├── 00-silicy-capsule-pre.hook     # 升级前自动快照 pacman hook
│   ├── 99-clean-cache-and-recompress.hook
│   └── silicy-macos-bridge            # APFS 只读挂载与共享盘管理
├── input/keyd/                        # default.conf, mac-mode.conf, pc-mode.conf
├── memory/                            # zram-generator.conf, earlyoom.conf
├── services/systemd-diet.sh           # 服务精简、纯内存 journald、greetd 配置
├── rootfs/
│   ├── pacman-silicy.conf             # 含 Apple 固件白名单的 NoExtract 规则
│   └── packages.silicy                # 完整软件包清单
├── skel/.config/                      # niri, hypr, waybar, fuzzel, kitty, swayosd, fastfetch, keyd, zsh
├── installer/
│   ├── installer_data.json            # Asahi 分区清单 (ROOTFS_SIZE_MB=8192)
│   └── silicy-setup-tui.sh            # 6 步首次启动配置向导
└── branding/                          # Logo (SVG/PNG)、Plymouth 启动主题、ASCII 图案、壁纸
```

---

## 11. 构建、安装与首次启动向导

### 前置条件
- Apple Silicon Mac（M1/M2/M3）且具备充足 APFS 可用空间（256 GB SSD 推荐分区：`silicyOS` 约 30 GB，macOS 215 GB）。
- 大型构建产物（`silicyos-apple-silicon.zip`, `.img`）已通过 `.gitignore` 排除，建议经由 GitHub Releases 分发。

### 方式 A：在 macOS 上通过 Lima Apple VZ 构建
1. 构建前运行验证：
   ```bash
   bash silicyos-build/verify-silicyos.sh
   ```
2. 在临时 `debian-13` Lima 虚拟机（`--vm-type=vz`）中构建 ARM64 rootfs 与 `silicyos-apple-silicon.zip`：
   ```bash
   cd silicyos-build
   ./macos-build-and-install.sh
   ```
3. 启动本地 HTTP 服务（`127.0.0.1:8765`）并运行 Asahi 安装器：
   ```bash
   ./install-silicyos-macos.sh
   ```

### 方式 B：在 Linux ARM64（`root`）环境中直接构建
```bash
cd silicyos-build
sudo ./build-silicyos.sh
```
`build-silicyos.sh` 关键构建行为：
- 镜像大小：`ROOTFS_SIZE_MB=8192`（`8589934592` 字节，与 `installer_data.json` 一致）与 `ESP_SIZE_MB=500`。
- 在 `arch-chroot` 内编译 `silicy-ctl`（使用 `make` 或 `clang -flto=thin -s -fuse-ld=lld` 回退）。
- 若软件源缺少 `apfs-fuse`，则自动拉取源码并以 `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` 编译安装 `apfs-fuse` 与 `apfsutil`。
- 生成 `/etc/mkinitcpio.conf`，包含 `MODULES=(apple-mailbox nvme_apple nvme simpledrm btrfs)` 与 `HOOKS=(... btrfs ...)`。
- 为 `systemd-boot` / `m1n1` 配置内核参数 `rootflags=subvol=@,compress-force=zstd:3`。

### 首次启动向导 (`silicy-setup-tui.sh`)
1. 解压 Apple Broadcom Wi-Fi/BT 固件（`asahi-fwextract`）并可选通过 `iwd` 连网。
2. 设置主机名，创建 `wheel` 用户（同时加入 `keyd` 组）并部署 `/etc/skel`。
3. 选择默认合成器（`niri` 或 `hyprland`）。
4. 选择键盘模式（`Mac Command` 或 `PC Ctrl`）。
5. 选择电源与视觉方案（`Max-Rice Performance` 或 `Ultra-Battery`：通过 `apply_ultra_battery_visuals` 仅关闭 Hyprland `blur` 而保留 `animations`，同时设置 `silicy-ctl battery-guard 80` 与 `power-profile eco`）。
6. 生成 `/etc/greetd/config.toml` 并进入 Wayland 会话。

---

## 12. 自动化验证与审计 (`verify-silicyos.sh`)

运行 8 阶段审计脚本：
```bash
bash silicyos-build/verify-silicyos.sh
```

在 macOS ARM64 宿主机上的实测结果：**`205 PASS | 0 WARN | 0 FAIL`**
1. **[1/8] 文件树与语法**：62 个必需文件完整性、`bash -n`/`zsh -n`、`packages.silicy` 核心包校验、ananicy 规则文件名冲突检查。
2. **[2/8] `silicy-ctl` C11 编译与模拟 Sysfs**：`clang -Wall -Wextra -Werror -O3 -mcpu=apple-m1 -flto=thin` 零警告编译、零堆分配与原生系统调用验证、含 10 核 Pro 拓扑及只读 `/run` (`0555`) 的功能测试。
3. **[3/8] 独占工具 QA**：`silicy-capsule` 3 快照保留 + 回滚 + hook；`silicy-macos-bridge` APFS 只读 + Data 卷 + FS 类型校验；`silicy-center` 全 7 模块 + Niri/Hyprland 动态输出及合盖 4K 缩放保留；`keyd` `app.conf` 顺序与 Kitty `SIGTSTP` 防护；`silicy-setup-tui.sh` 模糊块作用域边界测试；`swayosd` `max_volume = 100`。
4. **[4/8] Zero AI Slop 与配色规范**：零禁止表情符号、零 bash `/sys/` 轮询、Waybar/SwayOSD/Kitty/Fastfetch/`os-release` 的 Apple Industrial Titanium 一致性、零 TokyoNight 残留。
5. **[5/8] 引导与 Btrfs**：`rootflags=subvol=@,compress-force=zstd:3`、Apple Silicon 内核模块与 mkinitcpio `btrfs` hook 一致性。
6. **[6/8] Pacman 与内核**：固件 `NoExtract` 白名单（`brcm/*`, `apple/*`, `vendor/*`, `regulatory.db*`, `asahi-boot/*`）、`CONFIG_ARM64_16K_PAGES=y`、`CONFIG_SCHED_BORE=y`、`CONFIG_LTO_CLANG_THIN=y`、`CONFIG_HZ_1000=y`、`vm.page-cluster = 0`、零 x86 编译标志。
7. **[7/8] Rice 语法与安装器 Schema**：JSON/JSONC/TOML/KDL 校验及 `installer_data.json` 字节大小对齐。
8. **[8/8] 干跑暂存与打包**：可执行权限 `+x`、`/etc/keyd/default.conf` 单一配置文件及干跑 ZIP 打包校验。

---

## 13. 故障排查与测试边界

- **macOS 宿主机与真机边界**：macOS 上的 `verify-silicyos.sh` 负责验证编译、静态检查、暂存布局以及 `SILICY_SYSROOT` / 模拟 IPC 行为。`build-silicyos.sh` 的完整 `pacstrap`/`arch-chroot` 镜像生成与真机硬件运行（`/sys/class/power_supply/macsmc-battery/`, `/sys/class/hwmon/`, `apfs-fuse` 实机挂载、`btrfs subvolume snapshot`、`niri`/`Hyprland`/`keyd`/`swayosd-server` 实时 IPC 与首次 TUI 执行）需在 Linux ARM64 / Apple Silicon 真机上验证。
- **电池/CPU 节点权限报错**：请确认 `/etc/udev/rules.d/71-silicy-macsmc.rules` 已部署且当前用户属于 `wheel` 组。
- **FileVault APFS 挂载失败**：请在 `kitty` 终端中运行 `silicy-macos-bridge` 并交互输入解锁密码。
