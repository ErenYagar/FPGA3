#!/usr/bin/env python3
"""Render every report figure from DOT with Graphviz 14.1.3."""

from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess


EXPECTED_VERSION = "14.1.3"
HERE = Path(__file__).resolve().parent
FIGURES = HERE / "figures"
STEMS = (
    "cover_flow",
    "architecture",
    "core_architecture",
    "throughput",
    "resource_utilization",
    "placement_regions",
    "power_breakdown",
    "timing_iterations",
    "nist_validation",
)


def find_dot() -> str:
    configured = os.environ.get("GRAPHVIZ_DOT")
    executable = configured or shutil.which("dot")
    if not executable:
        raise SystemExit(
            "Graphviz 'dot' was not found. Install Graphviz 14.1.3 or set "
            "GRAPHVIZ_DOT to its dot executable."
        )
    return executable


def require_exact_version(executable: str) -> None:
    result = subprocess.run(
        [executable, "-V"],
        check=True,
        capture_output=True,
        text=True,
    )
    version_text = f"{result.stdout}\n{result.stderr}"
    match = re.search(r"graphviz version\s+([0-9]+(?:\.[0-9]+){2})", version_text)
    actual = match.group(1) if match else "unknown"
    if actual != EXPECTED_VERSION:
        raise SystemExit(
            f"Graphviz {EXPECTED_VERSION} is required; detected {actual} at {executable}."
        )


def render(executable: str, stem: str) -> None:
    source = FIGURES / f"{stem}.dot"
    if not source.is_file():
        raise SystemExit(f"Missing DOT source: {source}")
    subprocess.run(
        [executable, "-Tsvg", str(source), "-o", str(FIGURES / f"{stem}.svg")],
        check=True,
    )
    subprocess.run(
        [
            executable,
            "-Gdpi=300",
            "-Tpng",
            str(source),
            "-o",
            str(FIGURES / f"{stem}.png"),
        ],
        check=True,
    )


def main() -> None:
    executable = find_dot()
    require_exact_version(executable)
    for stem in STEMS:
        render(executable, stem)
    print(f"Rendered {len(STEMS)} figures with Graphviz {EXPECTED_VERSION}.")


if __name__ == "__main__":
    main()
