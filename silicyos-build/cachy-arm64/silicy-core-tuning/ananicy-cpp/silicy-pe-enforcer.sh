#!/usr/bin/env bash
# ==============================================================================
# /usr/local/bin/silicy-pe-enforcer.sh
# silicyOS Apple Silicon P-Core / E-Core Topology & Cpuset/Taskset Enforcer
# Dynamically discovers Efficiency (Icestorm/Blizzard/Sawtooth) and Performance
# (Firestorm/Avalanche/Everest) clusters via ARM64 cpu_capacity and enforces
# hardware CPU affinity via cgroup v2 cpuset + taskset.
# ==============================================================================

set -euo pipefail

CGROUP_ROOT="/sys/fs/cgroup"
ECORE_LIST=""
PCORE_LIST=""

detect_apple_silicon_topology() {
  local cpu_dir cpu_id cap
  local ecores=()
  local pcores=()

  for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
    [[ -d "${cpu_dir}" ]] || continue
    cpu_id="${cpu_dir##*/cpu}"
    if [[ -r "${cpu_dir}/cpu_capacity" ]]; then
      cap="$(<"${cpu_dir}/cpu_capacity")"
      # On Apple Silicon (linux-asahi), P-cores have capacity 1024; E-cores < 650
      if (( cap < 650 )); then
        ecores+=("${cpu_id}")
      else
        pcores+=("${cpu_id}")
      fi
    fi
  done

  # Fallback to standard 8-core M1/M2/M3 layout (0-3 E-cores, 4-7 P-cores)
  if (( ${#ecores[@]} == 0 || ${#pcores[@]} == 0 )); then
    ECORE_LIST="0-3"
    PCORE_LIST="4-7"
  else
    ECORE_LIST="$(IFS=,; echo "${ecores[*]}")"
    PCORE_LIST="$(IFS=,; echo "${pcores[*]}")"
  fi

  echo "[silicy-pe-enforcer] Detected Apple Silicon Topology: E-Cores=[${ECORE_LIST}] | P-Cores=[${PCORE_LIST}]"
}

setup_cgroup_cpusets() {
  if [[ -w "${CGROUP_ROOT}/cgroup.subtree_control" ]]; then
    echo "+cpuset +cpu" > "${CGROUP_ROOT}/cgroup.subtree_control" 2>/dev/null || true
  fi

  local cg
  for cg in pcores_rt pcores_interactive; do
    mkdir -p "${CGROUP_ROOT}/${cg}"
    if [[ -w "${CGROUP_ROOT}/${cg}/cpuset.cpus" ]]; then
      echo "${PCORE_LIST}" > "${CGROUP_ROOT}/${cg}/cpuset.cpus"
      chgrp wheel "${CGROUP_ROOT}/${cg}/cpuset.cpus" 2>/dev/null || true
      chmod 0664 "${CGROUP_ROOT}/${cg}/cpuset.cpus" 2>/dev/null || true
    fi
    if [[ -w "${CGROUP_ROOT}/${cg}/cpu.weight" ]]; then
      echo "1000" > "${CGROUP_ROOT}/${cg}/cpu.weight"
    fi
  done

  for cg in ecores_background ecores_idle; do
    mkdir -p "${CGROUP_ROOT}/${cg}"
    if [[ -w "${CGROUP_ROOT}/${cg}/cpuset.cpus" ]]; then
      echo "${ECORE_LIST}" > "${CGROUP_ROOT}/${cg}/cpuset.cpus"
      chgrp wheel "${CGROUP_ROOT}/${cg}/cpuset.cpus" 2>/dev/null || true
      chmod 0664 "${CGROUP_ROOT}/${cg}/cpuset.cpus" 2>/dev/null || true
    fi
    if [[ -w "${CGROUP_ROOT}/${cg}/cpu.weight" ]]; then
      echo "25" > "${CGROUP_ROOT}/${cg}/cpu.weight"
    fi
  done

  # Grant wheel group direct write access to BORE scheduler, cpufreq, and silicy state files
  local node
  for node in \
    /proc/sys/kernel/sched_bore \
    /proc/sys/kernel/sched_burst_penalty_offset \
    /proc/sys/kernel/sched_burst_smoothness_long \
    /proc/sys/kernel/sched_burst_smoothness_short \
    /proc/sys/vm/dirty_writeback_centisecs \
    /etc/silicy-power-profile \
    /etc/silicy-battery.conf \
    /etc/silicy-kb-mode \
    /etc/keyd/default.conf; do
    if [[ -e "${node}" ]]; then
      chgrp wheel "${node}" 2>/dev/null || true
      chmod 0664 "${node}" 2>/dev/null || true
    fi
  done

  for node in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor \
              /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_max_freq \
              /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_min_freq; do
    if [[ -e "${node}" ]]; then
      chgrp wheel "${node}" 2>/dev/null || true
      chmod 0664 "${node}" 2>/dev/null || true
    fi
  done
}

pin_pids_by_name() {
  local core_mask="$1"
  shift
  local proc_name pid
  for proc_name in "$@"; do
    while read -r pid; do
      [[ -n "${pid}" ]] || continue
      taskset -acp "${core_mask}" "${pid}" >/dev/null 2>&1 || true
    done < <(pgrep -x "${proc_name}" 2>/dev/null || true)
  done
}

pin_focused_wayland_window() {
  local target_mask="${1:-${PCORE_LIST}}"
  local focused_pid=""

  # Hyprland IPC focus detection
  if command -v hyprctl >/dev/null 2>&1 && pgrep -x "Hyprland" >/dev/null 2>&1; then
    focused_pid="$(hyprctl activewindow -j 2>/dev/null | sed -n 's/.*"pid":[[:space:]]*\([0-9]*\).*/\1/p' | head -n1 || true)"
  # Sway IPC focus detection
  elif command -v swaymsg >/dev/null 2>&1 && pgrep -x "sway" >/dev/null 2>&1; then
    focused_pid="$(swaymsg -t get_tree 2>/dev/null | tr '{' '\n' | grep '"focused": true' | sed -n 's/.*"pid":[[:space:]]*\([0-9]*\).*/\1/p' | head -n1 || true)"
  # Niri IPC focus detection
  elif command -v niri >/dev/null 2>&1 && pgrep -x "niri" >/dev/null 2>&1; then
    focused_pid="$(niri msg -j focused-window 2>/dev/null | sed -n 's/.*"pid":[[:space:]]*\([0-9]*\).*/\1/p' | head -n1 || true)"
  fi

  if [[ -n "${focused_pid}" && "${focused_pid}" =~ ^[0-9]+$ && "${focused_pid}" -gt 1 ]]; then
    taskset -acp "${target_mask}" "${focused_pid}" >/dev/null 2>&1 || true
    renice -n -5 -p "${focused_pid}" >/dev/null 2>&1 || true
  fi
}

get_active_power_profile() {
  if [[ -r /etc/silicy-power-profile ]]; then
    head -n1 /etc/silicy-power-profile | tr -d '[:space:]'
  elif [[ -r /run/silicy-power-profile ]]; then
    head -n1 /run/silicy-power-profile | tr -d '[:space:]'
  else
    printf "balanced"
  fi
}

main() {
  detect_apple_silicon_topology
  setup_cgroup_cpusets
  /usr/local/bin/silicy-ctl power-profile "$(get_active_power_profile)" >/dev/null 2>&1 || true

  while true; do
    local cur_profile interactive_mask
    cur_profile="$(get_active_power_profile)"
    if [[ "${cur_profile}" == "eco" ]]; then
      interactive_mask="${ECORE_LIST}"
    else
      interactive_mask="${PCORE_LIST}"
    fi

    # 1. Pin Wayland Compositors & PipeWire Audio DSP to P-Cores, interactive shell to active profile cluster
    pin_pids_by_name "${PCORE_LIST}" \
      Hyprland sway niri river labwc \
      pipewire pipewire-pulse wireplumber

    pin_pids_by_name "${interactive_mask}" \
      waybar foot footclient fuzzel kitty

    # 2. Pin currently focused Wayland client window according to power profile (E-Cores in eco, P-Cores otherwise)
    pin_focused_wayland_window "${interactive_mask}"

    # 3. Pin background indexers, loggers, package managers & kernel scrubbers strictly to E-Cores
    pin_pids_by_name "${ECORE_LIST}" \
      systemd-journald systemd-oomd logrotate \
      updatedb plocate-build mandb baloo_file tracker-miner-fs-3 \
      pacman pacstrap makepkg btrfs fstrim fwupd

    sleep 3
  done
}

main "$@"
