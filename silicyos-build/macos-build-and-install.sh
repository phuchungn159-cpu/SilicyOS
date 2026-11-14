#!/usr/bin/env bash
# ==============================================================================
# silicyOS macOS Host Orchestrator (Hướng A: Lima VZ Builder + Asahi Installer)
# Target Host: Apple M1 (macOS 26.2) | Target Split: 30GB silicyOS / 215GB macOS
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VM_NAME="silicy-builder"
OUT_ZIP="${SCRIPT_DIR}/silicyos-apple-silicon.zip"

echo "=============================================================================="
echo "  [silicyOS - Hướng A] Khởi tạo môi trường Build ARM64 (Lima Apple VZ)"
echo "=============================================================================="

if ! command -v limactl >/dev/null 2>&1; then
    echo "[ERROR] Chưa tìm thấy 'limactl'. Đang cài đặt qua Homebrew..."
    brew install lima
fi

# 1. Start or create ARM64 builder VM with writable project mount
if ! limactl list -q | grep -qx "${VM_NAME}"; then
    echo "[1/4] Tạo máy ảo Linux ARM64 (${VM_NAME}) trên Apple Virtualization.framework..."
    limactl start --name="${VM_NAME}" --vm-type=vz --cpus=4 --memory=4 --disk=24 \
        --mount="${PROJECT_ROOT}:w" --tty=false template:debian-13
else
    echo "[1/4] Khởi động máy ảo ${VM_NAME}..."
    limactl start "${VM_NAME}" --tty=false || true
fi

# 2. Bootstrap Arch Linux ARM64 chroot & execute build-silicyos.sh inside VM
echo "[2/4] Thiết lập môi trường Arch Linux ARM64 + Asahi ALARM và chạy build-silicyos.sh..."
limactl shell --workdir "${SCRIPT_DIR}" "${VM_NAME}" sudo bash -c '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y arch-install-scripts pacman-package-manager btrfs-progs dosfstools zip unzip rsync zstd curl jq udev
    ./verify-silicyos.sh
    ./build-silicyos.sh
'

# 3. Stop and remove temporary builder VM to reclaim all APFS space before partitioning
echo "[3/4] Dọn dẹp máy ảo tạm (${VM_NAME}) để trả lại dung lượng trống cho APFS..."
limactl stop "${VM_NAME}" || true
limactl delete -f "${VM_NAME}" || true

echo "=============================================================================="
echo "[4/4] Đã tạo xong bộ cài: ${OUT_ZIP}"
ls -lh "${OUT_ZIP}"
echo "=============================================================================="
