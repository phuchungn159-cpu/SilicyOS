#!/usr/bin/env bash
# ==============================================================================
# silicyOS Systemd Daemon Diet & Session Provisioner (Runs inside Rootfs Chroot)
# Target: < 420MB Idle RAM | Zero Unnecessary SSD Writes | Sub-4MB TUI Login
# ==============================================================================
set -euo pipefail

echo "[1/6] Installing Unified Memory ZRAM & EarlyOOM configurations..."
install -Dm644 /etc/silicyos/memory/zram-generator.conf /etc/systemd/zram-generator.conf 2>/dev/null || true
install -Dm644 /etc/silicyos/memory/earlyoom.conf /etc/default/earlyoom 2>/dev/null || true
rm -f /etc/sysctl.d/99-silicy-memory.conf

echo "[2/6] Masking redundant background services on Apple Silicon MacBooks..."
MASKED_SERVICES=(
    "ModemManager.service"
    "systemd-networkd-wait-online.service"
    "cups.service"
    "cups.socket"
    "cups.path"
    "avahi-daemon.service"
    "avahi-daemon.socket"
    "lvm2-monitor.service"
    "ldconfig.service"
    "systemd-FirstBoot.service"
    "remote-fs.target"
)

for svc in "${MASKED_SERVICES[@]}"; do
    systemctl mask "${svc}" || true
done

echo "[3/6] Enabling essential ultra-lightweight Asahi & silicyOS services..."
ENABLED_SERVICES=(
    "dbus-broker.service"
    "iwd.service"
    "seatd.service"
    "earlyoom.service"
    "ananicy-cpp.service"
    "speakersafetyd.service"
    "tiny-dfr.service"
    "keyd.service"
    "swayosd-libinput-backend.service"
    "greetd.service"
)

for svc in "${ENABLED_SERVICES[@]}"; do
    systemctl enable "${svc}" || true
done

echo "[4/6] Configuring volatile RAM-only journald (/etc/systemd/journald.conf)..."
mkdir -p /etc/systemd
cat <<'EOF' > /etc/systemd/journald.conf
# /etc/systemd/journald.conf - silicyOS SSD Wear-Leveling Protection
[Journal]
Storage=volatile
Compress=yes
Seal=no
SplitMode=none
RuntimeMaxUse=16M
RuntimeKeepFree=32M
RuntimeMaxFileSize=4M
RuntimeMaxFiles=4
MaxRetentionSec=1day
ForwardToSyslog=no
ForwardToKMsg=no
ForwardToConsole=no
ForwardToWall=no
EOF

echo "[5/6] Disabling core dumps completely (/etc/systemd/coredump.conf)..."
cat <<'EOF' > /etc/systemd/coredump.conf
# /etc/systemd/coredump.conf - silicyOS Zero-Disk-Waste Core Dump Policy
[Coredump]
Storage=none
ProcessSizeMax=0
ExternalSizeMax=0
JournalSizeMax=0
EOF

echo "[6/6] Configuring greetd + tuigreet (< 4MB RAM) for Niri & Hyprland Wayland sessions..."
mkdir -p /etc/greetd /var/cache/tuigreet /usr/share/wayland-sessions

if id -u greeter >/dev/null 2>&1; then
    chown -R greeter:greeter /var/cache/tuigreet
    chmod 0750 /var/cache/tuigreet
    usermod -aG video,seat greeter || true
fi

cat <<'EOF' > /usr/share/wayland-sessions/niri.desktop
[Desktop Entry]
Name=Niri (Scrollable Tiling Wayland)
Comment=Ultra-lightweight scrollable-tiling Wayland compositor for silicyOS
Exec=niri-session
Type=Application
DesktopNames=niri
EOF

cat <<'EOF' > /usr/share/wayland-sessions/hyprland.desktop
[Desktop Entry]
Name=Hyprland (Dynamic Tiling Wayland)
Comment=Dynamic tiling Wayland compositor on Asahi AGX
Exec=Hyprland
Type=Application
DesktopNames=Hyprland
EOF

cat <<'EOF' > /etc/greetd/config.toml
# /etc/greetd/config.toml - silicyOS Ultra-Lightweight TUI Greeter
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --remember-session --asterisks --greeting 'silicyOS ARM64 (Asahi 16K + CachyOS)' --sessions /usr/share/wayland-sessions --cmd niri-session"
user = "greeter"
EOF

echo "[DONE] silicyOS daemon diet and Unified Memory protections applied."
