# Ledge — build and packaging.
#
# SwiftPM builds a bare Mach-O executable, but a menu bar app needs a bundle: LSUIElement lives
# in Info.plist, and — more importantly — Accessibility permission is granted to a *bundle
# identity*. A loose binary has none, so `swift run` can never hold the permission this app
# depends on. Use `make run`, which launches the assembled bundle instead.
#
# The ad-hoc signature (`codesign --sign -`) is the most this can do without a paid Developer
# account. It is enough for macOS to accept the bundle locally.
#
# It is NOT enough for the Accessibility grant to survive a rebuild, and the fixed
# CFBundleIdentifier in Resources/Info.plist does not make it so. TCC matches a designated
# requirement, and for an ad-hoc signature that requirement is derived from the code directory
# hash — which changes every time the binary changes. So after a rebuild the app is, to TCC, a
# different program wearing the same name.
#
# The symptom is nastier than an outright refusal: the app still appears in
# Privacy & Security > Accessibility, still shows its checkbox enabled, and the grant does
# nothing. `CGEvent.tapCreate` returns nil and the app reports no permission while the settings
# pane insists otherwise. Do not spend time on the event tap before ruling this out — a nil
# `tapCreate` looks identical to the tap simply not delivering gesture events.
#
# When that happens: `make reset-permission`, relaunch, and grant again. Removing the entry by
# hand with the "-" button in the settings pane does the same job.
#
# The way to avoid it altogether, still with no paid account: sign with a stable self-signed
# code-signing certificate from Keychain Access instead of ad-hoc. A certificate that does not
# change between builds gives a designated requirement that does not either, so the grant sticks.
# Swap the `codesign --sign -` below for `codesign --sign "<certificate name>"`.

CONFIG ?= release
APP_NAME := Ledge
SIGNING_IDENTITY ?= Apple Development: trituyen2003@gmail.com (NZFRWQGKR8)
BUNDLE := dist/$(APP_NAME).app
CONTENTS := $(BUNDLE)/Contents

# Recursively expanded on purpose, so `make clean` and `make test` never invoke it. `swift build
# --show-bin-path` only prints a path; it resolves the per-architecture directory that
# .build/$(CONFIG) is a symlink to, which is more reliable than hard-coding either.
BIN_DIR = $(shell swift build -c $(CONFIG) --show-bin-path)

BUNDLE_ID := xyz.tuyennedd.ledge

.PHONY: all build app dmg install reinstall run test cert reset-permission clean

all: app

## Compile. On Linux this builds and tests LedgeCore only — the Ledge target is added to
## Package.swift under `#if os(macOS)`.
build:
	swift build -c $(CONFIG)

## Assemble dist/Ledge.app and sign it ad-hoc.
app: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources" "$(CONTENTS)/Frameworks"
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	cp "$(BIN_DIR)/$(APP_NAME)" "$(CONTENTS)/MacOS/$(APP_NAME)"
	@# Add rpath so the binary finds frameworks in Contents/Frameworks/
	install_name_tool -add_rpath @executable_path/../Frameworks "$(CONTENTS)/MacOS/$(APP_NAME)" 2>/dev/null || true
	@# Copy Sparkle.framework into the bundle so the dynamic linker can find it at @rpath
	@SPARKLE_PATH=$$(find .build -path "*/release/Sparkle.framework" -type d 2>/dev/null | head -1); \
	if [ -z "$$SPARKLE_PATH" ]; then \
		SPARKLE_PATH=$$(find .build -path "*/Sparkle.framework" -type d 2>/dev/null | head -1); \
	fi; \
	if [ -n "$$SPARKLE_PATH" ]; then \
		cp -R "$$SPARKLE_PATH" "$(CONTENTS)/Frameworks/Sparkle.framework"; \
		echo "Copied $$SPARKLE_PATH"; \
	else \
		echo "WARNING: Sparkle.framework not found in .build/"; \
	fi
	codesign --force --deep --sign "$(SIGNING_IDENTITY)" "$(BUNDLE)"
	@echo "Built $(BUNDLE) — verify with: codesign -dv $(BUNDLE)"
	@echo "# Ad-hoc: make app SIGNING_IDENTITY=\"-\""

## Create a distributable .dmg disk image with ad-hoc signing (no developer certificate needed).
## The version is extracted from Resources/Info.plist CFBundleShortVersionString.
dmg:
	$(MAKE) app SIGNING_IDENTITY="-"
	$(eval VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist))
	rm -rf dist/dmg-staging
	mkdir -p dist/dmg-staging
	cp -R "$(BUNDLE)" dist/dmg-staging/
	ln -s /Applications dist/dmg-staging/Applications
	@printf '%s\n' \
		"Ledge — First Run Guide" \
		"" \
		"1. Drag Ledge.app to the Applications folder (shortcut is right here)" \
		"" \
		"2. If macOS says \"cannot be opened because the developer cannot be verified\":" \
		"   → Right-click (or Control-click) Ledge.app" \
		"   → Click \"Open\" from the menu" \
		"   → Click \"Open\" in the dialog" \
		"   (You only need to do this once)" \
		"" \
		"3. Grant Accessibility permission when asked, then relaunch the app" \
		"" \
		"4. Slide along the right edge of your trackpad — volume should change!" \
		"" \
		"Tips:" \
		"- Settings: click the menu bar icon → Settings... (or ⌘,)" \
		"- Left edge = brightness, right edge = volume" \
		"- The gesture zone is very close to the physical edge (~4mm)" \
		> dist/dmg-staging/FIRST-RUN.txt
	rm -f "dist/$(APP_NAME)-$(VERSION).dmg"
	hdiutil create -volname "$(APP_NAME)" \
		-srcfolder dist/dmg-staging \
		-ov -format UDZO \
		"dist/$(APP_NAME)-$(VERSION).dmg"
	rm -rf dist/dmg-staging
	@echo "Created dist/$(APP_NAME)-$(VERSION).dmg"

## Replace the copy in /Applications. Launch-at-login via SMAppService expects the app to live
## somewhere the system can find it, so install before testing that menu item.
install: app
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(BUNDLE)" /Applications/
	@echo "Installed /Applications/$(APP_NAME).app"

## Quit, rebuild, install, and relaunch in one step. Useful during development when the app is
## already running.
reinstall:
	osascript -e 'quit app "Ledge"' || true
	sleep 1
	$(MAKE) install
	open /Applications/$(APP_NAME).app

## Launch the bundle, not the bare binary, so it runs under the identity that holds the
## Accessibility grant.
run: app
	open "$(BUNDLE)"

## Forget the Accessibility decision for this bundle id, so the next launch asks again.
##
## Only needed with ad-hoc signing (SIGNING_IDENTITY="-"), because the ad-hoc signature's
## designated requirement changes with the binary and TCC keeps matching the old one — see the
## note at the top of this file. When using a stable certificate (the default "Ledge Dev") the
## grant persists across rebuilds and this target is unnecessary.
##
## Run this whenever the app claims it has no permission while the settings pane shows it enabled.
## Quit the app first; then relaunch and grant when prompted.
## Ensure the Apple WWDR intermediate certificate is in the keychain so the Apple Development
## identity is trusted. Only needed once — after creating the cert in Xcode.
## For a fresh machine: open Xcode → Settings → Accounts → Manage Certificates → + Apple Development
cert:
	@if security find-identity -v -p codesigning | grep -q "Apple Development"; then \
		echo "Apple Development certificate is valid and trusted."; \
	else \
		echo "Downloading Apple WWDR intermediate certificate..."; \
		curl -sO https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer; \
		security import AppleWWDRCAG3.cer -k ~/Library/Keychains/login.keychain-db; \
		rm -f AppleWWDRCAG3.cer; \
		if security find-identity -v -p codesigning | grep -q "Apple Development"; then \
			echo "Done! Certificate is now trusted."; \
		else \
			echo "Certificate still not valid. Open Xcode → Settings → Accounts → Manage Certificates → + Apple Development"; \
			exit 1; \
		fi; \
	fi

reset-permission:
	tccutil reset Accessibility $(BUNDLE_ID)
	@echo "Reset Accessibility for $(BUNDLE_ID) — relaunch the app and grant again."

test:
	swift test

clean:
	rm -rf dist
	swift package clean
