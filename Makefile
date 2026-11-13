PACKAGE := Packages/BrievieKit
# Preferred simulator name; the device is picked by UDID on the newest iOS runtime
# (scripts/simulator-udid.sh). Set SIMULATOR_ID to use a specific device.
SIMULATOR ?= iPhone 17
SIMULATOR_ID ?=
HOST ?= ../Brievie_host

.PHONY: generate test lint build test-keychain sync-api

generate:
	xcodegen generate

test:
	swift test --package-path $(PACKAGE)

lint:
	swiftlint --strict

build:
	@udid="$(SIMULATOR_ID)"; [ -n "$$udid" ] || udid=$$(scripts/simulator-udid.sh "$(SIMULATOR)") || exit 1; \
	echo "Simulator $$udid"; \
	xcodebuild build \
		-project Brievie.xcodeproj \
		-scheme Brievie \
		-destination "id=$$udid" \
		-skipPackagePluginValidation \
		-quiet

# Keychain tests need an entitled process: run them hosted in the app on the simulator.
test-keychain:
	@udid="$(SIMULATOR_ID)"; [ -n "$$udid" ] || udid=$$(scripts/simulator-udid.sh "$(SIMULATOR)") || exit 1; \
	echo "Simulator $$udid"; \
	xcodebuild test \
		-project Brievie.xcodeproj \
		-scheme Brievie \
		-destination "id=$$udid" \
		-skipPackagePluginValidation \
		-quiet

sync-api:
	@test -f "$(HOST)/docs/api/openapi.json" || { echo "No openapi.json at $(HOST)/docs/api"; exit 1; }
	cp "$(HOST)/docs/api/openapi.json" $(PACKAGE)/Sources/BrievieAPI/openapi.json
	plutil -extract info.version raw -o - $(PACKAGE)/Sources/BrievieAPI/openapi.json > $(PACKAGE)/Sources/BrievieAPI/API_VERSION
