APP = build/trackget.app
BIN = .build/release/trackget

.PHONY: bootstrap build app run install clean

bootstrap:
	swift package resolve

build:
	swift build -c release

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BIN) $(APP)/Contents/MacOS/trackget
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)

run: app
	open $(APP)

install: app
	rm -rf /Applications/trackget.app
	cp -R $(APP) /Applications/

clean:
	rm -rf .build build
