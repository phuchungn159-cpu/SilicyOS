# silicyOS

**Ngôn ngữ:** [English](README.md) | **Tiếng Việt** | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

`silicyOS` là bản phân phối Arch Linux ARM64 (`aarch64`) được thiết kế chuyên biệt cho máy Mac Apple Silicon (M1, M2, M3). Hệ điều hành kết hợp nhân Asahi Linux chuẩn trang nhớ 16KB với bộ lập lịch tương tác CachyOS BORE, biên dịch LLVM/Clang ThinLTO, hệ thống tệp Btrfs nén trong suốt và môi trường Wayland thống nhất theo quy chuẩn thiết kế **Apple Industrial Titanium**.

---

## Mục lục

- [1. Triết lý thiết kế & Mục tiêu phần cứng](#1-triết-lý-thiết-kế--mục-tiêu-phần-cứng)
- [2. Nhân hệ điều hành, Bộ lập lịch & Mạng](#2-nhân-hệ-điều-hành-bộ-lập-lịch--mạng)
- [3. Bộ nhớ hợp nhất, ZRAM, I/O & Tối giản dịch vụ](#3-bộ-nhớ-hợp-nhất-zram-io--tối-giản-dịch-vụ)
- [4. Phân vùng lưu trữ & Snapshot Btrfs (`silicy-capsule`)](#4-phân-vùng-lưu-trữ--snapshot-btrfs-silicy-capsule)
- [5. Lõi điều khiển phần cứng thuần C (`silicy-ctl`)](#5-lõi-điều-khiển-phần-cứng-thuần-c-silicy-ctl)
- [6. Trung tâm điều khiển tương tác (`silicy-center`)](#6-trung-tâm-điều-khiển-tương-tác-silicy-center)
- [7. Cầu nối dữ liệu macOS APFS an toàn (`silicy-macos-bridge`)](#7-cầu-nối-dữ-liệu-macos-apfs-an-toàn-silicy-macos-bridge)
- [8. Đồng bộ phím `Command` thông minh & HUD kính mờ (`keyd` + `swayosd`)](#8-đồng-bộ-phím-command-thông-minh--hud-kính-mờ-keyd--swayosd)
- [9. Môi trường Desktop, Quy chuẩn giao diện & Phím tắt](#9-môi-trường-desktop-quy-chuẩn-giao-diện--phím-tắt)
- [10. Kiến trúc mã nguồn](#10-kiến-trúc-mã-nguồn)
- [11. Hướng dẫn Build, Cài đặt & Cấu hình lần đầu](#11-hướng-dẫn-build-cài-đặt--cấu-hình-lần-đầu)
- [12. Kiểm toán & Xác minh tự động (`verify-silicyos.sh`)](#12-kiểm-toán--xác-minh-tự-động-verify-silicyossh)
- [13. Xử lý sự cố & Phạm vi kiểm thử](#13-xử-lý-sự-cố--phạm-vi-kiểm-thử)

---

## 1. Triết lý thiết kế & Mục tiêu phần cứng

Phần cứng Apple Silicon khác biệt căn bản so với laptop x86_64 truyền thống ở kích thước trang nhớ, cụm nhân không đồng nhất, bộ điều khiển NVMe và cơ chế nạp firmware. `silicyOS` được xây dựng xoay quanh các đặc thù phần cứng này:

- **Khớp chuẩn trang nhớ 16KB**: Phần cứng IOMMU và Dart của Apple Silicon hoạt động gốc với trang 16KB (`CONFIG_ARM64_16K_PAGES=y`, `CONFIG_ARM64_PAGE_SHIFT=14`). Swap, ZRAM và readahead NVMe đều được căn chỉnh theo bội số 16KB để tránh khuếch đại page-fault.
- **Nhận biết cụm nhân E-Core / P-Core**: Tiến trình đọc cảm biến và tác vụ nền được cô lập vào cụm nhân tiết kiệm điện E-core (Icestorm/Blizzard/Sawtooth), trong khi Wayland compositor và ứng dụng tương tác được ưu tiên trên cụm hiệu năng cao P-core (Firestorm/Avalanche/Everest) tùy theo hồ sơ năng lượng.
- **Không polling bằng vòng lặp shell**: Việc dùng `while true; do cat /sys/...; sleep 1; done` gây đánh thức nhân P-core liên tục và hao pin. Tác vụ đọc cảm biến được viết bằng C11 thuần (`silicy-ctl`) chỉ dùng stack và syscall trực tiếp.
- **Tối ưu dung lượng & RAM nhàn rỗi**: Hướng tới dưới `2.8 GB` dung lượng ổ đĩa và dưới `420 MB` RAM khi nhàn rỗi nhờ journald chỉ lưu RAM, tắt core dump, quy tắc `NoExtract` trong pacman (có whitelist riêng cho firmware Apple) và tự động dọn cache gói sau mỗi giao dịch.

---

## 2. Nhân hệ điều hành, Bộ lập lịch & Mạng

Mã nguồn: [`silicyos-build/kernel/PKGBUILD`](silicyos-build/kernel/PKGBUILD) | [`config.silicy`](silicyos-build/kernel/config.silicy) | [`99-silicy-cachyos.conf`](silicyos-build/cachy-arm64/silicy-core-tuning/99-silicy-cachyos.conf)

### Cấu hình build nhân (`linux-silicy-asahi`)
- **Mã nguồn gốc**: `AsahiLinux/linux` tag `asahi-6.12.12-1` (`pkgver=6.12.12.asahi1`).
- **Bản vá tích hợp**: CachyOS `0001-bore-cachy.patch` (bộ lập lịch BORE) và `0002-bbr3.patch` (TCP BBRv3).
- **Trình biên dịch**: Toàn bộ bằng LLVM/Clang (`LLVM=1`, `LLVM_IAS=1`, `CC=clang`, `LD=ld.lld`) với cờ `-O3 -mcpu=apple-m1 -mtune=apple-m1` và `KRUSTFLAGS="-C opt-level=3 -C target-cpu=apple-m1"`.
- **Cờ bắt buộc**: `CONFIG_ARM64_16K_PAGES=y`, `CONFIG_ARM64_PAGE_SHIFT=14`, `CONFIG_SCHED_BORE=y`, `CONFIG_LTO_CLANG_THIN=y`, `CONFIG_HZ_1000=y`.

### Tinh chỉnh Sysctl (`/etc/sysctl.d/99-silicy-cachyos.conf`)

| Phân hệ | Tham số | Giá trị | Lý do kỹ thuật |
| --- | --- | --- | --- |
| ZRAM / Swap | `vm.page-cluster` | `0` | Tránh đọc gộp `2^3 * 16KB = 128KB` mỗi page-fault; giải nén đúng từng trang 16KB |
| ZRAM / Swap | `vm.swappiness` | `150` | Ưu tiên nén RAM qua `zstd` trong ZRAM thay vì ghi ra SSD NAND |
| Cache Btrfs | `vm.vfs_cache_pressure` | `50` | Giữ dentry/inode Btrfs trong RAM lâu hơn để giảm đánh thức ANS2 NVMe |
| Ghi đĩa | `vm.dirty_ratio` / `dirty_background_ratio` | `10` / `5` | Giới hạn trang bẩn để tránh nghẽn I/O khi dùng nén `zstd:3` |
| BORE Scheduler | `kernel.sched_bore` | `1` | Ưu tiên luồng giao diện Wayland và âm thanh PipeWire |
| BORE Scheduler | `kernel.sched_burst_penalty_offset` | `22` (mặc định) | Được `silicy-ctl` điều chỉnh động (`28` eco, `22` balanced, `16` burst) |
| Mạng | `net.core.default_qdisc` / `tcp_congestion_control` | `fq` / `bbr` | Bật TCP BBRv3 kèm TCP Fast Open (`3`) và ECN (`1` có fallback) |

---

## 3. Bộ nhớ hợp nhất, ZRAM, I/O & Tối giản dịch vụ

Mã nguồn: [`memory/zram-generator.conf`](silicyos-build/memory/zram-generator.conf) | [`memory/earlyoom.conf`](silicyos-build/memory/earlyoom.conf) | [`70-silicy-io.rules`](silicyos-build/cachy-arm64/silicy-core-tuning/70-silicy-io.rules) | [`services/systemd-diet.sh`](silicyos-build/services/systemd-diet.sh)

### Bảo vệ bộ nhớ hợp nhất (`zram` + `earlyoom`)
Trên Apple Silicon, CPU và GPU Asahi AGX dùng chung RAM LPDDR. Nếu tràn RAM, compositor có thể treo cứng trước khi OOM của kernel kịp can thiệp:
- **`zram0`**: Cấu hình `zram-size = ram`, thuật toán nén `zstd`, `swap-priority = 100`.
- **`earlyoom`**: Gửi `SIGTERM` khi RAM trống `<= 4%` / ZRAM trống `<= 10%` và `SIGKILL` ở mức `<= 2%` / `<= 5%`. Bảo vệ các tiến trình nền tảng (`niri`, `Hyprland`, `kitty`, `greetd`, `seatd`, `dbus-broker`, `pipewire`, `speakersafetyd`, `tiny-dfr`, `keyd`, `swayosd-server`) bằng `--avoid`, đồng thời ưu tiên xử lý trình duyệt/trình biên dịch nặng (`chromium`, `firefox`, `rustc`, `clang`, `node`) qua `--prefer`.

### Quy tắc I/O & Udev (`70-silicy-io.rules`)
- **NVMe nội bộ Apple ANS2 (`nvme*n*`)**: `scheduler="none"`, `read_ahead_kb="256"` (`16 x 16KB`), `nr_requests="1024"`, `rq_affinity="2"`, `iostats="0"`, `wbt_lat_usec="2000"`.
- **ZRAM (`zram*`)**: `read_ahead_kb="0"`, `nomerges="2"`, `iostats="0"`.
- **SSD ngoài USB/Thunderbolt (`sd[a-z]`)**: `scheduler="kyber"`, `read_ahead_kb="512"`.
- **Âm thanh & Wayland DRM**: Cấp quyền `0660` cho nhóm `audio` (`rtc0`/`hpet`) và nhóm `video` (`UDMABUF`/`dma_heap`).

### Phân tầng Cgroup (`ananicy-cpp` + `silicy-pe-enforcer.sh`)
- `00-cgroups.cgroups` định nghĩa 4 mức: `pcores_rt` (`CPUQuota: 100`), `pcores_interactive` (`95`), `ecores_background` (`40`), `ecores_idle` (`20`).
- `silicy-pe-enforcer.sh` đọc `/sys/devices/system/cpu/cpu*/cpu_capacity` (`< 650` là E-core, `1024` là P-core), cấp quyền ghi nhóm `wheel` cho cpufreq và BORE sysctl, ghim Wayland compositor/PipeWire vào P-core, ghim cửa sổ đang focus theo profile hiện tại, và ép các tiến trình nền (`pacman`, `makepkg`, `btrfs`, `systemd-journald`) chạy trên E-core.

### Tối giản dịch vụ Systemd (`systemd-diet.sh`)
- **Vô hiệu hóa (Mask)**: `ModemManager`, `systemd-networkd-wait-online`, `cups` (`.service`/`.socket`/`.path`), `avahi-daemon`, `lvm2-monitor`, `ldconfig`, `systemd-FirstBoot`, `remote-fs.target`.
- **Kích hoạt (Enable)**: `dbus-broker`, `iwd`, `seatd`, `earlyoom`, `ananicy-cpp`, `speakersafetyd`, `tiny-dfr`, `keyd`, `swayosd-libinput-backend`, `greetd`.
- **Chống mòn SSD**: `journald` chỉ chạy trên RAM (`Storage=volatile`, `RuntimeMaxUse=16M`), tắt hoàn toàn core dump (`Storage=none`, `ProcessSizeMax=0`).

---

## 4. Phân vùng lưu trữ & Snapshot Btrfs (`silicy-capsule`)

Mã nguồn: [`storage/setup-btrfs-silicy.sh`](silicyos-build/storage/setup-btrfs-silicy.sh) | [`storage/silicy-capsule`](silicyos-build/storage/silicy-capsule) | [`00-silicy-capsule-pre.hook`](silicyos-build/storage/00-silicy-capsule-pre.hook) | [`99-clean-cache-and-recompress.hook`](silicyos-build/storage/99-clean-cache-and-recompress.hook)

### Cấu trúc Subvolume Btrfs
Các subvolume được mount với tùy chọn `compress-force=zstd:3,noatime,space_cache=v2` (kèm `ssd,discard=async` trong `fstab`):

| Subvolume | Điểm mount | Mục đích |
| --- | --- | --- |
| `@` | `/` | Hệ thống gốc (đối tượng snapshot & rollback) |
| `@home` | `/home` | Dữ liệu người dùng (được giữ nguyên khi rollback `@`) |
| `@pkg` | `/var/cache/pacman/pkg` | Bộ đệm tạm gói pacman |
| `@log` | `/var/log` | Nhật ký hệ thống |
| `@snapshots` | `/.snapshots` | Kho lưu trữ snapshot chỉ đọc |

### Quy trình `silicy-capsule`
- **Snapshot Zero-Space**: Tạo bản chụp chỉ đọc tức thì trong `/.snapshots/`.
- **Hook trước nâng cấp**: `00-silicy-capsule-pre.hook` tự động gọi `silicy-capsule auto-pre-upgrade` ở pha `PreTransaction` của mọi lệnh nâng cấp `pacman`.
- **Giới hạn lưu trữ**: Tự động xóa bản cũ, chỉ giữ tối đa **3 bản mới nhất** (`create`, `auto-pre-upgrade`, `prune`, `list`, `rollback`).
- **Dọn cache sau giao dịch**: `99-clean-cache-and-recompress.hook` xóa các tệp `.pkg.tar*` và dọn `/tmp`, `/var/tmp` sau khi cài/gỡ/cập nhật gói.

---

## 5. Lõi điều khiển phần cứng thuần C (`silicy-ctl`)

Mã nguồn: [`silicyos-build/silicy-ctl/silicy-ctl.c`](silicyos-build/silicy-ctl/silicy-ctl.c) | [`Makefile`](silicyos-build/silicy-ctl/Makefile) | [`71-silicy-macsmc.rules`](silicyos-build/silicy-ctl/71-silicy-macsmc.rules)

`silicy-ctl` tuân thủ chuẩn C11 nghiêm ngặt (`-Wall -Wextra -Werror -O3 -mcpu=apple-m1 -flto=thin`), không gọi `malloc`/`calloc`/`realloc`. Mọi thao tác đọc/ghi sysfs dùng `open()`, `pread()`, `pwrite()` và ghim nhân bằng `sched_setaffinity()`.

### Danh sách lệnh con

| Lệnh | Chức năng |
| --- | --- |
| `silicy-ctl telemetry` | Ghim tiến trình vào E-core, đọc `macsmc-battery` (`power_now`, fallback `current_now`*`voltage_now`, `capacity`, `status`, `charge_control_end_threshold`, `cycle_count`) và nhiệt độ SoC tại `/sys/class/hwmon/`, xuất JSON một dòng cho Waybar |
| `silicy-ctl telemetry --power\|--temp\|--memory` | Xuất nhanh công suất (`%.1fW`), nhiệt độ (`%.0f°C`) hoặc RAM/ZRAM |
| `silicy-ctl battery-guard <60\|80\|100\|status>` | Kiểm tra giá trị hợp lệ (`60`, `80`, `100`), ghi vào `charge_control_end_threshold` và lưu `/etc/silicy-battery.conf` |
| `silicy-ctl power-profile <eco\|balanced\|burst\|status>` | Chỉnh governor CPU, trần xung nhịp, affinity, `cpuset.cpus`, sysctl BORE, `dirty_writeback_centisecs` và bật/tắt blur Hyprland (`toggle_compositor_blur`) |
| `silicy-ctl keyboard-mode <mac\|pc\|status>` | Chép preset `/usr/share/silicyos/keyd/{mac,pc}-mode.conf` sang `/etc/keyd/default.conf` và lưu `/etc/silicy-kb-mode` |

### Cấu trúc JSON cho Waybar
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

### Quyền nhóm `wheel` không cần `sudo` (`71-silicy-macsmc.rules`)
- Cấp quyền ghi (`0664`) cho nhóm `wheel` đối với `macsmc-battery/charge_control_end_threshold`, `cpufreq/scaling_{governor,max_freq,min_freq}`, `*kbd_backlight*/brightness` và `backlight/*/brightness`.
- Tự động khôi phục mức giới hạn từ `/etc/silicy-battery.conf` khi có sự kiện udev `add|change`.
- `/etc/sudoers.d/20-silicy-nopasswd` cho phép thành viên nhóm `wheel` chạy `systemctl restart keyd`, `silicy-capsule` và `silicy-macos-bridge` không cần nhập mật khẩu.

---

## 6. Trung tâm điều khiển tương tác (`silicy-center`)

Mã nguồn: [`silicyos-build/scripts/silicy-center`](silicyos-build/scripts/silicy-center)

Gọi bằng `Super + Ctrl + Space` hoặc click trên Waybar, dùng `fuzzel --dmenu` phối màu Apple Industrial Titanium:

| Module | Thao tác tương tác | Cờ CLI trực tiếp |
| --- | --- | --- |
| `[Power Profile]` | Chuyển `eco` / `balanced` / `burst` kèm mức Watt hiện tại | `silicy-center --power [eco\|balanced\|burst]` |
| `[Battery Care]` | Chỉnh ngưỡng sạc `60%`, `80%`, `100%` qua MacSMC | `silicy-center --battery [60\|80\|100]` |
| `[Display Comfort]` | Bật/tắt `wlsunset -t 4200 -T 4201`, đổi `120Hz ProMotion` <-> `60Hz Battery Saver` | `silicy-center --display` |
| `[Keyboard Mode]` | Chuyển `Mac (Command)` <-> `PC (Ctrl)` và khởi động lại `keyd` / `keyd-application-mapper` | `silicy-center --keyboard [mac\|pc]` |
| `[macOS Shared Drive]` | Mount/unmount APFS RO hoặc mở `~/macOS-Shared` trong `kitty` | `silicy-center --macos` |
| `[System Capsule]` | Tạo snapshot, dọn bản cũ, hoặc mở menu rollback trong `kitty` | `silicy-center --capsule` |
| `[Shortcut Guide]` | Hiển thị bảng tra cứu phím tắt (hỗ trợ cả chế độ TTY) | `silicy-center --shortcuts` |

### Tự động nhận diện màn hình trên Niri & Hyprland
- Ưu tiên biến môi trường phiên (`NIRI_SOCKET`, `HYPRLAND_INSTANCE_SIGNATURE`) trước khi kiểm tra `pgrep`, tránh chọn nhầm compositor nền.
- Trên **Niri**: Dò output nội bộ động bằng `detect_niri_internal_output` và chọn mode phù hợp từ `niri msg --json outputs`.
- Trên **Hyprland**: Dò monitor đang hoạt động qua `detect_hyprland_internal_output` (`hyprctl monitors -j`, bỏ qua mục disabled hoặc tên rỗng) và giữ nguyên độ phân giải + scale hiện hành cho màn hình ngoài (hỗ trợ chế độ gập máy clamshell 4K).

---

## 7. Cầu nối dữ liệu macOS APFS an toàn (`silicy-macos-bridge`)

Mã nguồn: [`silicyos-build/storage/silicy-macos-bridge`](silicyos-build/storage/silicy-macos-bridge)

- **Chỉ đọc tuyệt đối**: Không bao giờ mount phân vùng macOS APFS ở chế độ ghi (RW), loại bỏ nguy cơ hỏng cấu trúc APFS của Apple.
- **Nhận diện volume Data**: Dùng `lsblk` (`PARTLABEL` / `FSTYPE=apfs`) kết hợp `apfsutil` (`detect_apfs_volume_id`) để ưu tiên tự động volume `Data` (`* - Data`), hỗ trợ chỉ định thủ công `--vol N`.
- **Điểm mount**: `/run/media/$USER/macOS` qua `apfs-fuse` (đã bật `user_allow_other` trong `/etc/fuse.conf`) hoặc `fsapfsmount`.
- **Thư mục trung chuyển (`~/macOS-Shared`)**: Kiểm tra `FSTYPE` trước khi mount phân vùng chia sẻ — chỉ truyền `uid`/`gid`/`umask` cho `vfat|msdos|exfat|ntfs|ntfs3`, giữ nguyên quyền POSIX trên filesystem Linux (`ext4`, `btrfs`, `xfs`, `f2fs`).
- **Lưu ý FileVault**: Nếu volume macOS được mã hóa FileVault, `silicy-center` hướng dẫn mở khóa tương tác trong cửa sổ `kitty`.

---

## 8. Đồng bộ phím `Command` thông minh & HUD kính mờ (`keyd` + `swayosd`)

Mã nguồn: [`input/keyd/default.conf`](silicyos-build/input/keyd/default.conf) | [`mac-mode.conf`](silicyos-build/input/keyd/mac-mode.conf) | [`pc-mode.conf`](silicyos-build/input/keyd/pc-mode.conf) | [`skel/.config/keyd/app.conf`](silicyos-build/skel/.config/keyd/app.conf) | [`skel/.config/swayosd/`](silicyos-build/skel/.config/swayosd/config.toml)

### Kiến trúc bàn phím (`keyd`)
- Chỉ duy nhất `/etc/keyd/default.conf` nằm trong `/etc/keyd/` (các preset cô lập tại `/usr/share/silicyos/keyd/`) để tránh nạp trùng cấu hình.
- `default.conf` dùng tầng `[meta:M]` (`leftmeta`/`rightmeta = layer(meta)`) và `capslock = overload(control, esc)`.
- `app.conf` đặt `[*]` trước `[kitty]` và `[org-wezfurlong-wezterm]`:
  - **Ứng dụng đồ họa & Trình duyệt (`[*]`)**: `meta.c/v/x/z/a/w/t/s/n` ánh xạ sang `C-*`; riêng `meta.f`, `meta.r`, `meta.l`, `meta.q` giữ `M-*` để không đè phím điều khiển cửa sổ.
  - **Terminal (`[kitty]`)**: `Ctrl+C` vật lý giữ nguyên là `SIGINT` POSIX; `meta.c/v/t/w` chuyển sang `C-S-*`, và `meta.z = M-z` (kết hợp `map super+z no_op` trong `kitty.conf`) ngăn `Cmd+Z` gửi nhầm `SIGTSTP`.
- **Chế độ PC**: Hoán đổi `leftmeta`/`rightmeta` <-> `control` và không chạy `keyd-application-mapper -d`.

### HUD kính mờ (`swayosd`)
- `swayosd-server` tự động khởi chạy cùng phiên Niri và Hyprland.
- `swayosd/config.toml` đặt `show_percentage = true` và `max_volume = 100`, tuân thủ giới hạn bảo vệ loa của `speakersafetyd`.
- Các phím phần cứng (`XF86MonBrightness*`, `XF86KbdBrightness*`, `XF86Audio*`) gọi trực tiếp `swayosd-client` kèm fallback (`brightnessctl`, `wpctl`).

---

## 9. Môi trường Desktop, Quy chuẩn giao diện & Phím tắt

### Bảng màu Apple Industrial Titanium

| Vai trò | Mã Hex | RGB (Terminal / Fastfetch / `os-release`) |
| --- | --- | --- |
| Nền chính (Background) | `#0B0B0E` | `11, 11, 14` |
| Bề mặt kính (Glass) | `#141418` | `20, 20, 24` |
| Viền (Border) | `#26262E` | `38, 38, 46` |
| Chữ chính (Primary) | `#F2F2F7` | `38;2;242;242;247` |
| Chữ phụ (Secondary) | `#8E8E93` | `142, 142, 147` |
| Điểm nhấn (Accent) | `#0A84FF` | `38;2;10;132;255` |

### Bảng phím tắt chính (Niri & Hyprland)

| Phím tắt | Hành động |
| --- | --- |
| `Super + Ctrl + Space` | Mở `silicy-center` |
| `Super + /` | Mở bảng hướng dẫn phím tắt (`silicy-center --shortcuts`) |
| `Super + Space` | Mở launcher `fuzzel` |
| `Super + Return` | Mở terminal `kitty` |
| `Super + Q` | Đóng cửa sổ đang chọn |
| `Super + Shift + 3` / `4` | Chụp toàn màn hình / vùng chọn (`grim` + `slurp` + `wl-copy`) |
| `Super + 1..6` | Chuyển workspace `1..6` |
| `Super + Shift + 1..6` | Di chuyển cửa sổ/cột sang workspace `1..6` |
| `Super + H/J/K/L` hoặc Mũi tên | Điều hướng tiêu điểm |
| `Super + Shift + H/J/K/L` hoặc Mũi tên | Di chuyển cửa sổ/cột |
| `Super + F` / `Super + Shift + F` | Phóng to cột (Niri) / Toàn màn hình |
| `Super + Shift + V` | Bật/tắt chế độ cửa sổ nổi |
| `Super + Shift + E` | Thoát phiên compositor |

---

## 10. Kiến trúc mã nguồn

```text
silicyos-build/
├── build-silicyos.sh                  # Script đóng gói rootfs Arch ARM64 + ESP Asahi tổng thể
├── verify-silicyos.sh                 # Bộ kiểm toán tự động 8 giai đoạn
├── macos-build-and-install.sh         # Điều phối build bằng Lima Apple VZ trên macOS
├── install-silicyos-macos.sh          # Máy chủ HTTP cục bộ (127.0.0.1:8765) + Asahi installer
├── kernel/
│   ├── PKGBUILD                       # linux-silicy-asahi (6.12.12 + BORE + BBRv3 + Clang ThinLTO)
│   └── config.silicy                  # Cấu hình kernel 16KB page size
├── cachy-arm64/
│   ├── makepkg-silicy.conf            # Cờ biên dịch ARM64 Apple M1
│   └── silicy-core-tuning/
│       ├── 99-silicy-cachyos.conf     # Sysctl: ZRAM 16KB, BORE, BBRv3
│       ├── 70-silicy-io.rules         # Udev: ANS2 NVMe, ZRAM, USB SSD, DRM/audio
│       ├── ananicy-silicy.rules       # Quy tắc ưu tiên tiến trình (99-silicy-overrides.rules)
│       └── ananicy-cpp/               # 00-cgroups.cgroups, 00-types.types, silicy-pe-enforcer.{sh,service}
├── silicy-ctl/
│   ├── silicy-ctl.c                   # Lõi điều khiển phần cứng thuần C
│   ├── Makefile
│   ├── 71-silicy-macsmc.rules         # Phân quyền nhóm wheel + khôi phục giới hạn pin khi boot
│   └── silicy-battery.conf            # Ngưỡng sạc mặc định 80%
├── scripts/
│   └── silicy-center                  # Trung tâm điều khiển fuzzel
├── storage/
│   ├── setup-btrfs-silicy.sh          # Khởi tạo subvolume Btrfs & sinh fstab
│   ├── silicy-capsule                 # CLI snapshot & rollback
│   ├── 00-silicy-capsule-pre.hook     # Hook tự chụp trước nâng cấp pacman
│   ├── 99-clean-cache-and-recompress.hook
│   └── silicy-macos-bridge            # Cầu nối APFS RO & phân vùng chia sẻ
├── input/keyd/                        # default.conf, mac-mode.conf, pc-mode.conf
├── memory/                            # zram-generator.conf, earlyoom.conf
├── services/systemd-diet.sh           # Tối giản systemd, journald RAM-only, cấu hình greetd
├── rootfs/
│   ├── pacman-silicy.conf             # NoExtract có whitelist firmware Apple
│   └── packages.silicy                # Danh sách gói đầy đủ
├── skel/.config/                      # niri, hypr, waybar, fuzzel, kitty, swayosd, fastfetch, keyd, zsh
├── installer/
│   ├── installer_data.json            # Manifest phân vùng Asahi (ROOTFS_SIZE_MB=8192)
│   └── silicy-setup-tui.sh            # Trình hướng dẫn cấu hình lần đầu 6 bước
└── branding/                          # Logo (SVG/PNG), theme Plymouth, ASCII art, hình nền
```

---

## 11. Hướng dẫn Build, Cài đặt & Cấu hình lần đầu

### Yêu cầu chuẩn bị
- Máy Mac Apple Silicon (M1/M2/M3) còn đủ dung lượng APFS trống (khuyến nghị trên SSD `256 GB`: dành `~30 GB` cho `silicyOS` và `215 GB` cho macOS).
- Các tệp nhị phân tạo ra trong quá trình build (`silicyos-apple-silicon.zip`, `.img`) đã được loại trừ trong `.gitignore` và nên phân phối qua GitHub Releases.

### Cách A: Build trên macOS qua Lima Apple VZ
1. Chạy kiểm toán trước khi build:
   ```bash
   bash silicyos-build/verify-silicyos.sh
   ```
2. Đóng gói rootfs ARM64 và `silicyos-apple-silicon.zip` trong VM `debian-13` tạm thời (`--vm-type=vz`):
   ```bash
   cd silicyos-build
   ./macos-build-and-install.sh
   ```
3. Khởi chạy máy chủ HTTP cục bộ (`127.0.0.1:8765`) và nạp vào Asahi Installer:
   ```bash
   ./install-silicyos-macos.sh
   ```

### Cách B: Build trực tiếp trên Linux ARM64 (`root`)
```bash
cd silicyos-build
sudo ./build-silicyos.sh
```
Các thông số chính trong `build-silicyos.sh`:
- Kích thước ảnh: `ROOTFS_SIZE_MB=8192` (`8589934592` byte, khớp với `installer_data.json`) và `ESP_SIZE_MB=500`.
- Biên dịch `silicy-ctl` bên trong `arch-chroot` (dùng `make` hoặc fallback `clang -flto=thin -s -fuse-ld=lld`).
- Biên dịch `apfs-fuse` và `apfsutil` từ mã nguồn với `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` nếu chưa có sẵn trong repo.
- Cấu hình `/etc/mkinitcpio.conf` gồm `MODULES=(apple-mailbox nvme_apple nvme simpledrm btrfs)` và `HOOKS=(... btrfs ...)`.
- Thiết lập tham số boot `systemd-boot` / `m1n1` với `rootflags=subvol=@,compress-force=zstd:3`.

### Trình hướng dẫn lần đầu (`silicy-setup-tui.sh`)
1. Giải nén firmware Broadcom Wi-Fi/BT (`asahi-fwextract`) và tùy chọn kết nối qua `iwd`.
2. Đặt hostname, tạo user thuộc nhóm `wheel` (đồng thời thêm vào nhóm `keyd`) và chép `/etc/skel`.
3. Chọn compositor mặc định (`niri` hoặc `hyprland`).
4. Chọn kiểu bàn phím (`Mac Command` hoặc `PC Ctrl`).
5. Chọn hồ sơ năng lượng (`Max-Rice Performance` hoặc `Ultra-Battery` — chạy `apply_ultra_battery_visuals` tắt riêng `blur` của Hyprland mà giữ nguyên `animations`, bật `silicy-ctl battery-guard 80` và đặt `power-profile eco`).
6. Tạo `/etc/greetd/config.toml` và khởi chạy phiên Wayland.

---

## 12. Kiểm toán & Xác minh tự động (`verify-silicyos.sh`)

Chạy bộ kiểm toán 8 giai đoạn:
```bash
bash silicyos-build/verify-silicyos.sh
```

Kết quả quan sát trực tiếp trên host macOS ARM64: **`205 PASS | 0 WARN | 0 FAIL`**:
1. **[1/8] Cây thư mục & Cú pháp**: Đủ 62 tệp bắt buộc, `bash -n`/`zsh -n`, kiểm tra đủ gói thiết yếu trong `packages.silicy`, chống trùng tên rule ananicy.
2. **[2/8] Biên dịch C11 `silicy-ctl` & Mock Sysfs**: Biên dịch sạch với `clang -Wall -Wextra -Werror -O3 -mcpu=apple-m1 -flto=thin`, xác nhận zero heap và raw syscall; kiểm thử `telemetry`, `battery-guard`, `power-profile`, `keyboard-mode` (bao gồm giả lập 10-core Pro và `/run` chỉ đọc `0555`).
3. **[3/8] Kiểm thử các công cụ độc quyền**: `silicy-capsule` giữ tối đa 3 snapshot + rollback + hook; `silicy-macos-bridge` mount APFS RO + chọn volume Data + kiểm tra loại filesystem; `silicy-center` đủ 7 module + dò output động Niri/Hyprland & bảo toàn scale 4K clamshell; thứ tự `keyd` `app.conf` & chống `SIGTSTP` trong Kitty; các trường hợp biên `apply_ultra_battery_visuals`; `swayosd` `max_volume = 100`.
4. **[4/8] Chống AI Slop & Bảng màu**: Không emoji cấm, không vòng lặp polling `/sys/`, đúng bảng màu Apple Industrial Titanium trên Waybar, SwayOSD, Kitty, Fastfetch, `os-release` và không sót mã màu TokyoNight.
5. **[5/8] Bootloader & Btrfs**: Khớp `rootflags=subvol=@,compress-force=zstd:3`, module Apple Silicon và hook `btrfs` trong `mkinitcpio.conf`.
6. **[6/8] Pacman & Kernel**: Whitelist firmware `NoExtract` (`brcm/*`, `apple/*`, `vendor/*`, `regulatory.db*`, `asahi-boot/*`), `CONFIG_ARM64_16K_PAGES=y`, `CONFIG_SCHED_BORE=y`, `CONFIG_LTO_CLANG_THIN=y`, `CONFIG_HZ_1000=y`, `vm.page-cluster = 0`, không có cờ x86.
7. **[7/8] Cú pháp Wayland Rice & Installer**: Hợp lệ JSON/JSONC/TOML/KDL và khớp dung lượng byte `installer_data.json`.
8. **[8/8] Staging & Đóng gói Dry-Run**: Kiểm tra quyền thực thi `+x`, cô lập `/etc/keyd/default.conf` và đóng gói thử zip.

---

## 13. Xử lý sự cố & Phạm vi kiểm thử

- **Host macOS so với Phần cứng thật**: `verify-silicyos.sh` trên macOS kiểm chứng khâu biên dịch, kiểm tra tĩnh, staging và hành vi giả lập qua `SILICY_SYSROOT` / mock IPC. Quá trình đóng gói rootfs đầy đủ bằng `build-silicyos.sh` (`pacstrap`/`arch-chroot`) và tương tác trực tiếp trên phần cứng Apple Silicon (`/sys/class/power_supply/macsmc-battery/`, `/sys/class/hwmon/`, `apfs-fuse`, `btrfs subvolume snapshot`, IPC sống của `niri`/`Hyprland`/`keyd`/`swayosd-server`, và chạy thật TUI lần đầu) cần được thực hiện trên Linux ARM64 / máy Mac chạy Asahi Linux.
- **Lỗi quyền ghi Pin / CPU**: Đảm bảo `71-silicy-macsmc.rules` đã nằm trong `/etc/udev/rules.d/` và tài khoản người dùng thuộc nhóm `wheel`.
- **Lỗi mount APFS có FileVault**: Chạy `silicy-macos-bridge` trong cửa sổ terminal `kitty` để nhập mật khẩu giải mã tương tác.
