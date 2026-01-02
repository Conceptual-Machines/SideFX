# Convenience Makefile for SideFX Modulation Extension

BUILD_DIR = build

.PHONY: all clean configure build install

all: build

configure:
	@mkdir -p $(BUILD_DIR)
	cd $(BUILD_DIR) && cmake ..

build: configure
	cd $(BUILD_DIR) && cmake --build .

clean:
	rm -rf $(BUILD_DIR)

install: build
	cd $(BUILD_DIR) && cmake --install .

# Development: rebuild and copy to portable REAPER
dev: build
	@echo "Extension copied to reaper-portable/UserPlugins/"

