#!/usr/bin/env bash
# ==============================================================================
# silicyOS Master Build & Asahi Payload Packaging Pipeline
# Target: Apple Silicon M1/M2/M3 (Arch Linux ARM64 + CachyOS BORE/LTO + 16K Page)
# Output: silicyos-apple-silicon.zip (Ready for macOS asahi-installer)
# ==============================================================================
set -euo pipefail

# --- Build Paths & Image Constants ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${WORK_DIR:-/var/tmp/silicyos-work}"
STAGE_ROOT="${WORK_DIR}/stage-rootfs"
MNT_DIR="${WORK_DIR}/mnt"
IMG_DIR="${WORK_DIR}/images"
OUT_ZIP="${SCRIPT_DIR}/silicyos-apple-silicon.zip"

ESP_IMG="${IMG_DIR}/esp.img"
ROOTFS_IMG="${IMG_DIR}/rootfs.img"
ESP_SIZE_MB=500
ROOTFS_SIZE_MB=8192

LOOP_ESP=""
LOOP_ROOT=""

# --- Cleanup Trap ---
cleanup() {
    set +e
    echo "[CLEANUP] Unmounting filesystems and detaching loop devices..."
    if mountpoint -q "${MNT_DIR}/boot/efi" 2>/dev/null; then umount -R "${MNT_DIR}/boot/efi"; fi
    if mountpoint -q "${MNT_DIR}" 2>/dev/null; then umount -R "${MNT_DIR}"; fi
    if mountpoint -q "${STAGE_ROOT}" 2>/dev/null; then umount -R "${STAGE_ROOT}"; fi
    [[ -n "${LOOP_ESP}" ]] && losetup -d "${LOOP_ESP}" 2>/dev/null || true
    [[ -n "${LOOP_ROOT}" ]] && losetup -d "${LOOP_ROOT}" 2>/dev/null || true
}
trap cleanup EXIT

# --- Pre-flight Verification ---
if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] build-silicyos.sh must be executed as root." >&2
    exit 1
fi

if [[ "$(uname -m)" != "aarch64" ]]; then
    echo "[WARN] Host architecture is $(uname -m); ensure binfmt_misc/qemu-user-static is active for aarch64 chroot."
fi

for cmd in pacstrap arch-chroot mkfs.fat mkfs.btrfs btrfs losetup blkid zip rsync; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "[ERROR] Required build tool '${cmd}' is not installed." >&2
        exit 1
    fi
done

rm -rf "${WORK_DIR}"
mkdir -p "${STAGE_ROOT}" "${MNT_DIR}" "${IMG_DIR}"

# ==============================================================================
# STEP 1: Bootstrap Minimal Base Rootfs with NoExtract & CachyOS-ARM64 Config
# ==============================================================================
echo "=============================================================================="
echo "[STEP 1/4] Bootstrapping silicyOS ARM64 Rootfs..."
echo "=============================================================================="

mapfile -t PKG_LIST < <(grep -vE '^\s*#|^\s*$' "${SCRIPT_DIR}/rootfs/packages.silicy")

if [[ -f /etc/pacman.d/mirrorlist.asahi-alarm ]] || [[ -f /etc/pacman.d/mirrorlist-asahi ]]; then
    pacstrap -C "${SCRIPT_DIR}/rootfs/pacman-silicy.conf" -c -G -M "${STAGE_ROOT}" "${PKG_LIST[@]}"
else
    SEED_CACHE_DIR="/var/tmp/silicyos-seed-cache"
    mkdir -p "${WORK_DIR}/esp-seed"
    if [[ -d "${SEED_CACHE_DIR}/rootfs/etc" ]]; then
        echo "  -> Using cached Asahi ALARM 16K ARM64 seed from ${SEED_CACHE_DIR}..."
        rsync -aHAX --numeric-ids "${SEED_CACHE_DIR}/rootfs/" "${STAGE_ROOT}/"
        if [[ -d "${SEED_CACHE_DIR}/esp-seed" ]]; then
            cp -a "${SEED_CACHE_DIR}/esp-seed/." "${WORK_DIR}/esp-seed/"
        fi
        cp -a "${STAGE_ROOT}/var/lib/pacman/sync/." "${SEED_CACHE_DIR}/rootfs/var/lib/pacman/sync/" 2>/dev/null || true
    else
        echo "  -> Non-Asahi builder host detected; seeding ARM64 base from ArchLinuxARM + Asahi GitHub Releases CDN..."
        SEED_TAR="${WORK_DIR}/ArchLinuxARM-aarch64-latest.tar.gz"
        SEED_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
        mkdir -p "${WORK_DIR}/seed" "${SEED_CACHE_DIR}/rootfs" "${SEED_CACHE_DIR}/esp-seed"
        if command -v aria2c >/dev/null 2>&1; then
            aria2c -x 8 -s 8 -k 1M --file-allocation=none --allow-overwrite=true \
                -d "${WORK_DIR}" -o "ArchLinuxARM-aarch64-latest.tar.gz" "${SEED_URL}"
        else
            curl -L --fail --retry 3 -o "${SEED_TAR}" "${SEED_URL}"
        fi

        if command -v bsdtar >/dev/null 2>&1; then
            bsdtar -xpf "${SEED_TAR}" -C "${STAGE_ROOT}"
        else
            tar --numeric-owner -xpf "${SEED_TAR}" -C "${STAGE_ROOT}"
        fi
        rm -f "${SEED_TAR}"

        mkdir -p "${STAGE_ROOT}/etc/pacman.d"
        cat <<'EOF' > "${STAGE_ROOT}/etc/pacman.d/mirrorlist.asahi-alarm"
# Asahi Linux repository mirrorlist (GitHub Releases CDN)
Server = https://github.com/asahi-alarm/asahi-alarm/releases/download/$arch
EOF

        rsync -aHAX --numeric-ids "${STAGE_ROOT}/" "${SEED_CACHE_DIR}/rootfs/"
    fi
fi

# Install silicyOS optimized pacman.conf and makepkg.conf
if [[ -f "${STAGE_ROOT}/etc/pacman.d/mirrorlist.asahi-alarm" ]]; then
    install -Dm644 "${SCRIPT_DIR}/rootfs/pacman-silicy.conf" "${STAGE_ROOT}/etc/pacman.conf"
elif [[ -f "${STAGE_ROOT}/etc/pacman.d/mirrorlist-asahi" ]]; then
    install -Dm644 "${SCRIPT_DIR}/rootfs/pacman-silicy.conf" "${STAGE_ROOT}/etc/pacman.conf"
    sed -i 's|/etc/pacman.d/mirrorlist.asahi-alarm|/etc/pacman.d/mirrorlist-asahi|g' "${STAGE_ROOT}/etc/pacman.conf"
else
    # Inject NoExtract rules into the seeded Asahi ALARM pacman.conf
    cp -a "${SCRIPT_DIR}/rootfs/pacman-silicy.conf" "${STAGE_ROOT}/etc/pacman-silicy.conf"
    sed -n '/^# ULTRA-COMPACT NOEXTRACT RULES/,/^# REPOSITORIES/p' "${SCRIPT_DIR}/rootfs/pacman-silicy.conf" \
        | sed '$d' > "${STAGE_ROOT}/etc/pacman-noextract.conf"
    if ! grep -q "pacman-noextract.conf" "${STAGE_ROOT}/etc/pacman.conf"; then
        sed -i '/^\[options\]/a Include = /etc/pacman-noextract.conf' "${STAGE_ROOT}/etc/pacman.conf"
    fi
fi
# Ensure DisableSandbox is active and CheckSpace is disabled during chroot package installation
if ! grep -q "^DisableSandbox" "${STAGE_ROOT}/etc/pacman.conf"; then
    sed -i '/^\[options\]/a DisableSandbox' "${STAGE_ROOT}/etc/pacman.conf"
fi
sed -i 's/^CheckSpace/#CheckSpace/' "${STAGE_ROOT}/etc/pacman.conf"
install -Dm644 "${SCRIPT_DIR}/cachy-arm64/makepkg-silicy.conf" "${STAGE_ROOT}/etc/makepkg.conf"

# Ensure DNS resolution inside chroot and install available silicyOS packages
rm -f "${STAGE_ROOT}/etc/resolv.conf"
cp -L /etc/resolv.conf "${STAGE_ROOT}/etc/resolv.conf"

arch-chroot "${STAGE_ROOT}" /bin/bash -c "
    set -e
    pacman-key --init 2>/dev/null || true
    pacman-key --populate archlinuxarm 2>/dev/null || pacman-key --populate 2>/dev/null || true
    if ! pacman -Q asahi-alarm-keyring >/dev/null 2>&1; then
        sed 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf > /tmp/pacman-asahi-bootstrap.conf
        pacman --config /tmp/pacman-asahi-bootstrap.conf -Sy --noconfirm asahi-alarm-keyring 2>/dev/null || true
        rm -f /tmp/pacman-asahi-bootstrap.conf
    fi
    pacman-key --populate archlinuxarm asahi-alarm asahi 2>/dev/null || pacman-key --populate 2>/dev/null || true
    pacman -Sy --noconfirm
    pacman -Rdd --noconfirm systemd-resolvconf 2>/dev/null || true
    AVAIL_PKGS=\$(comm -12 <(pacman -Slq | sort -u) <(printf '%s\n' ${PKG_LIST[*]} | sort -u))
    if [[ -n \"\${AVAIL_PKGS}\" ]]; then
        yes | pacman -Syu --needed \${AVAIL_PKGS}
    fi
    if ! command -v apfs-fuse >/dev/null 2>&1 && ! command -v fsapfsmount >/dev/null 2>&1; then
        echo '[INFO] apfs-fuse not found in pacman binary repos; building Read-Only APFS FUSE driver from source...'
        pacman -S --noconfirm --needed clang cmake git make pkgconf bzip2 zlib attr fuse3 >/dev/null || true
        rm -rf /tmp/apfs-fuse-src
        if git clone --depth 1 https://github.com/sgan81/apfs-fuse.git /tmp/apfs-fuse-src; then
            git -C /tmp/apfs-fuse-src submodule update --init --recursive --depth 1
            cmake -S /tmp/apfs-fuse-src -B /tmp/apfs-fuse-src/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DUSE_FUSE3=ON
            cmake --build /tmp/apfs-fuse-src/build -j\"\$(nproc)\"
            install -Dm755 /tmp/apfs-fuse-src/build/apfs-fuse /usr/local/bin/apfs-fuse
            if [ -f /tmp/apfs-fuse-src/build/apfsutil ]; then
                install -Dm755 /tmp/apfs-fuse-src/build/apfsutil /usr/local/bin/apfsutil
            fi
            rm -rf /tmp/apfs-fuse-src
        else
            echo '[WARN] Failed to clone sgan81/apfs-fuse fallback; macOS APFS bridge will check fsapfsmount/kernel module.' >&2
        fi
    fi
"
mkdir -p "${STAGE_ROOT}/etc"
if [[ -f "${STAGE_ROOT}/etc/fuse.conf" ]]; then
    sed -i 's/^[#[:space:]]*user_allow_other/user_allow_other/' "${STAGE_ROOT}/etc/fuse.conf"
    grep -qx 'user_allow_other' "${STAGE_ROOT}/etc/fuse.conf" || echo 'user_allow_other' >> "${STAGE_ROOT}/etc/fuse.conf"
else
    echo 'user_allow_other' > "${STAGE_ROOT}/etc/fuse.conf"
fi
mkdir -p "/var/tmp/silicyos-seed-cache/rootfs/var/lib/pacman/sync" "/var/tmp/silicyos-seed-cache/rootfs/var/cache/pacman/pkg"
cp -a "${STAGE_ROOT}/var/lib/pacman/sync/." "/var/tmp/silicyos-seed-cache/rootfs/var/lib/pacman/sync/" 2>/dev/null || true
cp -a "${STAGE_ROOT}/var/cache/pacman/pkg/." "/var/tmp/silicyos-seed-cache/rootfs/var/cache/pacman/pkg/" 2>/dev/null || true
sed -i 's/^#CheckSpace/CheckSpace/' "${STAGE_ROOT}/etc/pacman.conf"

# ==============================================================================
# STEP 2: Install linux-silicy-asahi Kernel, Tuning Configs, Dotfiles & Diet
# ==============================================================================
echo "=============================================================================="
echo "[STEP 2/4] Installing linux-silicy-asahi (16K BORE+LTO) & System Configurations"
echo "=============================================================================="

# 2.1 Install prebuilt linux-silicy-asahi package if present, or build from PKGBUILD when BUILD_CUSTOM_KERNEL=1
shopt -s nullglob
KERNEL_PKGS=("${SCRIPT_DIR}/kernel/"linux-silicy-asahi-*.pkg.tar.*)
shopt -u nullglob

if (( ${#KERNEL_PKGS[@]} == 0 )) && [[ "${BUILD_CUSTOM_KERNEL:-0}" == "1" ]]; then
    echo "  -> Compiling linux-silicy-asahi kernel with Clang Full LTO + BORE..."
    install -d -m 0777 "${WORK_DIR}/kbuild"
    cp -a "${SCRIPT_DIR}/kernel/PKGBUILD" "${SCRIPT_DIR}/kernel/config.silicy" "${WORK_DIR}/kbuild/"
    su - nobody -s /bin/bash -c "cd '${WORK_DIR}/kbuild' && MAKEFLAGS=\"-j\$(nproc)\" makepkg --config '${SCRIPT_DIR}/cachy-arm64/makepkg-silicy.conf' -sf --noconfirm"
    shopt -s nullglob
    KERNEL_PKGS=("${WORK_DIR}/kbuild/"linux-silicy-asahi-*.pkg.tar.*)
    shopt -u nullglob
fi

if (( ${#KERNEL_PKGS[@]} > 0 )); then
    cp -a "${KERNEL_PKGS[@]}" "${STAGE_ROOT}/var/cache/pacman/pkg/"
    arch-chroot "${STAGE_ROOT}" pacman -U --noconfirm /var/cache/pacman/pkg/linux-silicy-asahi-*.pkg.tar.*
    rm -f "${STAGE_ROOT}/var/cache/pacman/pkg/"linux-silicy-asahi-*.pkg.tar.*
else
    echo "[INFO] Using prebuilt Asahi 16K Page Size kernel (linux-asahi)..."
    arch-chroot "${STAGE_ROOT}" pacman -S --noconfirm --needed linux-asahi || true
fi

# 2.2 Install CachyOS-ARM64 Sysctl, NVMe I/O Udev Rules & Ananicy-Cpp P/E-Core Rules
install -Dm644 "${SCRIPT_DIR}/cachy-arm64/silicy-core-tuning/99-silicy-cachyos.conf" \
    "${STAGE_ROOT}/etc/sysctl.d/99-silicy-cachyos.conf"
install -Dm644 "${SCRIPT_DIR}/cachy-arm64/silicy-core-tuning/70-silicy-io.rules" \
    "${STAGE_ROOT}/etc/udev/rules.d/70-silicy-io.rules"
mkdir -p "${STAGE_ROOT}/etc/ananicy.d"

if [[ -d "${SCRIPT_DIR}/cachy-arm64/silicy-core-tuning/ananicy-cpp" ]]; then
    cp -a "${SCRIPT_DIR}/cachy-arm64/silicy-core-tuning/ananicy-cpp/"*.cgroups "${STAGE_ROOT}/etc/ananicy.d/" 2>/dev/null || true
    cp -a "${SCRIPT_DIR}/cachy-arm64/silicy-core-tuning/ananicy-cpp/"*.types "${STAGE_ROOT}/etc/ananicy.d/" 2>/dev/null || true
    cp -a "${SCRIPT_DIR}/cachy-arm64/silicy-core-tuning/ananicy-cpp/"*.rules "${STAGE_ROOT}/etc/ananicy.d/" 2>/dev/null || true
    install -Dm644 "${SCRIPT_DIR}/cachy-arm64/silicy-core-tuning/ananicy-cpp/ananicy.conf" \
        "${STAGE_ROOT}/etc/ananicy.d/ananicy.conf" 2>/dev/null || true
    install -Dm755 "${SCRIPT_DIR}/cachy-arm64/silicy-core-tuning/ananicy-cpp/silicy-pe-enforcer.sh" \
        "${STAGE_ROOT}/usr/local/bin/silicy-pe-enforcer.sh" 2>/dev/null || true
    install -Dm644 "${SCRIPT_DIR}/cachy-arm64/silicy-core-tuning/ananicy-cpp/silicy-pe-enforcer.service" \
        "${STAGE_ROOT}/etc/systemd/system/silicy-pe-enforcer.service" 2>/dev/null || true
fi

install -Dm644 "${SCRIPT_DIR}/cachy-arm64/silicy-core-tuning/ananicy-silicy.rules" \
    "${STAGE_ROOT}/etc/ananicy.d/99-silicy-overrides.rules"

# 2.3 Install Btrfs Pacman Hooks, Zero-Space Capsule, macOS APFS Bridge & Provisioning Helper
install -Dm644 "${SCRIPT_DIR}/storage/00-silicy-capsule-pre.hook" \
    "${STAGE_ROOT}/etc/pacman.d/hooks/00-silicy-capsule-pre.hook"
install -Dm644 "${SCRIPT_DIR}/storage/99-clean-cache-and-recompress.hook" \
    "${STAGE_ROOT}/etc/pacman.d/hooks/99-clean-cache-and-recompress.hook"
install -Dm755 "${SCRIPT_DIR}/storage/setup-btrfs-silicy.sh" \
    "${STAGE_ROOT}/usr/local/sbin/setup-btrfs-silicy.sh"
install -Dm755 "${SCRIPT_DIR}/storage/silicy-capsule" \
    "${STAGE_ROOT}/usr/local/bin/silicy-capsule"
install -Dm755 "${SCRIPT_DIR}/storage/silicy-macos-bridge" \
    "${STAGE_ROOT}/usr/local/bin/silicy-macos-bridge"

# 2.3b Compile & Install Pure-C Apple SMC Controller (silicy-ctl), Udev Rules & Interactive Control Center
install -Dm644 "${SCRIPT_DIR}/silicy-ctl/silicy-ctl.c" \
    "${STAGE_ROOT}/usr/src/silicy-ctl/silicy-ctl.c"
install -Dm644 "${SCRIPT_DIR}/silicy-ctl/Makefile" \
    "${STAGE_ROOT}/usr/src/silicy-ctl/Makefile"
arch-chroot "${STAGE_ROOT}" /bin/bash -c "
    set -e
    cd /usr/src/silicy-ctl
    if command -v make >/dev/null 2>&1; then
        make clean all
        install -Dm755 /usr/src/silicy-ctl/silicy-ctl /usr/local/bin/silicy-ctl
        make clean
    else
        clang -std=c11 -O3 -mcpu=apple-m1 -flto=thin -Wall -Wextra -Werror -fno-plt -pipe -s -fuse-ld=lld -o /usr/local/bin/silicy-ctl silicy-ctl.c
        chmod 0755 /usr/local/bin/silicy-ctl
    fi
"
install -Dm644 "${SCRIPT_DIR}/silicy-ctl/71-silicy-macsmc.rules" \
    "${STAGE_ROOT}/etc/udev/rules.d/71-silicy-macsmc.rules"
install -Dm664 "${SCRIPT_DIR}/silicy-ctl/silicy-battery.conf" \
    "${STAGE_ROOT}/etc/silicy-battery.conf"
echo "balanced" > "${STAGE_ROOT}/etc/silicy-power-profile"
chmod 0664 "${STAGE_ROOT}/etc/silicy-power-profile"
install -Dm755 "${SCRIPT_DIR}/scripts/silicy-center" \
    "${STAGE_ROOT}/usr/local/bin/silicy-center"

# 2.3c Install Keyd Smart Command (⌘) Remapper Configs & Sudoers NOPASSWD Rule for Wheel
# NOTE: Only default.conf lives in /etc/keyd/ (keyd loads every *.conf in /etc/keyd simultaneously);
# preset templates reside under /usr/share/silicyos/keyd/.
install -Dm664 "${SCRIPT_DIR}/input/keyd/default.conf" \
    "${STAGE_ROOT}/etc/keyd/default.conf"
rm -f "${STAGE_ROOT}/etc/keyd/mac-mode.conf" "${STAGE_ROOT}/etc/keyd/pc-mode.conf"
install -Dm644 "${SCRIPT_DIR}/input/keyd/mac-mode.conf" \
    "${STAGE_ROOT}/usr/share/silicyos/keyd/mac-mode.conf"
install -Dm644 "${SCRIPT_DIR}/input/keyd/pc-mode.conf" \
    "${STAGE_ROOT}/usr/share/silicyos/keyd/pc-mode.conf"
echo "Mac (Command)" > "${STAGE_ROOT}/etc/silicy-kb-mode"
chmod 0664 "${STAGE_ROOT}/etc/silicy-kb-mode"

mkdir -p "${STAGE_ROOT}/etc/tmpfiles.d"
cat <<'EOF' > "${STAGE_ROOT}/etc/tmpfiles.d/silicyos.conf"
f /run/silicy-power-profile 0664 root wheel -
f /run/silicy-kb-mode 0664 root wheel -
EOF

mkdir -p "${STAGE_ROOT}/etc/sudoers.d"
cat <<'EOF' > "${STAGE_ROOT}/etc/sudoers.d/20-silicy-nopasswd"
%wheel ALL=(root) NOPASSWD: /usr/local/bin/silicy-ctl, /usr/local/bin/silicy-capsule, /usr/local/bin/silicy-macos-bridge, /usr/bin/keyd, /usr/bin/systemctl restart keyd.service
EOF
chmod 0440 "${STAGE_ROOT}/etc/sudoers.d/20-silicy-nopasswd"

# 2.4 Install Unified Memory ZRAM & EarlyOOM Configs
install -Dm644 "${SCRIPT_DIR}/memory/zram-generator.conf" \
    "${STAGE_ROOT}/etc/systemd/zram-generator.conf"
install -Dm644 "${SCRIPT_DIR}/memory/earlyoom.conf" \
    "${STAGE_ROOT}/etc/default/earlyoom"
install -Dm644 "${SCRIPT_DIR}/memory/zram-generator.conf" \
    "${STAGE_ROOT}/etc/silicyos/memory/zram-generator.conf"
install -Dm644 "${SCRIPT_DIR}/memory/earlyoom.conf" \
    "${STAGE_ROOT}/etc/silicyos/memory/earlyoom.conf"

# 2.5 Populate /etc/skel/.config/ with Apple Industrial Titanium Dotfiles & Branding
mkdir -p "${STAGE_ROOT}/etc/skel/.config"
cp -a "${SCRIPT_DIR}/skel/.config/." "${STAGE_ROOT}/etc/skel/.config/"
ln -sf ".config/zsh/.zshrc" "${STAGE_ROOT}/etc/skel/.zshrc"

# 2.5b Install Vectorized SVG Boot Logo, Plymouth Theme, Icons & Wallpaper
install -Dm644 "${SCRIPT_DIR}/branding/silicyos-logo.svg" \
    "${STAGE_ROOT}/usr/share/pixmaps/silicyos.svg"
install -Dm644 "${SCRIPT_DIR}/branding/silicyos-logo-mono.svg" \
    "${STAGE_ROOT}/usr/share/pixmaps/silicyos-mono.svg"
install -Dm644 "${SCRIPT_DIR}/branding/silicyos-logo.png" \
    "${STAGE_ROOT}/usr/share/pixmaps/silicyos-logo.png"
install -Dm644 "${SCRIPT_DIR}/branding/silicyos-boot.png" \
    "${STAGE_ROOT}/usr/share/pixmaps/silicyos-boot.png"
install -Dm644 "${SCRIPT_DIR}/branding/silicyos-logo.svg" \
    "${STAGE_ROOT}/usr/share/icons/hicolor/scalable/apps/silicyos.svg"

for sz in 16 32 64 128 256 512; do
    install -Dm644 "${SCRIPT_DIR}/branding/mark-${sz}.png" \
        "${STAGE_ROOT}/usr/share/icons/hicolor/${sz}x${sz}/apps/silicyos.png"
done

install -Dm644 "${SCRIPT_DIR}/branding/silicyos-wallpaper.png" \
    "${STAGE_ROOT}/usr/share/backgrounds/silicyos/silicyos-wallpaper.png"

install -Dm644 "${SCRIPT_DIR}/branding/plymouth/silicyos/silicyos.plymouth" \
    "${STAGE_ROOT}/usr/share/plymouth/themes/silicyos/silicyos.plymouth"
install -Dm644 "${SCRIPT_DIR}/branding/plymouth/silicyos/silicyos.script" \
    "${STAGE_ROOT}/usr/share/plymouth/themes/silicyos/silicyos.script"
install -Dm644 "${SCRIPT_DIR}/branding/silicyos-boot.png" \
    "${STAGE_ROOT}/usr/share/plymouth/themes/silicyos/silicyos-boot.png"
install -Dm644 "${SCRIPT_DIR}/branding/silicyos-logo-mono.svg" \
    "${STAGE_ROOT}/usr/share/plymouth/themes/silicyos/silicyos-logo-mono.svg"
install -Dm644 "${SCRIPT_DIR}/branding/silicyos-logo.svg" \
    "${STAGE_ROOT}/usr/share/plymouth/themes/silicyos/silicyos-logo.svg"

# 2.6 Install First-Boot TUI Wizard & One-Shot Systemd Service
install -Dm755 "${SCRIPT_DIR}/installer/silicy-setup-tui.sh" \
    "${STAGE_ROOT}/usr/local/sbin/silicy-setup-tui.sh"

cat <<'EOF' > "${STAGE_ROOT}/etc/systemd/system/silicy-firstboot.service"
[Unit]
Description=silicyOS First-Boot Apple Silicon TUI Setup Wizard
After=systemd-user-sessions.service iwd.service dbus-broker.service
Before=greetd.service getty@tty1.service
ConditionPathExists=!/etc/silicyos-installed

[Service]
Type=oneshot
Environment=TERM=linux
StandardInput=tty
StandardOutput=tty
StandardError=tty
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
ExecStart=/usr/local/sbin/silicy-setup-tui.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# 2.7 Configure Locale, OS-Release & Execute systemd-diet.sh inside Chroot
echo "en_US.UTF-8 UTF-8" > "${STAGE_ROOT}/etc/locale.gen"
echo "LANG=en_US.UTF-8" > "${STAGE_ROOT}/etc/locale.conf"
echo "silicyos" > "${STAGE_ROOT}/etc/hostname"

cat <<'EOF' > "${STAGE_ROOT}/etc/os-release"
NAME="silicyOS"
PRETTY_NAME="silicyOS (CachyOS-ARM64 + Asahi 16K Ultra-Light)"
ID=silicyos
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="38;2;10;132;255"
HOME_URL="https://asahilinux.org"
LOGO=silicyos
EOF

mkdir -p "${STAGE_ROOT}/usr/lib/firmware/vendor"

cat <<'EOF' > "${STAGE_ROOT}/etc/mkinitcpio.conf"
# /etc/mkinitcpio.conf - silicyOS Apple Silicon M1/M2/M3 NVMe + Btrfs Early Boot
MODULES=(apple-mailbox nvme_apple nvme simpledrm btrfs)
BINARIES=(/usr/bin/btrfs)
FILES=()
HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block btrfs filesystems fsck)
COMPRESSION="zstd"
COMPRESSION_OPTIONS=(-3 -T0)
EOF

install -Dm755 "${SCRIPT_DIR}/services/systemd-diet.sh" "${STAGE_ROOT}/usr/local/sbin/systemd-diet.sh"
arch-chroot "${STAGE_ROOT}" /bin/bash -c "
    locale-gen
    chgrp wheel /etc/silicy-battery.conf /etc/silicy-power-profile /etc/silicy-kb-mode /etc/keyd/default.conf 2>/dev/null || true
    chmod 0664 /etc/silicy-battery.conf /etc/silicy-power-profile /etc/silicy-kb-mode /etc/keyd/default.conf 2>/dev/null || true
    /usr/local/sbin/systemd-diet.sh
    systemctl enable silicy-firstboot.service
    systemctl enable silicy-pe-enforcer.service 2>/dev/null || true
    mkinitcpio -P
"
rm -f "${STAGE_ROOT}/usr/local/sbin/systemd-diet.sh"

# ==============================================================================
# STEP 3: Build ESP (FAT32) & Btrfs (zstd:3) Rootfs Disk Images via setup-btrfs-silicy.sh
# ==============================================================================
echo "=============================================================================="
echo "[STEP 3/4] Provisioning ESP (${ESP_SIZE_MB}MB FAT32) & Btrfs Rootfs (${ROOTFS_SIZE_MB}MB zstd:3)"
echo "=============================================================================="

truncate -s "${ESP_SIZE_MB}M" "${ESP_IMG}"
truncate -s "${ROOTFS_SIZE_MB}M" "${ROOTFS_IMG}"

mkfs.fat -F 32 -n "SILICY_EFI" "${ESP_IMG}"

LOOP_ESP="$(losetup --find --show "${ESP_IMG}")"
LOOP_ROOT="$(losetup --find --show "${ROOTFS_IMG}")"

# Execute setup-btrfs-silicy.sh on the loop block devices
"${SCRIPT_DIR}/storage/setup-btrfs-silicy.sh" "${LOOP_ROOT}" "${LOOP_ESP}" "${MNT_DIR}"

echo "  -> Copying staged rootfs into zstd:3 compressed Btrfs hierarchy..."
rsync -aHAX --numeric-ids --exclude='/boot/efi/*' "${STAGE_ROOT}/" "${MNT_DIR}/"
# Restore generated fstab with exact loop UUIDs
ROOT_UUID="$(blkid -s UUID -o value "${LOOP_ROOT}")"
EFI_UUID="$(blkid -s UUID -o value "${LOOP_ESP}")"
BTRFS_OPTS="rw,noatime,compress-force=zstd:3,ssd,discard=async,space_cache=v2,commit=120"

cat <<EOF > "${MNT_DIR}/etc/fstab"
# /etc/fstab: static file system information for silicyOS (Apple Silicon ARM64)
UUID=${ROOT_UUID}  /                       btrfs  ${BTRFS_OPTS},subvol=@          0 0
UUID=${ROOT_UUID}  /home                   btrfs  ${BTRFS_OPTS},subvol=@home      0 0
UUID=${ROOT_UUID}  /var/cache/pacman/pkg   btrfs  ${BTRFS_OPTS},subvol=@pkg       0 0
UUID=${ROOT_UUID}  /var/log                btrfs  ${BTRFS_OPTS},subvol=@log       0 0
UUID=${ROOT_UUID}  /.snapshots             btrfs  ${BTRFS_OPTS},subvol=@snapshots 0 0
UUID=${EFI_UUID}   /boot/efi               vfat   rw,noatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro 0 2
tmpfs              /tmp                    tmpfs  rw,nosuid,nodev,noatime,size=1G,mode=1777 0 0
EOF

echo "  -> Installing systemd-boot, U-Boot & m1n1 chainloader into ESP..."
mkdir -p "${MNT_DIR}/boot/efi/EFI/BOOT" \
         "${MNT_DIR}/boot/efi/loader/entries" \
         "${MNT_DIR}/boot/efi/m1n1"

if [[ -d "${WORK_DIR}/esp-seed" ]]; then
    cp -a "${WORK_DIR}/esp-seed/." "${MNT_DIR}/boot/efi/" 2>/dev/null || true
fi

arch-chroot "${MNT_DIR}" bootctl --esp-path=/boot/efi --no-variables install || true

# Copy kernel and initramfs to ESP so systemd-boot / U-Boot can load them directly
cp -f "${MNT_DIR}/boot/Image" "${MNT_DIR}/boot/efi/Image" 2>/dev/null || \
cp -f "${MNT_DIR}/boot/vmlinuz-"* "${MNT_DIR}/boot/efi/Image" 2>/dev/null || true
cp -f "${MNT_DIR}/boot/initramfs-"*.img "${MNT_DIR}/boot/efi/initramfs-linux.img" 2>/dev/null || true
cp -f "${MNT_DIR}/usr/lib/asahi-boot/u-boot-nodtb.bin" "${MNT_DIR}/boot/efi/u-boot-nodtb.bin" 2>/dev/null || true
install -Dm644 "${SCRIPT_DIR}/branding/silicyos-boot.bmp" "${MNT_DIR}/boot/efi/loader/silicyos-boot.bmp"
install -Dm644 "${SCRIPT_DIR}/branding/silicyos-boot.png" "${MNT_DIR}/boot/efi/loader/silicyos-boot.png"
install -Dm644 "${SCRIPT_DIR}/branding/silicyos-logo.svg" "${MNT_DIR}/boot/efi/loader/silicyos-logo.svg"
install -Dm644 "${SCRIPT_DIR}/branding/silicyos-logo-mono.svg" "${MNT_DIR}/boot/efi/loader/silicyos-logo-mono.svg"

cat <<EOF > "${MNT_DIR}/boot/efi/loader/loader.conf"
default silicyos.conf
timeout 1
console-mode max
editor no
EOF

cat <<EOF > "${MNT_DIR}/boot/efi/loader/entries/silicyos.conf"
title   silicyOS (Apple Silicon 16K • BORE • LTO)
linux   /Image
initrd  /initramfs-linux.img
options root=UUID=${ROOT_UUID} rootflags=subvol=@,compress-force=zstd:3 rw quiet loglevel=3 systemd.show_status=auto apple_dcp.show_notch=1
EOF

# Build m1n1 + DTB + U-Boot payload for Apple Silicon bootchain
arch-chroot "${MNT_DIR}" update-m1n1 /boot/efi/m1n1/boot.bin 2>/dev/null || true

echo "  -> Running final Btrfs zstd defragment/recompression pass & syncing..."
btrfs filesystem defragment -r -czstd "${MNT_DIR}" || true
sync

umount -R "${MNT_DIR}"
losetup -d "${LOOP_ESP}" && LOOP_ESP=""
losetup -d "${LOOP_ROOT}" && LOOP_ROOT=""

# ==============================================================================
# STEP 4: Package Asahi Installer Payload (silicyos-apple-silicon.zip)
# ==============================================================================
echo "=============================================================================="
echo "[STEP 4/4] Packaging Asahi Installer Payload -> ${OUT_ZIP}"
echo "=============================================================================="

mkdir -p "${IMG_DIR}/esp"
mount -o loop,ro "${ESP_IMG}" "${MNT_DIR}"
cp -a "${MNT_DIR}/." "${IMG_DIR}/esp/"
umount "${MNT_DIR}"

cp -f "${SCRIPT_DIR}/installer/installer_data.json" "${IMG_DIR}/installer_data.json"

rm -f "${OUT_ZIP}"
(
    cd "${IMG_DIR}"
    zip -r -9 "${OUT_ZIP}" esp/ esp.img rootfs.img installer_data.json
)

echo "=============================================================================="
echo "[SUCCESS] Master Build Complete: ${OUT_ZIP}"
ls -lh "${OUT_ZIP}"
echo "=============================================================================="
