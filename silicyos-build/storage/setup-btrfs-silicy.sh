#!/usr/bin/env bash
# ==============================================================================
# silicyOS Btrfs Storage Engine Provisioner
# Target: Apple Silicon Internal NVMe (Soldered SSD Longevity + zstd:3 Force)
# ==============================================================================
set -euo pipefail

ROOT_PART="${1:-}"
EFI_PART="${2:-}"
TARGET_MNT="${3:-/mnt/silicyos}"

if [[ -z "${ROOT_PART}" ]]; then
    echo "Usage: $0 <ROOT_PARTITION> [EFI_PARTITION] [MOUNT_POINT]" >&2
    echo "Example: $0 /dev/nvme0n1p5 /dev/nvme0n1p4 /mnt/silicyos" >&2
    exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] This script must be run as root." >&2
    exit 1
fi

if [[ ! -b "${ROOT_PART}" ]]; then
    echo "[ERROR] Block device ${ROOT_PART} does not exist." >&2
    exit 1
fi

if [[ -n "${EFI_PART}" && ! -b "${EFI_PART}" ]]; then
    echo "[ERROR] EFI block device ${EFI_PART} does not exist." >&2
    exit 1
fi

BTRFS_OPTS="rw,noatime,compress-force=zstd:3,ssd,discard=async,space_cache=v2,commit=120"
SUBVOLS=("@" "@home" "@pkg" "@log" "@snapshots")

echo "[1/6] Formatting ${ROOT_PART} as Btrfs (label: silicyOS)..."
mkfs.btrfs -f -L "silicyOS" --nodesize 16384 "${ROOT_PART}"

echo "[2/6] Mounting top-level Btrfs volume (subvolid=5) to create subvolumes..."
mkdir -p "${TARGET_MNT}"
mount -t btrfs -o "rw,noatime,ssd" "${ROOT_PART}" "${TARGET_MNT}"

for sv in "${SUBVOLS[@]}"; do
    echo "  -> Creating subvolume ${sv}"
    btrfs subvolume create "${TARGET_MNT}/${sv}"
done

umount "${TARGET_MNT}"

echo "[3/6] Mounting @ root subvolume with Apple SSD preservation & zstd:3 options..."
mount -t btrfs -o "${BTRFS_OPTS},subvol=@" "${ROOT_PART}" "${TARGET_MNT}"

echo "[4/6] Creating mountpoints and mounting child subvolumes (@home, @pkg, @log, @snapshots)..."
mkdir -p \
    "${TARGET_MNT}/home" \
    "${TARGET_MNT}/var/cache/pacman/pkg" \
    "${TARGET_MNT}/var/log" \
    "${TARGET_MNT}/.snapshots" \
    "${TARGET_MNT}/boot/efi" \
    "${TARGET_MNT}/etc"

mount -t btrfs -o "${BTRFS_OPTS},subvol=@home"      "${ROOT_PART}" "${TARGET_MNT}/home"
mount -t btrfs -o "${BTRFS_OPTS},subvol=@pkg"       "${ROOT_PART}" "${TARGET_MNT}/var/cache/pacman/pkg"
mount -t btrfs -o "${BTRFS_OPTS},subvol=@log"       "${ROOT_PART}" "${TARGET_MNT}/var/log"
mount -t btrfs -o "${BTRFS_OPTS},subvol=@snapshots" "${ROOT_PART}" "${TARGET_MNT}/.snapshots"

if [[ -n "${EFI_PART}" ]]; then
    echo "  -> Mounting Apple/Asahi EFI System Partition ${EFI_PART} at /boot/efi..."
    mount "${EFI_PART}" "${TARGET_MNT}/boot/efi"
fi

echo "[5/6] Resolving filesystem UUIDs..."
udevadm settle || true
ROOT_UUID="$(blkid -s UUID -o value "${ROOT_PART}")"
if [[ -z "${ROOT_UUID}" ]]; then
    echo "[ERROR] Failed to retrieve UUID for ${ROOT_PART}." >&2
    exit 1
fi

EFI_UUID=""
if [[ -n "${EFI_PART}" ]]; then
    EFI_UUID="$(blkid -s UUID -o value "${EFI_PART}")"
fi

echo "[6/6] Generating ${TARGET_MNT}/etc/fstab..."
cat <<EOF > "${TARGET_MNT}/etc/fstab"
# /etc/fstab: static file system information for silicyOS (Apple Silicon ARM64)
# Generated automatically by setup-btrfs-silicy.sh
#
# <file system>                           <dir>                   <type>  <options>                                                                                   <dump> <pass>
UUID=${ROOT_UUID}                         /                       btrfs   ${BTRFS_OPTS},subvol=@                                                                      0      0
UUID=${ROOT_UUID}                         /home                   btrfs   ${BTRFS_OPTS},subvol=@home                                                                  0      0
UUID=${ROOT_UUID}                         /var/cache/pacman/pkg   btrfs   ${BTRFS_OPTS},subvol=@pkg                                                                   0      0
UUID=${ROOT_UUID}                         /var/log                btrfs   ${BTRFS_OPTS},subvol=@log                                                                   0      0
UUID=${ROOT_UUID}                         /.snapshots             btrfs   ${BTRFS_OPTS},subvol=@snapshots                                                             0      0
tmpfs                                     /tmp                    tmpfs   rw,nosuid,nodev,noatime,size=1G,mode=1777                                                   0      0
EOF

if [[ -n "${EFI_UUID}" ]]; then
    cat <<EOF >> "${TARGET_MNT}/etc/fstab"
UUID=${EFI_UUID}                          /boot/efi               vfat    rw,noatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro 0      2
EOF
fi

echo "[DONE] silicyOS Btrfs storage hierarchy is mounted at ${TARGET_MNT} and /etc/fstab is ready."
