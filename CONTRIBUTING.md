# Contributing to silicyOS

Thank you for helping improve `silicyOS`. Every pull request must preserve strict hardware alignment, minimalist resource usage, and clean system-level design.

## Engineering Standards

1. **Zero AI Slop**:
   - Do not include decorative emojis in source code, comments, systemd units, configuration files, or documentation.
   - Never leave placeholder stubs (`TODO`, `...`, `implement later`).
2. **Pure-C Hardware Telemetry (`silicy-ctl`)**:
   - Continuous hardware or `sysfs` reads must remain in strict C11 using raw syscalls (`open`, `pread`, `pwrite`, `sched_setaffinity`) and stack-only buffers.
   - Zero heap allocations (`malloc`, `calloc`, `realloc`, `free`) and zero bash polling loops (`while true; do cat /sys/...; sleep ...; done`).
   - Must compile with `-std=c11 -Wall -Wextra -Werror -O3 -mcpu=apple-m1 -flto=thin`.
3. **16KB Apple Silicon Page Alignment**:
   - Keep `CONFIG_ARM64_16K_PAGES=y`, `CONFIG_ARM64_PAGE_SHIFT=14`, and `vm.page-cluster = 0`.
   - Never inject x86_64 flags (`-march=x86-64`, `-mavx`, `-msse*`) into kernel, `makepkg`, or C flags.
   - Never block Apple firmware or bootloader assets (`brcm/*`, `apple/*`, `vendor/*`, `regulatory.db*`, `asahi-boot/*`) in `pacman-silicy.conf` `NoExtract`.
4. **Apple Industrial Titanium Palette**:
   - All desktop UI components must adhere strictly to `#0B0B0E`, `#141418`, `#26262E`, `#F2F2F7`, `#8E8E93`, and `#0A84FF`.

## Mandatory Verification Gate

Before opening a pull request, run the full 8-stage verification suite and ensure zero failures and zero warnings:

```bash
make verify
```

All commits affecting rootfs staging, boot chain, or udev rules should clearly note whether they were tested on macOS, Linux ARM64 VM, or Apple Silicon bare metal.
