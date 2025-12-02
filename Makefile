# Makefile for vstface

.PHONY: all clean configure vstface fixture help test check build_tests

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

# Build all test executables and dependencies
build_tests: configure
	cmake --build build --target build_tests --config Release

# Run tests using CTest
test: configure
	cd build && ctest --output-on-failure

# Build and run all tests (recommended)
check: configure
	cmake --build build --target check --config Release

# Show help
help:
	@echo "vstface Makefile targets:"
	@echo ""
	@echo "Build targets:"
	@echo "  make              - Build vstface binary (default)"
	@echo "  make vstface      - Build vstface binary"
	@echo "  make fixture      - Build vstface_test_fixture plugin"
	@echo "  make full         - Build all targets"
	@echo ""
	@echo "Test targets:"
	@echo "  make test         - Run tests using CTest"
	@echo "  make check        - Build and run all tests (recommended)"
	@echo "  make build_tests  - Build all test executables"
	@echo ""
	@echo "Other targets:"
	@echo "  make clean        - Remove build directory"
	@echo "  make rebuild      - Clean and rebuild"
	@echo "  make configure    - Run CMake configuration only"
	@echo "  make help         - Show this help message"
	@echo ""
	@echo "Built artifacts:"
	@echo "  ./build/vstface                                      - Main binary"
	@echo "  ./build/VST3/Release/vstface_test_fixture.vst3       - Test plugin"
	@echo "  ./build/bin/Release/unit_tests                       - Unit tests"
	@echo "  ./build/bin/Release/integration_tests                - Integration tests"
