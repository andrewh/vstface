# Repository Guidelines

## Project Structure & Module Organization
Source lives under `src/`, split between the CLI entrypoint (`main.cpp`) and the Objective-C++ host bridge (`ScreenshotHost.hpp/.mm`). VST3 SDK headers are expected in `third_party/vst3sdk`; keep the folder pristine so SDK updates can be dropped in cleanly. Generated binaries and intermediate CMake state go to `build/`, while helper utilities such as `scripts/scan.py` sit in `scripts/`. Avoid checking artifacts into version control—only committed code should mirror the tree above.

## Build, Test, and Development Commands
- `cmake -B build -S .`: configure the Xcode/Clang toolchain and embed the SDK path assumptions.
- `cmake --build build --config Release`: produce the `build/vstface` binary; use `Debug` when iterating on host behavior.
- `./build/vstface <plugin.vst3> <out.png>`: run a one-off capture to validate changes.
- `./scripts/scan.py ./screens`: batch sweep standard plugin locations; ideal for regression checks across multiple vendors.

## Coding Style & Naming Conventions
Stick to modern C++17 for CLI code and Objective-C++ for host-specific logic. Use 4 spaces, no tabs, brace-on-same-line for functions, and prefer RAII helpers over raw pointers. File names follow `PascalCase` for Objective-C++ wrappers and `snake_case` for scripts. Include guards or `#pragma once` every header. Before submitting, run `clang-format` with the default LLVM style on touched files to keep diffs clean.

## Testing Guidelines
There is no automated suite yet; rely on manual smoke tests. Capture a known plugin twice and binary-diff the PNGs to ensure stability, and make sure the tool gracefully rejects a missing `.vst3`. When adding logic-heavy code, provide lightweight unit tests under `src/` using (new) GoogleTest fixtures so they can be picked up by CTest in the future.

## Commit & Pull Request Guidelines
Write commits in the imperative mood (`Add CLI width flag`), scoped to a single concern. Pull requests should describe the user-facing impact, list tested plugins or macOS versions, and mention any SDK or entitlement changes. Include screenshots of resulting captures when UI-affecting code is touched, and link to any tracking issues or design docs.
