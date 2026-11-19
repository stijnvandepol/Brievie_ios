PACKAGE := Packages/BrievieKit
# Preferred simulator name; the device is picked by UDID on the newest iOS runtime
# (scripts/simulator-udid.sh). Set SIMULATOR_ID to use a specific device.
SIMULATOR ?= iPhone 17
SIMULATOR_ID ?=
HOST ?= ../Brievie_host

.PHONY: generate check-project test coverage lint build test-keychain sync-api archive

generate:
	xcodegen generate
	@mkdir -p Brievie.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
	@cp $(PACKAGE)/Package.resolved Brievie.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

# The project is committed for Xcode Cloud; it must match project.yml.
check-project: generate
	git diff --exit-code -- Brievie.xcodeproj

test:
	swift test --package-path $(PACKAGE)

# `make test` with code coverage: prints line coverage per target, writes build/coverage/{summary.txt,codecov.json}.
coverage:
	swift test --package-path $(PACKAGE) --enable-code-coverage
	scripts/coverage-summary.sh "$$(swift test --package-path $(PACKAGE) --show-codecov-path)" build/coverage

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

# Release archive for TestFlight. Upload goes through Xcode Organizer (open build/Brievie.xcarchive).
archive:
	xcodegen generate
	xcodebuild archive \
		-project Brievie.xcodeproj \
		-scheme Brievie \
		-configuration Release \
		-destination "generic/platform=iOS" \
		-archivePath build/Brievie.xcarchive \
		-skipPackagePluginValidation \
		-allowProvisioningUpdates
