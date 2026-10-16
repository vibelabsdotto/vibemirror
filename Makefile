SHELL := /bin/bash

APP_NAME     := VibeMirror
BUILD_DIR    := build
APP          := $(BUILD_DIR)/$(APP_NAME).app
ENTITLEMENTS := Resources/VibeMirror.entitlements
VERSION      := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
GITHUB_REPO  := vibelabsdotto/vibemirror

# Release signing. Any "Developer ID Application" identity in the keychain works.
SIGN_IDENTITY ?= Developer ID Application
# JSON with apple_key_id, apple_issuer_id, apple_key_path (App Store Connect API key).
NOTARY_CONFIG ?= $(HOME)/VibeLabs/mobile-app-release-config/max_dev_config.json

.PHONY: build app run list icon release publish clean

build:
	swift build

# Debug app bundle, ad-hoc signed. macOS asks for camera access again after each rebuild.
app: build
	@$(MAKE) --no-print-directory bundle BIN="$$(swift build --show-bin-path)/$(APP_NAME)"
	codesign --force --sign - --entitlements $(ENTITLEMENTS) $(APP)

run: app
	@pkill -x $(APP_NAME) 2>/dev/null || true
	open $(APP)

# Lists connected iOS devices without opening a window.
list: app
	$(APP)/Contents/MacOS/$(APP_NAME) --list

bundle:
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@cp "$(BIN)" $(APP)/Contents/MacOS/$(APP_NAME)
	@cp Resources/Info.plist $(APP)/Contents/Info.plist
	@cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	@echo "bundled $(APP)"

icon:
	swift scripts/make-icon.swift .
	iconutil -c icns $(BUILD_DIR)/AppIcon.iconset -o Resources/AppIcon.icns

# Universal, Developer ID signed, notarized and stapled zip in build/.
release:
	swift build -c release --arch arm64 --arch x86_64
	@$(MAKE) --no-print-directory bundle BIN="$$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$(APP_NAME)"
	codesign --force --timestamp --options runtime --entitlements $(ENTITLEMENTS) --sign "$(SIGN_IDENTITY)" $(APP)
	codesign --verify --strict --verbose=2 $(APP)
	ditto -c -k --keepParent $(APP) $(BUILD_DIR)/notarize.zip
	@read -r KEY_ID ISSUER KEY_PATH < <(python3 -c "import json;d=json.load(open('$(NOTARY_CONFIG)'));print(d['apple_key_id'],d['apple_issuer_id'],d['apple_key_path'])"); \
	xcrun notarytool submit $(BUILD_DIR)/notarize.zip --key "$$KEY_PATH" --key-id "$$KEY_ID" --issuer "$$ISSUER" --wait
	xcrun stapler staple $(APP)
	spctl --assess --type execute --verbose $(APP)
	@rm -f $(BUILD_DIR)/notarize.zip
	ditto -c -k --keepParent $(APP) $(BUILD_DIR)/$(APP_NAME)-$(VERSION).zip
	@echo "$(BUILD_DIR)/$(APP_NAME)-$(VERSION).zip"

publish:
	@test -f $(BUILD_DIR)/$(APP_NAME)-$(VERSION).zip || { echo "run 'make release' first"; exit 1; }
	gh release create v$(VERSION) $(BUILD_DIR)/$(APP_NAME)-$(VERSION).zip --repo $(GITHUB_REPO) --title "$(APP_NAME) $(VERSION)" --generate-notes

clean:
	rm -rf .build $(BUILD_DIR)
