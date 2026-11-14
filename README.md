<div align="center">

<img src="silicyos-build/branding/mark-128.png" width="88" height="88" alt="silicyOS Mark">

# silicyOS

**Arch Linux ARM64 Engineered for Apple Silicon — 16KB Pages, CachyOS BORE, LLVM ThinLTO & Industrial Titanium Wayland**

![Audit](https://img.shields.io/badge/Audit-205%20Checks%20Pass-0A84FF?style=flat-square&labelColor=141418)
![Architecture](https://img.shields.io/badge/Arch-ARM64%20(16KB%20Pages)-0A84FF?style=flat-square&labelColor=141418)
![Hardware](https://img.shields.io/badge/Target-Apple%20M1%20%7C%20M2%20%7C%20M3-141418?style=flat-square&labelColor=0B0B0E)
![Wayland](https://img.shields.io/badge/Wayland-Niri%20%7C%20Hyprland-141418?style=flat-square&labelColor=0B0B0E)
[![License: MIT](https://img.shields.io/badge/License-MIT-141418?style=flat-square&labelColor=0B0B0E)](LICENSE)

**English** · [Tiếng Việt](docs/README.vi.md) · [日本語](docs/README.ja.md) · [简体中文](docs/README.zh-CN.md)

</div>

---

## Overview

`silicyOS` is a minimal, hardware-aligned Arch Linux ARM64 (`aarch64`) distribution built specifically for Apple Silicon MacBooks (M1, M2, and M3). Instead of adapting generic desktop defaults, it aligns memory paging, heterogeneous core scheduling, storage layout, hardware telemetry, and Wayland input around Apple Silicon hardware constraints:

| Layer | Specification | Target |
| --- | --- | --- |
| **Kernel & ABI** | Asahi Linux `16KB` pages (`CONFIG_ARM64_16K_PAGES=y`), CachyOS BORE, TCP BBRv3, Clang ThinLTO | `linux-asahi` / `linux-silicy-asahi` |
| **Telemetry & SMC** | Pure C11 [`silicy-ctl`](silicyos-build/silicy-ctl/silicy-ctl.c) (`open`/`pread`/`pwrite`, zero heap, E-core pinned) | Sub-millisecond JSON, battery limits (`60/80/100%`) |
| **Storage & Safety** | Btrfs `compress-force=zstd:3` (`@`, `@home`, `@pkg`, `@log`, `@snapshots`) + RO APFS bridge | Pre-`pacman` snapshots (`silicy-capsule`), `< 2.8 GB` footprint |
| **Memory & Services** | 1:1 `zstd` ZRAM (`vm.page-cluster = 0`), `earlyoom`, E/P-core cgroup tiering, volatile RAM journald | `< 420 MB` idle RAM, minimal SSD wear |
| **Desktop & Input** | `Niri` + `Hyprland`, `Waybar`, `Fuzzel`, `Kitty`, `SwayOSD`, `keyd` smart `Command` sync | Apple Industrial Titanium (`#0B0B0E` / `#0A84FF`) |

```text
Apple BootROM ─▶ m1n1 ─▶ DTBs + U-Boot ─▶ systemd-boot ─▶ linux-asahi (16KB) ─▶ Btrfs (@, zstd:3) ─▶ greetd/tuigreet ─▶ Niri / Hyprland
```

---

## Quick Start

### 1. Run Pre-Build Audit (`verify-silicyos.sh`)

```bash
git clone https://github.com/phuchungn159-cpu/SilicyOS.git
cd SilicyOS
make verify
```

### 2. Build Installer Bundle on macOS (Lima Apple VZ ARM64)

Builds `silicyos-build/silicyos-apple-silicon.zip` inside an isolated `debian-13` Apple Virtualization VM and cleans up the staging environment automatically:

```bash
make build-macos
```

*(On an existing Linux ARM64 host as root, run `make build-linux` instead.)*

### 3. Install Dual-Boot Alongside macOS

Serves `silicyos-apple-silicon.zip` locally on `127.0.0.1:8765` and launches the official Asahi installer (`256 GB` SSD suggestion: reserve `~30 GB` for `silicyOS` by allocating `215 GB` to macOS):

```bash
make install-macos
```

---

## Contents

- [1. Design Philosophy & Hardware Targets](#1-design-philosophy--hardware-targets)
- [2. Kernel, Scheduler & Networking Stack](#2-kernel-scheduler--networking-stack)
- [3. Unified Memory, ZRAM, I/O & Service Diet](#3-unified-memory-zram-io--service-diet)
- [4. Storage Layout & Btrfs Snapshots (`silicy-capsule`)](#4-storage-layout--btrfs-snapshots-silicy-capsule)
- [5. Pure-C Hardware Controller (`silicy-ctl`)](#5-pure-c-hardware-controller-silicy-ctl)
- [6. Interactive Control Center (`silicy-center`)](#6-interactive-control-center-silicy-center)
- [7. Safe macOS APFS Data Bridge (`silicy-macos-bridge`)](#7-safe-macos-apfs-data-bridge-silicy-macos-bridge)
- [8. Smart `Command` Key Sync & Frosted OSD (`keyd` + `swayosd`)](#8-smart-command-key-sync--frosted-osd-keyd--swayosd)
- [9. Desktop Environment, Visual Spec & Keybindings](#9-desktop-environment-visual-spec--keybindings)
- [10. Repository Architecture](#10-repository-architecture)
- [11. Building, Installing & First-Boot Setup](#11-building-installing--first-boot-setup)
- [12. Automated Verification & Audit (`verify-silicyos.sh`)](#12-automated-verification--audit-verify-silicyossh)
- [13. Troubleshooting & Verification Boundaries](#13-troubleshooting--verification-boundaries)

---

## 1. Design Philosophy & Hardware Targets

Apple Silicon hardware differs fundamentally from x86_64 laptops in memory page geometry, heterogeneous core clusters, NVMe submission queues, and firmware loading. `silicyOS` is built around those hardware realities:

- **Strict 16KB Page Size Alignment**: Apple Silicon IOMMU and DART hardware operate natively on 16KB pages (`CONFIG_ARM64_16K_PAGES=y`, `CONFIG_ARM64_PAGE_SHIFT=14`). Swap, ZRAM, and NVMe readahead are aligned to 16KB boundaries to prevent page-fault amplification.
- **Heterogeneous E-Core / P-Core Awareness**: Telemetry readers and background indexers are isolated to Efficiency cores (Icestorm/Blizzard/Sawtooth), while interactive Wayland compositors and foreground tasks are prioritized on Performance cores (Firestorm/Avalanche/Everest) according to the active power profile.
- **Zero-Polling Telemetry**: Continuous sensor polling in shell loops (`while true; do cat /sys/...; sleep 1; done`) causes unnecessary P-core wakeups and battery drain. Hardware telemetry is implemented in pure C11 (`silicy-ctl`) using stack-only buffers and raw file descriptor syscalls.
- **Zero-Disk-Waste Footprint**: Target footprint is under `2.8 GB` disk usage and under `420 MB` idle RAM, achieved through RAM-only volatile logging, disabled core dumps, `NoExtract` pacman rules (with strict Apple firmware whitelists), and automatic post-transaction package cache cleanup.

---

## 2. Kernel, Scheduler & Networking Stack

Sources: [`kernel/PKGBUILD`](silicyos-build/kernel/PKGBUILD) | [`config.silicy`](silicyos-build/kernel/config.silicy) | [`99-silicy-cachyos.conf`](silicyos-build/cachy-arm64/silicy-core-tuning/99-silicy-cachyos.conf)

### Kernel Profiles
- **Default Prebuilt Track**: Upstream Asahi ALARM `linux-asahi` (16KB page size, Apple Silicon DTBs, `m1n1` + `uboot-asahi` + `systemd-boot`).
- **Custom Compiled Track (`BUILD_CUSTOM_KERNEL=1`)**: `linux-silicy-asahi` built from `AsahiLinux/linux` tag `asahi-6.12.12-1` (`pkgver=6.12.12.asahi1`) with CachyOS `0001-bore-cachy.patch` (BORE scheduler), `0002-bbr3.patch` (TCP BBRv3), full LLVM/Clang ThinLTO (`LLVM=1`, `LLVM_IAS=1`, `-O3 -mcpu=apple-m1 -mtune=apple-m1`), Rust `-C opt-level=3 -C target-cpu=apple-m1`, and mandatory flags `CONFIG_ARM64_16K_PAGES=y`, `CONFIG_ARM64_PAGE_SHIFT=14`, `CONFIG_SCHED_BORE=y`, `CONFIG_LTO_CLANG_THIN=y`, and `CONFIG_HZ_1000=y`.

### Core Sysctl Tuning (`/etc/sysctl.d/99-silicy-cachyos.conf`)

| Subsystem | Parameter | Value | Rationale |
| --- | --- | --- | --- |
| ZRAM / Swap | `vm.page-cluster` | `0` | Prevents reading `2^3 * 16KB = 128KB` per swap fault; decompresses strictly single 16KB pages |
| ZRAM / Swap | `vm.swappiness` | `150` | Prefers in-memory `zstd` ZRAM compression over NAND write wear |
| Btrfs Cache | `vm.vfs_cache_pressure` | `50` | Retains Btrfs dentries/inodes longer to minimize ANS2 NVMe wakeups |
| Writeback | `vm.dirty_ratio` / `dirty_background_ratio` | `10` / `5` | Bounds dirty pages to avoid I/O stalls on `zstd:3` Btrfs mounts |
| BORE Scheduler | `kernel.sched_bore` | `1` | Prioritizes bursty Wayland/PipeWire interactive threads |
| BORE Scheduler | `kernel.sched_burst_penalty_offset` | `22` (default) | Adjusted dynamically by `silicy-ctl` (`28` eco, `22` balanced, `16` burst) |
| Network | `net.core.default_qdisc` / `tcp_congestion_control` | `fq` / `bbr` | Enables TCP BBRv3 with TCP Fast Open (`3`) and ECN (`1` with fallback) |

---

## 3. Unified Memory, ZRAM, I/O & Service Diet

Sources: [`zram-generator.conf`](silicyos-build/memory/zram-generator.conf) | [`earlyoom.conf`](silicyos-build/memory/earlyoom.conf) | [`70-silicy-io.rules`](silicyos-build/cachy-arm64/silicy-core-tuning/70-silicy-io.rules) | [`systemd-diet.sh`](silicyos-build/services/systemd-diet.sh)

- **Unified Memory Protection (`zram` + `earlyoom`)**: Because CPU cores and the Asahi AGX GPU share LPDDR memory, `zram0` uses 1:1 `ram` size with `zstd` (`swap-priority = 100`). `earlyoom` sends `SIGTERM` at `<= 4%` free RAM / `<= 10%` free ZRAM and `SIGKILL` at `<= 2%` / `<= 5%`, protecting compositors and system daemons (`--avoid`) while targeting heavy browsers/compilers first (`--prefer`).
- **Block I/O & Hardware Udev Rules (`70-silicy-io.rules`)**: Apple ANS2 NVMe (`nvme*n*`) sets `scheduler="none"`, `read_ahead_kb="256"`, `nr_requests="1024"`, `rq_affinity="2"`, `wbt_lat_usec="2000"`. ZRAM uses `read_ahead_kb="0"`, `nomerges="2"`. External USB/Thunderbolt SSDs use `scheduler="kyber"`. Audio (`rtc0`/`hpet`) and DRM (`UDMABUF`/`dma_heap`) grant `0660` permissions to `audio`/`video`.
- **Cgroup Tiering (`ananicy-cpp` + `silicy-pe-enforcer.sh`)**: Discovers E-cores (`cpu_capacity < 650`) and P-cores (`1024`) dynamically, configures `pcores_rt`, `pcores_interactive`, `ecores_background`, and `ecores_idle`, pins compositors and PipeWire to P-cores, and confines background builds/indexers (`pacman`, `makepkg`, `btrfs`, `systemd-journald`) strictly to E-cores.
- **Systemd Daemon Diet (`systemd-diet.sh`)**: Masks `ModemManager`, `systemd-networkd-wait-online`, `cups`, `avahi-daemon`, `lvm2-monitor`, `ldconfig`, `systemd-FirstBoot`, and `remote-fs.target`; locks `journald` to volatile RAM (`RuntimeMaxUse=16M`) and disables core dumps (`Storage=none`).

---

## 4. Storage Layout & Btrfs Snapshots (`silicy-capsule`)

Sources: [`setup-btrfs-silicy.sh`](silicyos-build/storage/setup-btrfs-silicy.sh) | [`silicy-capsule`](silicyos-build/storage/silicy-capsule) | [`00-silicy-capsule-pre.hook`](silicyos-build/storage/00-silicy-capsule-pre.hook) | [`99-clean-cache-and-recompress.hook`](silicyos-build/storage/99-clean-cache-and-recompress.hook)

### Btrfs Subvolume Topology
All subvolumes mount with `compress-force=zstd:3,noatime,space_cache=v2` (and `ssd,discard=async` in `fstab`):

| Subvolume | Mountpoint | Purpose |
| --- | --- | --- |
| `@` | `/` | Root filesystem (snapshot & rollback target) |
| `@home` | `/home` | User data (preserved across `@` rollbacks) |
| `@pkg` | `/var/cache/pacman/pkg` | Pacman package staging |
| `@log` | `/var/log` | System logs |
| `@snapshots` | `/.snapshots` | Read-only system snapshots |

### `silicy-capsule` CLI & Automation
- Creates instant copy-on-write read-only snapshots under `/.snapshots/`.
- `00-silicy-capsule-pre.hook` runs `silicy-capsule auto-pre-upgrade` on every `pacman` `Upgrade` `PreTransaction`, retaining at most the **3 newest** snapshots (`create`, `auto-pre-upgrade`, `prune`, `list`, `rollback`).
- `99-clean-cache-and-recompress.hook` cleans `.pkg.tar*` archives and `/tmp` / `/var/tmp` staging remnants after every `pacman` Install/Upgrade/Remove.

---

## 5. Pure-C Hardware Controller (`silicy-ctl`)

Sources: [`silicy-ctl.c`](silicyos-build/silicy-ctl/silicy-ctl.c) | [`Makefile`](silicyos-build/silicy-ctl/Makefile) | [`71-silicy-macsmc.rules`](silicyos-build/silicy-ctl/71-silicy-macsmc.rules)

Compiled in strict C11 (`-Wall -Wextra -Werror -O3 -mcpu=apple-m1 -flto=thin`) with zero heap allocation (`malloc`/`calloc`/`realloc`), raw `open()`/`pread()`/`pwrite()` I/O, and `sched_setaffinity()` CPU pinning:

| Command | Behavior |
| --- | --- |
| `silicy-ctl telemetry` | Pins to E-cores, reads `macsmc-battery` and `/sys/class/hwmon/` SoC temperature, prints single-line Waybar JSON |
| `silicy-ctl telemetry --power\|--temp\|--memory` | Prints concise wattage (`%.1fW`), temperature (`%.0f°C`), or RAM/ZRAM summary |
| `silicy-ctl battery-guard <60\|80\|100\|status>` | Writes `charge_control_end_threshold` in `macsmc-battery` and persists `/etc/silicy-battery.conf` |
| `silicy-ctl power-profile <eco\|balanced\|burst\|status>` | Updates CPU governors, frequency ceilings, process affinity, `cpuset.cpus`, BORE sysctls, and Hyprland blur state |
| `silicy-ctl keyboard-mode <mac\|pc\|status>` | Copies `/usr/share/silicyos/keyd/{mac,pc}-mode.conf` to `/etc/keyd/default.conf` and persists `/etc/silicy-kb-mode` |

<details>
<summary>Waybar Telemetry JSON Output Schema & Rootless <code>wheel</code> Rules</summary>

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

- `71-silicy-macsmc.rules` grants `wheel` (`0664`) write access to `macsmc-battery/charge_control_end_threshold`, `cpufreq/scaling_{governor,max_freq,min_freq}`, `*kbd_backlight*/brightness`, and `backlight/*/brightness`, and restores `/etc/silicy-battery.conf` on boot/udev events.
- `/etc/sudoers.d/20-silicy-nopasswd` grants passwordless `wheel` execution for `silicy-ctl`, `silicy-capsule`, `silicy-macos-bridge`, `keyd`, and `systemctl restart keyd.service`.

</details>

---

## 6. Interactive Control Center (`silicy-center`)

Source: [`silicy-center`](silicyos-build/scripts/silicy-center)

Invoked via `Super + Ctrl + Space` or Waybar click (`fuzzel --dmenu` in Apple Industrial Titanium colors):

| Module | Interactive Actions | CLI Shortcut |
| --- | --- | --- |
| `[Power Profile]` | Switch `eco` / `balanced` / `burst` (with live Watt draw) | `silicy-center --power [eco\|balanced\|burst]` |
| `[Battery Care]` | Set `60%`, `80%`, or `100%` MacSMC hardware limit | `silicy-center --battery [60\|80\|100]` |
| `[Display Comfort]` | Toggle `wlsunset -t 4200 -T 4201`, switch `120Hz ProMotion` <-> `60Hz Battery Saver` | `silicy-center --display` |
| `[Keyboard Mode]` | Switch `Mac (Command)` <-> `PC (Ctrl)` and restart `keyd` / `keyd-application-mapper` | `silicy-center --keyboard [mac\|pc]` |
| `[macOS Shared Drive]` | Mount/unmount APFS RO partition or open `~/macOS-Shared` in `kitty` | `silicy-center --macos` |
| `[System Capsule]` | Create snapshot, prune to 3, or launch interactive rollback in `kitty` | `silicy-center --capsule` |
| `[Shortcut Guide]` | Render full shortcut reference in `fuzzel` (falls back to stdout on TTY) | `silicy-center --shortcuts` |

Checks `NIRI_SOCKET` and `HYPRLAND_INSTANCE_SIGNATURE` before falling back to `pgrep`, and resolves internal/external connectors dynamically (`detect_niri_internal_output` / `detect_hyprland_internal_output`) to preserve external 4K/clamshell modes and scales.

---

## 7. Safe macOS APFS Data Bridge (`silicy-macos-bridge`)

Source: [`silicy-macos-bridge`](silicyos-build/storage/silicy-macos-bridge)

- Mounts macOS APFS strictly **read-only** at `/run/media/$USER/macOS` via `apfs-fuse` (with `user_allow_other` in `/etc/fuse.conf`) or `fsapfsmount`.
- Automatically prioritizes the `* - Data` APFS volume (`lsblk` + `apfsutil` `detect_apfs_volume_id`, or `--vol N`).
- Probes `FSTYPE` before mounting `~/macOS-Shared` so `uid`/`gid`/`umask` flags are passed only on FAT/exFAT/NTFS filesystems and never break POSIX filesystems. Prompts inside `kitty` for FileVault-encrypted volumes.

---

## 8. Smart `Command` Key Sync & Frosted OSD (`keyd` + `swayosd`)

Sources: [`default.conf`](silicyos-build/input/keyd/default.conf) | [`mac-mode.conf`](silicyos-build/input/keyd/mac-mode.conf) | [`pc-mode.conf`](silicyos-build/input/keyd/pc-mode.conf) | [`app.conf`](silicyos-build/skel/.config/keyd/app.conf) | [`swayosd/config.toml`](silicyos-build/skel/.config/swayosd/config.toml)

- **Keyd Single-Config Isolation**: Only `/etc/keyd/default.conf` lives in `/etc/keyd/` (presets live in `/usr/share/silicyos/keyd/`). `default.conf` sets `[meta:M]` (`leftmeta`/`rightmeta = layer(meta)`) and `capslock = overload(control, esc)`.
- **App-Aware Remapping**: `[*]`: GUI/browser `meta.{c,v,x,z,a,w,t,s,n}` map to `C-*` while `meta.{f,r,l,q}` remain `M-*` for compositor controls. `[kitty]`: physical `Ctrl+C` stays POSIX `SIGINT`, `meta.{c,v,t,w}` map to `C-S-*`, and `meta.z` stays `M-z` (`no_op` in `kitty.conf`) to prevent accidental `SIGTSTP`.
- **PC Mode**: Swaps `leftmeta`/`rightmeta` to `control`, swaps `leftcontrol` to `meta`, and skips launching `keyd-application-mapper -d`.
- **Frosted HUD (`swayosd`)**: `show_percentage = true` and `max_volume = 100` (respecting `speakersafetyd`), bound to all MacBook media, screen brightness, and keyboard backlight keys.

---

## 9. Desktop Environment, Visual Spec & Keybindings

### Apple Industrial Titanium Design System

<div align="center">
  <img src="silicyos-build/branding/silicyos-boot.png" width="160" alt="silicyOS Boot Emblem">
</div>

| Role | Hex | RGB / ANSI | Usage |
| --- | --- | --- | --- |
| Background | `#0B0B0E` | `11, 11, 14` | Primary canvas, terminal, compositor base |
| Glass Surface | `#141418` | `20, 20, 24` | Waybar, Fuzzel, SwayOSD frosted surfaces |
| Border | `#26262E` | `38, 38, 46` | 1px subtle container outlines |
| Primary Text | `#F2F2F7` | `38;2;242;242;247` | Foreground labels and active states |
| Secondary Text | `#8E8E93` | `142, 142, 147` | Muted telemetry metadata and hints |
| Accent | `#0A84FF` | `38;2;10;132;255` | Focus rings, `os-release`, active controls |

### Core Keybindings (Niri & Hyprland)

| Shortcut | Action |
| --- | --- |
| `Super + Ctrl + Space` | Open `silicy-center` |
| `Super + /` | Open Shortcut Guide (`silicy-center --shortcuts`) |
| `Super + Space` | Open `fuzzel` launcher |
| `Super + Return` | Open `kitty` terminal |
| `Super + Q` | Close active window |
| `Super + Shift + 3` / `4` | Full-screen / region screenshot (`grim` + `slurp` + `wl-copy`) |
| `Super + 1..6` / `Shift + 1..6` | Switch workspace / move window to workspace `1..6` |
| `Super + H/J/K/L` or Arrows | Move focus left/down/up/right (`+ Shift` moves window/column) |
| `Super + F` / `Super + Shift + F` | Maximize column (Niri) / Fullscreen |
| `Super + Shift + V` | Toggle floating |
| `Super + Shift + E` | Exit compositor session |

---

## 10. Repository Architecture

<details>
<summary>Expand full workspace directory layout</summary>

```text
SilicyOS/
├── .github/
│   ├── ISSUE_TEMPLATE/                # Structured Apple Silicon bug & feature forms
│   └── pull_request_template.md
├── docs/
│   ├── README.vi.md                   # Vietnamese documentation
│   ├── README.ja.md                   # Japanese documentation
│   └── README.zh-CN.md                # Simplified Chinese documentation
├── CONTRIBUTING.md
├── LICENSE                            # MIT License
├── Makefile                           # Root targets: verify, build-macos, build-linux, install-macos
├── README.md
├── SECURITY.md
└── silicyos-build/
    ├── build-silicyos.sh              # Master Arch ARM64 + Asahi rootfs & ESP builder
    ├── verify-silicyos.sh             # 8-stage automated QA & mock-sysroot audit suite
    ├── macos-build-and-install.sh     # Lima Apple VZ ARM64 builder orchestrator
    ├── install-silicyos-macos.sh      # Local HTTP payload server (127.0.0.1:8765) + Asahi installer
    ├── kernel/                        # PKGBUILD (linux-silicy-asahi) & config.silicy (16KB pages)
    ├── cachy-arm64/                   # makepkg-silicy.conf & silicy-core-tuning (sysctl, io, ananicy-cpp)
    ├── silicy-ctl/                    # silicy-ctl.c, Makefile, 71-silicy-macsmc.rules, silicy-battery.conf
    ├── scripts/silicy-center          # Interactive fuzzel control center
    ├── storage/                       # setup-btrfs-silicy.sh, silicy-capsule, pacman hooks, silicy-macos-bridge
    ├── input/keyd/                    # default.conf, mac-mode.conf, pc-mode.conf
    ├── memory/                        # zram-generator.conf, earlyoom.conf
    ├── services/systemd-diet.sh       # Systemd masking, RAM-only journald, greetd setup
    ├── rootfs/                        # pacman-silicy.conf (NoExtract + firmware whitelists), packages.silicy
    ├── skel/.config/                  # niri, hypr, waybar, fuzzel, kitty, swayosd, fastfetch, keyd, zsh
    ├── installer/                     # installer_data.json (ROOTFS_SIZE_MB=8192) & silicy-setup-tui.sh
    └── branding/                      # SVG/PNG logos, Plymouth theme, ASCII art, wallpaper
```

</details>

---

## 11. Building, Installing & First-Boot Setup

### Prerequisites
- Apple Silicon Mac (M1/M2/M3) with sufficient free APFS space (recommended `256 GB` SSD split: `~30 GB` for `silicyOS` and `215 GB` for macOS).
- Large build outputs (`silicyos-apple-silicon.zip`, `.img`) are excluded via `.gitignore` and meant to be built locally or distributed via GitHub Releases.

### Method A: Build & Install from macOS (Lima Apple VZ)
1. Audit all scripts and configs: `make verify`
2. Build `silicyos-build/silicyos-apple-silicon.zip` inside a temporary `debian-13` Lima VM (`--vm-type=vz`): `make build-macos`
   - Seeds the ARM64 rootfs from `ArchLinuxARM-aarch64-latest.tar.gz` via `aria2c`, enables Asahi GitHub Releases (`github.com/asahi-alarm/asahi-alarm`), installs `packages.silicy`, compiles `apfs-fuse` (`-DCMAKE_CXX_FLAGS="-include cstdint"`) and `silicy-ctl`, builds the Btrfs `zstd:3` rootfs (`8192 MiB`) and FAT32 ESP (`500 MiB`) images, installs `systemd-boot` + `m1n1/boot.bin`, and packages `silicyos-apple-silicon.zip`.
3. Serve the local payload over `127.0.0.1:8765` and run the Asahi installer: `make install-macos`

### Method B: Build Directly on Linux ARM64 (`root`)
```bash
make build-linux
```

### First-Boot Wizard (`silicy-setup-tui.sh`)
On first boot (`silicy-firstboot.service`), the 6-step TUI wizard runs on `tty1`:
1. Extracts Apple Broadcom Wi-Fi/BT firmware (`asahi-fwextract`) and optionally connects via `iwd`.
2. Sets hostname, creates the `wheel` + `keyd` user, and deploys `/etc/skel`.
3. Selects default compositor (`niri` or `hyprland`).
4. Selects modifier mode (`Mac Command` or `PC Ctrl`).
5. Selects power/visual profile (`Max-Rice Performance` or `Ultra-Battery` — disables Hyprland `blur` while preserving `animations`, sets `battery-guard 80`, applies `power-profile eco`).
6. Generates `/etc/greetd/config.toml` and launches the session.

---

## 12. Automated Verification & Audit (`verify-silicyos.sh`)

```bash
make verify
```

Observed result on both macOS ARM64 and Lima Debian 13 ARM64 Linux (`205 PASS | 0 WARN | 0 FAIL`):

1. **[1/8] File Tree & Syntax**: All 62 required files, `bash -n` / `zsh -n`, `packages.silicy`, ananicy filename collision guard.
2. **[2/8] `silicy-ctl` C11 Compilation & Mock Sysfs**: Strict `clang -Wall -Wextra -Werror -O3 -mcpu=apple-m1 -flto=thin` compile, zero heap allocation, raw syscalls, `telemetry` / `battery-guard` / `power-profile` / `keyboard-mode` including 10-core Pro topology and read-only `/run` (`0555`).
3. **[3/8] Exclusive Tools QA**: `silicy-capsule` retention & rollback; `silicy-macos-bridge` APFS RO + Data volume + fs-type gating; `silicy-center` 7 modules & clamshell monitor handling; `keyd` `app.conf` ordering & Kitty `SIGTSTP` protection; `silicy-setup-tui.sh` blur scoping edge cases; `swayosd` `max_volume = 100`.
4. **[4/8] Zero AI Slop & Palette**: Zero forbidden emojis, zero bash `/sys/` polling loops, verified Apple Industrial Titanium hex/RGB values, zero legacy TokyoNight colors.
5. **[5/8] Bootloader & Btrfs**: Kernel cmdline `rootflags=subvol=@,compress-force=zstd:3`, `mkinitcpio.conf` Apple Silicon modules & `btrfs` hook.
6. **[6/8] Pacman & Kernel Audit**: Firmware `NoExtract` whitelists (`brcm/*`, `apple/*`, `vendor/*`, `regulatory.db*`, `asahi-boot/*`), `CONFIG_ARM64_16K_PAGES=y`, `CONFIG_SCHED_BORE=y`, `CONFIG_LTO_CLANG_THIN=y`, `CONFIG_HZ_1000=y`, `vm.page-cluster = 0`, zero x86 flags.
7. **[7/8] Rice Syntax & Installer Schema**: JSON/JSONC/TOML/KDL validation and exact `installer_data.json` byte-size alignment.
8. **[8/8] Dry-Run Staging & Packaging**: Staged `+x` permissions, isolated `/etc/keyd/default.conf`, dry-run zip manifest.

---

## 13. Troubleshooting & Verification Boundaries

- **macOS / CI Host vs Bare-Metal Hardware**: `verify-silicyos.sh` validates compilation, static syntax, staging, and `SILICY_SYSROOT` / mock IPC behavior. Live hardware execution (`macsmc-battery`, `hwmon`, kernel `apfs-fuse` mounts, live `btrfs subvolume snapshot`, Niri/Hyprland/keyd/swayosd IPC, and bare-metal `1TR` boot) requires Apple Silicon Linux hardware.
- **Permission Errors on Battery/CPU Nodes**: Ensure `71-silicy-macsmc.rules` is in `/etc/udev/rules.d/` and your user belongs to `wheel`.
- **FileVault APFS Mount Failure**: Unlock the encrypted macOS volume interactively via `silicy-macos-bridge` inside `kitty`.

---

<div align="center">
  <sub>Licensed under the <a href="LICENSE">MIT License</a> · See <a href="CONTRIBUTING.md">Contributing Guidelines</a> and <a href="SECURITY.md">Security Policy</a></sub>
</div>
