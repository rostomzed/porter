APP := Porter

.PHONY: build install test test-native clean icon help

help: ## Show available targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

build: ## Build build/Porter.app and build/Porter.dmg (universal)
	./scripts/build.sh

install: build ## Install to /Applications + the `porter` CLI, then launch
	./scripts/install.sh

test: ## Full test suite (includes Office/iWork engines — local Macs only)
	./scripts/test.sh

test-native: ## Native-engine tests only (what CI runs)
	./scripts/test.sh --native

icon: ## Regenerate docs/icon.png from scripts/make-icon.swift
	swift scripts/make-icon.swift docs/icon.png 512

clean: ## Remove build artifacts
	rm -rf build
