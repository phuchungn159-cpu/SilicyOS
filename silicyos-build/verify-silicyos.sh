#!/usr/bin/env bash
# ==============================================================================
# silicyOS Comprehensive Integration Audit & QA Suite (Exclusive Edition)
# Target: Apple Silicon M1/M2/M3 (Arch ARM64 + CachyOS BORE/LTO + 16K Page)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

C_RESET='\033[0m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'
C_CYAN='\033[1;36m'

log_pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf "  ${C_GREEN}[PASS]${C_RESET} %s\n" "$1"
}

log_warn() {
    WARN_COUNT=$((WARN_COUNT + 1))
    printf "  ${C_YELLOW}[WARN]${C_RESET} %s\n" "$1"
}

log_fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf "  ${C_RED}[FAIL]${C_RESET} %s\n" "$1"
}

section() {
    printf "\n${C_CYAN}==============================================================================${C_RESET}\n"
    printf "${C_CYAN}%s${C_RESET}\n" "$1"
    printf "${C_CYAN}==============================================================================${C_RESET}\n"
}

# Ensure executable permissions on all project scripts
chmod +x \
    "${SCRIPT_DIR}/build-silicyos.sh" \
    "${SCRIPT_DIR}/verify-silicyos.sh" \
    "${SCRIPT_DIR}/install-silicyos-macos.sh" \
    "${SCRIPT_DIR}/macos-build-and-install.sh" \
    "${SCRIPT_DIR}/storage/setup-btrfs-silicy.sh" \
    "${SCRIPT_DIR}/storage/silicy-capsule" \
    "${SCRIPT_DIR}/storage/silicy-macos-bridge" \
    "${SCRIPT_DIR}/scripts/silicy-center" \
    "${SCRIPT_DIR}/services/systemd-diet.sh" \
    "${SCRIPT_DIR}/installer/silicy-setup-tui.sh" \
    "${SCRIPT_DIR}/cachy-arm64/silicy-core-tuning/ananicy-cpp/silicy-pe-enforcer.sh"

# ==============================================================================
# 1. CROSS-PHASE PATH DRIFT & BASH/ZSH SYNTAX AUDIT
# ==============================================================================
section "[1/8] Cross-Phase File Tree & 100% Shell Syntax Verification"

REQUIRED_FILES=(
    "build-silicyos.sh"
    "verify-silicyos.sh"
    "install-silicyos-macos.sh"
    "macos-build-and-install.sh"
    "kernel/PKGBUILD"
    "kernel/config.silicy"
    "cachy-arm64/makepkg-silicy.conf"
    "cachy-arm64/silicy-core-tuning/99-silicy-cachyos.conf"
    "cachy-arm64/silicy-core-tuning/70-silicy-io.rules"
    "cachy-arm64/silicy-core-tuning/ananicy-silicy.rules"
    "cachy-arm64/silicy-core-tuning/ananicy-cpp/00-cgroups.cgroups"
    "cachy-arm64/silicy-core-tuning/ananicy-cpp/00-silicy-apple-silicon.rules"
    "cachy-arm64/silicy-core-tuning/ananicy-cpp/00-types.types"
    "cachy-arm64/silicy-core-tuning/ananicy-cpp/ananicy.conf"
    "cachy-arm64/silicy-core-tuning/ananicy-cpp/silicy-pe-enforcer.service"
    "cachy-arm64/silicy-core-tuning/ananicy-cpp/silicy-pe-enforcer.sh"
    "silicy-ctl/silicy-ctl.c"
    "silicy-ctl/Makefile"
    "silicy-ctl/71-silicy-macsmc.rules"
    "silicy-ctl/silicy-battery.conf"
    "scripts/silicy-center"
    "storage/setup-btrfs-silicy.sh"
    "storage/99-clean-cache-and-recompress.hook"
    "storage/00-silicy-capsule-pre.hook"
    "storage/silicy-capsule"
    "storage/silicy-macos-bridge"
    "input/keyd/default.conf"
    "input/keyd/mac-mode.conf"
    "input/keyd/pc-mode.conf"
    "rootfs/pacman-silicy.conf"
    "rootfs/packages.silicy"
    "memory/zram-generator.conf"
    "memory/earlyoom.conf"
    "services/systemd-diet.sh"
    "skel/.config/niri/config.kdl"
    "skel/.config/hypr/hyprland.conf"
    "skel/.config/waybar/config.jsonc"
    "skel/.config/waybar/style.css"
    "skel/.config/fuzzel/fuzzel.ini"
    "skel/.config/kitty/kitty.conf"
    "skel/.config/fastfetch/config.jsonc"
    "skel/.config/fastfetch/silicyos-ascii.txt"
    "skel/.config/zsh/.zshrc"
    "skel/.config/keyd/app.conf"
    "skel/.config/swayosd/config.toml"
    "skel/.config/swayosd/style.css"
    "installer/installer_data.json"
    "installer/silicy-setup-tui.sh"
    "branding/silicyos-logo.svg"
    "branding/silicyos-logo-mono.svg"
    "branding/silicyos-logo.png"
    "branding/silicyos-boot.png"
    "branding/silicyos-boot.bmp"
    "branding/silicyos-wallpaper.png"
    "branding/silicyos-ascii.txt"
    "branding/preview.html"
    "branding/mark-512.png"
    "branding/mark-256.png"
    "branding/mark-128.png"
    "branding/mark-64.png"
    "branding/mark-32.png"
    "branding/mark-16.png"
    "branding/plymouth/silicyos/silicyos.plymouth"
    "branding/plymouth/silicyos/silicyos.script"
)

for rel_path in "${REQUIRED_FILES[@]}"; do
    if [[ -s "${SCRIPT_DIR}/${rel_path}" ]]; then
        log_pass "File present & non-empty: ${rel_path}"
    else
        log_fail "Missing or empty file: ${rel_path}"
    fi
done

BASH_SCRIPTS=(
    "build-silicyos.sh"
    "verify-silicyos.sh"
    "install-silicyos-macos.sh"
    "macos-build-and-install.sh"
    "storage/setup-btrfs-silicy.sh"
    "storage/silicy-capsule"
    "storage/silicy-macos-bridge"
    "scripts/silicy-center"
    "services/systemd-diet.sh"
    "installer/silicy-setup-tui.sh"
    "cachy-arm64/silicy-core-tuning/ananicy-cpp/silicy-pe-enforcer.sh"
    "kernel/PKGBUILD"
    "cachy-arm64/makepkg-silicy.conf"
)

for sh_file in "${BASH_SCRIPTS[@]}"; do
    if bash -n "${SCRIPT_DIR}/${sh_file}" 2>/dev/null; then
        log_pass "bash -n syntax valid: ${sh_file}"
    else
        log_fail "bash -n syntax error in: ${sh_file}"
    fi
done

if command -v zsh >/dev/null 2>&1; then
    if zsh -n "${SCRIPT_DIR}/skel/.config/zsh/.zshrc" 2>/dev/null; then
        log_pass "zsh -n syntax valid: skel/.config/zsh/.zshrc"
    else
        log_fail "zsh -n syntax error in: skel/.config/zsh/.zshrc"
    fi
fi

# Verify essential packages (including new exclusive feature dependencies) in packages.silicy
ESSENTIAL_PKGS=(
    zsh mkinitcpio btrfs-progs compsize pacman-contrib wireless-regdb
    asahi-fwextract m1n1 uboot-asahi niri hyprland waybar fuzzel kitty
    greetd zram-generator earlyoom ananicy-cpp
    keyd python jq swayosd wlsunset libnotify fuse3 apfs-fuse clang lld
)
for pkg in "${ESSENTIAL_PKGS[@]}"; do
    if grep -qx "${pkg}" "${SCRIPT_DIR}/rootfs/packages.silicy"; then
        log_pass "Package manifest includes required package: ${pkg}"
    else
        log_fail "Package manifest MISSING required package: ${pkg}"
    fi
done

# Verify build-silicyos.sh does not overwrite 00-silicy-apple-silicon.rules or call --fstab-only
if grep -q "99-silicy-overrides.rules" "${SCRIPT_DIR}/build-silicyos.sh"; then
    log_pass "Ananicy rules installed without filename collision (99-silicy-overrides.rules)"
else
    log_fail "build-silicyos.sh collides on 00-silicy-apple-silicon.rules"
fi

if ! grep -q -- "--fstab-only" "${SCRIPT_DIR}/build-silicyos.sh"; then
    log_pass "No invalid '--fstab-only' invocation of setup-btrfs-silicy.sh"
else
    log_fail "build-silicyos.sh still calls unsupported 'setup-btrfs-silicy.sh --fstab-only'"
fi

# ==============================================================================
# 2. PURE-C APPLE SMC ENGINE (silicy-ctl) STRICT COMPILATION & FUNCTIONAL QA
# ==============================================================================
section "[2/8] Pure-C Apple SMC Engine (silicy-ctl.c) Compilation & Functional Audit"

DRYRUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/silicyos-dryrun.XXXXXX")"
trap 'rm -rf "${DRYRUN_DIR}"' EXIT

CTL_SRC="${SCRIPT_DIR}/silicy-ctl/silicy-ctl.c"
CTL_BIN="${DRYRUN_DIR}/silicy-ctl"

if clang -std=c11 -Wall -Wextra -Werror -O3 -mcpu=apple-m1 -flto=thin -o "${CTL_BIN}" "${CTL_SRC}" 2>"${DRYRUN_DIR}/clang.err"; then
    log_pass "silicy-ctl.c compiled cleanly with 'clang -Wall -Wextra -Werror -O3 -mcpu=apple-m1 -flto=thin' (0 warnings, 0 errors)"
else
    log_fail "silicy-ctl.c failed strict compilation: $(tr '\n' ' ' < "${DRYRUN_DIR}/clang.err")"
fi

if make -C "${SCRIPT_DIR}/silicy-ctl" clean all >/dev/null 2>&1; then
    log_pass "silicy-ctl/Makefile builds silicy-ctl binary cleanly"
else
    log_fail "silicy-ctl/Makefile build failed"
fi

# Verify zero heap allocation and required raw syscalls in silicy-ctl.c
if grep -E '\b(malloc|calloc|realloc|free|fopen|opendir)\s*\(' "${CTL_SRC}" >/dev/null 2>&1; then
    log_fail "silicy-ctl.c contains prohibited heap allocation calls"
else
    log_pass "silicy-ctl.c enforces zero heap allocation (stack-only buffers)"
fi

for syscall_fn in open pread pwrite sched_setaffinity; do
    if grep -q "${syscall_fn}" "${CTL_SRC}"; then
        log_pass "silicy-ctl.c uses low-level syscall: ${syscall_fn}()"
    else
        log_fail "silicy-ctl.c missing required syscall: ${syscall_fn}()"
    fi
done

# Functional test of silicy-ctl against mock sysfs tree
MOCK_SYS="${DRYRUN_DIR}/mock-sysroot"
mkdir -p \
    "${MOCK_SYS}/sys/class/power_supply/macsmc-battery" \
    "${MOCK_SYS}/sys/class/hwmon/hwmon0" \
    "${MOCK_SYS}/sys/devices/system/cpu/cpu0/cpufreq" \
    "${MOCK_SYS}/sys/devices/system/cpu/cpu4/cpufreq" \
    "${MOCK_SYS}/sys/fs/cgroup/ecores_background" \
    "${MOCK_SYS}/sys/fs/cgroup/pcores_interactive" \
    "${MOCK_SYS}/proc/sys/kernel" \
    "${MOCK_SYS}/proc/sys/vm" \
    "${MOCK_SYS}/etc" \
    "${MOCK_SYS}/run"

echo "-4200000" > "${MOCK_SYS}/sys/class/power_supply/macsmc-battery/power_now"
echo "86"       > "${MOCK_SYS}/sys/class/power_supply/macsmc-battery/capacity"
echo "Discharging" > "${MOCK_SYS}/sys/class/power_supply/macsmc-battery/status"
echo "80"       > "${MOCK_SYS}/sys/class/power_supply/macsmc-battery/charge_control_end_threshold"
echo "24"       > "${MOCK_SYS}/sys/class/power_supply/macsmc-battery/cycle_count"
echo "38500"    > "${MOCK_SYS}/sys/class/hwmon/hwmon0/temp1_input"
echo "420"      > "${MOCK_SYS}/sys/devices/system/cpu/cpu0/cpu_capacity"
echo "2064000"  > "${MOCK_SYS}/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq"
echo "600000"   > "${MOCK_SYS}/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq"
echo "schedutil" > "${MOCK_SYS}/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
echo "2064000"  > "${MOCK_SYS}/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq"
echo "1024"     > "${MOCK_SYS}/sys/devices/system/cpu/cpu4/cpu_capacity"
echo "3204000"  > "${MOCK_SYS}/sys/devices/system/cpu/cpu4/cpufreq/cpuinfo_max_freq"
echo "600000"   > "${MOCK_SYS}/sys/devices/system/cpu/cpu4/cpufreq/cpuinfo_min_freq"
echo "schedutil" > "${MOCK_SYS}/sys/devices/system/cpu/cpu4/cpufreq/scaling_governor"
echo "3204000"  > "${MOCK_SYS}/sys/devices/system/cpu/cpu4/cpufreq/scaling_max_freq"
echo "1"        > "${MOCK_SYS}/proc/sys/kernel/sched_bore"
echo "22"       > "${MOCK_SYS}/proc/sys/kernel/sched_burst_penalty_offset"
echo "1"        > "${MOCK_SYS}/proc/sys/kernel/sched_burst_smoothness_long"
echo "0"        > "${MOCK_SYS}/proc/sys/kernel/sched_burst_smoothness_short"
echo "1500"     > "${MOCK_SYS}/proc/sys/vm/dirty_writeback_centisecs"
cat <<'EOF' > "${MOCK_SYS}/proc/meminfo"
MemTotal:       16777216 kB
MemAvailable:   15204352 kB
SwapTotal:      16777216 kB
SwapFree:       16646144 kB
EOF

TELEM_OUT="$(SILICY_SYSROOT="${MOCK_SYS}" "${CTL_BIN}" telemetry)"
if command -v jq >/dev/null 2>&1 && printf "%s\n" "${TELEM_OUT}" | jq -e '.capacity == 86 and .charge_threshold == 80 and .cycle_count == 24 and (.text | length > 0)' >/dev/null 2>&1; then
    log_pass "silicy-ctl telemetry outputs valid single-line Waybar JSON: ${TELEM_OUT}"
else
    log_fail "silicy-ctl telemetry JSON validation failed: ${TELEM_OUT}"
fi

# Test battery-guard 60 / 80 / 100 and invalid threshold rejection
SILICY_SYSROOT="${MOCK_SYS}" "${CTL_BIN}" battery-guard 60 >/dev/null
if [[ "$(cat "${MOCK_SYS}/sys/class/power_supply/macsmc-battery/charge_control_end_threshold")" == "60" ]] && \
   [[ "$(cat "${MOCK_SYS}/etc/silicy-battery.conf")" == "60" ]]; then
    log_pass "silicy-ctl battery-guard writes directly to macsmc charge_control_end_threshold & /etc/silicy-battery.conf"
else
    log_fail "silicy-ctl battery-guard failed to persist threshold"
fi

SILICY_SYSROOT="${MOCK_SYS}" "${CTL_BIN}" battery-guard 80 >/dev/null
if ! SILICY_SYSROOT="${MOCK_SYS}" "${CTL_BIN}" battery-guard 75 >/dev/null 2>&1 && \
   ! SILICY_SYSROOT="${MOCK_SYS}" "${CTL_BIN}" battery-guard 80abc >/dev/null 2>&1; then
    log_pass "silicy-ctl battery-guard rejects invalid thresholds (75, 80abc)"
else
    log_fail "silicy-ctl battery-guard accepted invalid threshold"
fi

EMPTY_SYS="${DRYRUN_DIR}/empty-sysroot"
mkdir -p "${EMPTY_SYS}"
EMPTY_TELEM="$(SILICY_SYSROOT="${EMPTY_SYS}" "${CTL_BIN}" telemetry)"
if command -v jq >/dev/null 2>&1 && printf "%s\n" "${EMPTY_TELEM}" | jq -e '.capacity == 100 and .charge_threshold == 80' >/dev/null 2>&1; then
    log_pass "silicy-ctl telemetry gracefully handles missing sysfs nodes with valid JSON fallback"
else
    log_fail "silicy-ctl telemetry failed on missing sysfs fallback"
fi

if WAYLAND_DISPLAY="" PATH="${DRYRUN_DIR}:${PATH}" "${SCRIPT_DIR}/scripts/silicy-center" --shortcuts >/dev/null 2>&1; then
    log_pass "silicy-center --shortcuts executes cleanly under non-GUI TTY fallback"
else
    log_fail "silicy-center --shortcuts failed execution"
fi

mkdir -p "${MOCK_SYS}/etc/keyd" "${MOCK_SYS}/usr/share/silicyos/keyd"
cp -f "${SCRIPT_DIR}/input/keyd/default.conf" "${MOCK_SYS}/etc/keyd/default.conf"
cp -f "${SCRIPT_DIR}/input/keyd/mac-mode.conf" "${MOCK_SYS}/usr/share/silicyos/keyd/mac-mode.conf"
cp -f "${SCRIPT_DIR}/input/keyd/pc-mode.conf" "${MOCK_SYS}/usr/share/silicyos/keyd/pc-mode.conf"
if WAYLAND_DISPLAY="" DBUS_SESSION_BUS_ADDRESS="" SILICY_SYSROOT="${MOCK_SYS}" PATH="${DRYRUN_DIR}:${PATH}" \
   "${SCRIPT_DIR}/scripts/silicy-center" --power eco >/dev/null && \
   WAYLAND_DISPLAY="" DBUS_SESSION_BUS_ADDRESS="" SILICY_SYSROOT="${MOCK_SYS}" PATH="${DRYRUN_DIR}:${PATH}" \
   "${SCRIPT_DIR}/scripts/silicy-center" --battery 60 >/dev/null && \
   WAYLAND_DISPLAY="" DBUS_SESSION_BUS_ADDRESS="" SILICY_SYSROOT="${MOCK_SYS}" PATH="${DRYRUN_DIR}:${PATH}" \
   "${SCRIPT_DIR}/scripts/silicy-center" --keyboard pc >/dev/null && \
   [[ "$(cat "${MOCK_SYS}/etc/silicy-power-profile")" == "eco" ]] && \
   [[ "$(cat "${MOCK_SYS}/etc/silicy-battery.conf")" == "60" ]] && \
   [[ "$(cat "${MOCK_SYS}/etc/silicy-kb-mode")" == "PC (Ctrl)" ]]; then
    log_pass "silicy-center CLI end-to-end delegates --power, --battery, and --keyboard cleanly to silicy-ctl"
else
    log_fail "silicy-center CLI end-to-end integration test failed"
fi

# Test power-profile eco / balanced / burst and invalid profile rejection
SILICY_SYSROOT="${MOCK_SYS}" "${CTL_BIN}" power-profile eco >/dev/null
if [[ "$(cat "${MOCK_SYS}/sys/devices/system/cpu/cpu4/cpufreq/scaling_governor")" == "powersave" ]] && \
   [[ "$(cat "${MOCK_SYS}/etc/silicy-power-profile")" == "eco" ]]; then
    log_pass "silicy-ctl power-profile eco throttles P-core governor and persists 'eco'"
else
    log_fail "silicy-ctl power-profile eco failed"
fi

SILICY_SYSROOT="${MOCK_SYS}" "${CTL_BIN}" power-profile burst >/dev/null
if [[ "$(cat "${MOCK_SYS}/sys/devices/system/cpu/cpu4/cpufreq/scaling_governor")" == "performance" ]] && \
   [[ "$(cat "${MOCK_SYS}/proc/sys/kernel/sched_burst_penalty_offset")" == "16" ]]; then
    log_pass "silicy-ctl power-profile burst unlocks P-core performance & BORE latency boost"
else
    log_fail "silicy-ctl power-profile burst failed"
fi

SILICY_SYSROOT="${MOCK_SYS}" "${CTL_BIN}" power-profile balanced >/dev/null
if ! SILICY_SYSROOT="${MOCK_SYS}" "${CTL_BIN}" power-profile invalid_mode >/dev/null 2>&1; then
    log_pass "silicy-ctl power-profile rejects invalid mode"
else
    log_fail "silicy-ctl power-profile accepted invalid mode"
fi

# Test keyboard-mode switching & unprivileged /run read-only tolerance
mkdir -p "${MOCK_SYS}/etc/keyd" "${MOCK_SYS}/usr/share/silicyos/keyd"
cp -f "${SCRIPT_DIR}/input/keyd/default.conf" "${MOCK_SYS}/etc/keyd/default.conf"
cp -f "${SCRIPT_DIR}/input/keyd/mac-mode.conf" "${MOCK_SYS}/usr/share/silicyos/keyd/mac-mode.conf"
cp -f "${SCRIPT_DIR}/input/keyd/pc-mode.conf" "${MOCK_SYS}/usr/share/silicyos/keyd/pc-mode.conf"
chmod 0555 "${MOCK_SYS}/run"

if SILICY_SYSROOT="${MOCK_SYS}" "${CTL_BIN}" power-profile eco >/dev/null && \
   [[ "$(cat "${MOCK_SYS}/etc/silicy-power-profile")" == "eco" ]]; then
    log_pass "silicy-ctl power-profile succeeds cleanly when /run is unprivileged/read-only (0555)"
else
    log_fail "silicy-ctl power-profile failed due to unprivileged /run mirror"
fi

if SILICY_SYSROOT="${MOCK_SYS}" "${CTL_BIN}" keyboard-mode pc >/dev/null && \
   grep -q "leftmeta = layer(control)" "${MOCK_SYS}/etc/keyd/default.conf" && \
   [[ "$(cat "${MOCK_SYS}/etc/silicy-kb-mode")" == "PC (Ctrl)" ]]; then
    log_pass "silicy-ctl keyboard-mode pc switches /etc/keyd/default.conf & persists 'PC (Ctrl)'"
else
    log_fail "silicy-ctl keyboard-mode pc failed"
fi

if SILICY_SYSROOT="${MOCK_SYS}" "${CTL_BIN}" keyboard-mode mac >/dev/null && \
   grep -q "leftmeta = layer(meta)" "${MOCK_SYS}/etc/keyd/default.conf" && \
   [[ "$(cat "${MOCK_SYS}/etc/silicy-kb-mode")" == "Mac (Command)" ]]; then
    log_pass "silicy-ctl keyboard-mode mac restores Command layer & persists 'Mac (Command)'"
else
    log_fail "silicy-ctl keyboard-mode mac failed"
fi

if ! SILICY_SYSROOT="${MOCK_SYS}" "${CTL_BIN}" keyboard-mode invalid_kb >/dev/null 2>&1; then
    log_pass "silicy-ctl keyboard-mode rejects invalid mode"
else
    log_fail "silicy-ctl keyboard-mode accepted invalid mode"
fi

chmod 0755 "${MOCK_SYS}/run"

# Test Apple Silicon Pro/Max asymmetric topology (2 E-cores + 8 P-cores) telemetry
PRO_SYS="${DRYRUN_DIR}/pro-sysroot"
mkdir -p "${PRO_SYS}/sys/devices/system/cpu"
for cpu_i in 0 1; do
    mkdir -p "${PRO_SYS}/sys/devices/system/cpu/cpu${cpu_i}"
    echo "420" > "${PRO_SYS}/sys/devices/system/cpu/cpu${cpu_i}/cpu_capacity"
done
for cpu_i in 2 3 4 5 6 7 8 9; do
    mkdir -p "${PRO_SYS}/sys/devices/system/cpu/cpu${cpu_i}"
    echo "1024" > "${PRO_SYS}/sys/devices/system/cpu/cpu${cpu_i}/cpu_capacity"
done
if command -v jq >/dev/null 2>&1 && SILICY_SYSROOT="${PRO_SYS}" "${CTL_BIN}" telemetry | jq -e '.capacity == 100' >/dev/null 2>&1; then
    log_pass "silicy-ctl telemetry handles 10-core Apple Silicon Pro topology cleanly"
else
    log_fail "silicy-ctl telemetry failed under 10-core Pro topology"
fi

if grep -q -- "-fuse-ld=lld" "${SCRIPT_DIR}/silicy-ctl/Makefile"; then
    log_pass "silicy-ctl/Makefile enforces ThinLTO linking via -fuse-ld=lld"
else
    log_fail "silicy-ctl/Makefile missing -fuse-ld=lld for Linux ThinLTO"
fi

# Check udev rule for wheel permissions on macsmc-battery
if grep -q "chgrp wheel /sys/class/power_supply/macsmc-battery/charge_control_end_threshold" "${SCRIPT_DIR}/silicy-ctl/71-silicy-macsmc.rules" && \
   grep -q "chmod 0664 /sys/class/power_supply/macsmc-battery/charge_control_end_threshold" "${SCRIPT_DIR}/silicy-ctl/71-silicy-macsmc.rules"; then
    log_pass "71-silicy-macsmc.rules grants wheel group write permission (0664) on macsmc-battery without sudo"
else
    log_fail "71-silicy-macsmc.rules missing wheel group permission grant for macsmc-battery"
fi

# ==============================================================================
# 3. EXCLUSIVE TOOLS QA: silicy-capsule, silicy-macos-bridge, silicy-center
# ==============================================================================
section "[3/8] Exclusive Tools QA (silicy-capsule, silicy-macos-bridge, silicy-center)"

CAPSULE_SIM_DIR="${DRYRUN_DIR}/snapshots"
for n in 1 2 3 4 5; do
    SILICY_CAPSULE_SIMULATE=1 SILICY_SNAPSHOT_DIR="${CAPSULE_SIM_DIR}" "${SCRIPT_DIR}/storage/silicy-capsule" create "test-${n}" >/dev/null
done
SNAP_COUNT="$(find "${CAPSULE_SIM_DIR}" -mindepth 1 -maxdepth 1 -type d -name "silicy-*" | wc -l | tr -d ' ')"
if [[ "${SNAP_COUNT}" -eq 3 ]]; then
    log_pass "silicy-capsule auto-prune strictly retains maximum 3 latest snapshots (created 5 -> kept 3)"
else
    log_fail "silicy-capsule retention failed (expected 3 snapshots, found ${SNAP_COUNT})"
fi

LATEST_SNAP="$(find "${CAPSULE_SIM_DIR}" -mindepth 1 -maxdepth 1 -type d -name "silicy-*" | sort | tail -n1)"
LATEST_SNAP_NAME="${LATEST_SNAP##*/}"
SILICY_CAPSULE_SIMULATE=1 SILICY_SNAPSHOT_DIR="${CAPSULE_SIM_DIR}" "${SCRIPT_DIR}/storage/silicy-capsule" rollback "${LATEST_SNAP_NAME}" >/dev/null
if [[ "$(cat "${CAPSULE_SIM_DIR}/.last-rollback")" == "${LATEST_SNAP_NAME}" ]]; then
    log_pass "silicy-capsule rollback verified for snapshot: ${LATEST_SNAP_NAME}"
else
    log_fail "silicy-capsule rollback test failed"
fi

if grep -q "When = PreTransaction" "${SCRIPT_DIR}/storage/00-silicy-capsule-pre.hook" && \
   grep -q "/usr/local/bin/silicy-capsule auto-pre-upgrade" "${SCRIPT_DIR}/storage/00-silicy-capsule-pre.hook"; then
    log_pass "Pacman PreTransaction hook (00-silicy-capsule-pre.hook) triggers silicy-capsule auto-pre-upgrade"
else
    log_fail "00-silicy-capsule-pre.hook malformed"
fi

BRIDGE_SIM_MNT="${DRYRUN_DIR}/macos-mnt"
MOCK_LSBLK="${DRYRUN_DIR}/lsblk-apfs.txt"
cat <<'EOF' > "${MOCK_LSBLK}"
/dev/nvme0n1p1 7c3457ef-0000-11aa-aa11-00306543ecac 524288000 iBoot System Container
/dev/nvme0n1p2 7c3457ef-0000-11aa-aa11-00306543ecac 10737418240 Recovery OS Container
/dev/nvme0n1p3 7c3457ef-0000-11aa-aa11-00306543ecac 494384795648 Macintosh HD
/dev/nvme0n1p4 0fc63daf-8483-4772-8e79-3d69d8477de4 256000000000 silicyOS
EOF

SILICY_BRIDGE_SIMULATE=1 SILICY_LSBLK_FILE="${MOCK_LSBLK}" SILICY_MACOS_MNT="${BRIDGE_SIM_MNT}" "${SCRIPT_DIR}/storage/silicy-macos-bridge" --no-gui mount >/dev/null
if [[ -f "${BRIDGE_SIM_MNT}/.bridge-ro-state" ]] && \
   grep -q "MOUNT_MODE=ro" "${BRIDGE_SIM_MNT}/.bridge-ro-state" && \
   grep -q "DEVICE=/dev/nvme0n1p3" "${BRIDGE_SIM_MNT}/.bridge-ro-state"; then
    log_pass "silicy-macos-bridge mounts APFS strictly RO and selects Macintosh HD even with multi-word PARTLABELs"
else
    log_fail "silicy-macos-bridge Read-Only mount or PARTLABEL detection check failed"
fi
SILICY_BRIDGE_SIMULATE=1 SILICY_MACOS_MNT="${BRIDGE_SIM_MNT}" "${SCRIPT_DIR}/storage/silicy-macos-bridge" umount >/dev/null

MOCK_APFSUTIL="${DRYRUN_DIR}/apfsutil.txt"
cat <<'EOF' > "${MOCK_APFSUTIL}"
Volume 0 11111111-1111-1111-1111-111111111111
Role:               Preboot
Name:               Preboot (Case-sensitive)

Volume 1 22222222-2222-2222-2222-222222222222
Role:               System
Name:               Macintosh HD (Case-sensitive)

Volume 2 33333333-3333-3333-3333-333333333333
Role:               Data
Name:               Macintosh HD - Data (Case-sensitive)

Volume 3 44444444-4444-4444-4444-444444444444
Role:               VM
Name:               VM (Case-sensitive)
EOF

SILICY_BRIDGE_SIMULATE=1 SILICY_LSBLK_FILE="${MOCK_LSBLK}" SILICY_APFSUTIL_FILE="${MOCK_APFSUTIL}" SILICY_MACOS_MNT="${BRIDGE_SIM_MNT}" "${SCRIPT_DIR}/storage/silicy-macos-bridge" --no-gui mount >/dev/null
if grep -q "VOLUME_ID=2" "${BRIDGE_SIM_MNT}/.bridge-ro-state" && \
   grep -q "vfat|msdos|exfat|ntfs|ntfs3" "${SCRIPT_DIR}/storage/silicy-macos-bridge"; then
    log_pass "silicy-macos-bridge selects APFS Data volume (vol 2) and gates uid/gid opts by filesystem type"
else
    log_fail "silicy-macos-bridge failed Data volume selection or filesystem-aware mount option check"
fi
SILICY_BRIDGE_SIMULATE=1 SILICY_MACOS_MNT="${BRIDGE_SIM_MNT}" "${SCRIPT_DIR}/storage/silicy-macos-bridge" umount >/dev/null

# Verify all 7 interactive modules in silicy-center
for center_mod in "\[Power Profile\]" "\[Battery Care\]" "\[Display Comfort\]" "\[Keyboard Mode\]" "\[macOS Shared Drive\]" "\[System Capsule\]" "\[Shortcut Guide\]"; do
    if grep -q "${center_mod}" "${SCRIPT_DIR}/scripts/silicy-center"; then
        log_pass "silicy-center includes interactive module: ${center_mod}"
    else
        log_fail "silicy-center missing required module: ${center_mod}"
    fi
done

if grep -q "wlsunset -t 4200 -T 4201" "${SCRIPT_DIR}/scripts/silicy-center" && \
   grep -q "detect_niri_internal_output" "${SCRIPT_DIR}/scripts/silicy-center" && \
   grep -q "detect_hyprland_internal_output" "${SCRIPT_DIR}/scripts/silicy-center" && \
   ! grep -q 'hyprctl keyword monitor "eDP-1,' "${SCRIPT_DIR}/scripts/silicy-center" && \
   grep -q 'hyprctl keyword decoration:blur:enabled' "${SCRIPT_DIR}/scripts/silicy-center" && \
   grep -q -- '-e bash -c' "${SCRIPT_DIR}/scripts/silicy-center" && \
   ! grep -Eq '(^|[[:space:]])sh -c .*read -r -p' "${SCRIPT_DIR}/scripts/silicy-center"; then
    log_pass "silicy-center handles wlsunset 4200K, dynamic Niri & Hyprland output detection, Hyprland blur & bash rollback shell"
else
    log_fail "silicy-center missing dynamic output detection, user-session blur sync, or bash rollback shell"
fi

# Functional test for dynamic Hyprland connector detection in silicy-center
if command -v jq >/dev/null 2>&1; then
    HYPR_MOCK_BIN="${DRYRUN_DIR}/hypr-mock-bin"
    HYPR_CALL_LOG="${DRYRUN_DIR}/hyprctl-calls.log"
    mkdir -p "${HYPR_MOCK_BIN}"

    cat <<'EOF' > "${HYPR_MOCK_BIN}/pgrep"
#!/usr/bin/env bash
if [[ "${1:-}" == "-x" && "${2:-}" == "Hyprland" ]]; then
    exit 0
fi
exit 1
EOF
    cat <<'EOF' > "${HYPR_MOCK_BIN}/hyprctl"
#!/usr/bin/env bash
if [[ "${1:-}" == "monitors" && "${2:-}" == "-j" ]]; then
    if [[ "${HYPR_MOCK_RC:-0}" -ne 0 ]]; then
        exit "${HYPR_MOCK_RC}"
    fi
    printf "%s\n" "${HYPR_MOCK_JSON:-[]}"
    exit 0
fi
if [[ -n "${HYPR_CALL_LOG:-}" ]]; then
    printf "%s\n" "$*" >> "${HYPR_CALL_LOG}"
fi
exit 0
EOF
    cat <<'EOF' > "${HYPR_MOCK_BIN}/fuzzel"
#!/usr/bin/env bash
cat >/dev/null
printf "%s\n" "${MOCK_FUZZEL_CHOICE:-}"
EOF
    cat <<'EOF' > "${HYPR_MOCK_BIN}/swayosd-client"
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${HYPR_MOCK_BIN}/pgrep" "${HYPR_MOCK_BIN}/hyprctl" "${HYPR_MOCK_BIN}/fuzzel" "${HYPR_MOCK_BIN}/swayosd-client"

    HYPR_DET_INTERNAL="$(SILICY_SYSROOT="${MOCK_SYS}" PATH="${HYPR_MOCK_BIN}:${PATH}" \
        HYPR_MOCK_JSON='[{"name":"DP-1","focused":true,"disabled":false},{"name":"eDP-2","focused":false,"disabled":false}]' \
        bash -c "source '${SCRIPT_DIR}/scripts/silicy-center' && detect_hyprland_internal_output")"
    HYPR_DET_EXTERNAL="$(SILICY_SYSROOT="${MOCK_SYS}" PATH="${HYPR_MOCK_BIN}:${PATH}" \
        HYPR_MOCK_JSON='[{"name":"HDMI-A-1","focused":true,"disabled":false}]' \
        bash -c "source '${SCRIPT_DIR}/scripts/silicy-center' && detect_hyprland_internal_output")"
    HYPR_DET_CLAMSHELL="$(SILICY_SYSROOT="${MOCK_SYS}" PATH="${HYPR_MOCK_BIN}:${PATH}" \
        HYPR_MOCK_JSON='[{"name":"eDP-1","focused":false,"disabled":true},{"name":"DP-2","focused":true,"disabled":false}]' \
        bash -c "source '${SCRIPT_DIR}/scripts/silicy-center' && detect_hyprland_internal_output")"
    HYPR_DET_EMPTY_NAME="$(SILICY_SYSROOT="${MOCK_SYS}" PATH="${HYPR_MOCK_BIN}:${PATH}" \
        HYPR_MOCK_JSON='[{"name":"","focused":true,"disabled":false},{"name":"DP-2","focused":false,"disabled":false}]' \
        bash -c "source '${SCRIPT_DIR}/scripts/silicy-center' && detect_hyprland_internal_output")"
    HYPR_DET_FALLBACK="$(SILICY_SYSROOT="${MOCK_SYS}" PATH="${HYPR_MOCK_BIN}:${PATH}" \
        HYPR_MOCK_JSON='[]' \
        bash -c "source '${SCRIPT_DIR}/scripts/silicy-center' && detect_hyprland_internal_output")"
    HYPR_DET_ERR_FALLBACK="$(SILICY_SYSROOT="${MOCK_SYS}" PATH="${HYPR_MOCK_BIN}:${PATH}" \
        HYPR_MOCK_RC=1 HYPR_MOCK_JSON='error' \
        bash -c "source '${SCRIPT_DIR}/scripts/silicy-center' && detect_hyprland_internal_output")"

    if [[ "${HYPR_DET_INTERNAL}" == "eDP-2" && \
          "${HYPR_DET_EXTERNAL}" == "HDMI-A-1" && \
          "${HYPR_DET_CLAMSHELL}" == "DP-2" && \
          "${HYPR_DET_EMPTY_NAME}" == "DP-2" && \
          "${HYPR_DET_FALLBACK}" == "eDP-1" && \
          "${HYPR_DET_ERR_FALLBACK}" == "eDP-1" ]]; then
        log_pass "silicy-center detect_hyprland_internal_output resolves eDP-2, HDMI-A-1, clamshell DP-2, empty-name skip & eDP-1 fallback"
    else
        log_fail "silicy-center detect_hyprland_internal_output failed (got: ${HYPR_DET_INTERNAL}, ${HYPR_DET_EXTERNAL}, ${HYPR_DET_CLAMSHELL}, ${HYPR_DET_EMPTY_NAME}, ${HYPR_DET_FALLBACK}, ${HYPR_DET_ERR_FALLBACK})"
    fi

    : > "${HYPR_CALL_LOG}"
    SILICY_SYSROOT="${MOCK_SYS}" WAYLAND_DISPLAY="wayland-1" DBUS_SESSION_BUS_ADDRESS="" \
        PATH="${HYPR_MOCK_BIN}:${PATH}" HYPR_CALL_LOG="${HYPR_CALL_LOG}" \
        HYPR_MOCK_JSON='[{"name":"DP-1","focused":true,"disabled":false},{"name":"eDP-2","focused":false,"disabled":false}]' \
        MOCK_FUZZEL_CHOICE="2. Set 120Hz ProMotion Adaptive" \
        "${SCRIPT_DIR}/scripts/silicy-center" --display >/dev/null
    SILICY_SYSROOT="${MOCK_SYS}" WAYLAND_DISPLAY="wayland-1" DBUS_SESSION_BUS_ADDRESS="" \
        PATH="${HYPR_MOCK_BIN}:${PATH}" HYPR_CALL_LOG="${HYPR_CALL_LOG}" \
        HYPR_MOCK_JSON='[{"name":"DP-1","focused":true,"disabled":false},{"name":"eDP-2","focused":false,"disabled":false}]' \
        MOCK_FUZZEL_CHOICE="3. Set 60Hz Battery Saver" \
        "${SCRIPT_DIR}/scripts/silicy-center" --display >/dev/null

    if grep -qx "keyword monitor eDP-2,highrr,auto,2" "${HYPR_CALL_LOG}" && \
       grep -qx "keyword monitor eDP-2,2560x1600@60,auto,2" "${HYPR_CALL_LOG}" && \
       ! grep -q "eDP-1" "${HYPR_CALL_LOG}"; then
        log_pass "silicy-center --display targets dynamically detected Hyprland connector (eDP-2) for 120Hz & 60Hz"
    else
        log_fail "silicy-center --display failed dynamic Hyprland monitor keyword dispatch"
    fi

    # Clamshell external monitor: verify resolution/scale from hyprctl monitors -j, DRM isolation, and runtime state file
    HYPR_RUN_DIR="${DRYRUN_DIR}/hypr-runtime"
    mkdir -p "${HYPR_RUN_DIR}" "${MOCK_SYS}/sys/class/drm/card0-eDP-1"
    printf "3024x1964\n" > "${MOCK_SYS}/sys/class/drm/card0-eDP-1/modes"
    RES_EXT_DRM="$(SILICY_SYSROOT="${MOCK_SYS}" bash -c "source '${SCRIPT_DIR}/scripts/silicy-center' && detect_edp_resolution 'DP-2'")"
    RES_INT_DRM="$(SILICY_SYSROOT="${MOCK_SYS}" bash -c "source '${SCRIPT_DIR}/scripts/silicy-center' && detect_edp_resolution 'eDP-1'")"

    : > "${HYPR_CALL_LOG}"
    SILICY_SYSROOT="${MOCK_SYS}" WAYLAND_DISPLAY="wayland-1" DBUS_SESSION_BUS_ADDRESS="" \
        XDG_RUNTIME_DIR="${HYPR_RUN_DIR}" PATH="${HYPR_MOCK_BIN}:${PATH}" HYPR_CALL_LOG="${HYPR_CALL_LOG}" \
        HYPR_MOCK_JSON='[{"name":"eDP-1","disabled":true,"focused":false,"width":3024,"height":1964,"scale":2.00},{"name":"DP-2","disabled":false,"focused":true,"width":3840,"height":2160,"scale":1.50}]' \
        MOCK_FUZZEL_CHOICE="2. Set 120Hz ProMotion Adaptive" \
        "${SCRIPT_DIR}/scripts/silicy-center" --display >/dev/null
    RATE_120_STAT="$(cat "${HYPR_RUN_DIR}/silicy-refresh-rate" 2>/dev/null || true)"
    SILICY_SYSROOT="${MOCK_SYS}" WAYLAND_DISPLAY="wayland-1" DBUS_SESSION_BUS_ADDRESS="" \
        XDG_RUNTIME_DIR="${HYPR_RUN_DIR}" PATH="${HYPR_MOCK_BIN}:${PATH}" HYPR_CALL_LOG="${HYPR_CALL_LOG}" \
        HYPR_MOCK_JSON='[{"name":"eDP-1","disabled":true,"focused":false,"width":3024,"height":1964,"scale":2.00},{"name":"DP-2","disabled":false,"focused":true,"width":3840,"height":2160,"scale":1.50}]' \
        MOCK_FUZZEL_CHOICE="3. Set 60Hz Battery Saver" \
        "${SCRIPT_DIR}/scripts/silicy-center" --display >/dev/null
    RATE_60_STAT="$(cat "${HYPR_RUN_DIR}/silicy-refresh-rate" 2>/dev/null || true)"

    if [[ "${RES_INT_DRM}" == "3024x1964" && "${RES_EXT_DRM}" == "2560x1600" && \
          "${RATE_120_STAT}" == "120Hz ProMotion" && "${RATE_60_STAT}" == "60Hz Fixed" ]] && \
       grep -qx "keyword monitor DP-2,highrr,auto,1.50" "${HYPR_CALL_LOG}" && \
       grep -qx "keyword monitor DP-2,3840x2160@60,auto,1.50" "${HYPR_CALL_LOG}"; then
        log_pass "silicy-center --display preserves external 4K resolution/scale (DP-2, 3840x2160, 1.50) & updates runtime rate state"
    else
        log_fail "silicy-center --display failed clamshell external resolution/scale or DRM isolation"
    fi

    # Session env precedence: HYPRLAND_INSTANCE_SIGNATURE must beat background niri process
    NIRI_SHADOW_BIN="${DRYRUN_DIR}/hypr-shadow-niri-bin"
    mkdir -p "${NIRI_SHADOW_BIN}"
    cp -f "${HYPR_MOCK_BIN}/hyprctl" "${HYPR_MOCK_BIN}/fuzzel" "${HYPR_MOCK_BIN}/swayosd-client" "${NIRI_SHADOW_BIN}/"
    cat <<'EOF' > "${NIRI_SHADOW_BIN}/pgrep"
#!/usr/bin/env bash
exit 0
EOF
    cat <<'EOF' > "${NIRI_SHADOW_BIN}/niri"
#!/usr/bin/env bash
printf "NIRI_UNEXPECTED %s\n" "$*" >> "${HYPR_CALL_LOG}"
EOF
    chmod +x "${NIRI_SHADOW_BIN}/pgrep" "${NIRI_SHADOW_BIN}/niri" "${NIRI_SHADOW_BIN}/hyprctl" "${NIRI_SHADOW_BIN}/fuzzel" "${NIRI_SHADOW_BIN}/swayosd-client"

    : > "${HYPR_CALL_LOG}"
    SILICY_SYSROOT="${MOCK_SYS}" WAYLAND_DISPLAY="wayland-1" DBUS_SESSION_BUS_ADDRESS="" \
        HYPRLAND_INSTANCE_SIGNATURE="sig-test" PATH="${NIRI_SHADOW_BIN}:${PATH}" HYPR_CALL_LOG="${HYPR_CALL_LOG}" \
        HYPR_MOCK_JSON='[{"name":"eDP-1","disabled":false,"focused":true,"width":3024,"height":1964,"scale":2}]' \
        MOCK_FUZZEL_CHOICE="3. Set 60Hz Battery Saver" \
        "${SCRIPT_DIR}/scripts/silicy-center" --display >/dev/null
    if grep -qx "keyword monitor eDP-1,3024x1964@60,auto,2" "${HYPR_CALL_LOG}" && \
       ! grep -q "NIRI_UNEXPECTED" "${HYPR_CALL_LOG}"; then
        log_pass "silicy-center --display prioritizes HYPRLAND_INSTANCE_SIGNATURE over unrelated niri processes"
    else
        log_fail "silicy-center --display failed HYPRLAND_INSTANCE_SIGNATURE compositor precedence"
    fi

    : > "${HYPR_CALL_LOG}"
    SILICY_SYSROOT="${MOCK_SYS}" WAYLAND_DISPLAY="wayland-1" DBUS_SESSION_BUS_ADDRESS="" \
        PATH="${HYPR_MOCK_BIN}:${PATH}" HYPR_CALL_LOG="${HYPR_CALL_LOG}" \
        HYPR_MOCK_JSON='[]' \
        MOCK_FUZZEL_CHOICE="2. Set 120Hz ProMotion Adaptive" \
        "${SCRIPT_DIR}/scripts/silicy-center" --display >/dev/null

    if grep -qx "keyword monitor eDP-1,highrr,auto,2" "${HYPR_CALL_LOG}"; then
        log_pass "silicy-center --display falls back cleanly to eDP-1 when hyprctl monitors -j returns empty"
    else
        log_fail "silicy-center --display failed eDP-1 fallback on empty hyprctl monitors -j"
    fi
fi

# Verify keyd & swayosd configurations
if grep -q "leftmeta = layer(meta)" "${SCRIPT_DIR}/input/keyd/default.conf" && \
   grep -q "^\[meta:M\]" "${SCRIPT_DIR}/input/keyd/default.conf" && \
   grep -q "leftmeta = layer(meta)" "${SCRIPT_DIR}/input/keyd/mac-mode.conf" && \
   grep -q "^\[meta:M\]" "${SCRIPT_DIR}/input/keyd/mac-mode.conf"; then
    log_pass "keyd default.conf & mac-mode.conf use [meta:M] layer matching keyd-application-mapper"
else
    log_fail "keyd default.conf / mac-mode.conf layer name mismatch with app.conf"
fi

STAR_LINE="$(grep -n '^\[\*\]' "${SCRIPT_DIR}/skel/.config/keyd/app.conf" | head -n1 | cut -d: -f1)"
KITTY_LINE="$(grep -n '^\[kitty\]' "${SCRIPT_DIR}/skel/.config/keyd/app.conf" | head -n1 | cut -d: -f1)"
if [[ -n "${STAR_LINE}" && -n "${KITTY_LINE}" && "${STAR_LINE}" -lt "${KITTY_LINE}" ]] && \
   grep -q "meta.c = C-c" "${SCRIPT_DIR}/skel/.config/keyd/app.conf" && \
   grep -q "^\[org-wezfurlong-wezterm\]" "${SCRIPT_DIR}/skel/.config/keyd/app.conf" && \
   ! grep -Eq '^meta\.(f|r|l)[[:space:]]*=' "${SCRIPT_DIR}/skel/.config/keyd/app.conf" && \
   grep -q 'meta\.z = M-z' "${SCRIPT_DIR}/skel/.config/keyd/app.conf" && \
   ! grep -q 'send_text all \\x1a' "${SCRIPT_DIR}/skel/.config/kitty/kitty.conf"; then
    log_pass "keyd app.conf orders [*] before [kitty], preserves Mod+F/R/L compositor keys, & prevents accidental Kitty SIGTSTP"
else
    log_fail "keyd app.conf ordering/compositor collision or Kitty SIGTSTP mapping check failed"
fi

if grep -q "/usr/share/silicyos/keyd/mac-mode.conf" "${SCRIPT_DIR}/build-silicyos.sh" && \
   grep -q "user_allow_other" "${SCRIPT_DIR}/build-silicyos.sh" && \
   grep -q "apfs-fuse.git" "${SCRIPT_DIR}/build-silicyos.sh" && \
   grep -q "CMAKE_POLICY_VERSION_MINIMUM=3.5" "${SCRIPT_DIR}/build-silicyos.sh" && \
   grep -q "/usr/local/bin/apfsutil" "${SCRIPT_DIR}/build-silicyos.sh" && \
   grep -q "tmpfiles.d/silicyos.conf" "${SCRIPT_DIR}/build-silicyos.sh"; then
    log_pass "build-silicyos.sh isolates keyd presets, enables fuse, & builds apfs-fuse+apfsutil with CMake 4+ policy floor"
else
    log_fail "build-silicyos.sh missing keyd preset isolation, fuse.conf, tmpfiles.d, or apfs-fuse/apfsutil CMake policy"
fi

if ! grep -q "ctrl:swap_lwin_lctl" "${SCRIPT_DIR}/installer/silicy-setup-tui.sh" && \
   grep -q "usermod -aG keyd" "${SCRIPT_DIR}/installer/silicy-setup-tui.sh"; then
    log_pass "silicy-setup-tui.sh adds user to keyd group and avoids XKB double-swap"
else
    log_fail "silicy-setup-tui.sh has XKB double-swap bug or missing keyd group"
fi

# Functional test for Ultra-Battery blur-scoped replacement in silicy-setup-tui.sh
TUI_SIM_HOME="${DRYRUN_DIR}/tui-sim-home"
mkdir -p "${TUI_SIM_HOME}/.config"
cp -a "${SCRIPT_DIR}/skel/.config/." "${TUI_SIM_HOME}/.config/"
(
    source "${SCRIPT_DIR}/installer/silicy-setup-tui.sh"
    apply_ultra_battery_visuals "${TUI_SIM_HOME}"
)
TUI_HYPR="${TUI_SIM_HOME}/.config/hypr/hyprland.conf"
TUI_KITTY="${TUI_SIM_HOME}/.config/kitty/kitty.conf"
BLUR_VAL="$(awk '/^[[:space:]]*blur[[:space:]]*\{/{inb=1;next} inb && /^[[:space:]]*\}/{inb=0} inb && /^[[:space:]]*enabled[[:space:]]*=/{print $3}' "${TUI_HYPR}")"
ANIM_VAL="$(awk '/^[[:space:]]*animations[[:space:]]*\{/{ina=1;next} ina && /^[[:space:]]*\}/{ina=0} ina && /^[[:space:]]*enabled[[:space:]]*=/{print $3}' "${TUI_HYPR}")"
SHADOW_VAL="$(awk '/^[[:space:]]*shadow[[:space:]]*\{/{ins=1;next} ins && /^[[:space:]]*\}/{ins=0} ins && /^[[:space:]]*enabled[[:space:]]*=/{print $3}' "${TUI_HYPR}")"

if ! grep -q "sed -i 's/enabled = true/enabled = false/'" "${SCRIPT_DIR}/installer/silicy-setup-tui.sh" && \
   [[ "${BLUR_VAL}" == "false" && "${ANIM_VAL}" == "true" && "${SHADOW_VAL}" == "false" ]] && \
   grep -q "background_blur            0" "${TUI_KITTY}" && \
   grep -q "background_opacity         0.94" "${TUI_KITTY}"; then
    log_pass "silicy-setup-tui.sh Ultra-Battery mode disables Hyprland blur while keeping animations enabled"
else
    log_fail "silicy-setup-tui.sh Ultra-Battery mode failed blur-only scoping (blur=${BLUR_VAL}, animations=${ANIM_VAL}, shadow=${SHADOW_VAL})"
fi

# Edge-case test with comment '# blur {', inline comment '# enabled = true', and 'shadow { enabled = true }'
TUI_EDGE_HOME="${DRYRUN_DIR}/tui-edge-home"
mkdir -p "${TUI_EDGE_HOME}/.config/hypr"
cat <<'EOF' > "${TUI_EDGE_HOME}/.config/hypr/hyprland.conf"
# blur {
decoration {
    shadow {
        enabled = true
    }
    blur { # enabled = true
        enabled = true # glass
        size = 7
        blur_enabled = true
    }
}
animations {
    enabled = true
}
EOF
(
    source "${SCRIPT_DIR}/installer/silicy-setup-tui.sh"
    apply_ultra_battery_visuals "${TUI_EDGE_HOME}"
)
EDGE_HYPR="${TUI_EDGE_HOME}/.config/hypr/hyprland.conf"
EDGE_SHADOW="$(awk '/^[[:space:]]*shadow[[:space:]]*\{/{ins=1;next} ins && /^[[:space:]]*\}/{ins=0} ins && /^[[:space:]]*enabled[[:space:]]*=/{print $3}' "${EDGE_HYPR}")"
EDGE_BLUR="$(awk '/^[[:space:]]*blur[[:space:]]*\{/{inb=1;next} inb && /^[[:space:]]*\}/{inb=0} inb && /^[[:space:]]*enabled[[:space:]]*=/{print $3}' "${EDGE_HYPR}")"
EDGE_ANIM="$(awk '/^[[:space:]]*animations[[:space:]]*\{/{ina=1;next} ina && /^[[:space:]]*\}/{ina=0} ina && /^[[:space:]]*enabled[[:space:]]*=/{print $3}' "${EDGE_HYPR}")"
if [[ "${EDGE_SHADOW}" == "true" && "${EDGE_BLUR}" == "false" && "${EDGE_ANIM}" == "true" ]] && \
   grep -q 'blur { # enabled = true$' "${EDGE_HYPR}" && \
   grep -q 'blur_enabled = true' "${EDGE_HYPR}"; then
    log_pass "silicy-setup-tui.sh blur scoping ignores '# blur {'/'# enabled = true' comments, blur_enabled, shadow, and animations"
else
    log_fail "silicy-setup-tui.sh blur scoping failed edge-case isolation (shadow=${EDGE_SHADOW}, blur=${EDGE_BLUR}, animations=${EDGE_ANIM})"
fi

# Edge-case test for Allman-style blur block and single-line decoration/blur/animations
TUI_SYNTAX_HOME="${DRYRUN_DIR}/tui-syntax-home"
mkdir -p "${TUI_SYNTAX_HOME}/.config/hypr"
cat <<'EOF' > "${TUI_SYNTAX_HOME}/.config/hypr/hyprland.conf"
decoration {
    blur
    # Allman comment
    {
        sub { enabled = true }
        enabled = true
    }
}
animations { enabled = true }
EOF
(
    source "${SCRIPT_DIR}/installer/silicy-setup-tui.sh"
    apply_ultra_battery_visuals "${TUI_SYNTAX_HOME}"
)
ALLMAN_HYPR="${TUI_SYNTAX_HOME}/.config/hypr/hyprland.conf"

TUI_ONELINE_HOME="${DRYRUN_DIR}/tui-oneline-home"
mkdir -p "${TUI_ONELINE_HOME}/.config/hypr"
cat <<'EOF' > "${TUI_ONELINE_HOME}/.config/hypr/hyprland.conf"
decoration { blur { enabled = true } } animations { enabled = true }
EOF
(
    source "${SCRIPT_DIR}/installer/silicy-setup-tui.sh"
    apply_ultra_battery_visuals "${TUI_ONELINE_HOME}"
)
ONELINE_HYPR="${TUI_ONELINE_HOME}/.config/hypr/hyprland.conf"

if grep -q 'sub { enabled = true }' "${ALLMAN_HYPR}" && \
   grep -qx '        enabled = false' "${ALLMAN_HYPR}" && \
   grep -qx 'animations { enabled = true }' "${ALLMAN_HYPR}" && \
   grep -qx 'decoration { blur { enabled = false } } animations { enabled = true }' "${ONELINE_HYPR}"; then
    log_pass "silicy-setup-tui.sh handles Allman blur braces, nested sub-blocks, and single-line blur/animations"
else
    log_fail "silicy-setup-tui.sh failed Allman or single-line blur scoping"
fi

if grep -q "silicy-ctl power-profile" "${SCRIPT_DIR}/cachy-arm64/silicy-core-tuning/ananicy-cpp/silicy-pe-enforcer.sh" && \
   ! grep -q "/var/run/keyd.socket" "${SCRIPT_DIR}/cachy-arm64/silicy-core-tuning/ananicy-cpp/silicy-pe-enforcer.sh" && \
   grep -q '"decoration:blur:enabled", (char \*)' "${SCRIPT_DIR}/silicy-ctl/silicy-ctl.c" && \
   grep -q "silicy-kb-mode" "${SCRIPT_DIR}/skel/.config/niri/config.kdl" && \
   grep -q "silicy-kb-mode" "${SCRIPT_DIR}/skel/.config/hypr/hyprland.conf"; then
    log_pass "Boot persistence, keyd.socket group preservation, & split hyprctl keyword argv verified"
else
    log_fail "Missing boot power-profile restore, keyd.socket preservation, split hyprctl argv, or PC-mode guard"
fi

if grep -q "max_volume = 100" "${SCRIPT_DIR}/skel/.config/swayosd/config.toml" && \
   ! grep -Eq '^[[:space:]]*\[client\]' "${SCRIPT_DIR}/skel/.config/swayosd/config.toml" && \
   ! grep -v '^[[:space:]]*#' "${SCRIPT_DIR}/skel/.config/swayosd/config.toml" | grep -q '~/' && \
   python3 -c "import tomllib, pathlib; d = tomllib.loads(pathlib.Path('${SCRIPT_DIR}/skel/.config/swayosd/config.toml').read_text()); assert 'client' not in d and d['server']['max_volume'] == 100 and 'style' not in d['server']" 2>/dev/null; then
    log_pass "swayosd config.toml enforces max_volume = 100 without unknown [client] fields or unexpanded ~/"
else
    log_fail "swayosd config.toml contains invalid [client] section or unexpanded ~/"
fi

# ==============================================================================
# 4. ZERO AI SLOP & APPLE INDUSTRIAL TITANIUM PALETTE AUDIT
# ==============================================================================
section "[4/8] Zero AI Slop & Apple Industrial Titanium Palette Verification"

if grep -rnE "[🚀✨🔥✅⚡]" \
    "${SCRIPT_DIR}/silicy-ctl" \
    "${SCRIPT_DIR}/scripts" \
    "${SCRIPT_DIR}/storage" \
    "${SCRIPT_DIR}/input" \
    "${SCRIPT_DIR}/skel" \
    "${SCRIPT_DIR}/services" \
    "${SCRIPT_DIR}/cachy-arm64" \
    "${SCRIPT_DIR}/installer" \
    "${SCRIPT_DIR}/kernel" \
    "${SCRIPT_DIR}/memory" \
    "${SCRIPT_DIR}/rootfs" \
    "${SCRIPT_DIR}/branding" \
    "${SCRIPT_DIR}/build-silicyos.sh" >/dev/null 2>&1; then
    log_fail "Prohibited emoji detected in source/config files!"
else
    log_pass "Zero prohibited emojis found across source, scripts, installer, kernel, and configs"
fi

if grep -rnIE --exclude="verify-silicyos.sh" --exclude="*.zip" --exclude="*.png" --exclude="*.bmp" \
    "while true;[[:space:]]*do[[:space:]]*cat /sys" "${SCRIPT_DIR}" >/dev/null 2>&1; then
    log_fail "Prohibited bash sysfs polling loop detected!"
else
    log_pass "Zero bash sysfs polling loops (telemetry handled in pure C via silicy-ctl)"
fi

for hex_col in "0B0B0E" "141418" "26262E" "F2F2F7" "8E8E93" "0A84FF"; do
    if grep -qi "${hex_col}" "${SCRIPT_DIR}/skel/.config/waybar/style.css" && \
       grep -qi "${hex_col}" "${SCRIPT_DIR}/skel/.config/swayosd/style.css" && \
       grep -qi "${hex_col}" "${SCRIPT_DIR}/skel/.config/kitty/kitty.conf"; then
        log_pass "Apple Industrial Titanium color #${hex_col} verified across Waybar, SwayOSD & Kitty"
    else
        log_fail "Missing Apple Industrial Titanium color #${hex_col} in UI theme files"
    fi
done

if grep -qx 'ANSI_COLOR="38;2;10;132;255"' "${SCRIPT_DIR}/build-silicyos.sh"; then
    log_pass "build-silicyos.sh os-release ANSI_COLOR uses Apple Industrial Titanium #0A84FF (38;2;10;132;255)"
else
    log_fail "build-silicyos.sh os-release ANSI_COLOR is not Apple Industrial Titanium 38;2;10;132;255"
fi

if command -v jq >/dev/null 2>&1; then
    if jq -e '.logo.color["1"] == "38;2;242;242;247" and .display.color.keys == "38;2;10;132;255" and .display.color.title == "38;2;242;242;247"' "${SCRIPT_DIR}/skel/.config/fastfetch/config.jsonc" >/dev/null 2>&1; then
        log_pass "fastfetch/config.jsonc uses Apple Industrial Titanium RGB codes (38;2;10;132;255 & 38;2;242;242;247)"
    else
        log_fail "fastfetch/config.jsonc contains non-Titanium RGB color values"
    fi
fi

LEGACY_COLOR_HITS="$(grep -rnIEi --exclude="verify-silicyos.sh" --exclude="*.zip" --exclude="*.png" --exclude="*.bmp" \
    "125[;:]207[;:]255|242[;:]245[;:]250|242[;:]244[;:]248|7dcfff|7aa2f7|1a1b26|24283b|c0caf5|bb9af7|f7768e|e0af68|9ece6a|2ac3de|414868|565f89|cfc9c2|a9b1d6" \
    "${SCRIPT_DIR}" || true)"
LEGACY_NONBRANDING_HEX="$(grep -rnIEi --exclude="verify-silicyos.sh" --exclude="*.zip" --exclude="*.png" --exclude="*.bmp" \
    "f2f5fa|f2f4f8" \
    "${SCRIPT_DIR}/skel" "${SCRIPT_DIR}/scripts" "${SCRIPT_DIR}/installer" "${SCRIPT_DIR}/build-silicyos.sh" \
    "${SCRIPT_DIR}/silicy-ctl" "${SCRIPT_DIR}/services" "${SCRIPT_DIR}/storage" "${SCRIPT_DIR}/input" || true)"
if [[ -n "${LEGACY_COLOR_HITS}" || -n "${LEGACY_NONBRANDING_HEX}" ]]; then
    log_fail "Legacy TokyoNight color code detected: $(printf '%s %s' "${LEGACY_COLOR_HITS}" "${LEGACY_NONBRANDING_HEX}" | tr '\n' ' ')"
else
    log_pass "Zero legacy TokyoNight color codes remain across source, installer, and UI configs"
fi

# ==============================================================================
# 5. BOOTLOADER, MKINITCPIO & BTRFS SUBVOLUME CONSISTENCY
# ==============================================================================
section "[5/8] Bootloader, Early-Boot Initramfs & Btrfs Subvolume Check"

if grep -q "rootflags=subvol=@,compress-force=zstd:3" "${SCRIPT_DIR}/build-silicyos.sh" && \
   grep -q 'subvol=@' "${SCRIPT_DIR}/storage/setup-btrfs-silicy.sh" && \
   grep -q 'subvol=@snapshots' "${SCRIPT_DIR}/storage/setup-btrfs-silicy.sh"; then
    log_pass "Kernel cmdline rootflags=subvol=@,compress-force=zstd:3 & @snapshots match setup-btrfs-silicy.sh"
else
    log_fail "Subvolume / zstd:3 mismatch between bootloader cmdline and setup-btrfs-silicy.sh"
fi

for mod in apple-mailbox nvme_apple nvme simpledrm btrfs; do
    if grep -E "MODULES=\(.*${mod}.*\)" "${SCRIPT_DIR}/build-silicyos.sh" >/dev/null 2>&1; then
        log_pass "mkinitcpio.conf MODULES includes Apple Silicon early-boot module: ${mod}"
    else
        log_fail "mkinitcpio.conf MODULES missing critical boot module: ${mod}"
    fi
done

if grep -E "HOOKS=\(.*btrfs.*\)" "${SCRIPT_DIR}/build-silicyos.sh" >/dev/null 2>&1; then
    log_pass "mkinitcpio.conf HOOKS includes 'btrfs' hook"
else
    log_fail "mkinitcpio.conf HOOKS missing 'btrfs' hook"
fi

# ==============================================================================
# 6. PACMAN NOEXTRACT, 16KB PAGE SIZE, BORE SCHEDULER & ZERO X86 FLAGS
# ==============================================================================
section "[6/8] Pacman NoExtract, 16KB Page Size, CachyOS BORE & ARM64 Audit"

PACMAN_CONF="${SCRIPT_DIR}/rootfs/pacman-silicy.conf"
for pattern in "!usr/lib/firmware/brcm/\*" "!usr/lib/firmware/apple/\*" "!usr/lib/firmware/vendor/\*" "!usr/lib/firmware/regulatory.db\*" "!usr/lib/asahi-boot/\*"; do
    if grep -q "${pattern}" "${PACMAN_CONF}"; then
        log_pass "pacman-silicy.conf whitelists: ${pattern}"
    else
        log_fail "pacman-silicy.conf blocks critical Asahi path (missing ${pattern})"
    fi
done

if grep -Eq '^\s*\[silicy-local\]' "${PACMAN_CONF}"; then
    log_fail "pacman-silicy.conf has active [silicy-local] repo that breaks cold pacstrap"
else
    log_pass "pacman-silicy.conf has no uninitialized local file:// repo blocking pacstrap"
fi

KCONFIG="${SCRIPT_DIR}/kernel/config.silicy"
for kopt in "CONFIG_ARM64_16K_PAGES=y" "CONFIG_ARM64_PAGE_SHIFT=14" "CONFIG_SCHED_BORE=y" "CONFIG_LTO_CLANG_THIN=y" "CONFIG_HZ_1000=y"; do
    if grep -qx "${kopt}" "${KCONFIG}"; then
        log_pass "kernel/config.silicy enforces: ${kopt}"
    else
        log_fail "kernel/config.silicy missing mandatory option: ${kopt}"
    fi
done

if grep -E "march=x86|x86-64|x86_64|-msse|-mavx" "${SCRIPT_DIR}/kernel/PKGBUILD" "${SCRIPT_DIR}/cachy-arm64/makepkg-silicy.conf" "${KCONFIG}" >/dev/null 2>&1; then
    log_fail "Foreign x86 compiler flags detected in ARM64 build configs!"
else
    log_pass "Zero x86 flags found in PKGBUILD, makepkg-silicy.conf, and config.silicy"
fi

if grep -Eq '^\s*vm\.page-cluster\s*=\s*0' "${SCRIPT_DIR}/cachy-arm64/silicy-core-tuning/99-silicy-cachyos.conf"; then
    log_pass "99-silicy-cachyos.conf enforces vm.page-cluster = 0 for 16KB Page ZRAM"
else
    log_fail "99-silicy-cachyos.conf missing vm.page-cluster = 0"
fi

# ==============================================================================
# 7. WAYLAND RICE SYNTAX, JSON/KDL/TOML & INSTALLER SCHEMA CHECK
# ==============================================================================
section "[7/8] Wayland Rice Syntax (JSON/KDL/TOML) & Asahi Installer Schema"

WAYBAR_CFG="${SCRIPT_DIR}/skel/.config/waybar/config.jsonc"
FASTFETCH_CFG="${SCRIPT_DIR}/skel/.config/fastfetch/config.jsonc"
NIRI_CFG="${SCRIPT_DIR}/skel/.config/niri/config.kdl"
HYPR_CFG="${SCRIPT_DIR}/skel/.config/hypr/hyprland.conf"
SWAYOSD_TOML="${SCRIPT_DIR}/skel/.config/swayosd/config.toml"

if command -v jq >/dev/null 2>&1; then
    if sed 's|//.*||g' "${WAYBAR_CFG}" | jq empty >/dev/null 2>&1; then
        log_pass "Waybar config.jsonc is valid JSON/JSONC"
    else
        log_fail "Waybar config.jsonc failed jq JSON validation"
    fi
    if jq empty "${FASTFETCH_CFG}" >/dev/null 2>&1; then
        log_pass "Fastfetch config.jsonc is valid JSON"
    else
        log_fail "Fastfetch config.jsonc failed jq JSON validation"
    fi
fi

if command -v python3 >/dev/null 2>&1; then
    if python3 -c "import tomllib, pathlib; tomllib.loads(pathlib.Path('${SWAYOSD_TOML}').read_text())" 2>/dev/null; then
        log_pass "swayosd/config.toml is valid TOML (verified via python3 tomllib)"
    else
        log_fail "swayosd/config.toml failed TOML validation"
    fi
fi

if grep -q "/sys/class/power_supply/macsmc-battery/power_now" "${WAYBAR_CFG}" && \
   grep -q "/sys/class/hwmon/hwmon\*/temp1_input" "${WAYBAR_CFG}" && \
   grep -q "silicy-ctl telemetry" "${WAYBAR_CFG}"; then
    log_pass "Waybar integrates silicy-ctl telemetry & documents Apple SMC sysfs paths"
else
    log_fail "Waybar missing silicy-ctl telemetry or Apple SMC sysfs references"
fi

if grep -q "Mod+Ctrl+Space" "${NIRI_CFG}" && grep -q "Mod+Slash" "${NIRI_CFG}" && \
   grep -q '\$mainMod CTRL, Space' "${HYPR_CFG}" && grep -q '\$mainMod, slash' "${HYPR_CFG}"; then
    log_pass "Both Niri and Hyprland bind Super+Ctrl+Space (silicy-center) and Super+/ (Shortcut Guide)"
else
    log_fail "Missing Super+Ctrl+Space or Super+/ bindings in Niri or Hyprland"
fi

NIRI_OPEN="$(tr -cd '{' < "${NIRI_CFG}" | wc -c | tr -d ' ')"
NIRI_CLOSE="$(tr -cd '}' < "${NIRI_CFG}" | wc -c | tr -d ' ')"
if [[ "${NIRI_OPEN}" -eq "${NIRI_CLOSE}" && "${NIRI_OPEN}" -gt 0 ]]; then
    log_pass "niri/config.kdl KDL block braces are balanced (${NIRI_OPEN} blocks)"
else
    log_fail "niri/config.kdl has unbalanced braces (open=${NIRI_OPEN}, close=${NIRI_CLOSE})"
fi

INSTALLER_JSON="${SCRIPT_DIR}/installer/installer_data.json"
if command -v jq >/dev/null 2>&1; then
    if jq -e '.os_list[0].partitions | length == 2' "${INSTALLER_JSON}" >/dev/null 2>&1 && \
       jq -e '.os_list[0].partitions[0].type == "EFI"' "${INSTALLER_JSON}" >/dev/null 2>&1 && \
       jq -e '.os_list[0].partitions[1].type == "Linux"' "${INSTALLER_JSON}" >/dev/null 2>&1; then
        log_pass "installer_data.json schema has valid os_list, EFI partition, and Linux partition"
    else
        log_fail "installer_data.json schema is malformed"
    fi

    LINUX_SIZE_STR="$(jq -r '.os_list[0].partitions[1].size' "${INSTALLER_JSON}")"
    ROOTFS_MB="$(sed -n 's/^ROOTFS_SIZE_MB=\([0-9]*\)/\1/p' "${SCRIPT_DIR}/build-silicyos.sh")"
    EXPECTED_BYTES=$(( ROOTFS_MB * 1024 * 1024 ))

    if [[ "${LINUX_SIZE_STR}" == "${EXPECTED_BYTES}B" ]]; then
        log_pass "installer_data.json Linux partition size (${LINUX_SIZE_STR}) matches ROOTFS_SIZE_MB (${ROOTFS_MB} MiB = ${EXPECTED_BYTES} bytes)"
    else
        log_fail "installer_data.json Linux partition size (${LINUX_SIZE_STR}) mismatches ROOTFS_SIZE_MB (${EXPECTED_BYTES}B)"
    fi
fi

# ==============================================================================
# 8. DRY-RUN STAGING & ASAHI PAYLOAD PACKAGING SIMULATION
# ==============================================================================
section "[8/8] Dry-Run Rootfs Staging & Asahi Zip Packaging Simulation"

STAGE_SIM="${DRYRUN_DIR}/stage-rootfs"
IMG_SIM="${DRYRUN_DIR}/images"
mkdir -p "${STAGE_SIM}/etc/skel/.config" \
         "${STAGE_SIM}/etc/sysctl.d" \
         "${STAGE_SIM}/etc/udev/rules.d" \
         "${STAGE_SIM}/etc/ananicy.d" \
         "${STAGE_SIM}/etc/pacman.d/hooks" \
         "${STAGE_SIM}/etc/systemd" \
         "${STAGE_SIM}/etc/default" \
         "${STAGE_SIM}/etc/keyd" \
         "${STAGE_SIM}/etc/sudoers.d" \
         "${STAGE_SIM}/usr/share/silicyos/keyd" \
         "${STAGE_SIM}/usr/local/bin" \
         "${STAGE_SIM}/usr/local/sbin" \
         "${STAGE_SIM}/usr/lib/firmware/vendor" \
         "${IMG_SIM}/esp/EFI/BOOT" \
         "${IMG_SIM}/esp/loader/entries" \
         "${IMG_SIM}/esp/m1n1"

# Simulate Step 2 file installations (portable across GNU & BSD/macOS install)
install -m 0644 "${SCRIPT_DIR}/rootfs/pacman-silicy.conf" "${STAGE_SIM}/etc/pacman.conf"
install -m 0644 "${SCRIPT_DIR}/cachy-arm64/makepkg-silicy.conf" "${STAGE_SIM}/etc/makepkg.conf"
install -m 0644 "${SCRIPT_DIR}/cachy-arm64/silicy-core-tuning/99-silicy-cachyos.conf" "${STAGE_SIM}/etc/sysctl.d/99-silicy-cachyos.conf"
install -m 0644 "${SCRIPT_DIR}/cachy-arm64/silicy-core-tuning/70-silicy-io.rules" "${STAGE_SIM}/etc/udev/rules.d/70-silicy-io.rules"
install -m 0644 "${SCRIPT_DIR}/silicy-ctl/71-silicy-macsmc.rules" "${STAGE_SIM}/etc/udev/rules.d/71-silicy-macsmc.rules"
install -m 0664 "${SCRIPT_DIR}/silicy-ctl/silicy-battery.conf" "${STAGE_SIM}/etc/silicy-battery.conf"
install -m 0644 "${SCRIPT_DIR}/cachy-arm64/silicy-core-tuning/ananicy-silicy.rules" "${STAGE_SIM}/etc/ananicy.d/99-silicy-overrides.rules"
install -m 0644 "${SCRIPT_DIR}/storage/00-silicy-capsule-pre.hook" "${STAGE_SIM}/etc/pacman.d/hooks/00-silicy-capsule-pre.hook"
install -m 0644 "${SCRIPT_DIR}/storage/99-clean-cache-and-recompress.hook" "${STAGE_SIM}/etc/pacman.d/hooks/99-clean-cache-and-recompress.hook"
install -m 0755 "${SCRIPT_DIR}/storage/setup-btrfs-silicy.sh" "${STAGE_SIM}/usr/local/sbin/setup-btrfs-silicy.sh"
install -m 0755 "${SCRIPT_DIR}/storage/silicy-capsule" "${STAGE_SIM}/usr/local/bin/silicy-capsule"
install -m 0755 "${SCRIPT_DIR}/storage/silicy-macos-bridge" "${STAGE_SIM}/usr/local/bin/silicy-macos-bridge"
install -m 0755 "${SCRIPT_DIR}/scripts/silicy-center" "${STAGE_SIM}/usr/local/bin/silicy-center"
install -m 0755 "${CTL_BIN}" "${STAGE_SIM}/usr/local/bin/silicy-ctl"
install -m 0664 "${SCRIPT_DIR}/input/keyd/default.conf" "${STAGE_SIM}/etc/keyd/default.conf"
install -m 0644 "${SCRIPT_DIR}/input/keyd/mac-mode.conf" "${STAGE_SIM}/usr/share/silicyos/keyd/mac-mode.conf"
install -m 0644 "${SCRIPT_DIR}/input/keyd/pc-mode.conf" "${STAGE_SIM}/usr/share/silicyos/keyd/pc-mode.conf"
install -m 0644 "${SCRIPT_DIR}/memory/zram-generator.conf" "${STAGE_SIM}/etc/systemd/zram-generator.conf"
install -m 0644 "${SCRIPT_DIR}/memory/earlyoom.conf" "${STAGE_SIM}/etc/default/earlyoom"
install -m 0755 "${SCRIPT_DIR}/installer/silicy-setup-tui.sh" "${STAGE_SIM}/usr/local/sbin/silicy-setup-tui.sh"
cp -a "${SCRIPT_DIR}/skel/.config/." "${STAGE_SIM}/etc/skel/.config/"
ln -sf ".config/zsh/.zshrc" "${STAGE_SIM}/etc/skel/.zshrc"

KEYD_CONF_COUNT="$(find "${STAGE_SIM}/etc/keyd" -maxdepth 1 -name '*.conf' | wc -l | tr -d ' ')"
if [[ "${KEYD_CONF_COUNT}" -eq 1 && -f "${STAGE_SIM}/etc/keyd/default.conf" ]]; then
    log_pass "Staged /etc/keyd/ holds strictly 1 active config (default.conf; presets isolated)"
else
    log_fail "Staged /etc/keyd/ contains multiple/missing *.conf files (${KEYD_CONF_COUNT})"
fi

for staged_bin in \
    "/usr/local/bin/silicy-ctl" \
    "/usr/local/bin/silicy-center" \
    "/usr/local/bin/silicy-capsule" \
    "/usr/local/bin/silicy-macos-bridge" \
    "/usr/local/sbin/setup-btrfs-silicy.sh" \
    "/usr/local/sbin/silicy-setup-tui.sh"; do
    if [[ -x "${STAGE_SIM}${staged_bin}" ]]; then
        log_pass "Staged binary/script is executable (+x): ${staged_bin}"
    else
        log_fail "Staged binary/script missing executable permission: ${staged_bin}"
    fi
done

# Simulate Step 3 & Step 4 Asahi payload creation
touch "${IMG_SIM}/esp/m1n1/boot.bin" \
      "${IMG_SIM}/esp/u-boot-nodtb.bin" \
      "${IMG_SIM}/esp/Image" \
      "${IMG_SIM}/esp/initramfs-linux.img" \
      "${IMG_SIM}/esp/loader/loader.conf" \
      "${IMG_SIM}/esp/loader/entries/silicyos.conf"
truncate -s 1M "${IMG_SIM}/esp.img"
truncate -s 1M "${IMG_SIM}/rootfs.img"
cp -f "${SCRIPT_DIR}/installer/installer_data.json" "${IMG_SIM}/installer_data.json"

DRYRUN_ZIP="${DRYRUN_DIR}/silicyos-apple-silicon-dryrun.zip"
(
    cd "${IMG_SIM}"
    zip -q -r -1 "${DRYRUN_ZIP}" esp/ esp.img rootfs.img installer_data.json
)

unzip -l "${DRYRUN_ZIP}" > "${DRYRUN_DIR}/zip-manifest.txt"
if [[ -s "${DRYRUN_ZIP}" ]] && \
   grep -q "esp/m1n1/boot.bin" "${DRYRUN_DIR}/zip-manifest.txt" && \
   grep -q "rootfs.img" "${DRYRUN_DIR}/zip-manifest.txt" && \
   grep -q "installer_data.json" "${DRYRUN_DIR}/zip-manifest.txt"; then
    log_pass "Dry-run Asahi installer bundle packaged & verified (${DRYRUN_ZIP##*/})"
else
    log_fail "Dry-run Asahi installer bundle failed verification"
fi

# Clean up build artifact in silicy-ctl/ after test
make -C "${SCRIPT_DIR}/silicy-ctl" clean >/dev/null 2>&1 || true

printf "\n==============================================================================\n"
printf "  AUDIT SUMMARY: ${C_GREEN}%d PASS${C_RESET} | ${C_YELLOW}%d WARN${C_RESET} | ${C_RED}%d FAIL${C_RESET}\n" "${PASS_COUNT}" "${WARN_COUNT}" "${FAIL_COUNT}"
printf "==============================================================================\n"

[[ "${FAIL_COUNT}" -eq 0 ]]
