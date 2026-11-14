## Summary

<!-- Describe what this pull request changes and why. -->

## Hardware & Environment Tested

- [ ] `bash silicyos-build/verify-silicyos.sh` (`205 PASS | 0 WARN | 0 FAIL`)
- [ ] macOS Lima Apple VZ full rootfs + `.zip` build
- [ ] Apple Silicon bare-metal boot / live session verification

## Checklist

- [ ] Zero emojis in source code, scripts, configs, and logs
- [ ] Pure-C stack-only telemetry preserved (`silicy-ctl.c`, zero bash sysfs polling)
- [ ] Strict 16KB page alignment & Apple firmware whitelists intact
- [ ] Apple Industrial Titanium palette tokens preserved
