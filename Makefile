# Ledge — build and packaging.
#
# SwiftPM builds a bare Mach-O executable, but a menu bar app needs a bundle: LSUIElement lives
# in Info.plist, and — more importantly — Accessibility permission is granted to a *bundle
# identity*. A loose binary has none, so `swift run` can never hold the permission this app
# depends on. Use `make run`, which launches the assembled bundle instead.
#
# The ad-hoc signature (`codesign --sign -`) is the most this can do without a paid Developer
# account. It is enough for macOS to accept the bundle locally, and combined with the fixed
# CFBundleIdentifier in Resources/Info.plist it is enough for the Accessibility grant to survive
# a rebuild.

CONFIG ?= release
APP_NAME := Ledge
BUNDLE := dist/$(APP_NAME).app
CONTENTS := $(BUNDLE)/Contents

# Recursively expanded on purpose, so `make clean` and `make test` never invoke it. `swift build
# --show-bin-path` only prints a path; it resolves the per-architecture directory that
# .build/$(CONFIG) is a symlink to, which is more reliable than hard-coding either.
BIN_DIR = $(shell swift build -c $(CONFIG) --show-bin-path)

.PHONY: all build app install run test clean

all: app

## Compile. On Linux this builds and tests LedgeCore only — the Ledge target is added to
## Package.swift under `#if os(macOS)`.
build:
	swift build -c $(CONFIG)

## Assemble dist/Ledge.app and sign it ad-hoc.
app: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	cp "$(BIN_DIR)/$(APP_NAME)" "$(CONTENTS)/MacOS/$(APP_NAME)"
	codesign --force --sign - "$(BUNDLE)"
	@echo "Built $(BUNDLE) — verify with: codesign -dv $(BUNDLE)"

## Replace the copy in /Applications. Launch-at-login via SMAppService expects the app to live
## somewhere the system can find it, so install before testing that menu item.
install: app
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(BUNDLE)" /Applications/
	@echo "Installed /Applications/$(APP_NAME).app"

## Launch the bundle, not the bare binary, so it runs under the identity that holds the
## Accessibility grant.
run: app
	open "$(BUNDLE)"

test:
	swift test

clean:
	rm -rf dist
	swift package clean
