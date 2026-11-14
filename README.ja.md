# silicyOS

**言語:** [English](README.md) | [Tiếng Việt](README.vi.md) | **日本語** | [简体中文](README.zh-CN.md)

`silicyOS` は Apple Silicon Mac（M1 / M2 / M3 シリーズ）専用に設計された Arch Linux ARM64（`aarch64`）ディストリビューションです。Asahi Linux の 16KB ページサイズ対応カーネルに、CachyOS BORE インタラクティブスケジューラ、LLVM/Clang ThinLTO ビルド、Btrfs 透過圧縮、そして **Apple Industrial Titanium** デザイン仕様で統一された Wayland デスクトップ環境を統合しています。

---

## 目次

- [1. 設計思想と対象ハードウェア](#1-設計思想と対象ハードウェア)
- [2. カーネル・スケジューラ・ネットワークスタック](#2-カーネルスケジューラネットワークスタック)
- [3. ユニファイドメモリ・ZRAM・I/O・サービス最適化](#3-ユニファイドメモリzramioサービス最適化)
- [4. ストレージ構成と Btrfs スナップショット (`silicy-capsule`)](#4-ストレージ構成と-btrfs-スナップショット-silicy-capsule)
- [5. 純粋 C ハードウェアコントローラ (`silicy-ctl`)](#5-純粋-c-ハードウェアコントローラ-silicy-ctl)
- [6. インタラクティブ・コントロールセンター (`silicy-center`)](#6-インタラクティブコントロールセンター-silicy-center)
- [7. 安全な読み取り専用 macOS APFS ブリッジ (`silicy-macos-bridge`)](#7-安全な読み取り専用-macos-apfs-ブリッジ-silicy-macos-bridge)
- [8. `Command` キー同期とフロスト HUD (`keyd` + `swayosd`)](#8-command-キー同期とフロスト-hud-keyd--swayosd)
- [9. デスクトップ環境・カラー仕様・キーバインド](#9-デスクトップ環境カラー仕様キーバインド)
- [10. リポジトリ構成](#10-リポジトリ構成)
- [11. ビルド・インストール・初回起動セットアップ](#11-ビルドインストール初回起動セットアップ)
- [12. 自動検証と監査 (`verify-silicyos.sh`)](#12-自動検証と監査-verify-silicyossh)
- [13. トラブルシューティングと検証範囲](#13-トラブルシューティングと検証範囲)

---

## 1. 設計思想と対象ハードウェア

Apple Silicon は、メモリページサイズ、ヘテロジニアス CPU クラスタ、NVMe キュー処理、ファームウェア展開方式において従来の x86_64 PC と根本的に異なります。`silicyOS` はこのハードウェア特性に合わせて最適化されています。

- **16KB ページサイズへの完全整合**: Apple Silicon の IOMMU / Dart は 16KB ページ（`CONFIG_ARM64_16K_PAGES=y`, `CONFIG_ARM64_PAGE_SHIFT=14`）で動作します。スワップ、ZRAM、NVMe 先読みを 16KB 単位に合わせ、ページフォールト時の過剰な読み出しを防ぎます。
- **E-Core / P-Core クラスタ分離**: テレメトリ取得やバックグラウンドのインデックス処理は高効率コア（E-core: Icestorm/Blizzard/Sawtooth）に閉じ込め、Wayland コンポジタやフォアグラウンド処理は電源プロファイルに応じて高性能コア（P-core: Firestorm/Avalanche/Everest）へ割り当てます。
- **シェルのポーリングループ排除**: `while true; do cat /sys/...; sleep 1; done` のようなループは P-core の不要なウェイクアップとバッテリー消費を招きます。センサー監視は純粋 C11（`silicy-ctl`）のスタック専用バッファと生システムコールで実装しています。
- **最小フットプリント**: RAM 常駐の揮発性 journald、コアダンプ無効化、Apple ファームウェア用ホワイトリスト付き `NoExtract`、`pacman` トランザクション後の自動キャッシュ削除により、ディスク使用量 `< 2.8 GB`、アイドル時 RAM `< 420 MB` を目標としています。

---

## 2. カーネル・スケジューラ・ネットワークスタック

ソース: [`silicyos-build/kernel/PKGBUILD`](silicyos-build/kernel/PKGBUILD) | [`config.silicy`](silicyos-build/kernel/config.silicy) | [`99-silicy-cachyos.conf`](silicyos-build/cachy-arm64/silicy-core-tuning/99-silicy-cachyos.conf)

### カーネルビルド構成 (`linux-silicy-asahi`)
- **ベース**: `AsahiLinux/linux` タグ `asahi-6.12.12-1`（`pkgver=6.12.12.asahi1`）。
- **適用パッチ**: CachyOS `0001-bore-cachy.patch`（BORE スケジューラ）および `0002-bbr3.patch`（TCP BBRv3）。
- **ツールチェーン**: LLVM/Clang フルビルド（`LLVM=1`, `LLVM_IAS=1`, `CC=clang`, `LD=ld.lld`）、`-O3 -mcpu=apple-m1 -mtune=apple-m1`、`KRUSTFLAGS="-C opt-level=3 -C target-cpu=apple-m1"`。
- **必須カーネル設定**: `CONFIG_ARM64_16K_PAGES=y`, `CONFIG_ARM64_PAGE_SHIFT=14`, `CONFIG_SCHED_BORE=y`, `CONFIG_LTO_CLANG_THIN=y`, `CONFIG_HZ_1000=y`。

### Sysctl チューニング (`/etc/sysctl.d/99-silicy-cachyos.conf`)

| サブシステム | パラメータ | 設定値 | 技術的理由 |
| --- | --- | --- | --- |
| ZRAM / Swap | `vm.page-cluster` | `0` | フォールト時の `2^3 * 16KB = 128KB` 一括先読みを防ぎ、単一 16KB ページのみ展開 |
| ZRAM / Swap | `vm.swappiness` | `150` | NAND への書き込み摩耗を抑え、メモリ内 `zstd` ZRAM 圧縮を優先 |
| Btrfs キャッシュ | `vm.vfs_cache_pressure` | `50` | dentry/inode を長く保持し ANS2 NVMe のウェイクアップを削減 |
| ライトバック | `vm.dirty_ratio` / `dirty_background_ratio` | `10` / `5` | `zstd:3` Btrfs マウント上の I/O ストールを防止 |
| BORE | `kernel.sched_bore` | `1` | Wayland / PipeWire の対話的スレッドを優先スケジューリング |
| BORE | `kernel.sched_burst_penalty_offset` | `22`（既定） | `silicy-ctl` により動的に変更（`28` eco / `22` balanced / `16` burst） |
| ネットワーク | `net.core.default_qdisc` / `tcp_congestion_control` | `fq` / `bbr` | TCP BBRv3、TCP Fast Open (`3`)、フォールバック付き ECN (`1`) を有効化 |

---

## 3. ユニファイドメモリ・ZRAM・I/O・サービス最適化

ソース: [`memory/zram-generator.conf`](silicyos-build/memory/zram-generator.conf) | [`memory/earlyoom.conf`](silicyos-build/memory/earlyoom.conf) | [`70-silicy-io.rules`](silicyos-build/cachy-arm64/silicy-core-tuning/70-silicy-io.rules) | [`services/systemd-diet.sh`](silicyos-build/services/systemd-diet.sh)

### ユニファイドメモリ保護 (`zram` + `earlyoom`)
Apple Silicon は CPU と Asahi AGX GPU で物理 LPDDR メモリを共有するため、メモリ枯渇時にカーネル OOM より先にコンポジタが停止するリスクがあります。
- **`zram0`**: `zram-size = ram`、`compression-algorithm = zstd`、`swap-priority = 100`。
- **`earlyoom`**: 空き RAM `<= 4%` / 空き ZRAM `<= 10%` で `SIGTERM`、`<= 2%` / `<= 5%` で `SIGKILL` を送信。基幹デーモン（`niri`, `Hyprland`, `kitty`, `greetd`, `seatd`, `dbus-broker`, `pipewire`, `speakersafetyd`, `tiny-dfr`, `keyd`, `swayosd-server`）を `--avoid` で保護し、ブラウザやコンパイラ（`chromium`, `firefox`, `rustc`, `clang`, `node`）を `--prefer` で優先終了対象とします。

### ブロック I/O とハードウェア Udev ルール (`70-silicy-io.rules`)
- **内蔵 Apple ANS2 NVMe (`nvme*n*`)**: `scheduler="none"`, `read_ahead_kb="256"` (`16 x 16KB`), `nr_requests="1024"`, `rq_affinity="2"`, `iostats="0"`, `wbt_lat_usec="2000"`。
- **ZRAM (`zram*`)**: `read_ahead_kb="0"`, `nomerges="2"`, `iostats="0"`。
- **外付け USB/Thunderbolt SSD (`sd[a-z]`)**: `scheduler="kyber"`, `read_ahead_kb="512"`。
- **オーディオ・Wayland DRM**: `rtc0`/`hpet` に `audio` グループ `0660`、`UDMABUF`/`dma_heap` に `video` グループ `0660` を付与。

### Cgroup 階層制御 (`ananicy-cpp` + `silicy-pe-enforcer.sh`)
- `00-cgroups.cgroups` は `pcores_rt` (`CPUQuota: 100`)、`pcores_interactive` (`95`)、`ecores_background` (`40`)、`ecores_idle` (`20`) の 4 階層を定義します。
- `silicy-pe-enforcer.sh` は `/sys/devices/system/cpu/cpu*/cpu_capacity`（`< 650` が E-core、`1024` が P-core）からトポロジを自動検出し、cpufreq/BORE ノードへ `wheel` 書込権限を付与、コンポジタと PipeWire を P-core に固定し、バックグラウンド処理（`pacman`, `makepkg`, `btrfs`, `systemd-journald`）を E-core に隔離します。

### Systemd ダイエット (`systemd-diet.sh`)
- **マスク対象**: `ModemManager`, `systemd-networkd-wait-online`, `cups` (`.service`/`.socket`/`.path`), `avahi-daemon`, `lvm2-monitor`, `ldconfig`, `systemd-FirstBoot`, `remote-fs.target`。
- **有効化対象**: `dbus-broker`, `iwd`, `seatd`, `earlyoom`, `ananicy-cpp`, `speakersafetyd`, `tiny-dfr`, `keyd`, `swayosd-libinput-backend`, `greetd`。
- **SSD 摩耗保護**: `journald` を揮発 RAM 専用（`Storage=volatile`, `RuntimeMaxUse=16M`）に制限し、コアダンプを無効化（`Storage=none`, `ProcessSizeMax=0`）。

---

## 4. ストレージ構成と Btrfs スナップショット (`silicy-capsule`)

ソース: [`storage/setup-btrfs-silicy.sh`](silicyos-build/storage/setup-btrfs-silicy.sh) | [`storage/silicy-capsule`](silicyos-build/storage/silicy-capsule) | [`00-silicy-capsule-pre.hook`](silicyos-build/storage/00-silicy-capsule-pre.hook) | [`99-clean-cache-and-recompress.hook`](silicyos-build/storage/99-clean-cache-and-recompress.hook)

### Btrfs サブボリューム構成
全サブボリュームは `compress-force=zstd:3,noatime,space_cache=v2`（`fstab` では `ssd,discard=async` 併用）でマウントされます。

| サブボリューム | マウントポイント | 用途 |
| --- | --- | --- |
| `@` | `/` | ルートファイルシステム（スナップショット・ロールバック対象） |
| `@home` | `/home` | ユーザーデータ（`@` ロールバック時も保持） |
| `@pkg` | `/var/cache/pacman/pkg` | Pacman パッケージ領域 |
| `@log` | `/var/log` | システムログ |
| `@snapshots` | `/.snapshots` | 読み取り専用スナップショット格納領域 |

### `silicy-capsule` CLI と自動保護
- **ゼロ容量スナップショット**: `/.snapshots/` に Copy-on-Write の読み取り専用スナップショットを即時作成します。
- **アップグレード前自動フック**: `00-silicy-capsule-pre.hook` が `pacman` `Upgrade` の `PreTransaction` で `silicy-capsule auto-pre-upgrade` を実行します。
- **世代管理**: 古いスナップショットを自動削除し、最新 **3 世代** のみを保持します（`create`, `auto-pre-upgrade`, `prune`, `list`, `rollback`）。
- **事後キャッシュ削除**: `99-clean-cache-and-recompress.hook` がパッケージ操作後に `.pkg.tar*` と `/tmp`・`/var/tmp` を整理します。

---

## 5. 純粋 C ハードウェアコントローラ (`silicy-ctl`)

ソース: [`silicyos-build/silicy-ctl/silicy-ctl.c`](silicyos-build/silicy-ctl/silicy-ctl.c) | [`Makefile`](silicyos-build/silicy-ctl/Makefile) | [`71-silicy-macsmc.rules`](silicyos-build/silicy-ctl/71-silicy-macsmc.rules)

`silicy-ctl` は厳格な C11（`-Wall -Wextra -Werror -O3 -mcpu=apple-m1 -flto=thin`）で実装され、`malloc`/`calloc`/`realloc` を一切使用しません。すべての I/O は `open()`, `pread()`, `pwrite()` を、CPU 固定は `sched_setaffinity()` を使用します。

### サブコマンド

| コマンド | 動作 |
| --- | --- |
| `silicy-ctl telemetry` | E-core に固定し、`macsmc-battery`（`power_now`、フォールバック `current_now`*`voltage_now`、`capacity`、`status`、`charge_control_end_threshold`、`cycle_count`）と `/sys/class/hwmon/` SoC 温度を読み取り、Waybar 用 1 行 JSON を出力 |
| `silicy-ctl telemetry --power\|--temp\|--memory` | 消費電力（`%.1fW`）、温度（`%.0f°C`）、RAM/ZRAM サマリを出力 |
| `silicy-ctl battery-guard <60\|80\|100\|status>` | 閾値（`60`, `80`, `100`）を検証し、`charge_control_end_threshold` と `/etc/silicy-battery.conf` へ書き込み |
| `silicy-ctl power-profile <eco\|balanced\|burst\|status>` | CPU ガバナー、最大周波数、プロセス親和性、`cpuset.cpus`、BORE sysctl、`dirty_writeback_centisecs`、Hyprland ブラー状態（`toggle_compositor_blur`）を更新 |
| `silicy-ctl keyboard-mode <mac\|pc\|status>` | `/usr/share/silicyos/keyd/{mac,pc}-mode.conf` を `/etc/keyd/default.conf` にコピーし `/etc/silicy-kb-mode` を更新 |

### Waybar JSON 出力例
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

### `wheel` グループの `sudo` 不要アクセス (`71-silicy-macsmc.rules`)
- `macsmc-battery/charge_control_end_threshold`、`cpufreq/scaling_{governor,max_freq,min_freq}`、`*kbd_backlight*/brightness`、`backlight/*/brightness` に対し `wheel` グループへ `0664` 書き込み権限を付与します。
- udev `add|change` イベント時に `/etc/silicy-battery.conf` の上限値を自動復元します。
- `/etc/sudoers.d/20-silicy-nopasswd` により `wheel` ユーザーはパスワードなしで `systemctl restart keyd`、`silicy-capsule`、`silicy-macos-bridge` を実行できます。

---

## 6. インタラクティブ・コントロールセンター (`silicy-center`)

ソース: [`silicyos-build/scripts/silicy-center`](silicyos-build/scripts/silicy-center)

`Super + Ctrl + Space` または Waybar クリックで起動する Apple Industrial Titanium 配色の `fuzzel --dmenu` UI です。

| モジュール | インタラクティブ操作 | CLI ショートカット |
| --- | --- | --- |
| `[Power Profile]` | 現在の消費電力（W）を確認しながら `eco` / `balanced` / `burst` を切り替え | `silicy-center --power [eco\|balanced\|burst]` |
| `[Battery Care]` | `60%` / `80%` / `100%` の MacSMC 充電上限を設定 | `silicy-center --battery [60\|80\|100]` |
| `[Display Comfort]` | `wlsunset -t 4200 -T 4201` の切替、`120Hz ProMotion` <-> `60Hz Battery Saver` の切替 | `silicy-center --display` |
| `[Keyboard Mode]` | `Mac (Command)` <-> `PC (Ctrl)` 切替および `keyd` / `keyd-application-mapper` 再起動 | `silicy-center --keyboard [mac\|pc]` |
| `[macOS Shared Drive]` | APFS 読み取り専用マウント/アンマウント、`kitty` で `~/macOS-Shared` を開く | `silicy-center --macos` |
| `[System Capsule]` | スナップショット作成、整理、`kitty` 上での対話式ロールバック起動 | `silicy-center --capsule` |
| `[Shortcut Guide]` | ショートカット一覧表示（TTY フォールバック対応） | `silicy-center --shortcuts` |

### 動的コンポジタ・クラムシェルディスプレイ検出
- `pgrep` より先にセッション環境変数（`NIRI_SOCKET`, `HYPRLAND_INSTANCE_SIGNATURE`）を確認し、別セッションのバックグラウンドプロセス誤認を防ぎます。
- **Niri**: `detect_niri_internal_output` で内部出力を検出し、`niri msg --json outputs` から最適なモードを選択します。
- **Hyprland**: `detect_hyprland_internal_output`（`hyprctl monitors -j`、無効化・空名エントリをスキップ）で出力先を特定し、外付けディスプレイ接続時（クラムシェル 4K 環境など）は現在の解像度とスケーリングを保持します。

---

## 7. 安全な読み取り専用 macOS APFS ブリッジ (`silicy-macos-bridge`)

ソース: [`silicyos-build/storage/silicy-macos-bridge`](silicyos-build/storage/silicy-macos-bridge)

- **厳格な読み取り専用**: macOS APFS コンテナを読み書きモードでマウントせず、APFS メタデータ破損を防止します。
- **Data ボリューム自動選択**: `lsblk`（`PARTLABEL` / `FSTYPE=apfs`）および `apfsutil`（`detect_apfs_volume_id`）を用いて `Data` ボリューム（`* - Data`）を優先選択し、`--vol N` による手動指定にも対応します。
- **マウント先**: `/etc/fuse.conf` の `user_allow_other` 有効化のもと、`apfs-fuse` または `fsapfsmount` により `/run/media/$USER/macOS` にマウントします。
- **共有フォルダ (`~/macOS-Shared`)**: マウント前に `FSTYPE` を判定し、`vfat|msdos|exfat|ntfs|ntfs3` の場合のみ `uid`/`gid`/`umask` を適用して POSIX ファイルシステム（`ext4`, `btrfs`, `xfs`, `f2fs`）の権限を維持します。
- **FileVault に関する注意**: macOS 側で FileVault が有効な場合、`silicy-center` は `kitty` ターミナル上で対話式ロック解除を案内します。

---

## 8. `Command` キー同期とフロスト HUD (`keyd` + `swayosd`)

ソース: [`input/keyd/default.conf`](silicyos-build/input/keyd/default.conf) | [`mac-mode.conf`](silicyos-build/input/keyd/mac-mode.conf) | [`pc-mode.conf`](silicyos-build/input/keyd/pc-mode.conf) | [`skel/.config/keyd/app.conf`](silicyos-build/skel/.config/keyd/app.conf) | [`skel/.config/swayosd/`](silicyos-build/skel/.config/swayosd/config.toml)

### キーボード設計 (`keyd`)
- `/etc/keyd/` 配下には有効な `default.conf` のみを配置し（プリセットは `/usr/share/silicyos/keyd/` に隔離）、設定重複を回避しています。
- `default.conf` は `[meta:M]`（`leftmeta`/`rightmeta = layer(meta)`）と `capslock = overload(control, esc)` を定義します。
- `app.conf` は `[*]` を `[kitty]` および `[org-wezfurlong-wezterm]` より前に配置します:
  - **GUI / ブラウザ (`[*]`)**: `meta.c/v/x/z/a/w/t/s/n` を `C-*` に変換し、`meta.f/r/l/q` はコンポジタ操作用に `M-*` を維持します。
  - **ターミナル (`[kitty]`)**: 物理 `Ctrl+C` を POSIX `SIGINT` のまま維持しつつ、`meta.c/v/t/w` を `C-S-*` に、`meta.z = M-z`（`kitty.conf` 側で `no_op`）に設定して誤った `SIGTSTP` 発生を防止します。
- **PC モード**: `leftmeta`/`rightmeta` と `leftcontrol` を入れ替え、セッション起動時の `keyd-application-mapper -d` をスキップします。

### フロスト HUD (`swayosd`)
- Niri・Hyprland 双方で `swayosd-server` が自動起動します。
- `swayosd/config.toml` は `show_percentage = true`・`max_volume = 100` を設定し、Asahi `speakersafetyd` のスピーカー保護制限を尊重します。
- ハードウェアキー（`XF86MonBrightness*`, `XF86KbdBrightness*`, `XF86Audio*`）は `swayosd-client` を直接呼び出し、`brightnessctl` / `wpctl` をフォールバックとして備えます。

---

## 9. デスクトップ環境・カラー仕様・キーバインド

### Apple Industrial Titanium カラーパレット

| 用途 | Hex | RGB (ターミナル / Fastfetch / `os-release`) |
| --- | --- | --- |
| 背景 (Background) | `#0B0B0E` | `11, 11, 14` |
| グラス面 (Glass) | `#141418` | `20, 20, 24` |
| 枠線 (Border) | `#26262E` | `38, 38, 46` |
| 主文字色 (Primary) | `#F2F2F7` | `38;2;242;242;247` |
| 副文字色 (Secondary) | `#8E8E93` | `142, 142, 147` |
| アクセント (Accent) | `#0A84FF` | `38;2;10;132;255` |

### 主要キーバインド (Niri & Hyprland)

| ショートカット | 動作 |
| --- | --- |
| `Super + Ctrl + Space` | `silicy-center` を開く |
| `Super + /` | ショートカットガイドを表示 (`silicy-center --shortcuts`) |
| `Super + Space` | `fuzzel` ランチャーを開く |
| `Super + Return` | `kitty` ターミナルを開く |
| `Super + Q` | アクティブウィンドウを閉じる |
| `Super + Shift + 3` / `4` | 全画面 / 範囲スクリーンショット (`grim` + `slurp` + `wl-copy`) |
| `Super + 1..6` | ワークスペース `1..6` へ移動 |
| `Super + Shift + 1..6` | ウィンドウ / カラムをワークスペース `1..6` へ移動 |
| `Super + H/J/K/L` または矢印キー | フォーカス移動 |
| `Super + Shift + H/J/K/L` または矢印キー | ウィンドウ / カラム移動 |
| `Super + F` / `Super + Shift + F` | カラム最大化 (Niri) / フルスクリーン |
| `Super + Shift + V` | フローティング切替 |
| `Super + Shift + E` | コンポジタ終了 |

---

## 10. リポジトリ構成

```text
silicyos-build/
├── build-silicyos.sh                  # Arch ARM64 + Asahi rootfs・ESP イメージ総合ビルダー
├── verify-silicyos.sh                 # 8 段階自動 QA・モック sysroot 監査スクリプト
├── macos-build-and-install.sh         # Lima Apple VZ ARM64 ビルドオーケストレータ
├── install-silicyos-macos.sh          # ローカル HTTP 配信 (127.0.0.1:8765) + Asahi インストーラ
├── kernel/
│   ├── PKGBUILD                       # linux-silicy-asahi (6.12.12 + BORE + BBRv3 + Clang ThinLTO)
│   └── config.silicy                  # 16KB ページサイズカーネル設定
├── cachy-arm64/
│   ├── makepkg-silicy.conf            # ARM64 Apple M1 makepkg フラグ
│   └── silicy-core-tuning/
│       ├── 99-silicy-cachyos.conf     # Sysctl: ZRAM 16KB, BORE, BBRv3
│       ├── 70-silicy-io.rules         # Udev: ANS2 NVMe, ZRAM, USB SSD, DRM/audio
│       ├── ananicy-silicy.rules       # プロセス優先度ルール (99-silicy-overrides.rules)
│       └── ananicy-cpp/               # 00-cgroups.cgroups, 00-types.types, silicy-pe-enforcer.{sh,service}
├── silicy-ctl/
│   ├── silicy-ctl.c                   # 純粋 C ハードウェアコントローラ
│   ├── Makefile
│   ├── 71-silicy-macsmc.rules         # wheel 書込権限 + 起動時バッテリー上限復元
│   └── silicy-battery.conf            # 既定 80% 充電上限
├── scripts/
│   └── silicy-center                  # fuzzel コントロールセンター
├── storage/
│   ├── setup-btrfs-silicy.sh          # Btrfs サブボリューム構築 & fstab 生成
│   ├── silicy-capsule                 # スナップショット・ロールバック CLI
│   ├── 00-silicy-capsule-pre.hook     # アップグレード前自動スナップショットフック
│   ├── 99-clean-cache-and-recompress.hook
│   └── silicy-macos-bridge            # APFS RO & 共有ドライブ管理
├── input/keyd/                        # default.conf, mac-mode.conf, pc-mode.conf
├── memory/                            # zram-generator.conf, earlyoom.conf
├── services/systemd-diet.sh           # サービス削減、RAM 専用 journald、greetd 設定
├── rootfs/
│   ├── pacman-silicy.conf             # Apple ファームウェアホワイトリスト付き NoExtract
│   └── packages.silicy                # パッケージマニフェスト
├── skel/.config/                      # niri, hypr, waybar, fuzzel, kitty, swayosd, fastfetch, keyd, zsh
├── installer/
│   ├── installer_data.json            # Asahi パーティション定義 (ROOTFS_SIZE_MB=8192)
│   └── silicy-setup-tui.sh            # 初回起動 6 ステップ TUI ウィザード
└── branding/                          # ロゴ (SVG/PNG)、Plymouth テーマ、ASCII アート、壁紙
```

---

## 11. ビルド・インストール・初回起動セットアップ

### 前提条件
- Apple Silicon Mac（M1/M2/M3）と十分な APFS 空き容量（256 GB SSD 推奨分割: `silicyOS` 約 30 GB / macOS 215 GB）。
- 生成された大容量ファイル（`silicyos-apple-silicon.zip`, `.img`）は `.gitignore` で除外されており、GitHub Releases での配布を想定しています。

### 方法 A: macOS 上で Lima Apple VZ を使用してビルド
1. ビルド前検証を実行:
   ```bash
   bash silicyos-build/verify-silicyos.sh
   ```
2. 一時 `debian-13` Lima VM（`--vm-type=vz`）内で ARM64 rootfs と `silicyos-apple-silicon.zip` をビルド:
   ```bash
   cd silicyos-build
   ./macos-build-and-install.sh
   ```
3. `127.0.0.1:8765` でローカル配信し Asahi インストーラを起動:
   ```bash
   ./install-silicyos-macos.sh
   ```

### 方法 B: Linux ARM64（`root`）上で直接ビルド
```bash
cd silicyos-build
sudo ./build-silicyos.sh
```
`build-silicyos.sh` の主な処理:
- イメージサイズ: `ROOTFS_SIZE_MB=8192`（`8589934592` バイト、`installer_data.json` と一致）および `ESP_SIZE_MB=500`。
- `arch-chroot` 内で `silicy-ctl` をコンパイル（`make` または `clang -flto=thin -s -fuse-ld=lld` フォールバック）。
- リポジトリに `apfs-fuse` が無い場合、`-DCMAKE_POLICY_VERSION_MINIMUM=3.5` 付きでソースから `apfs-fuse` と `apfsutil` をビルド。
- `/etc/mkinitcpio.conf` に `MODULES=(apple-mailbox nvme_apple nvme simpledrm btrfs)` と `HOOKS=(... btrfs ...)` を設定。
- `systemd-boot` / `m1n1` のカーネルコマンドラインに `rootflags=subvol=@,compress-force=zstd:3` を設定。

### 初回起動ウィザード (`silicy-setup-tui.sh`)
1. Broadcom Wi-Fi/BT ファームウェアを展開（`asahi-fwextract`）し、`iwd` 接続を選択。
2. ホスト名設定、`wheel`（兼 `keyd`）ユーザー作成、`/etc/skel` 配備。
3. デフォルトコンポジタ選択（`niri` または `hyprland`）。
4. キーボードモード選択（`Mac Command` または `PC Ctrl`）。
5. 電源・視覚プロファイル選択（`Max-Rice Performance` または `Ultra-Battery`：`apply_ultra_battery_visuals` により `animations` を維持したまま Hyprland `blur` のみ無効化し、`silicy-ctl battery-guard 80` と `power-profile eco` を適用）。
6. `/etc/greetd/config.toml` を生成して Wayland セッションを起動。

---

## 12. 自動検証と監査 (`verify-silicyos.sh`)

8 段階の自動検証スクリプトを実行:
```bash
bash silicyos-build/verify-silicyos.sh
```

macOS ARM64 ホスト上での実測結果: **`205 PASS | 0 WARN | 0 FAIL`**
1. **[1/8] ファイルツリーと構文**: 必須 62 ファイルの存在、`bash -n`/`zsh -n`、`packages.silicy` 必須パッケージ検証、ananicy ルール名衝突チェック。
2. **[2/8] `silicy-ctl` C11 ビルドとモック Sysfs**: `clang -Wall -Wextra -Werror -O3 -mcpu=apple-m1 -flto=thin` 無警告ビルド、ヒープ未使用・生システムコール確認、10 コア Pro トポロジや読み取り専用 `/run` (`0555`) を含む機能テスト。
3. **[3/8] 独自ツール QA**: `silicy-capsule` 3 世代保持 + ロールバック + hook、`silicy-macos-bridge` APFS RO + Data ボリューム + FS 種別チェック、`silicy-center` 全 7 モジュール + Niri/Hyprland 動的検出 & クラムシェル 4K スケール維持、`keyd` `app.conf` 順序 & Kitty `SIGTSTP` 防止、`silicy-setup-tui.sh` ブラー限定エッジケース、`swayosd` `max_volume = 100`。
4. **[4/8] Zero AI Slop とカラー仕様**: 禁止絵文字ゼロ、bash `/sys/` ポーリングゼロ、Waybar・SwayOSD・Kitty・Fastfetch・`os-release` での Apple Industrial Titanium 一貫性、旧 TokyoNight 色の残存ゼロ。
5. **[5/8] ブートローダと Btrfs**: `rootflags=subvol=@,compress-force=zstd:3`、Apple Silicon モジュール、mkinitcpio `btrfs` フックの整合性。
6. **[6/8] Pacman とカーネル**: ファームウェア `NoExtract` ホワイトリスト（`brcm/*`, `apple/*`, `vendor/*`, `regulatory.db*`, `asahi-boot/*`）、`CONFIG_ARM64_16K_PAGES=y`, `CONFIG_SCHED_BORE=y`, `CONFIG_LTO_CLANG_THIN=y`, `CONFIG_HZ_1000=y`, `vm.page-cluster = 0`、x86 フラグゼロ。
7. **[7/8] Rice 構文とインストーラスキーマ**: JSON/JSONC/TOML/KDL 検証および `installer_data.json` バイトサイズ整合。
8. **[8/8] ドライランステージング**: `+x` 実行権限、`/etc/keyd/default.conf` 単一化、ドライラン ZIP 生成検証。

---

## 13. トラブルシューティングと検証範囲

- **macOS ホストと実機環境の差異**: macOS 上の `verify-silicyos.sh` はコンパイル、静的検証、ステージング模擬、および `SILICY_SYSROOT` / モック IPC テストを実施します。`build-silicyos.sh` による `pacstrap`/`arch-chroot` 実イメージ生成や実機での動作確認（`/sys/class/power_supply/macsmc-battery/`, `/sys/class/hwmon/`, `apfs-fuse` 実マウント、`btrfs subvolume snapshot`、`niri`/`Hyprland`/`keyd`/`swayosd-server` ライブ IPC、初回 TUI 実行）は Linux ARM64 / Apple Silicon 実機で実行する必要があります。
- **バッテリー/CPU ノードの権限エラー**: `/etc/udev/rules.d/71-silicy-macsmc.rules` の配置とユーザーが `wheel` グループに所属しているか確認してください。
- **FileVault 暗号化ボリュームのマウント失敗**: `kitty` ターミナル上で `silicy-macos-bridge` を実行し、対話的に復号パスワードを入力してください。
