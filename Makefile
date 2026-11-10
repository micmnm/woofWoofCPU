# Xcode's toolchain even while xcode-select points at the Command Line Tools,
# whose Swift Testing macro plugin fails on multi-file test targets.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
DERIVED := $(ROOT)/build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/woofWoofCPU.app
RELEASE_APP := $(DERIVED)/Build/Products/Release/woofWoofCPU.app
MIAW := $(ROOT)/Tools/miawMiawCPU

DIST := $(ROOT)/dist

.PHONY: test project build run install dist miaw tidy clean

# make test FILTER=MachTimeTests  — run one suite or test (the filter goes to both packages)
test:
	swift test --package-path $(ROOT)/Packages/WoofCore $(if $(FILTER),--filter $(FILTER))
	swift test --package-path $(MIAW) $(if $(FILTER),--filter $(FILTER))

# The stress toy that gives the dog something to bark at: bin/miawMiawCPU help
miaw:
	swift build -c release --package-path $(MIAW)
	mkdir -p $(ROOT)/bin
	cp "$$(swift build -c release --package-path $(MIAW) --show-bin-path)/miawMiawCPU" $(ROOT)/bin/miawMiawCPU

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

# Apple silicon only, ad-hoc signed (not notarized) app and drag-to-Applications dmg for direct download, kept in dist/;
# the ~1 GB of build intermediates is dropped afterwards.
dist: project
	xcodebuild -quiet -project $(ROOT)/WoofWoofCPU.xcodeproj -scheme WoofWoofCPU \
		-destination "generic/platform=macOS" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
		-configuration Release -derivedDataPath $(DERIVED) build
	codesign --verify --deep --strict $(RELEASE_APP)
	rm -rf $(DIST)
	mkdir -p $(DIST)
	ditto $(RELEASE_APP) $(DIST)/woofWoofCPU.app
	mkdir -p $(DIST)/dmg
	ditto $(RELEASE_APP) $(DIST)/dmg/woofWoofCPU.app
	ln -s /Applications $(DIST)/dmg/Applications
	hdiutil create -quiet -volname woofWoofCPU -srcfolder $(DIST)/dmg -format UDZO -ov \
		"$(DIST)/woofWoofCPU-$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $(RELEASE_APP)/Contents/Info.plist).dmg"
	rm -rf $(DIST)/dmg
	$(MAKE) tidy

# Drops build intermediates; keeps the products in dist/ and bin/.
tidy:
	rm -rf $(ROOT)/build $(ROOT)/Packages/WoofCore/.build $(MIAW)/.build $(ROOT)/WoofWoofCPU.xcodeproj

clean: tidy
	rm -rf $(ROOT)/bin $(DIST)
