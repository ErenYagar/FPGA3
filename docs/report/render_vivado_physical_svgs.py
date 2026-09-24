#!/usr/bin/env python3
"""Render report-grade SVGs from Vivado-exported physical TSV data."""

from __future__ import annotations

import argparse
import csv
from collections import Counter, defaultdict
from html import escape
from math import log2
from pathlib import Path


GROUP_COLORS = {
    "AES_MAIN": "#0057a8",
    "AES_FIRST": "#2f80c9",
    "AES_SECOND": "#5aa6df",
    "GHASH": "#009688",
    "KEY_CONTEXT": "#7b61a8",
    "CORE_FIFO": "#d98324",
    "CORE_CONTROL": "#6b7280",
    "AXI_WRAPPER": "#b34d7d",
    "UART_BRIDGE": "#c0392b",
    "BOARD_LOGIC": "#374151",
}

GROUP_LABELS = {
    "AES_MAIN": "Main AES engine",
    "AES_FIRST": "First-block AES engine",
    "AES_SECOND": "Second AES engine",
    "GHASH": "GHASH",
    "KEY_CONTEXT": "Key context",
    "CORE_FIFO": "Core FIFOs",
    "CORE_CONTROL": "Core control",
    "AXI_WRAPPER": "AXI wrapper",
    "UART_BRIDGE": "UART bridge",
    "BOARD_LOGIC": "Board logic",
}

ROUTE_COLORS = (
    "#0057a8",
    "#007c91",
    "#009688",
    "#d98324",
    "#c0392b",
    "#7b61a8",
)


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def tile_category(tile_type: str) -> str:
    value = tile_type.upper()
    if "BRAM" in value:
        return "BRAM"
    if "DSP" in value:
        return "DSP"
    if any(token in value for token in ("IOB", "IOI", "PCIE", "GTP")):
        return "IO"
    if any(token in value for token in ("CMT", "HCLK", "CLK", "MMCM", "PLL")):
        return "CLOCK"
    if "CLB" in value:
        return "CLB"
    return "OTHER"


def load_metrics(path: Path) -> dict[str, str]:
    return {row["metric"]: row["value"] for row in read_tsv(path)}


def svg_header(width: int, height: int, title: str, description: str) -> list[str]:
    return [
        '<?xml version="1.0" encoding="UTF-8"?>',
        (
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" '
            f'height="{height}" viewBox="0 0 {width} {height}" role="img">'
        ),
        f"<title>{escape(title)}</title>",
        f"<desc>{escape(description)}</desc>",
        "<style>",
        "text{font-family:Arial,Helvetica,sans-serif;fill:#111827}",
        ".title{font-size:28px;font-weight:700}",
        ".subtitle{font-size:15px;fill:#374151}",
        ".label{font-size:13px}",
        ".small{font-size:11px;fill:#4b5563}",
        "</style>",
        '<rect width="100%" height="100%" fill="#ffffff"/>',
    ]


def transform_factory(
    min_x: int,
    max_x: int,
    min_y: int,
    max_y: int,
    left: float,
    top: float,
    plot_width: float,
    plot_height: float,
):
    span_x = max(1, max_x - min_x)
    span_y = max(1, max_y - min_y)

    def transform(x: int, y: int) -> tuple[float, float]:
        px = left + (x - min_x) * plot_width / span_x
        py = top + (y - min_y) * plot_height / span_y
        return px, py

    return transform


def combined_tile_paths(
    rows: list[dict[str, str]],
    transform,
    tile_width: float,
    tile_height: float,
) -> dict[str, str]:
    commands: dict[str, list[str]] = defaultdict(list)
    seen: set[tuple[str, int, int]] = set()
    for row in rows:
        x = int(row["grid_x"])
        y = int(row["grid_y"])
        category = tile_category(row["tile_type"])
        key = (category, x, y)
        if key in seen:
            continue
        seen.add(key)
        px, py = transform(x, y)
        commands[category].append(
            f"M{px:.2f},{py:.2f}h{tile_width:.2f}v{tile_height:.2f}"
            f"h{-tile_width:.2f}z"
        )
    return {category: "".join(parts) for category, parts in commands.items()}


def render_placement(output_dir: Path) -> Path:
    tiles = read_tsv(output_dir / "vivado_device_tiles.tsv")
    cells = read_tsv(output_dir / "vivado_placement_cells.tsv")
    metrics = load_metrics(output_dir / "vivado_figure_metrics.tsv")

    xs = [int(row["grid_x"]) for row in tiles]
    ys = [int(row["grid_y"]) for row in tiles]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)

    width, height = 1500, 920
    left, top = 85.0, 105.0
    plot_width, plot_height = 1030.0, 700.0
    transform = transform_factory(
        min_x, max_x, min_y, max_y, left, top, plot_width, plot_height
    )
    tile_w = max(0.45, plot_width / max(1, max_x - min_x) * 0.92)
    tile_h = max(0.45, plot_height / max(1, max_y - min_y) * 0.92)

    lines = svg_header(
        width,
        height,
        "Vivado Implementation Device Placement",
        "Full-device placement derived from the retained routed Vivado DCP.",
    )
    lines.extend(
        [
            '<text x="70" y="48" class="title">Vivado Implementation Device Placement</text>',
            (
                '<text x="70" y="76" class="subtitle">'
                f'Artix-7 {escape(metrics["part"])} | 175 MHz | '
                f'{int(metrics["placed_primitive_cells"]):,} placed primitive cells'
                "</text>"
            ),
            (
                f'<rect x="{left - 5}" y="{top - 5}" width="{plot_width + 10}" '
                f'height="{plot_height + 10}" fill="#ffffff" stroke="#111827" '
                'stroke-width="1.2"/>'
            ),
        ]
    )

    tile_fills = {
        "CLB": "#e5e7eb",
        "BRAM": "#cfe8ff",
        "DSP": "#fde7bd",
        "IO": "#e5d9f2",
        "CLOCK": "#d6f0e7",
        "OTHER": "#f8fafc",
    }
    for category, path_data in combined_tile_paths(
        tiles, transform, tile_w, tile_h
    ).items():
        lines.append(
            f'<path d="{path_data}" fill="{tile_fills[category]}" '
            'stroke="none" opacity="0.90"/>'
        )

    aggregate: Counter[tuple[int, int, str]] = Counter()
    group_counts: Counter[str] = Counter()
    for row in cells:
        key = (int(row["grid_x"]), int(row["grid_y"]), row["group"])
        aggregate[key] += 1
        group_counts[row["group"]] += 1

    for (x, y, group), count in aggregate.items():
        px, py = transform(x, y)
        radius = min(4.2, 0.95 + 0.48 * log2(count + 1))
        lines.append(
            f'<circle cx="{px:.2f}" cy="{py:.2f}" r="{radius:.2f}" '
            f'fill="{GROUP_COLORS[group]}" fill-opacity="0.68" stroke="none"/>'
        )

    legend_x = 1160
    lines.append(
        f'<text x="{legend_x}" y="125" class="label" font-weight="700">'
        "Placed cells by function</text>"
    )
    legend_y = 155
    for group, count in group_counts.most_common():
        lines.append(
            f'<circle cx="{legend_x + 8}" cy="{legend_y - 4}" r="5" '
            f'fill="{GROUP_COLORS[group]}"/>'
        )
        lines.append(
            f'<text x="{legend_x + 22}" y="{legend_y}" class="label">'
            f'{escape(GROUP_LABELS[group])}: {count:,}</text>'
        )
        legend_y += 29

    legend_y += 20
    lines.append(
        f'<text x="{legend_x}" y="{legend_y}" class="label" font-weight="700">'
        "Device resources</text>"
    )
    legend_y += 28
    for category in ("CLB", "BRAM", "DSP", "IO", "CLOCK", "OTHER"):
        lines.append(
            f'<rect x="{legend_x + 2}" y="{legend_y - 13}" width="13" height="13" '
            f'fill="{tile_fills[category]}" stroke="#9ca3af" stroke-width="0.5"/>'
        )
        lines.append(
            f'<text x="{legend_x + 24}" y="{legend_y - 2}" class="label">'
            f"{category}</text>"
        )
        legend_y += 25

    lines.extend(
        [
            (
                f'<text x="{left + plot_width / 2}" y="850" '
                'text-anchor="middle" class="small">'
                "Vivado device GRID_POINT_X</text>"
            ),
            (
                '<text x="28" y="455" text-anchor="middle" class="small" '
                'transform="rotate(-90 28 455)">Vivado device GRID_POINT_Y</text>'
            ),
            (
                '<text x="70" y="895" class="small">'
                "Source: retained 175 MHz routed DCP; dots are placed primitives "
                "aggregated by tile and hierarchy.</text>"
            ),
            "</svg>",
        ]
    )
    output = output_dir / "vivado_implementation_device_placement.svg"
    output.write_text("\n".join(lines), encoding="utf-8")
    return output


def render_routing(output_dir: Path) -> Path:
    tiles = read_tsv(output_dir / "vivado_device_tiles.tsv")
    cells = read_tsv(output_dir / "vivado_critical_path_cells.tsv")
    pips = read_tsv(output_dir / "vivado_critical_path_routed_pips.tsv")
    metrics = load_metrics(output_dir / "vivado_figure_metrics.tsv")

    route_points = [
        (int(row["grid_x"]), int(row["grid_y"])) for row in pips
    ]
    cell_points = [
        (int(row["grid_x"]), int(row["grid_y"])) for row in cells
    ]
    xs = [point[0] for point in route_points + cell_points]
    ys = [point[1] for point in route_points + cell_points]
    min_x, max_x = min(xs) - 3, max(xs) + 3
    min_y, max_y = min(ys) - 3, max(ys) + 3

    width, height = 1500, 900
    left, top = 75.0, 130.0
    plot_width, plot_height = 1040.0, 620.0
    transform = transform_factory(
        min_x, max_x, min_y, max_y, left, top, plot_width, plot_height
    )
    tile_w = max(1.0, plot_width / max(1, max_x - min_x) * 0.88)
    tile_h = max(1.0, plot_height / max(1, max_y - min_y) * 0.88)

    visible_tiles = [
        row
        for row in tiles
        if min_x <= int(row["grid_x"]) <= max_x
        and min_y <= int(row["grid_y"]) <= max_y
    ]
    lines = svg_header(
        width,
        height,
        "Vivado Worst-Setup Critical Path Routing",
        "Ordered routed PIPs for the worst setup path in the retained DCP.",
    )
    lines.extend(
        [
            '<text x="65" y="46" class="title">Vivado Worst-Setup Critical Path Routing</text>',
            (
                '<text x="65" y="75" class="subtitle">'
                f'WNS {float(metrics["setup_slack_ns"]):+.3f} ns | '
                f'Datapath {float(metrics["datapath_delay_ns"]):.3f} ns | '
                f'Logic {float(metrics["logic_delay_ns"]):.3f} ns | '
                f'Net {float(metrics["net_delay_ns"]):.3f} ns | '
                f'{metrics["logic_levels"]} logic levels</text>'
            ),
            (
                '<text x="65" y="101" class="small">'
                f'{escape(metrics["setup_startpoint"])}  →  '
                f'{escape(metrics["setup_endpoint"])}</text>'
            ),
            (
                f'<rect x="{left - 5}" y="{top - 5}" width="{plot_width + 10}" '
                f'height="{plot_height + 10}" fill="#ffffff" stroke="#111827" '
                'stroke-width="1.2"/>'
            ),
        ]
    )

    background_fills = {
        "CLB": "#f3f4f6",
        "BRAM": "#e8f3ff",
        "DSP": "#fff4dd",
        "IO": "#f2ebf8",
        "CLOCK": "#eaf6f2",
        "OTHER": "#fafafa",
    }
    for category, path_data in combined_tile_paths(
        visible_tiles, transform, tile_w, tile_h
    ).items():
        lines.append(
            f'<path d="{path_data}" fill="{background_fills[category]}" '
            'stroke="none"/>'
        )

    stage_rows: dict[int, list[dict[str, str]]] = defaultdict(list)
    for row in pips:
        stage_rows[int(row["stage"])].append(row)

    for stage in sorted(stage_rows):
        rows = sorted(stage_rows[stage], key=lambda row: int(row["pip_index"]))
        unique_points: list[tuple[int, int]] = []
        for row in rows:
            point = (int(row["grid_x"]), int(row["grid_y"]))
            if not unique_points or point != unique_points[-1]:
                unique_points.append(point)
        transformed = [transform(x, y) for x, y in unique_points]
        color = ROUTE_COLORS[stage % len(ROUTE_COLORS)]
        if len(transformed) == 1:
            px, py = transformed[0]
            lines.append(
                f'<circle cx="{px:.2f}" cy="{py:.2f}" r="5" '
                f'fill="{color}"/>'
            )
        else:
            points = " ".join(f"{px:.2f},{py:.2f}" for px, py in transformed)
            lines.append(
                f'<polyline points="{points}" fill="none" stroke="{color}" '
                'stroke-width="5" stroke-linecap="round" '
                'stroke-linejoin="round"/>'
            )
        for px, py in transformed:
            lines.append(
                f'<circle cx="{px:.2f}" cy="{py:.2f}" r="2.4" '
                f'fill="{color}"/>'
            )

    for row in cells:
        px, py = transform(int(row["grid_x"]), int(row["grid_y"]))
        stage = int(row["stage"])
        lines.append(
            f'<circle cx="{px:.2f}" cy="{py:.2f}" r="12" fill="#ffffff" '
            'stroke="#111827" stroke-width="2"/>'
        )
        lines.append(
            f'<text x="{px:.2f}" y="{py + 4:.2f}" text-anchor="middle" '
            f'class="label" font-weight="700">{stage + 1}</text>'
        )

    legend_x = 1150
    lines.append(
        f'<text x="{legend_x}" y="145" class="label" font-weight="700">'
        "Ordered routed nets</text>"
    )
    legend_y = 177
    for stage in sorted(stage_rows):
        rows = stage_rows[stage]
        color = ROUTE_COLORS[stage % len(ROUTE_COLORS)]
        net = rows[0]["net"]
        short_net = net if len(net) <= 39 else "…" + net[-38:]
        lines.append(
            f'<line x1="{legend_x}" y1="{legend_y - 5}" '
            f'x2="{legend_x + 30}" y2="{legend_y - 5}" '
            f'stroke="{color}" stroke-width="5"/>'
        )
        lines.append(
            f'<text x="{legend_x + 40}" y="{legend_y}" class="small">'
            f'{stage + 1}. {escape(short_net)}</text>'
        )
        legend_y += 42

    lines.extend(
        [
            (
                f'<text x="{legend_x}" y="{legend_y + 15}" class="label" '
                'font-weight="700">Cell markers</text>'
            ),
            (
                f'<text x="{legend_x}" y="{legend_y + 42}" class="small">'
                "1 = startpoint FF</text>"
            ),
            (
                f'<text x="{legend_x}" y="{legend_y + 64}" class="small">'
                f'{len(cells)} = endpoint FF</text>'
            ),
            (
                '<text x="65" y="842" class="small">'
                "Source: ordered Vivado routed PIPs. Lines connect PIP tile "
                "centres for a legible report-scale physical route view.</text>"
            ),
            (
                '<text x="65" y="867" class="small">'
                "This is a Vivado-derived vector view; the native Device window "
                "is raster-only in Vivado 2021.1.</text>"
            ),
            "</svg>",
        ]
    )
    output = output_dir / "vivado_critical_path_routing.svg"
    output.write_text("\n".join(lines), encoding="utf-8")
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    output_dir = args.output_dir.resolve()
    placement = render_placement(output_dir)
    routing = render_routing(output_dir)
    print(f"Rendered {placement}")
    print(f"Rendered {routing}")


if __name__ == "__main__":
    main()
