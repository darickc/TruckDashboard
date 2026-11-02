# TruckDashboard — F-250 AGL head unit. `make help` lists targets.
#
# Test and lint targets cover only the components that exist. A component that
# hasn't landed yet prints a "skip" line saying which phase adds it, and exits 0.
# Run targets (ui, sim, deploy, logs) exit non-zero until their phase lands, so
# they can never look like they ran.

SHELL := /bin/bash
ROOT  := $(shell git rev-parse --show-toplevel)

PIO     ?= $(shell command -v pio 2>/dev/null || echo $(HOME)/.platformio/penv/bin/pio)
FLUTTER ?= fvm flutter
# Homebrew's rustup is keg-only; make cargo reachable without shell changes.
export PATH := $(shell brew --prefix rustup 2>/dev/null)/bin:$(HOME)/.cargo/bin:$(PATH)

FW_DIR  := firmware/esp32
APP_DIR := apps/infotainment

HAVE_CARGO   := $(wildcard Cargo.toml)
HAVE_APP     := $(wildcard $(APP_DIR)/pubspec.yaml)
HAVE_PROTO   := $(wildcard shared/proto/buf.yaml)

skip = @echo "skip: $(1)"

.PHONY: help setup doctor test lint \
        fw-test fw-build \
        rust-test rust-lint linux-test \
        proto proto-lint \
        ui ui-test ui-lint \
        sim deploy logs docs-lint

help: ## List targets
	@grep -hE '^[a-z][a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*## "}; {printf "  \033[1m%-12s\033[0m %s\n", $$1, $$2}'

# ---- environment ------------------------------------------------------------

setup: ## Install/check the macOS dev toolchain (Homebrew, rustup, fvm, buf)
	tools/dev/setup-macos.sh

doctor: ## Print tool versions without installing anything
	@echo "rustc:   $$(rustc --version 2>/dev/null || echo missing)"
	@echo "cargo:   $$(cargo --version 2>/dev/null || echo missing)"
	@echo "flutter: $$($(FLUTTER) --version 2>/dev/null | head -1 || echo missing)"
	@echo "protoc:  $$(protoc --version 2>/dev/null || echo missing)"
	@echo "buf:     $$(buf --version 2>/dev/null || echo missing)"
	@echo "pio:     $$($(PIO) --version 2>/dev/null || echo missing)"
	@echo "docker:  $$(docker --version 2>/dev/null || echo missing)"

# ---- aggregate --------------------------------------------------------------

test: fw-test rust-test ui-test ## Run every test available in this environment

lint: docs-lint rust-lint proto-lint ui-lint ## Run every linter available

# ---- ESP32 firmware (existing) ---------------------------------------------

fw-test: ## ESP32 host-side unit tests (no hardware)
	cd $(FW_DIR) && $(PIO) test -e native

fw-build: ## Build the ESP32 firmware
	cd $(FW_DIR) && $(PIO) run -e esp32dev

# ---- Rust (Phase 3) ---------------------------------------------------------

rust-test: ## Rust workspace tests
ifneq ($(HAVE_CARGO),)
	cargo test --workspace
else
	$(call skip,rust-test — no Cargo workspace yet (Phase 3))
endif

rust-lint: ## rustfmt + clippy
ifneq ($(HAVE_CARGO),)
	cargo fmt --all -- --check
	cargo clippy --workspace --all-targets -- -D warnings
else
	$(call skip,rust-lint — no Cargo workspace yet (Phase 3))
endif

linux-test: ## Rust tests inside Linux (Docker), including Linux-only code
ifneq ($(HAVE_CARGO),)
	docker run --rm -v "$(ROOT)":/src -w /src rust:1 cargo test --workspace
else
	$(call skip,linux-test — no Cargo workspace yet (Phase 3))
endif

# ---- protobuf API (Phase 3) -------------------------------------------------

proto: ## Generate Rust/Dart code from shared/proto
ifneq ($(HAVE_PROTO),)
	cd shared/proto && buf generate
else
	$(call skip,proto — no shared/proto/buf.yaml yet (Phase 3))
endif

proto-lint: ## buf lint
ifneq ($(HAVE_PROTO),)
	cd shared/proto && buf lint
else
	$(call skip,proto-lint — no protos yet (Phase 3))
endif

# ---- Flutter UI (Phase 2) ---------------------------------------------------

ui: ## Run the dashboard on macOS (800x480 window)
ifneq ($(HAVE_APP),)
	cd $(APP_DIR) && $(FLUTTER) run -d macos
else
	@echo "ui: the Flutter app does not exist yet (Phase 2)"; exit 1
endif

ui-test: ## Flutter widget/unit tests
ifneq ($(HAVE_APP),)
	cd $(APP_DIR) && $(FLUTTER) test
else
	$(call skip,ui-test — no Flutter app yet (Phase 2))
endif

ui-lint: ## flutter analyze
ifneq ($(HAVE_APP),)
	cd $(APP_DIR) && $(FLUTTER) analyze
else
	$(call skip,ui-lint — no Flutter app yet (Phase 2))
endif

# ---- docs -------------------------------------------------------------------

docs-lint: ## Check relative Markdown links
	python3 tools/dev/check_links.py

# ---- not yet available ------------------------------------------------------

sim: ## Gateway with the simulated transport driving the UI (Phase 3)
	@echo "sim: available from Phase 3 (vehicle-gateway + simulated transport)"; exit 1

deploy: ## Copy services + UI bundle to a Pi: make deploy PI=<host> (Phase 5)
	@echo "deploy: available from Phase 5"; exit 1

logs: ## Collect service logs from a Pi: make logs PI=<host> (Phase 5)
	@echo "logs: available from Phase 5"; exit 1
