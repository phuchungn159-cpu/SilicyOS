# silicyOS

**Languages:** **English** | [Tiếng Việt](README.vi.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

`silicyOS` is an Arch Linux ARM64 (`aarch64`) distribution engineered specifically for Apple Silicon Macs (M1, M2, and M3 series). It pairs the upstream Asahi Linux 16KB page-size kernel with CachyOS BORE interactive scheduling, LLVM/Clang ThinLTO compilation, Btrfs transparent compression, and a Wayland desktop environment unified under the **Apple Industrial Titanium** design specification.

---

## Table of Contents

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

Apple Silicon hardware differs fundamentally from x86_64 laptops in memory page geometry, heterogeneous core clusters, NVMe submission queues, and firmware loading. `silicyOS` is built around those hardware realities rather than adapting generic desktop defaults:

- **Strict 16KB Page Size Alignment**: Apple Silicon IOMMU and Dart hardware operate natively on 16KB pages (`CONFIG_ARM64_16K_PAGES=y`, `CONFIG_ARM64_PAGE_SHIFT=14`). Swap, ZRAM, and NVMe readahead are tuned explicitly for 16KB boundaries to avoid page-fault amplification.
- **Heterogeneous E-Core / P-Core Awareness**: Telemetry readers and background indexers are isolated to Efficiency cores (Icestorm/Blizzard/Sawtooth), while interactive Wayland compositors and foreground tasks are prioritized on Performance cores (Firestorm/Avalanche/Everest) according to the active power profile.
- **Zero-Polling Telemetry**: Continuous sensor polling in shell loops (`while true; do cat /sys/...; sleep 1; done`) causes unnecessary P-core wakeups and battery drain. Hardware telemetry is implemented in pure C11 (`silicy-ctl`) using stack-only buffers and raw file descriptor syscalls.
- **Zero-Disk-Waste Footprint**: Target footprint is under `2.8 GB` disk usage and under `420 MB` idle RAM, achieved through RAM-only volatile logging, disabled core dumps, `NoExtract` pacman rules (with strict Apple firmware whitelists), and automatic post-transaction package cache cleanup.

---

## 2. Kernel, Scheduler & Networking Stack

Sources: [`silicyos-build/kernel/PKGBUILD`](silicyos-build/kernel/PKGBUILD) | [`config.silicy`](silicyos-build/kernel/config.silicy) | [`99-silicy-cachyos.conf`](silicyos-build/cachy-arm64/silicy-core-tuning/99-silicy-cachyos.conf)

### Kernel Build Profile (`linux-silicy-asahi`)
- **Upstream Base**: `AsahiLinux/linux` tag `asahi-6.12.12-1` (`pkgver=6.12.12.asahi1`).
- **Patches**: CachyOS `0001-bore-cachy.patch` (BORE scheduler) and `0002-bbr3.patch` (TCP BBRv3).
- **Toolchain**: Full LLVM/Clang build (`LLVM=1`, `LLVM_IAS=1`, `CC=clang`, `LD=ld.lld`) with `-O3 -mcpu=apple-m1 -mtune=apple-m1` and Rust `KRUSTFLAGS="-C opt-level=3 -C target-cpu=apple-m1"`.
- **Mandatory Kernel Flags**: `CONFIG_ARM64_16K_PAGES=y`, `CONFIG_ARM64_PAGE_SHIFT=14`, `CONFIG_SCHED_BORE=y`, `CONFIG_LTO_CLANG_THIN=y`, `CONFIG_HZ_1000=y`.

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

Sources: [`memory/zram-generator.conf`](silicyos-build/memory/zram-generator.conf) | [`memory/earlyoom.conf`](silicyos-build/memory/earlyoom.conf) | [`70-silicy-io.rules`](silicyos-build/cachy-arm64/silicy-core-tuning/70-silicy-io.rules) | [`services/systemd-diet.sh`](silicyos-build/services/systemd-diet.sh)

### Unified Memory Protection (`zram` + `earlyoom`)
Because Apple Silicon shares physical LPDDR memory between CPU cores and the Asahi AGX GPU, running out of memory freezes the compositor before kernel OOM triggers:
- **`zram0`**: Configured at `zram-size = ram` with `compression-algorithm = zstd` and `swap-priority = 100`.
- **`earlyoom`**: Triggers `SIGTERM` at `<= 4%` free RAM / `<= 10%` free ZRAM and `SIGKILL` at `<= 2%` / `<= 5%`. Critical system daemons (`niri`, `Hyprland`, `kitty`, `greetd`, `seatd`, `dbus-broker`, `pipewire`, `speakersafetyd`, `tiny-dfr`, `keyd`, `swayosd-server`) are explicitly protected (`--avoid`), while heavy browsers/compilers (`chromium`, `firefox`, `rustc`, `clang`, `node`) are targeted first (`--prefer`).

### Block I/O & Hardware Udev Rules (`70-silicy-io.rules`)
- **Apple ANS2 Internal NVMe (`nvme*n*`)**: `scheduler="none"`, `read_ahead_kb="256"` (aligned to `16 x 16KB`), `nr_requests="1024"`, `rq_affinity="2"`, `iostats="0"`, `wbt_lat_usec="2000"`.
- **ZRAM (`zram*`)**: `read_ahead_kb="0"`, `nomerges="2"`, `iostats="0"`.
- **External USB/Thunderbolt SSD (`sd[a-z]`)**: `scheduler="kyber"`, `read_ahead_kb="512"`.
- **Audio & Wayland DRM**: Grants `audio` group `0660` on `rtc0`/`hpet`, and `video` group `0660` on `UDMABUF`/`dma_heap`.

### Cgroup Tiering (`ananicy-cpp` + `silicy-pe-enforcer.sh`)
- `00-cgroups.cgroups` defines four cgroup tiers: `pcores_rt` (`CPUQuota: 100`), `pcores_interactive` (`95`), `ecores_background` (`40`), and `ecores_idle` (`20`).
- `silicy-pe-enforcer.sh` discovers E-core and P-core topology dynamically via `/sys/devices/system/cpu/cpu*/cpu_capacity` (`< 650` = E-core, `1024` = P-core), sets `wheel` write permissions on cpufreq and BORE sysctl nodes, pins Wayland compositors and PipeWire to P-cores, pins focused windows according to the active power profile, and confines background indexers/package builds (`pacman`, `makepkg`, `btrfs`, `systemd-journald`) strictly to E-cores.

### Systemd Daemon Diet (`systemd-diet.sh`)
- **Masked Services**: `ModemManager`, `systemd-networkd-wait-online`, `cups` (`.service`/`.socket`/`.path`), `avahi-daemon`, `lvm2-monitor`, `ldconfig`, `systemd-FirstBoot`, `remote-fs.target`.
- **Enabled Services**: `dbus-broker`, `iwd`, `seatd`, `earlyoom`, `ananicy-cpp`, `speakersafetyd`, `tiny-dfr`, `keyd`, `swayosd-libinput-backend`, `greetd`.
- **SSD Wear Protection**: `journald` is locked to volatile RAM (`Storage=volatile`, `RuntimeMaxUse=16M`) and core dumps are completely disabled (`Storage=none`, `ProcessSizeMax=0`).

---

## 4. Storage Layout & Btrfs Snapshots (`silicy-capsule`)

Sources: [`storage/setup-btrfs-silicy.sh`](silicyos-build/storage/setup-btrfs-silicy.sh) | [`storage/silicy-capsule`](silicyos-build/storage/silicy-capsule) | [`00-silicy-capsule-pre.hook`](silicyos-build/storage/00-silicy-capsule-pre.hook) | [`99-clean-cache-and-recompress.hook`](silicyos-build/storage/99-clean-cache-and-recompress.hook)

### Btrfs Subvolume Topology
All subvolumes are mounted with `compress-force=zstd:3,noatime,space_cache=v2` (and `ssd,discard=async` in `fstab`):

| Subvolume | Mountpoint | Purpose |
| --- | --- | --- |
| `@` | `/` | Root filesystem (snapshot & rollback target) |
| `@home` | `/home` | User data (preserved across `@` rollbacks) |
| `@pkg` | `/var/cache/pacman/pkg` | Pacman package staging |
| `@log` | `/var/log` | System logs |
| `@snapshots` | `/.snapshots` | Read-only system snapshots |

### `silicy-capsule` CLI & Automation
- **Zero-Space Snapshots**: Creates instant copy-on-write read-only snapshots under `/.snapshots/`.
- **Automatic Pre-Upgrade Hook**: `00-silicy-capsule-pre.hook` triggers `silicy-capsule auto-pre-upgrade` on every `pacman` `Upgrade` `PreTransaction`.
- **Automatic Retention**: Prunes older snapshots automatically to retain at most the **3 newest** snapshots (`create`, `auto-pre-upgrade`, `prune`, `list`, `rollback`).
- **Post-Transaction Cleanup**: `99-clean-cache-and-recompress.hook` removes `.pkg.tar*` archives and `/tmp` / `/var/tmp` leftovers after every `pacman` Install/Upgrade/Remove.

---

## 5. Pure-C Hardware Controller (`silicy-ctl`)

Sources: [`silicyos-build/silicy-ctl/silicy-ctl.c`](silicyos-build/silicy-ctl/silicy-ctl.c) | [`Makefile`](silicyos-build/silicy-ctl/Makefile) | [`71-silicy-macsmc.rules`](silicyos-build/silicy-ctl/71-silicy-macsmc.rules)

`silicy-ctl` is written in strict C11 (`-Wall -Wextra -Werror -O3 -mcpu=apple-m1 -flto=thin`) with zero `malloc`/`calloc`/`realloc` calls. All file I/O uses raw `open()`, `pread()`, and `pwrite()`, and CPU pinning uses `sched_setaffinity()`.

### Subcommands

| Command | Behavior |
| --- | --- |
| `silicy-ctl telemetry` | Pins to E-cores, reads `macsmc-battery` (`power_now`, `current_now`/`voltage_now` fallback, `capacity`, `status`, `charge_control_end_threshold`, `cycle_count`) and `/sys/class/hwmon/` SoC temperature, prints single-line Waybar JSON |
| `silicy-ctl telemetry --power\|--temp\|--memory` | Prints concise wattage (`%.1fW`), temperature (`%.0f°C`), or RAM/ZRAM summary |
| `silicy-ctl battery-guard <60\|80\|100\|status>` | Validates threshold (`60`, `80`, or `100`), writes to `/sys/class/power_supply/macsmc-battery/charge_control_end_threshold` and `/etc/silicy-battery.conf` |
| `silicy-ctl power-profile <eco\|balanced\|burst\|status>` | Applies CPU governors, frequency ceilings, process affinity, cgroup `cpuset.cpus`, BORE sysctl values, `dirty_writeback_centisecs`, and Hyprland blur state (`toggle_compositor_blur`) |
| `silicy-ctl keyboard-mode <mac\|pc\|status>` | Copies `/usr/share/silicyos/keyd/{mac,pc}-mode.conf` to `/etc/keyd/default.conf` and persists `/etc/silicy-kb-mode` |

### Waybar JSON Output Schema
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

### Rootless `wheel` Group Permissions (`71-silicy-macsmc.rules`)
- Grants `wheel` (`0664`) write access to `macsmc-battery/charge_control_end_threshold` (and `start_threshold` if present), `cpufreq/scaling_{governor,max_freq,min_freq}`, `*kbd_backlight*/brightness`, and `backlight/*/brightness`.
- Automatically restores the saved limit from `/etc/silicy-battery.conf` on `add|change` udev events.
- `/etc/sudoers.d/20-silicy-nopasswd` permits `wheel` members passwordless `systemctl restart keyd`, `silicy-capsule`, and `silicy-macos-bridge` execution.

---

## 6. Interactive Control Center (`silicy-center`)

Source: [`silicyos-build/scripts/silicy-center`](silicyos-build/scripts/silicy-center)

Invoked via `Super + Ctrl + Space` or Waybar click, styled with `fuzzel --dmenu` in Apple Industrial Titanium colors:

| Module | Interactive Actions | CLI Shortcut |
| --- | --- | --- |
| `[Power Profile]` | Switch `eco` / `balanced` / `burst` (displays live Watt draw) | `silicy-center --power [eco\|balanced\|burst]` |
| `[Battery Care]` | Set `60%`, `80%`, or `100%` MacSMC hardware limit | `silicy-center --battery [60\|80\|100]` |
| `[Display Comfort]` | Toggle `wlsunset -t 4200 -T 4201`, switch `120Hz ProMotion` <-> `60Hz Battery Saver` | `silicy-center --display` |
| `[Keyboard Mode]` | Switch `Mac (Command)` <-> `PC (Ctrl)` and restart `keyd` / `keyd-application-mapper` | `silicy-center --keyboard [mac\|pc]` |
| `[macOS Shared Drive]` | Mount/unmount APFS RO partition or open `~/macOS-Shared` in `kitty` | `silicy-center --macos` |
| `[System Capsule]` | Create snapshot, prune to 3, or launch interactive rollback in `kitty` | `silicy-center --capsule` |
| `[Shortcut Guide]` | Render full shortcut reference in `fuzzel` (falls back to stdout on TTY) | `silicy-center --shortcuts` |

### Dynamic Compositor & Clamshell Display Handling
- Checks session environment variables (`NIRI_SOCKET`, `HYPRLAND_INSTANCE_SIGNATURE`) before falling back to `pgrep`, preventing background processes from hijacking the active compositor.
- On **Niri**: Dynamically resolves the internal output via `detect_niri_internal_output` and matches available modes from `niri msg --json outputs`.
- On **Hyprland**: Dynamically resolves the active/internal monitor via `detect_hyprland_internal_output` (`hyprctl monitors -j`, skipping disabled/empty-name entries) and preserves current `width`x`height` and `scale` for external monitors (e.g., clamshell 4K displays).

---

## 7. Safe macOS APFS Data Bridge (`silicy-macos-bridge`)

Source: [`silicyos-build/storage/silicy-macos-bridge`](silicyos-build/storage/silicy-macos-bridge)

- **Strict Read-Only Protection**: Never mounts the macOS APFS container read-write, preventing APFS metadata corruption.
- **Volume Discovery**: Uses `lsblk` (`PARTLABEL` / `FSTYPE=apfs`) and queries `apfsutil` (`detect_apfs_volume_id`) to automatically prioritize the `Data` volume (`* - Data`), with manual `--vol N` override support.
- **Mount Target**: `/run/media/$USER/macOS` using `apfs-fuse` (with `allow_other` enabled in `/etc/fuse.conf`) or `fsapfsmount`.
- **Shared Exchange Folder (`~/macOS-Shared`)**: Probes `FSTYPE` before mounting shared partitions — passes `uid`/`gid`/`umask` only on `vfat|msdos|exfat|ntfs|ntfs3`, avoiding invalid mount flags on POSIX filesystems (`ext4`, `btrfs`, `xfs`, `f2fs`).
- **FileVault Note**: If the macOS Data volume is encrypted with FileVault, `silicy-center` prompts to unlock interactively inside a `kitty` terminal.

---

## 8. Smart `Command` Key Sync & Frosted OSD (`keyd` + `swayosd`)

Sources: [`input/keyd/default.conf`](silicyos-build/input/keyd/default.conf) | [`mac-mode.conf`](silicyos-build/input/keyd/mac-mode.conf) | [`pc-mode.conf`](silicyos-build/input/keyd/pc-mode.conf) | [`skel/.config/keyd/app.conf`](silicyos-build/skel/.config/keyd/app.conf) | [`skel/.config/swayosd/`](silicyos-build/skel/.config/swayosd/config.toml)

### Keyboard Architecture (`keyd`)
- Only `/etc/keyd/default.conf` resides in `/etc/keyd/` (presets live in `/usr/share/silicyos/keyd/`) so `keyd` never loads duplicate `.conf` files.
- `default.conf` defines `[meta:M]` (`leftmeta`/`rightmeta = layer(meta)`) and `capslock = overload(control, esc)`.
- `app.conf` orders `[*]` before `[kitty]` and `[org-wezfurlong-wezterm]`:
  - **All GUI/Browser Apps (`[*]`)**: `meta.c/v/x/z/a/w/t/s/n` translate to `C-*`, while `meta.f`, `meta.r`, `meta.l`, and `meta.q` remain `M-*` so compositor window bindings stay intact.
  - **Terminal (`[kitty]`)**: Physical `Ctrl+C` remains POSIX `SIGINT`. `meta.c/v/t/w` map to `C-S-*`, and `meta.z = M-z` (mapped to `no_op` in `kitty.conf`) prevents accidental `SIGTSTP` job suspension.
- **PC Mode**: Swaps `leftmeta`/`rightmeta` to `control` and `leftcontrol` to `meta`, and skips launching `keyd-application-mapper -d` at session startup.

### Frosted HUD (`swayosd`)
- `swayosd-server` starts automatically in both Niri and Hyprland.
- `swayosd/config.toml` sets `show_percentage = true` and `max_volume = 100`, respecting Asahi `speakersafetyd` tweeter/woofer excursion limits.
- Hardware keys (`XF86MonBrightnessUp/Down`, `XF86KbdBrightnessUp/Down`, `XF86AudioRaiseVolume/LowerVolume/Mute/MicMute`) drive `swayosd-client` directly with CLI fallbacks (`brightnessctl`, `wpctl`).

---

## 9. Desktop Environment, Visual Spec & Keybindings

### Apple Industrial Titanium Palette

| Role | Hex | RGB (Terminal / Fastfetch / `os-release`) |
| --- | --- | --- |
| Background | `#0B0B0E` | `11, 11, 14` |
| Glass Surface | `#141418` | `20, 20, 24` |
| Border | `#26262E` | `38, 38, 46` |
| Primary Text | `#F2F2F7` | `38;2;242;242;247` |
| Secondary Text | `#8E8E93` | `142, 142, 147` |
| Accent | `#0A84FF` | `38;2;10;132;255` |

### Core Keybindings (Niri & Hyprland)

| Shortcut | Action |
| --- | --- |
| `Super + Ctrl + Space` | Open `silicy-center` |
| `Super + /` | Open Shortcut Guide (`silicy-center --shortcuts`) |
| `Super + Space` | Open `fuzzel` launcher |
| `Super + Return` | Open `kitty` terminal |
| `Super + Q` | Close active window |
| `Super + Shift + 3` / `4` | Full-screen / region screenshot (`grim` + `slurp` + `wl-copy`) |
| `Super + 1..6` | Switch to workspace `1..6` |
| `Super + Shift + 1..6` | Move window/column to workspace `1..6` |
| `Super + H/J/K/L` or Arrows | Move focus left/down/up/right |
| `Super + Shift + H/J/K/L` or Arrows | Move window/column |
| `Super + F` / `Super + Shift + F` | Maximize column (Niri) / Fullscreen |
| `Super + Shift + V` | Toggle floating |
| `Super + Shift + E` | Exit compositor session |

---

## 10. Repository Architecture

```text
silicyos-build/
├── build-silicyos.sh                  # Master Arch ARM64 + Asahi rootfs & ESP builder
├── verify-silicyos.sh                 # 8-stage automated QA & mock-sysroot audit suite
├── macos-build-and-install.sh         # Lima Apple VZ ARM64 builder orchestrator
├── install-silicyos-macos.sh          # Local HTTP payload server (127.0.0.1:8765) + Asahi installer
├── kernel/
│   ├── PKGBUILD                       # linux-silicy-asahi (6.12.12 + BORE + BBRv3 + Clang ThinLTO)
│   └── config.silicy                  # 16KB page size kernel config
├── cachy-arm64/
│   ├── makepkg-silicy.conf            # ARM64 Apple M1 makepkg compiler flags
│   └── silicy-core-tuning/
│       ├── 99-silicy-cachyos.conf     # Sysctl: ZRAM 16KB, BORE, BBRv3
│       ├── 70-silicy-io.rules         # Udev: ANS2 NVMe, ZRAM, USB SSD, DRM/audio
│       ├── ananicy-silicy.rules       # Process niceness/cgroup rules (99-silicy-overrides.rules)
│       └── ananicy-cpp/               # 00-cgroups.cgroups, 00-types.types, silicy-pe-enforcer.{sh,service}
├── silicy-ctl/
│   ├── silicy-ctl.c                   # Pure-C hardware controller
│   ├── Makefile
│   ├── 71-silicy-macsmc.rules         # Wheel permissions + boot battery limit restore
│   └── silicy-battery.conf            # Default 80% ceiling
├── scripts/
│   └── silicy-center                  # Interactive fuzzel control center
├── storage/
│   ├── setup-btrfs-silicy.sh          # Btrfs subvolume creator & fstab generator
│   ├── silicy-capsule                 # Snapshot & rollback CLI
│   ├── 00-silicy-capsule-pre.hook     # PreTransaction upgrade snapshot hook
│   ├── 99-clean-cache-and-recompress.hook
│   └── silicy-macos-bridge            # APFS RO & shared drive manager
├── input/keyd/                        # default.conf, mac-mode.conf, pc-mode.conf
├── memory/                            # zram-generator.conf, earlyoom.conf
├── services/systemd-diet.sh           # Systemd masking, journald RAM-only, greetd setup
├── rootfs/
│   ├── pacman-silicy.conf             # NoExtract rules with Apple firmware whitelists
│   └── packages.silicy                # Full package manifest
├── skel/.config/                      # niri, hypr, waybar, fuzzel, kitty, swayosd, fastfetch, keyd, zsh
├── installer/
│   ├── installer_data.json            # Asahi partition & package manifest (ROOTFS_SIZE_MB=8192)
│   └── silicy-setup-tui.sh            # 6-step first-boot provisioning wizard
└── branding/                          # Logos (SVG/PNG), Plymouth boot splash, ASCII art, wallpaper
```

---

## 11. Building, Installing & First-Boot Setup

### Prerequisites
- Apple Silicon Mac (M1/M2/M3) with sufficient free APFS space (recommended `256 GB` SSD split: `~30 GB` for `silicyOS` and `215 GB` for macOS).
- Large build outputs (`silicyos-apple-silicon.zip`, `.img`) are excluded via `.gitignore` and should be distributed through GitHub Releases.

### Method A: Build on macOS via Lima Apple VZ
1. Run pre-build verification:
   ```bash
   bash silicyos-build/verify-silicyos.sh
   ```
2. Build the ARM64 rootfs and `silicyos-apple-silicon.zip` inside a temporary `debian-13` Lima VM (`--vm-type=vz`):
   ```bash
   cd silicyos-build
   ./macos-build-and-install.sh
   ```
3. Serve the local payload over `127.0.0.1:8765` and invoke the official Asahi installer:
   ```bash
   ./install-silicyos-macos.sh
   ```

### Method B: Build Directly on Linux ARM64 (`root`)
```bash
cd silicyos-build
sudo ./build-silicyos.sh
```
Key staging details in `build-silicyos.sh`:
- Image sizes: `ROOTFS_SIZE_MB=8192` (`8589934592` bytes, matching `installer_data.json`) and `ESP_SIZE_MB=500`.
- Compiles `silicy-ctl` inside `arch-chroot` (using `make` or direct `clang -flto=thin -s -fuse-ld=lld` fallback).
- Builds `apfs-fuse` and `apfsutil` from source with `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` if `apfs-fuse` is unavailable from repos.
- Writes `/etc/mkinitcpio.conf` with `MODULES=(apple-mailbox nvme_apple nvme simpledrm btrfs)` and `HOOKS=(... btrfs ...)`.
- Configures `systemd-boot` / `m1n1` kernel cmdline with `rootflags=subvol=@,compress-force=zstd:3`.

### First-Boot Wizard (`silicy-setup-tui.sh`)
1. Extracts Apple Broadcom Wi-Fi/BT firmware (`asahi-fwextract`) and optionally connects via `iwd`.
2. Sets hostname, creates the `wheel` user (also added to `keyd` group), and deploys `/etc/skel`.
3. Selects default compositor (`niri` or `hyprland`).
4. Selects modifier mode (`Mac Command` or `PC Ctrl`).
5. Selects power/visual profile (`Max-Rice Performance` or `Ultra-Battery`, which applies `apply_ultra_battery_visuals` to disable Hyprland `blur` while keeping `animations` active, sets `silicy-ctl battery-guard 80`, and applies `silicy-ctl power-profile eco`).
6. Generates `/etc/greetd/config.toml` and launches the Wayland session.

---

## 12. Automated Verification & Audit (`verify-silicyos.sh`)

Run the 8-stage verification script:
```bash
bash silicyos-build/verify-silicyos.sh
```

Observed result on macOS ARM64 host: **`205 PASS | 0 WARN | 0 FAIL`** across:
1. **[1/8] File Tree & Syntax**: Presence of all 62 required files, `bash -n` / `zsh -n`, `packages.silicy` essential package checks, ananicy filename collision check.
2. **[2/8] `silicy-ctl` C11 Compilation & Mock Sysfs**: Clean `clang -Wall -Wextra -Werror -O3 -mcpu=apple-m1 -flto=thin` compile, zero heap allocation, raw syscalls, `telemetry` / `battery-guard` / `power-profile` / `keyboard-mode` functional tests including 10-core Pro topology and read-only `/run` (`0555`).
3. **[3/8] Exclusive Tools QA**: `silicy-capsule` 3-snapshot retention + rollback + pacman hook; `silicy-macos-bridge` APFS RO + Data volume + fs-type gating; `silicy-center` all 7 modules + dynamic Niri/Hyprland connector & clamshell 4K scale preservation; `keyd` `app.conf` ordering & Kitty `SIGTSTP` protection; `silicy-setup-tui.sh` blur-only scoping edge cases; `swayosd` `max_volume = 100`.
4. **[4/8] Zero AI Slop & Palette**: Zero forbidden emojis, zero bash `/sys/` polling loops, verified Apple Industrial Titanium hex/RGB values across Waybar, SwayOSD, Kitty, Fastfetch, and `os-release`, zero legacy TokyoNight colors.
5. **[5/8] Bootloader & Btrfs**: Kernel cmdline `rootflags=subvol=@,compress-force=zstd:3`, `mkinitcpio.conf` Apple Silicon modules & `btrfs` hook.
6. **[6/8] Pacman & Kernel Audit**: Firmware `NoExtract` whitelists (`brcm/*`, `apple/*`, `vendor/*`, `regulatory.db*`, `asahi-boot/*`), `CONFIG_ARM64_16K_PAGES=y`, `CONFIG_SCHED_BORE=y`, `CONFIG_LTO_CLANG_THIN=y`, `CONFIG_HZ_1000=y`, `vm.page-cluster = 0`, zero x86 flags.
7. **[7/8] Rice Syntax & Installer Schema**: JSON/JSONC/TOML/KDL validation and exact `installer_data.json` byte-size alignment.
8. **[8/8] Dry-Run Staging & Packaging**: Verified staged permissions (`+x`), isolated `/etc/keyd/default.conf`, and dry-run zip manifest.

---

## 13. Troubleshooting & Verification Boundaries

- **macOS Host vs Bare-Metal Hardware**: `verify-silicyos.sh` runs compilation, static checks, staging simulation, and `SILICY_SYSROOT` / mock IPC behavioral tests on macOS. Full `pacstrap`/`arch-chroot` image generation (`build-silicyos.sh`) and live hardware execution (`/sys/class/power_supply/macsmc-battery/`, `/sys/class/hwmon/`, `apfs-fuse` kernel mounts, `btrfs subvolume snapshot`, live `niri`/`Hyprland`/`keyd`/`swayosd-server` IPC, and first-boot TUI execution) require Linux ARM64 / Apple Silicon bare-metal hardware.
- **Permission Errors on Battery/CPU Nodes**: Verify `71-silicy-macsmc.rules` is installed in `/etc/udev/rules.d/` and your user belongs to `wheel`.
- **FileVault APFS Mount Failure**: Unlock the APFS volume interactively using `silicy-macos-bridge` in a `kitty` terminal.
