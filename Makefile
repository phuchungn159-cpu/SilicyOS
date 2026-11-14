.PHONY: help verify build-macos build-linux install-macos clean distclean

SHELL := /usr/bin/env bash
BUILD_DIR := silicyos-build

help:
	@echo "silicyOS Build & Verification Targets"
	@echo ""
	@echo "  make verify         Run the 8-stage QA & mock-sysroot audit (verify-silicyos.sh)"
	@echo "  make build-macos    Build silicyos-apple-silicon.zip on macOS via Lima Apple VZ"
	@echo "  make build-linux    Build silicyos-apple-silicon.zip directly on Linux ARM64 (root)"
	@echo "  make install-macos  Launch local Asahi installer for silicyos-apple-silicon.zip"
	@echo "  make clean          Remove compiled silicy-ctl binary and temporary dry-run artifacts"
	@echo "  make distclean      Also remove generated disk images and silicyos-apple-silicon.zip"

verify:
	@bash $(BUILD_DIR)/verify-silicyos.sh

build-macos:
	@cd $(BUILD_DIR) && ./macos-build-and-install.sh

build-linux:
	@cd $(BUILD_DIR) && sudo ./build-silicyos.sh

install-macos:
	@cd $(BUILD_DIR) && ./install-silicyos-macos.sh

clean:
	@$(MAKE) -C $(BUILD_DIR)/silicy-ctl clean
	@rm -rf /tmp/silicyos-dryrun.*

distclean: clean
	@rm -f $(BUILD_DIR)/*.img $(BUILD_DIR)/silicyos-apple-silicon.zip
