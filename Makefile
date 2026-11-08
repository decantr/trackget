APP = build/TrackGet.app
ZIP = build/TrackGet.zip
BIN = .build/release/trackget
VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')

# Swift Testing ships with Xcode, not the Command Line Tools
XCODE_DIR = $(shell [ -d /Applications/Xcode.app ] && echo /Applications/Xcode.app/Contents/Developer)

.PHONY: bootstrap build test lint icon app zip run install clean

bootstrap:
	mise install
	swift package resolve

build:
	swift build -c release

test:
	$(if $(XCODE_DIR),DEVELOPER_DIR=$(XCODE_DIR)) swift test

lint:
	actionlint

# Run after editing Resources/AppIcon.svg; the .icns is committed so builds need no renderer
icon:
	rm -rf build/AppIcon.iconset
	swift scripts/icon.swift Resources/AppIcon.svg build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/trackget
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	if [ -n "$(VERSION)" ]; then \
		/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" $(APP)/Contents/Info.plist; \
		/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" $(APP)/Contents/Info.plist; \
	fi
	codesign --force --sign - $(APP)

zip: app
	rm -f $(ZIP) $(ZIP).sha256
	ditto -c -k --keepParent $(APP) $(ZIP)
	cd build && shasum -a 256 TrackGet.zip > TrackGet.zip.sha256

run: app
	open $(APP)

install: app
	rm -rf /Applications/TrackGet.app
	cp -R $(APP) /Applications/

clean:
	rm -rf .build build
