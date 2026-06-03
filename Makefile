APP_NAME = PGPMenu
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
SOURCES = $(wildcard Sources/*.swift)
ARCH = $(shell uname -m)

ifeq ($(ARCH),arm64)
  TARGET = arm64-apple-macosx12.0
else
  TARGET = x86_64-apple-macosx12.0
endif

.PHONY: all clean install run

all: $(APP_BUNDLE)

$(APP_BUNDLE): $(SOURCES) Resources/Info.plist
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	swiftc -o $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME) \
		-target $(TARGET) \
		-framework Cocoa \
		-O \
		$(SOURCES)
	@cp Resources/Info.plist $(APP_BUNDLE)/Contents/

clean:
	rm -rf $(BUILD_DIR)

install: $(APP_BUNDLE)
	cp -R $(APP_BUNDLE) /Applications/

run: $(APP_BUNDLE)
	open $(APP_BUNDLE)
