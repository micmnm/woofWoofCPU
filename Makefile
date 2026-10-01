# Xcode's toolchain even while xcode-select points at the Command Line Tools,
# whose Swift Testing macro plugin fails on multi-file test targets.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
DERIVED := $(ROOT)/build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/woofWoofCPU.app
RELEASE_APP := $(DERIVED)/Build/Products/Release/woofWoofCPU.app

.PHONY: test project build run install clean

# make test FILTER=MachTimeTests  — run one suite or test
test:
	swift test --package-path $(ROOT)/Packages/WoofCore $(if $(FILTER),--filter $(FILTER))

project:
	xcodegen generate --quiet --spec $(ROOT)/project.yml --project $(ROOT)

build: project
	xcodebuild -quiet -project $(ROOT)/WoofWoofCPU.xcodeproj -scheme WoofWoofCPU \
		-destination "platform=macOS,arch=arm64" -configuration Debug -derivedDataPath $(DERIVED) build

run: build
	-pkill -x woofWoofCPU
	open $(APP)

# Launch at login is most reliable from /Applications. Installs a Release build (Debug costs more CPU).
install: project
	xcodebuild -quiet -project $(ROOT)/WoofWoofCPU.xcodeproj -scheme WoofWoofCPU \
		-destination "platform=macOS,arch=arm64" -configuration Release -derivedDataPath $(DERIVED) build
	-pkill -x woofWoofCPU
	ditto $(RELEASE_APP) /Applications/woofWoofCPU.app

clean:
	rm -rf $(ROOT)/build $(ROOT)/Packages/WoofCore/.build $(ROOT)/WoofWoofCPU.xcodeproj
