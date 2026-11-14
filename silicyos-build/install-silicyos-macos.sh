#!/usr/bin/env bash
# ==============================================================================
# silicyOS Local Asahi Installer Launcher (macOS Apple Silicon Host)
# Target: Apple M1/M2/M3 — Recommended Split: 30GB silicyOS / 215GB Macintosh HD
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIP_PATH="${SCRIPT_DIR}/silicyos-apple-silicon.zip"
JSON_SRC="${SCRIPT_DIR}/installer/installer_data.json"

if [[ ! -s "${ZIP_PATH}" ]]; then
    echo "[ERROR] Missing ${ZIP_PATH} — run build-silicyos.sh first." >&2
    exit 1
fi

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

export VERSION_FLAG="https://cdn.asahilinux.org/installer/latest"
export INSTALLER_BASE="https://cdn.asahilinux.org/installer"
export REPO_BASE="https://cdn.asahilinux.org"

TMP="/tmp/asahi-install"
rm -rf "${TMP}"
mkdir -p "${TMP}/os"

# Start local HTTP server on 127.0.0.1:8765 to serve silicyos-apple-silicon.zip at >1 GB/s
ln -sf "${ZIP_PATH}" "${TMP}/os/silicyos-apple-silicon.zip"
jq '.os_list[0].package = "http://127.0.0.1:8765/os/silicyos-apple-silicon.zip"' "${JSON_SRC}" > "${TMP}/installer_data.json"

python3 -m http.server 8765 --bind 127.0.0.1 --directory "${TMP}" >/dev/null 2>&1 &
HTTP_PID=$!
trap 'kill "${HTTP_PID}" 2>/dev/null || true' EXIT

cd "${TMP}"
echo "=============================================================================="
echo "  silicyOS Apple Silicon Installer (Local High-Speed Payload)"
echo "  Payload : ${ZIP_PATH} ($(du -h "${ZIP_PATH}" | awk '{print $1}'))"
echo "  Gợi ý chia ổ (245GB SSD): Nhập 215GB cho macOS (dành ~30GB cho silicyOS)"
echo "=============================================================================="

PKG_VER="$(curl --no-progress-meter -L "${VERSION_FLAG}")"
PKG="installer-${PKG_VER}.tar.gz"
echo "  -> Downloading official Asahi installer engine (${PKG_VER})..."
curl --no-progress-meter -L -o "${PKG}" "${INSTALLER_BASE}/${PKG}"
tar xf "${PKG}"

echo "  -> Launching Asahi Installer with silicyOS manifest..."
if [[ "${EUID}" -ne 0 ]]; then
    sudo -E caffeinate -dis ./install.sh "$@"
else
    caffeinate -dis ./install.sh "$@"
fi
