#!/usr/bin/env python3
"""Batch VST3 screenshot capture utility with timeout/logging options."""
from __future__ import annotations

import argparse
import logging
import os
import shutil
import subprocess
import sys
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable, List

DEFAULT_PLUG_DIRS = [
    "/Library/Audio/Plug-Ins/VST3",
    str(Path.home() / "Library/Audio/Plug-Ins/VST3"),
]

ARCH_MISMATCH_TOKEN = "doesn't contain a version for the current architecture"


@dataclass
class CaptureResult:
    """Result of attempting to capture a single plugin."""
    plugin: Path
    skipped: bool = False
    success: bool = False
    timed_out: bool = False
    failed: bool = False
    output: str = ""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "out_dir",
        nargs="?",
        default="./out",
        help="Directory where PNG captures are written (default: %(default)s)",
    )
    parser.add_argument(
        "--bin",
        default="./build/vstface",
        help="Path to the vstface binary (default: %(default)s)",
    )
    parser.add_argument(
        "--log-file",
        default=None,
        help="File to tee log output into (default: <out_dir>/vstface-<timestamp>.log)",
    )
    parser.add_argument(
        "--plugin-dir",
        action="append",
        dest="plugin_dirs",
        help="Additional plugin directories to scan (can be repeated). Defaults to common system/user paths.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=90,
        help="Seconds to wait for each capture before killing vstface (default: %(default)s)",
    )
    parser.add_argument(
        "--delete-unsupported",
        action="store_true",
        help="Delete plugin bundles that report they lack binaries for this architecture.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-capture even if a PNG already exists.",
    )
    return parser.parse_args()


def configure_logging(log_path: Path) -> logging.Logger:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger("scan")
    logger.setLevel(logging.INFO)
    formatter = logging.Formatter("%(asctime)s %(levelname)s: %(message)s")

    file_handler = logging.FileHandler(log_path, mode="w")
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)

    stream_handler = logging.StreamHandler(sys.stdout)
    stream_handler.setFormatter(formatter)
    logger.addHandler(stream_handler)

    return logger


def iter_plugins(dirs: Iterable[str]) -> Iterable[Path]:
    for base in dirs:
        base_path = Path(base).expanduser()
        if not base_path.is_dir():
            continue
        for plugin in sorted(base_path.glob("*.vst3")):
            yield plugin


def run_capture(cmd: List[str], timeout: int, logger: logging.Logger) -> tuple[int, bool, str]:
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        universal_newlines=True,
    )

    lines: List[str] = []

    def reader() -> None:
        assert proc.stdout is not None
        for line in proc.stdout:
            stripped = line.rstrip()
            lines.append(stripped)
            logger.info(stripped)

    thread = threading.Thread(target=reader, daemon=True)
    thread.start()
    timed_out = False
    try:
        returncode = proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        proc.kill()
        returncode = proc.wait()
    thread.join()
    return returncode, timed_out, "\n".join(lines)


def process_plugin(
    plugin: Path,
    out_dir: Path,
    vstface: Path,
    timeout: int,
    force: bool,
    logger: logging.Logger,
) -> CaptureResult:
    """Process a single plugin capture."""
    out_path = out_dir / f"{plugin.stem}.png"

    # Check if already captured
    if out_path.exists() and not force:
        logger.info("Skipping %s (already captured)", plugin)
        return CaptureResult(plugin=plugin, skipped=True)

    # Run capture
    logger.info("Capturing %s -> %s", plugin, out_path)
    cmd = [str(vstface), str(plugin), str(out_path)]
    returncode, timed_out, output = run_capture(cmd, timeout, logger)

    if timed_out:
        logger.warning("TIMEOUT: %s", plugin)
        return CaptureResult(plugin=plugin, timed_out=True, output=output)
    elif returncode != 0:
        logger.warning("FAILED (%d): %s", returncode, plugin)
        return CaptureResult(plugin=plugin, failed=True, output=output)
    else:
        logger.info("Captured %s", plugin)
        return CaptureResult(plugin=plugin, success=True)


def main() -> int:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.log_file:
        log_path = Path(args.log_file)
    else:
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        log_path = out_dir / f"vstface-{stamp}.log"

    logger = configure_logging(log_path)

    vstface = Path(args.bin)
    if not vstface.is_file():
        logger.error("Expected vstface binary at %s", vstface)
        return 1

    plugin_dirs = args.plugin_dirs if args.plugin_dirs else DEFAULT_PLUG_DIRS
    plugins = list(iter_plugins(plugin_dirs))
    total = len(plugins)

    if total == 0:
        logger.warning("No plugins found in %s", plugin_dirs)
        return 0

    # Use all available CPU cores
    max_workers = os.cpu_count() or 4
    logger.info("Processing %d plugins using %d workers", total, max_workers)

    skipped = 0
    success = 0
    failures = 0
    timeouts = 0

    # Process plugins in parallel
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        # Submit all tasks
        futures = {
            executor.submit(
                process_plugin,
                plugin,
                out_dir,
                vstface,
                args.timeout,
                args.force,
                logger,
            ): plugin
            for plugin in plugins
        }

        # Process results as they complete
        for future in as_completed(futures):
            result = future.result()

            if result.skipped:
                skipped += 1
            elif result.success:
                success += 1
            elif result.timed_out:
                timeouts += 1
            elif result.failed:
                failures += 1

            # Handle unsupported architecture deletion
            if (
                args.delete_unsupported
                and result.output
                and ARCH_MISMATCH_TOKEN in result.output.lower()
            ):
                logger.warning("Deleting unsupported plugin bundle: %s", result.plugin)
                try:
                    shutil.rmtree(result.plugin)
                except Exception as exc:  # noqa: BLE001
                    logger.error("Failed to delete %s: %s", result.plugin, exc)

    logger.info(
        "Done. total=%d success=%d skipped=%d failures=%d timeouts=%d",
        total,
        success,
        skipped,
        failures,
        timeouts,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
