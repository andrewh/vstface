# Makefile for vstface

.PHONY: all clean configure vstface fixture help

# Default target
all: vstface

# Configure CMake build
configure:
	cmake -B build -DCMAKE_BUILD_TYPE=Release

# Build vstface binary
vstface: configure
	cmake --build build --target vstface --config Release

# Build test fixture plugin
fixture: configure
	cmake --build build --target vstface_test_fixture --config Release

# Build everything
full: configure
	cmake --build build --config Release

# Clean build directory
clean:
	rm -rf build

# Rebuild from scratch
rebuild: clean all

# Show help
help:
	@echo "vstface Makefile targets:"
	@echo "  make              - Build vstface binary (default)"
	@echo "  make vstface      - Build vstface binary"
	@echo "  make fixture      - Build vstface_test_fixture plugin"
	@echo "  make full         - Build all targets"
	@echo "  make clean        - Remove build directory"
	@echo "  make rebuild      - Clean and rebuild"
	@echo "  make configure    - Run CMake configuration only"
	@echo "  make help         - Show this help message"
	@echo ""
	@echo "Built artifacts:"
	@echo "  ./build/vstface                                      - Main binary"
	@echo "  ./build/VST3/Release/vstface_test_fixture.vst3       - Test plugin"
