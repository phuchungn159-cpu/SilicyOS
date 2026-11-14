# Security Policy

## Scope & Design Model

`silicyOS` enforces strict privilege and partition boundaries on Apple Silicon dual-boot systems:

- **macOS APFS Safety**: `silicy-macos-bridge` mounts the macOS APFS container strictly read-only (`apfs-fuse` / `fsapfsmount`) and never performs read-write APFS operations.
- **Scoped Rootless Controls**: `71-silicy-macsmc.rules` and `/etc/sudoers.d/20-silicy-nopasswd` grant `wheel` group access strictly to `macsmc-battery` thresholds, `cpufreq` policies, backlights, `silicy-ctl`, `silicy-capsule`, `silicy-macos-bridge`, `keyd`, and `systemctl restart keyd.service`.
- **No Unverified Binaries**: Large installer disk archives (`silicyos-apple-silicon.zip`, `*.img`) are excluded from git source tracking and are meant to be built reproducibly from source or verified via release checksums.

## Reporting a Vulnerability

If you discover a privilege escalation issue in udev/sudoers rules, an unsafe mount/rollback path in `silicy-capsule` or `silicy-macos-bridge`, or a memory-safety defect in `silicy-ctl.c`:

1. Open a private security advisory on GitHub (**Security -> Advisories -> Report a vulnerability**) if available, or open a minimal issue requesting a private channel without posting exploit details publicly.
2. Include the affected file path, reproduction steps, and hardware/OS environment (`M1`/`M2`/`M3`, kernel version).
