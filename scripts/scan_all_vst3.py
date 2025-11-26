#!/usr/bin/env python3
"""Batch VST3 screenshot capture utility with timeout/logging options."""
from __future__ import annotations

import argparse
import logging
import shutil
import subprocess
import sys
import threading
from datetime import datetime
from pathlib import Path
from typing import Iterable, List

DEFAULT_PLUG_DIRS = [
    "/Library/Audio/Plug-Ins/VST3",
    str(Path.home() / "Library/Audio/Plug-Ins/VST3"),
]

ARCH_MISMATCH_TOKEN = "doesn't contain a version for the current architecture"


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
    logger = logging.getLogger("scan_all_vst3")
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
    total = 0
    skipped = 0
    success = 0
    failures = 0
    timeouts = 0

    for plugin in iter_plugins(plugin_dirs):
        total += 1
        out_path = out_dir / f"{plugin.stem}.png"
        if out_path.exists() and not args.force:
            logger.info("Skipping %s (already captured)", plugin)
            skipped += 1
            continue

        logger.info("Capturing %s -> %s", plugin, out_path)
        cmd = [str(vstface), str(plugin), str(out_path)]
        returncode, timed_out, output = run_capture(cmd, args.timeout, logger)

        if timed_out:
            logger.warning("TIMEOUT: %s", plugin)
            timeouts += 1
        elif returncode != 0:
            logger.warning("FAILED (%d): %s", returncode, plugin)
            failures += 1
        else:
            logger.info("Captured %s", plugin)
            success += 1
            continue

        if args.delete_unsupported and ARCH_MISMATCH_TOKEN in output.lower():
            logger.warning("Deleting unsupported plugin bundle: %s", plugin)
            try:
                shutil.rmtree(plugin)
            except Exception as exc:  # noqa: BLE001
                logger.error("Failed to delete %s: %s", plugin, exc)

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
