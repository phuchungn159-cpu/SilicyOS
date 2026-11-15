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

# Start local Range-capable HTTP server on 127.0.0.1:8765 (Asahi urlcache requires HTTP 206 Range support)
ln -sf "${ZIP_PATH}" "${TMP}/os/silicyos-apple-silicon.zip"
jq '.os_list[0].package = "http://127.0.0.1:8765/os/silicyos-apple-silicon.zip"' "${JSON_SRC}" > "${TMP}/installer_data.json"

python3 - "${TMP}" 8765 >/dev/null 2>&1 <<'PYEOF' &
import functools, http.server, os, re, socketserver, sys

directory, port = sys.argv[1], int(sys.argv[2])

class RangeHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Accept-Ranges", "bytes")
        super().end_headers()

    def send_head(self):
        path = self.translate_path(self.path)
        if os.path.isdir(path) or not os.path.exists(path):
            return super().send_head()
        f = open(path, "rb")
        fs = os.fstat(f.fileno())
        size = fs.st_size
        rng = self.headers.get("Range")
        if rng:
            m = re.match(r"bytes=(\d*)-(\d*)", rng)
            if m:
                start = int(m.group(1)) if m.group(1) else 0
                end = int(m.group(2)) if m.group(2) else size - 1
                end = min(end, size - 1)
                if start <= end < size:
                    self.send_response(206)
                    self.send_header("Content-type", self.guess_type(path))
                    self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
                    self.send_header("Content-Length", str(end - start + 1))
                    self.send_header("Last-Modified", self.date_time_string(fs.st_mtime))
                    self.end_headers()
                    f.seek(start)
                    self._range_remaining = end - start + 1
                    return f
        self._range_remaining = None
        f.close()
        return super().send_head()

    def copyfile(self, source, outputfile):
        rem = getattr(self, "_range_remaining", None)
        if rem is None:
            return super().copyfile(source, outputfile)
        while rem > 0:
            buf = source.read(min(65536, rem))
            if not buf:
                break
            outputfile.write(buf)
            rem -= len(buf)

class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True

handler = functools.partial(RangeHandler, directory=directory)
ThreadedHTTPServer(("127.0.0.1", port), handler).serve_forever()
PYEOF
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
