.DEFAULT_GOAL := help
SHELL         := /bin/bash
VENV_PYTHON   := ./.venv/bin/python

.PHONY: help test check-syntax \
        build-mac build-mac-dmg build-mac-status build-mac-reset \
        build-linux build-linux-status build-linux-reset \
        build-appimage build-rpm clean

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

## ── Verification ──────────────────────────────────────────────
test: ## Run unit tests
	$(VENV_PYTHON) -m unittest discover tests

check-syntax: ## Bytecode compile check across all modules
	$(VENV_PYTHON) -m py_compile src/onthespot/*.py src/onthespot/api/*.py src/onthespot/qt/*.py tests/*.py

## ── macOS Builds (Multiplexer) ────────────────────────────────
build-mac: ## Run all pending macOS build steps -> build/dist/OnTheSpotRebuilt.dmg
	./scripts/build_mux_mac.sh

build-mac-dmg: ## Fast package DMG (skips steps 1-3 if venv & ffmpeg ready)
	./scripts/build_mux_mac.sh --dmg

build-mac-status: ## Show status of macOS build steps
	./scripts/build_mux_mac.sh --status

build-mac-reset: ## Clear macOS build state and rebuild from scratch
	./scripts/build_mux_mac.sh --reset

## ── Linux Builds ──────────────────────────────────────────────
build-linux: ## Run all pending Linux build steps
	./scripts/build_mux_linux.sh

build-linux-status: ## Show status of Linux build steps
	./scripts/build_mux_linux.sh --status

build-linux-reset: ## Clear Linux build state and restart
	./scripts/build_mux_linux.sh --reset

build-appimage: ## Build Linux AppImage bundle
	./scripts/build_appimage.sh

build-rpm: ## Build RPM package
	./scripts/build_rpm.sh

## ── Clean ─────────────────────────────────────────────────────
clean: ## Remove build outputs, state markers, and logs
	rm -rf build/dist build/state build/logs
