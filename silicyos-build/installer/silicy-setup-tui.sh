#!/usr/bin/env bash
# ==============================================================================
# silicyOS First-Boot Interactive TUI Provisioner (Apple Silicon M1/M2/M3)
# Engine: gum / whiptail / dialog with pure-ANSI fallback
# ==============================================================================
set -euo pipefail

export TERM="${TERM:-linux}"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# --- TUI Abstraction Helpers (Supports gum -> whiptail -> dialog -> pure bash) ---
ui_banner() {
    clear
    cat <<'EOF'
  ======================================================================
   󰀵  s i l i c y O S   —   A p p l e   S i l i c o n   1 6 K   A R M
      CachyOS BORE + Clang Full-LTO + Btrfs zstd:3 + Wayland Glass
  ======================================================================
EOF
}

ui_input() {
    local prompt="$1"
    local default_val="${2:-}"
    if command -v gum >/dev/null 2>&1; then
        gum input --prompt "  ❯ ${prompt}: " --value "${default_val}"
    elif command -v whiptail >/dev/null 2>&1; then
        whiptail --title "silicyOS Setup" --inputbox "${prompt}" 10 64 "${default_val}" 3>&1 1>&2 2>&3
    elif command -v dialog >/dev/null 2>&1; then
        dialog --stdout --title "silicyOS Setup" --inputbox "${prompt}" 10 64 "${default_val}"
    else
        local ans
        read -r -p "  ❯ ${prompt} [${default_val}]: " ans
        echo "${ans:-$default_val}"
    fi
}

ui_password() {
    local prompt="$1"
    if command -v gum >/dev/null 2>&1; then
        gum input --password --prompt "  ❯ ${prompt}: "
    elif command -v whiptail >/dev/null 2>&1; then
        whiptail --title "silicyOS Security" --passwordbox "${prompt}" 10 64 3>&1 1>&2 2>&3
    elif command -v dialog >/dev/null 2>&1; then
        dialog --stdout --title "silicyOS Security" --insecure --passwordbox "${prompt}" 10 64
    else
        local pass
        read -r -s -p "  ❯ ${prompt}: " pass
        echo "" >&2
        echo "${pass}"
    fi
}

ui_choose() {
    local header="$1"
    shift
    local options=("$@")
    if command -v gum >/dev/null 2>&1; then
        gum choose --header "  ${header}" "${options[@]}"
    elif command -v whiptail >/dev/null 2>&1; then
        local menu_items=()
        for opt in "${options[@]}"; do
            menu_items+=("${opt}" "")
        done
        whiptail --title "silicyOS Setup" --menu "${header}" 15 72 6 "${menu_items[@]}" 3>&1 1>&2 2>&3
    elif command -v dialog >/dev/null 2>&1; then
        local menu_items=()
        for opt in "${options[@]}"; do
            menu_items+=("${opt}" "")
        done
        dialog --stdout --title "silicyOS Setup" --menu "${header}" 15 72 6 "${menu_items[@]}"
    else
        echo "  ${header}" >&2
        select opt in "${options[@]}"; do
            [[ -n "${opt}" ]] && { echo "${opt}"; break; }
        done
    fi
}

apply_ultra_battery_visuals() {
    local target_home="${1:-}"
    [[ -n "${target_home}" ]] || return 1
    local hypr_conf="${target_home}/.config/hypr/hyprland.conf"
    local kitty_conf="${target_home}/.config/kitty/kitty.conf"

    if [[ -f "${hypr_conf}" ]]; then
        local tmp_hypr=""
        tmp_hypr="$(mktemp "${TMPDIR:-/tmp}/silicy-hypr.XXXXXX" 2>/dev/null)" || return 1
        if awk '
            function disable_blur_enabled(s,    pre, mid, res) {
                res = ""
                while (match(s, /(^|[[:space:];{])enabled[[:space:]]*=[[:space:]]*true([[:space:];}]|$)/)) {
                    pre = substr(s, 1, RSTART - 1)
                    mid = substr(s, RSTART, RLENGTH)
                    sub(/true/, "false", mid)
                    res = res pre mid
                    s = substr(s, RSTART + RLENGTH)
                }
                return res s
            }
            BEGIN { in_blur = 0; blur_depth = 0; pending_blur = 0 }
            {
                line = $0
                hash_idx = index(line, "#")
                if (hash_idx > 0) {
                    code = substr(line, 1, hash_idx - 1)
                    cmt = substr(line, hash_idx)
                } else {
                    code = line
                    cmt = ""
                }

                if (code ~ /^[[:space:]]*$/) {
                    print line
                    next
                }

                out = ""
                rem = code
                while (length(rem) > 0) {
                    if (in_blur == 0) {
                        if (pending_blur == 1) {
                            if (match(rem, /^[[:space:]]*\{/)) {
                                out = out substr(rem, 1, RLENGTH)
                                rem = substr(rem, RLENGTH + 1)
                                in_blur = 1
                                blur_depth = 1
                                pending_blur = 0
                                continue
                            }
                            pending_blur = 0
                        }
                        if (match(rem, /(^|[[:space:];{])blur[[:space:]]*\{/)) {
                            out = out substr(rem, 1, RSTART + RLENGTH - 1)
                            rem = substr(rem, RSTART + RLENGTH)
                            in_blur = 1
                            blur_depth = 1
                        } else if (match(rem, /(^|[[:space:];{])blur[[:space:]]*$/)) {
                            out = out rem
                            rem = ""
                            pending_blur = 1
                        } else {
                            out = out rem
                            rem = ""
                        }
                    } else {
                        seg = ""
                        n = length(rem)
                        consumed = 0
                        for (i = 1; i <= n; i++) {
                            ch = substr(rem, i, 1)
                            if (ch == "{") {
                                if (blur_depth == 1) {
                                    out = out disable_blur_enabled(seg)
                                    seg = ""
                                }
                                blur_depth++
                                out = out ch
                            } else if (ch == "}") {
                                if (blur_depth == 1) {
                                    out = out disable_blur_enabled(seg)
                                    seg = ""
                                }
                                blur_depth--
                                out = out ch
                                if (blur_depth <= 0) {
                                    in_blur = 0
                                    blur_depth = 0
                                    consumed = i
                                    break
                                }
                            } else {
                                if (blur_depth == 1) {
                                    seg = seg ch
                                } else {
                                    out = out ch
                                }
                            }
                            consumed = i
                        }
                        if (in_blur == 1 && blur_depth == 1 && seg != "") {
                            out = out disable_blur_enabled(seg)
                        }
                        rem = substr(rem, consumed + 1)
                    }
                }
                print out cmt
            }
        ' "${hypr_conf}" > "${tmp_hypr}"; then
            cat "${tmp_hypr}" > "${hypr_conf}"
        fi
        rm -f "${tmp_hypr}"
    fi

    if [[ -f "${kitty_conf}" ]]; then
        local tmp_kitty=""
        tmp_kitty="$(mktemp "${TMPDIR:-/tmp}/silicy-kitty.XXXXXX" 2>/dev/null)" || return 1
        if awk '
            /^[[:space:]]*background_blur[[:space:]]+[0-9]+([[:space:]]*(#.*)?)?$/ {
                match($0, /^[[:space:]]*background_blur[[:space:]]+/)
                pre = substr($0, 1, RLENGTH)
                rest = substr($0, RLENGTH + 1)
                sub(/^[0-9]+/, "0", rest)
                $0 = pre rest
            }
            /^[[:space:]]*background_opacity[[:space:]]+[0-9]+(\.[0-9]+)?([[:space:]]*(#.*)?)?$/ {
                match($0, /^[[:space:]]*background_opacity[[:space:]]+/)
                pre = substr($0, 1, RLENGTH)
                rest = substr($0, RLENGTH + 1)
                sub(/^[0-9]+(\.[0-9]+)?/, "0.94", rest)
                $0 = pre rest
            }
            { print }
        ' "${kitty_conf}" > "${tmp_kitty}"; then
            cat "${tmp_kitty}" > "${kitty_conf}"
        fi
        rm -f "${tmp_kitty}"
    fi
}

if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "${0}" ]]; then
    return 0
fi

# ==============================================================================
# 1. Extract Apple Broadcom Wi-Fi / Bluetooth Firmware & Connect via iwd
# ==============================================================================
ui_banner
echo "  [1/6] Extracting Apple Silicon Broadcom Wi-Fi/BT Firmware (asahi-fwextract)..."

if command -v asahi-fwextract >/dev/null 2>&1; then
    asahi-fwextract /boot/efi/vendorfw /lib/firmware/vendor 2>/dev/null || \
    asahi-fwextract 2>/dev/null || true
    modprobe -r brcmfmac_wcc brcmfmac hci_bcm4377 2>/dev/null || true
    modprobe brcmfmac 2>/dev/null || true
    modprobe hci_bcm4377 2>/dev/null || true
    udevadm settle --timeout=5 || true
fi

systemctl restart iwd.service 2>/dev/null || true
sleep 1

WIFI_CHOICE="$(ui_choose "Configure Apple Broadcom Wi-Fi via iwd now?" \
    "Connect to Wi-Fi Network" \
    "Skip Wi-Fi Setup (Offline)")"

if [[ "${WIFI_CHOICE}" == "Connect to Wi-Fi Network" ]]; then
    iwctl station wlan0 scan 2>/dev/null || true
    sleep 2
    SSID="$(ui_input "Enter Wi-Fi SSID (Network Name)" "")"
    if [[ -n "${SSID}" ]]; then
        WIFI_PASS="$(ui_password "Enter Wi-Fi Passphrase for ${SSID}")"
        if [[ -n "${WIFI_PASS}" ]]; then
            iwctl --passphrase "${WIFI_PASS}" station wlan0 connect "${SSID}" || true
        else
            iwctl station wlan0 connect "${SSID}" || true
        fi
    fi
fi

# ==============================================================================
# 2. Hostname, User Account (wheel/sudo) & /etc/skel Dotfiles Deployment
# ==============================================================================
ui_banner
echo "  [2/6] Configuring Hostname & Administrator Account..."

HOSTNAME_VAL="$(ui_input "Enter Mac Hostname" "silicy-mac")"
HOSTNAME_VAL="${HOSTNAME_VAL:-silicy-mac}"
echo "${HOSTNAME_VAL}" > /etc/hostname
cat <<EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME_VAL}.localdomain ${HOSTNAME_VAL}
EOF

USERNAME_VAL="$(ui_input "Enter Username (sudo/wheel)" "silicy")"
USERNAME_VAL="${USERNAME_VAL:-silicy}"

while true; do
    PASS1="$(ui_password "Enter Password for ${USERNAME_VAL}")"
    PASS2="$(ui_password "Confirm Password for ${USERNAME_VAL}")"
    if [[ -n "${PASS1}" && "${PASS1}" == "${PASS2}" ]]; then
        break
    fi
    echo "  [!] Passwords did not match or were empty. Please try again."
    sleep 1
done

if ! id -u "${USERNAME_VAL}" >/dev/null 2>&1; then
    useradd -m -k /etc/skel -s /bin/zsh -G wheel,video,audio,input,seat "${USERNAME_VAL}"
fi
getent group keyd >/dev/null 2>&1 && usermod -aG keyd "${USERNAME_VAL}" 2>/dev/null || true
echo "${USERNAME_VAL}:${PASS1}" | chpasswd
echo "root:${PASS1}" | chpasswd

mkdir -p /etc/sudoers.d
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel

cat <<'EOF' > /etc/sudoers.d/20-silicy-nopasswd
%wheel ALL=(root) NOPASSWD: /usr/local/bin/silicy-ctl, /usr/local/bin/silicy-capsule, /usr/local/bin/silicy-macos-bridge, /usr/bin/keyd, /usr/bin/systemctl restart keyd.service
EOF
chmod 0440 /etc/sudoers.d/20-silicy-nopasswd

USER_HOME="/home/${USERNAME_VAL}"
mkdir -p "${USER_HOME}/.config" "${USER_HOME}/Pictures/Screenshots" "${USER_HOME}/macOS-Shared"
cp -a /etc/skel/.config/. "${USER_HOME}/.config/"
ln -sf ".config/zsh/.zshrc" "${USER_HOME}/.zshrc"

# ==============================================================================
# 3. Select Default Wayland Compositor (Niri Scrolling vs Hyprland Tiling)
# ==============================================================================
ui_banner
COMP_CHOICE="$(ui_choose "Select Default Wayland Compositor:" \
    "Niri Scrolling (Recommended - <95MB RAM, Infinite Strip)" \
    "Hyprland Tiling (Dynamic Dwindle + Dual-Kawase Blur)")"

if [[ "${COMP_CHOICE}" == Hyprland* ]]; then
    SESSION_CMD="Hyprland"
else
    SESSION_CMD="niri-session"
fi

cat <<EOF > /etc/greetd/config.toml
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --remember-session --asterisks --greeting 'silicyOS ARM64 (Asahi 16K + CachyOS)' --sessions /usr/share/wayland-sessions --cmd ${SESSION_CMD}"
user = "greeter"
EOF

# ==============================================================================
# 4. Select Apple Keyboard Modifier Mode (Native Command ⌘ vs Swap Cmd <-> Ctrl)
# ==============================================================================
ui_banner
KB_CHOICE="$(ui_choose "Select Mac Keyboard Modifier Layout:" \
    "Keep Native Command ⌘ (Super = Command, Ctrl = Control)" \
    "Swap Command <-> Control (PC-Style Ctrl/Super Swap)")"

if [[ "${KB_CHOICE}" == Swap* ]]; then
    mkdir -p /etc/modprobe.d /etc/keyd
    echo "options hid_apple swap_opt_cmd=0 swap_fn_leftctrl=0" > /etc/modprobe.d/hid_apple.conf
    if [[ -f /usr/share/silicyos/keyd/pc-mode.conf ]]; then
        cp -f /usr/share/silicyos/keyd/pc-mode.conf /etc/keyd/default.conf
    elif [[ -f /etc/keyd/pc-mode.conf ]]; then
        cp -f /etc/keyd/pc-mode.conf /etc/keyd/default.conf
    fi
    rm -f /etc/keyd/mac-mode.conf /etc/keyd/pc-mode.conf
    echo "PC (Ctrl)" > /etc/silicy-kb-mode
else
    mkdir -p /etc/keyd
    if [[ -f /usr/share/silicyos/keyd/mac-mode.conf ]]; then
        cp -f /usr/share/silicyos/keyd/mac-mode.conf /etc/keyd/default.conf
    elif [[ -f /etc/keyd/mac-mode.conf ]]; then
        cp -f /etc/keyd/mac-mode.conf /etc/keyd/default.conf
    fi
    rm -f /etc/keyd/mac-mode.conf /etc/keyd/pc-mode.conf
    echo "Mac (Command)" > /etc/silicy-kb-mode
fi
chgrp wheel /etc/keyd/default.conf /etc/silicy-kb-mode 2>/dev/null || true
chmod 0664 /etc/keyd/default.conf /etc/silicy-kb-mode 2>/dev/null || true
systemctl restart keyd.service 2>/dev/null || true

# ==============================================================================
# 5. Select Power & Visual Profile (Ultra-Battery vs Max-Rice Performance)
# ==============================================================================
ui_banner
POWER_CHOICE="$(ui_choose "Select Apple Silicon Power & Visual Profile:" \
    "Max-Rice Performance (BORE Boost + 120Hz ProMotion + Glass Blur)" \
    "Ultra-Battery (Lock High E-Core Efficiency + Disable Blur + 3-4W Idle)")"

# Enable 80% MacSMC battery health guard by default on MacBooks
if command -v silicy-ctl >/dev/null 2>&1; then
    silicy-ctl battery-guard 80 >/dev/null 2>&1 || true
fi

if [[ "${POWER_CHOICE}" == Ultra-Battery* ]]; then
    # Disable blur & raise opacity in Hyprland and Kitty for minimal AGX GPU draw
    apply_ultra_battery_visuals "${USER_HOME}" || true

    # Configure cpufreq powersave/schedutil bias and conservative BORE tuning
    cat <<'EOF' > /etc/sysctl.d/99-silicy-power-profile.conf
kernel.sched_burst_penalty_offset = 28
kernel.sched_burst_smoothness_long = 3
vm.dirty_writeback_centisecs = 9000
EOF

    cat <<'EOF' > /etc/udev/rules.d/75-silicy-ultra-battery.rules
SUBSYSTEM=="cpu", KERNEL=="cpu[0-3]", ATTR{cpufreq/scaling_governor}="powersave"
SUBSYSTEM=="cpu", KERNEL=="cpu[4-9]*", ATTR{cpufreq/scaling_governor}="schedutil"
EOF
    if command -v silicy-ctl >/dev/null 2>&1; then
        silicy-ctl power-profile eco >/dev/null 2>&1 || true
    fi
else
    cat <<'EOF' > /etc/sysctl.d/99-silicy-power-profile.conf
kernel.sched_burst_penalty_offset = 22
kernel.sched_burst_smoothness_long = 1
kernel.sched_burst_smoothness_short = 0
EOF
    if command -v silicy-ctl >/dev/null 2>&1; then
        silicy-ctl power-profile balanced >/dev/null 2>&1 || true
    fi
fi

sysctl --system >/dev/null 2>&1 || true
chown -R "${USERNAME_VAL}:${USERNAME_VAL}" "${USER_HOME}"

# ==============================================================================
# 6. Remove First-Boot Service & Launch Wayland Session Directly
# ==============================================================================
ui_banner
echo "  [6/6] Finalizing silicyOS installation and launching ${SESSION_CMD}..."

touch /etc/silicyos-installed
systemctl disable silicy-firstboot.service 2>/dev/null || true
rm -f /etc/systemd/system/silicy-firstboot.service
systemctl daemon-reload 2>/dev/null || true

# Configure one-time seamless login via greetd into chosen Wayland compositor
cat <<EOF > /etc/greetd/config.toml
[terminal]
vt = 1

[initial_session]
command = "${SESSION_CMD}"
user = "${USERNAME_VAL}"

[default_session]
command = "tuigreet --time --remember --remember-session --asterisks --greeting 'silicyOS ARM64 (Asahi 16K + CachyOS)' --sessions /usr/share/wayland-sessions --cmd ${SESSION_CMD}"
user = "greeter"
EOF

systemctl start greetd.service --no-block 2>/dev/null || true
exit 0
