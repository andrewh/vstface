# VSTFace

VSTFace is a macOS command-line utility that launches VST3 plug-ins, opens their
editors, and saves PNG screenshots of the GUI. It exists to help build catalog
previews or monitor UI regressions without standing up a full DAW session.

> **Support policy**
>
> This repository is provided as-is without any support, warranty, or guarantee
> of continued maintenance. Issues and pull requests may be ignored.

## Platforms & Requirements

- macOS 13+ with Apple Clang / Xcode toolchain
- CMake 3.22+
- Steinberg VST3 SDK checked out under `third_party/vst3sdk`
- Plug-ins must provide VST3 bundles; AudioUnits or VST2 instruments are not
  supported and will be ignored

## Building

```bash
cmake -B build -S .
cmake --build build --config Release
```

This produces `build/vstface`, a self-contained host binary.

## Usage

Capture a single plug-in:

```bash
./build/vstface /Library/Audio/Plug-Ins/VST3/SomePlugin.vst3 ./SomePlugin.png
```

Sweep standard plug-in folders:

```bash
python3 ./scripts/scan.py ./out \
  --timeout 120 \
  --delete-unsupported
```

The Python helper enumerates `/Library/Audio/Plug-Ins/VST3` and the current
user’s `~/Library/Audio/Plug-Ins/VST3` directory by default, writes PNGs to the
requested output directory (default `./out`), and stores logs alongside the
captures as `vstface-<timestamp>.log`. Key options:

- `--bin` — alternate path to the `vstface` binary
- `--plugin-dir` — add extra directories to scan (can be repeated)
- `--log-file` — custom log destination (defaults to `<out_dir>/vstface-<timestamp>.log`)
- `--timeout` — per-plug-in watchdog in seconds (default 90)
- `--force` — re-capture even if a PNG already exists for a plug-in
- `--delete-unsupported` — remove bundles that report “doesn’t contain a version
  for the current architecture” (useful for pruning Intel-only VST3s)

Run `python3 scripts/scan.py --help` for the full CLI reference.

## Test Fixture

The tree now ships with `vstface_test_fixture`, a minimal VST3 plug-in with a
static Cocoa view that makes it easy to regression-test the host without
depending on third-party bundles.

- Build it once you have configured CMake:

  ```bash
  cmake --build build --config Release --target vstface_test_fixture
  ```

- The resulting bundle is written to
  `build/VST3/<Config>/vstface_test_fixture.vst3`. Capture it directly:

  ```bash
  ./build/vstface build/VST3/Release/vstface_test_fixture.vst3 ./out/fixture.png
  ```

This fixture only renders static UI but exercises the full launch and capture
pipeline, making it ideal for automated smoke checks.

## Behavior

- Only VST3 plug-ins are loaded. Attempting to pass other bundle types will
  result in errors.
- The host relies on macOS screen capture APIs, so you must grant it screen
  recording permission via System Settings when prompted.
- Plug-ins that allocate UI frameworks lazily may require the default 500 ms
  delay to render; adjust `ScreenshotOptions` in `src/main.cpp` if you need
  different sizing defaults.
- Some commercial plug-ins install Intel-only binaries; these will fail to load
  on Apple Silicon and can optionally be deleted with the scan script.

## Known Limitations

- macOS only. There is no Windows or Linux support planned.
- No audio processing or preset loading — this host only opens the editor and
  takes a screenshot.
- The binary does not sandbox plug-ins; they run with full user permissions.
- Timeouts are best-effort and enforced by the Python script. A misbehaving
  plug-in might still leave background processes running.
- There are no automated tests. Validate changes manually by capturing a few
  known plug-ins and inspecting the resulting PNGs.

## License & Support

This code is offered with no warranty or support. Use at your own risk. Before
building or redistributing, review the Steinberg VST3 SDK license under
`third_party/vst3sdk` and comply with all terms.

## Roadmap

See the [issues](https://github.com/andrewh/vstface/issues).
