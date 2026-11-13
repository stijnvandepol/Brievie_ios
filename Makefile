PACKAGE := Packages/BrievieKit
SIMULATOR ?= iPhone 17
HOST ?= ../Brievie_host

.PHONY: generate test lint build sync-api

generate:
	xcodegen generate

test:
	swift test --package-path $(PACKAGE)

lint:
	swiftlint --strict

build:
	xcodebuild build \
		-project Brievie.xcodeproj \
		-scheme Brievie \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR),OS=latest' \
		-skipPackagePluginValidation \
		-quiet

sync-api:
	@test -f "$(HOST)/docs/api/openapi.json" || { echo "No openapi.json at $(HOST)/docs/api"; exit 1; }
	cp "$(HOST)/docs/api/openapi.json" $(PACKAGE)/Sources/BrievieAPI/openapi.json
