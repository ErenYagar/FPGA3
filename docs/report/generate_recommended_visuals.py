#!/usr/bin/env python3
"""Generate the source-backed 175 MHz FPGA report visual suite.

Charts are written directly as SVG without matplotlib. Architecture and flow
figures are rendered from DOT with Graphviz 14.1.3. PNGs are exported through
Inkscape for report/slides compatibility.
"""

from __future__ import annotations

import csv
import hashlib
import html
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time


REPORT_DIR = Path(__file__).resolve().parent
REPO_ROOT = REPORT_DIR.parent.parent
OUTPUT_DIR = REPORT_DIR / "figures" / "recommended"
VIVADO_DIR = REPORT_DIR / "figures" / "vivado"
MANIFEST_PATH = REPO_ROOT / "verification" / "results" / "exact_current_manifest.json"
EXPECTED_GRAPHVIZ = "14.1.3"

WHITE = "#ffffff"
INK = "#111111"
MUTED = "#5a6470"
GRID = "#d5d9de"
PALE = "#eef2f5"
BLUE = "#1f4e79"
BLUE_PALE = "#d9e8f5"
GREEN = "#2f6b45"
GREEN_PALE = "#dcebdd"
ORANGE = "#9a5b13"
ORANGE_PALE = "#f4e6cf"
RED = "#9a3131"
RED_PALE = "#f2dddd"
FONT = "Arial, Helvetica, sans-serif"


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


class Svg:
    def __init__(self, width: int = 1600, height: int = 900) -> None:
        self.width = width
        self.height = height
        self.items = [
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
            f'viewBox="0 0 {width} {height}">',
            f'<rect width="{width}" height="{height}" fill="{WHITE}"/>',
            "<defs>",
            '<marker id="arrow" markerWidth="8" markerHeight="8" refX="7" refY="4" '
            'orient="auto" markerUnits="strokeWidth"><path d="M0,0 L8,4 L0,8 z" '
            f'fill="{INK}"/></marker>',
            "</defs>",
        ]

    def title(self, title: str, subtitle: str = "") -> None:
        self.text(70, 62, title, 34, weight=600)
        if subtitle:
            self.text(70, 99, subtitle, 19, fill=MUTED)
        self.line(70, 118, self.width - 70, 118, stroke=INK, width=1.2)

    def rect(
        self,
        x: float,
        y: float,
        w: float,
        h: float,
        *,
        fill: str = "none",
        stroke: str = INK,
        width: float = 1.2,
        rx: float = 0,
        opacity: float = 1.0,
    ) -> None:
        self.items.append(
            f'<rect x="{x:.2f}" y="{y:.2f}" width="{w:.2f}" height="{h:.2f}" '
            f'fill="{fill}" stroke="{stroke}" stroke-width="{width}" rx="{rx}" '
            f'opacity="{opacity}"/>'
        )

    def line(
        self,
        x1: float,
        y1: float,
        x2: float,
        y2: float,
        *,
        stroke: str = INK,
        width: float = 1.5,
        dash: str | None = None,
        arrow: bool = False,
    ) -> None:
        dash_attr = f' stroke-dasharray="{dash}"' if dash else ""
        arrow_attr = ' marker-end="url(#arrow)"' if arrow else ""
        self.items.append(
            f'<line x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}" '
            f'stroke="{stroke}" stroke-width="{width}"{dash_attr}{arrow_attr}/>'
        )

    def polyline(
        self,
        points: list[tuple[float, float]],
        *,
        stroke: str = INK,
        width: float = 2.2,
        fill: str = "none",
    ) -> None:
        encoded = " ".join(f"{x:.2f},{y:.2f}" for x, y in points)
        self.items.append(
            f'<polyline points="{encoded}" fill="{fill}" stroke="{stroke}" '
            f'stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"/>'
        )

    def circle(
        self,
        x: float,
        y: float,
        r: float,
        *,
        fill: str = WHITE,
        stroke: str = INK,
        width: float = 1.5,
    ) -> None:
        self.items.append(
            f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{r:.2f}" fill="{fill}" '
            f'stroke="{stroke}" stroke-width="{width}"/>'
        )

    def text(
        self,
        x: float,
        y: float,
        value: object,
        size: int = 22,
        *,
        anchor: str = "start",
        fill: str = INK,
        weight: int = 400,
        family: str = FONT,
        rotate: float | None = None,
    ) -> None:
        transform = f' transform="rotate({rotate} {x} {y})"' if rotate is not None else ""
        self.items.append(
            f'<text x="{x:.2f}" y="{y:.2f}" font-family="{family}" font-size="{size}" '
            f'font-weight="{weight}" text-anchor="{anchor}" fill="{fill}"{transform}>'
            f"{esc(value)}</text>"
        )

    def multiline(
        self,
        x: float,
        y: float,
        lines: list[str],
        size: int = 20,
        *,
        anchor: str = "start",
        fill: str = INK,
        weight: int = 400,
        leading: float = 1.25,
    ) -> None:
        self.items.append(
            f'<text x="{x:.2f}" y="{y:.2f}" font-family="{FONT}" font-size="{size}" '
            f'font-weight="{weight}" text-anchor="{anchor}" fill="{fill}">'
        )
        for index, line in enumerate(lines):
            dy = 0 if index == 0 else size * leading
            self.items.append(f'<tspan x="{x:.2f}" dy="{dy:.2f}">{esc(line)}</tspan>')
        self.items.append("</text>")

    def write(self, path: Path) -> None:
        path.write_text("\n".join(self.items + ["</svg>"]) + "\n", encoding="utf-8")


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def read_manifest() -> dict:
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def find_graphviz() -> Path:
    candidates = []
    if os.environ.get("GRAPHVIZ_DOT"):
        candidates.append(Path(os.environ["GRAPHVIZ_DOT"]))
    candidates.extend(
        [
            REPO_ROOT / ".tools" / "graphviz-14.1.3" / "Graphviz-14.1.3-win64" / "bin" / "dot.exe",
            Path(r"C:\Program Files\Graphviz\bin\dot.exe"),
        ]
    )
    for candidate in candidates:
        if candidate.is_file():
            result = subprocess.run(
                [str(candidate), "-V"], capture_output=True, text=True, check=True
            )
            version_text = result.stdout + result.stderr
            if re.search(r"graphviz version\s+14\.1\.3\b", version_text):
                return candidate
    raise SystemExit("Graphviz 14.1.3 dot.exe was not found")


def find_inkscape() -> Path:
    configured = os.environ.get("INKSCAPE")
    candidates = [Path(configured)] if configured else []
    candidates.append(Path(r"C:\Program Files\Inkscape\bin\inkscape.exe"))
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise SystemExit("Inkscape was not found")


def dot_header(name: str, rankdir: str = "LR") -> str:
    return f'''digraph {name} {{
  graph [rankdir={rankdir}, splines=ortho, bgcolor="white", pad="0.18", margin="0",
         nodesep="0.45", ranksep="0.75", outputorder="edgesfirst", charset="UTF-8",
         fontname="Arial", fontsize=20, fontcolor="#111111"];
  node [shape=box, style="filled", fillcolor="#ffffff", color="#111111",
        fontcolor="#111111", fontname="Arial", fontsize=12, penwidth=1.0,
        margin="0.14,0.10"];
  edge [color="#111111", penwidth=1.0, arrowsize=0.65, arrowhead=normal,
        fontname="Arial", fontsize=10, fontcolor="#111111"];
'''


def render_dot(dot: Path, svg: Path, dot_exe: Path) -> None:
    subprocess.run([str(dot_exe), "-Tsvg", str(dot), "-o", str(svg)], check=True)


def write_clock_reset_dot(path: Path) -> None:
    body = dot_header("Clock_Reset_Architecture") + r'''
  graph [ratio=fill, size="14,6!", label=<<B>175 MHz clock, reset, and CDC architecture</B>>, labelloc=t, labeljust=l];
  clk [label=<<B>Board clock</B><BR/>100 MHz input>];
  mmcm [label=<<B>MMCME2_ADV</B><BR/>100 → 175 MHz<BR/><FONT POINT-SIZE="10">feedback: 100 MHz</FONT>>];
  bufg [label=<<B>BUFGCTRL_X0Y16</B><BR/>core_clk = 175 MHz<BR/>5.714 ns>];
  core [label=<<B>AES-GCM core domain</B><BR/>9,039 clocked cells<BR/>setup/hold closed>];
  fb [label=<<B>MMCM feedback loop</B><BR/>BUFGCTRL_X0Y17 → CLKFBIN<BR/>100 MHz>];

  button [label=<<B>Button + MMCM LOCKED</B><BR/>asynchronous request>];
  gate [label=<<B>LUT2 request gate</B><BR/>combined run request>];
  sync [label=<<B>2-FF synchronizer</B><BR/>ASYNC_REG<BR/>sampled by core_clk>];
  qual [label=<<B>4-stage qualifier</B><BR/>stable-high release>];
  repl [label=<<B>Physical reset release</B><BR/>4 FF replicas @ SLICE_X49Y132<BR/>13,161 unique endpoints>];

  uart [label=<<B>UART RX pin</B><BR/>asynchronous serial input>];
  uart_sync [label=<<B>2-FF synchronizer</B><BR/>CDC-3 Info<BR/>sampled by core_clk>];
  bridge [label=<<B>UART bridge</B><BR/>core_clk domain>];

  clk -> mmcm -> bufg -> core;
  mmcm -> fb [style=dashed, arrowhead=none];
  button -> gate -> sync -> qual -> repl -> core;
  uart -> uart_sync -> bridge -> core;
}
'''
    path.write_text(body, encoding="utf-8")


def write_pipeline_dot(path: Path) -> None:
    body = dot_header("AES_GCM_Pipeline") + r'''
  graph [ratio=fill, size="14,6!", label=<<B>AES-GCM parallel pipeline and queue structure</B>>, labelloc=t, labeljust=l];
  regs [label=<<B>AXI4-Lite control</B><BR/>key / IV / lengths / mode>];
  desc [label=<<B>Descriptor FIFO</B><BR/>record metadata>];
  input [label=<<B>AXI-Stream input</B><BR/>IV / AAD / payload / tag>];
  parser [label=<<B>Byte parser + queues</B><BR/>ready/valid decoupling>];

  key [label=<<B>Key context</B><BR/>round-key expansion<BR/>BRAM-backed S-boxes>];
  first0 [label=<<B>First-block AES #0</B><BR/>one round / clock<BR/>10 / 12 / 14 clocks>];
  first1 [label=<<B>First-block AES #1</B><BR/>one round / clock<BR/>10 / 12 / 14 clocks>];
  shared [label=<<B>Shared AES engine</B><BR/>3 interleaved contexts<BR/>II = 10 / 12 / 14 clocks>];

  ctr [label=<<B>CTR XOR</B><BR/>keystream ⊕ payload>];
  cipherq [label=<<B>Ciphertext FIFO</B><BR/>clear-safe output staging>];
  ghashq [label=<<B>GHASH request FIFO</B><BR/>ciphertext/AAD blocks>];
  ghash [label=<<B>GHASH16</B><BR/>8 digit cycles<BR/>external II = 9>];
  tag [label=<<B>Tag generation</B><BR/>E(K,J₀) ⊕ GHASH>];
  output [label=<<B>AXI-Stream outputs</B><BR/>data / tag / result>];

  regs -> desc -> parser;
  input -> parser;
  regs -> key;
  key -> first0;
  key -> first1;
  key -> shared;
  parser -> first0;
  parser -> first1;
  parser -> shared;
  first0 -> ctr;
  first1 -> ctr;
  shared -> ctr;
  ctr -> cipherq -> output;
  parser -> ghashq;
  ctr -> ghashq;
  ghashq -> ghash -> tag -> output;
}
'''
    path.write_text(body, encoding="utf-8")


def write_verification_flow_dot(path: Path) -> None:
    body = dot_header("Verification_Flow") + r'''
  graph [ratio=fill, size="14,6!", label=<<B>Exact-current RTL-to-FPGA verification flow</B>>, labelloc=t, labeljust=l];
  rtl [label=<<B>Exact RTL + XDC identity</B><BR/>SHA-256 manifest>];
  sim [label=<<B>Simulation verification</B><BR/>smoke + 8/8 directed<BR/>47,250/0 NIST>];
  sva [label=<<B>SVA</B><BR/>37 properties<BR/>0 failures>];
  uvm [label=<<B>UVM 1.2</B><BR/>3 seeds, 24/0 scoreboard<BR/>100% maintained bins>];
  formal [label=<<B>Formal subset</B><BR/>19 combinational assertions<BR/>PARTIAL PASS scope>];
  synth [label=<<B>Vivado synthesis</B><BR/>WNS -0.298 ns<BR/>292 setup endpoints>];
  impl [label=<<B>Place + route</B><BR/>WNS +0.029 ns; WHS +0.044 ns<BR/>17,758/17,758 nets>];
  gates [label=<<B>Static hard gates</B><BR/>DRC / CDC / methodology / check_timing<BR/>Error/CW = 0/0>];
  bit [label=<<B>Bitstream provenance</B><BR/>DCP + BIN SHA-256<BR/>payload identity PASS>];
  board [label=<<B>Hardware Manager</B><BR/>program PASS<BR/>6/0 board smoke>];
  nist [label=<<B>FPGA NIST RSP</B><BR/>47,250 / 47,250 PASS<BR/>COM4, 1,208.505 s>];

  rtl -> sim -> synth -> impl -> gates -> bit -> board -> nist;
  rtl -> sva -> sim;
  rtl -> uvm -> sim;
  rtl -> formal -> synth;
}
'''
    path.write_text(body, encoding="utf-8")


def timing_closure_figure(path: Path) -> None:
    svg = Svg(1600, 930)
    svg.title(
        "175 MHz timing closure across implementation stages",
        "Retained Vivado 2021.1 reports; positive slack is required for final signoff",
    )
    stages = ["Synthesis", "Placed + phys_opt", "Final routed"]
    wns = [-0.298, 0.075, 0.029]
    whs = [0.045, -0.082, 0.044]
    x_values = [240, 590, 940]
    top, bottom = 180, 650
    y_min, y_max = -0.35, 0.12

    def y(value: float) -> float:
        return bottom - (value - y_min) / (y_max - y_min) * (bottom - top)

    for tick in [-0.3, -0.2, -0.1, 0.0, 0.1]:
        yy = y(tick)
        svg.line(150, yy, 1050, yy, stroke=INK if tick == 0 else GRID, width=1.5 if tick == 0 else 1)
        svg.text(130, yy + 7, f"{tick:+.1f}", 18, anchor="end", fill=MUTED)
    svg.text(76, 420, "Slack (ns)", 20, anchor="middle", rotate=-90)
    svg.polyline(list(zip(x_values, [y(v) for v in wns])), stroke=BLUE, width=4)
    svg.polyline(list(zip(x_values, [y(v) for v in whs])), stroke=ORANGE, width=4)
    for index, stage in enumerate(stages):
        x = x_values[index]
        svg.line(x, top, x, bottom, stroke=GRID, width=1, dash="4 6")
        svg.text(x, 696, stage, 20, anchor="middle", weight=600)
        for value, color, offset in [(wns[index], BLUE, -18), (whs[index], ORANGE, 24)]:
            yy = y(value)
            svg.circle(x, yy, 9, fill=WHITE, stroke=color, width=4)
            svg.text(x + 15, yy + offset, f"{value:+.3f}", 18, fill=color, weight=600)
    svg.line(200, 770, 250, 770, stroke=BLUE, width=4)
    svg.text(265, 777, "Setup WNS", 19)
    svg.line(440, 770, 490, 770, stroke=ORANGE, width=4)
    svg.text(505, 777, "Hold WHS", 19)

    svg.rect(1120, 170, 400, 570, fill=WHITE, stroke=INK)
    svg.text(1150, 215, "Failing-path summary", 24, weight=600)
    rows = [
        ("Stage", "Setup TNS / FEP", "Hold THS / FEP"),
        ("Synthesis", "-11.728 ns / 292", "0 / 0"),
        ("Placed", "0 / 0", "-0.364 ns / 9"),
        ("Final routed", "0 / 0", "0 / 0"),
    ]
    y0 = 260
    for row_index, row in enumerate(rows):
        yy = y0 + row_index * 92
        if row_index:
            svg.line(1140, yy - 38, 1500, yy - 38, stroke=GRID)
        svg.text(1150, yy, row[0], 18, weight=600 if row_index == 0 else 400)
        svg.text(1150, yy + 28, row[1], 17, fill=BLUE)
        svg.text(1355, yy + 28, row[2], 17, fill=ORANGE)
    svg.rect(1140, 640, 360, 64, fill=GREEN_PALE, stroke=GREEN)
    svg.text(1320, 681, "FINAL SETUP + HOLD PASS", 20, anchor="middle", fill=GREEN, weight=600)
    svg.text(70, 885, "Source: timing_synth.rpt, timing_placed.rpt, timing_routed.rpt", 16, fill=MUTED)
    svg.write(path)


def delay_breakdown_figure(path: Path, metrics: dict[str, str]) -> None:
    logic = float(metrics["logic_delay_ns"])
    net = float(metrics["net_delay_ns"])
    total = float(metrics["datapath_delay_ns"])
    svg = Svg(1600, 850)
    svg.title(
        "Final routed critical-path delay breakdown",
        "Worst setup path at 175 MHz; routed DCP WNS = +0.029 ns",
    )
    bar_x, bar_y, bar_w, bar_h = 150, 250, 1270, 120
    logic_w = bar_w * logic / total
    net_w = bar_w - logic_w
    svg.rect(bar_x, bar_y, logic_w, bar_h, fill=BLUE_PALE, stroke=INK)
    svg.rect(bar_x + logic_w, bar_y, net_w, bar_h, fill=PALE, stroke=INK)
    svg.text(bar_x + logic_w / 2, bar_y + 55, "Logic", 24, anchor="middle", weight=600)
    svg.text(bar_x + logic_w / 2, bar_y + 88, f"{logic:.3f} ns", 21, anchor="middle")
    svg.text(bar_x + logic_w + net_w / 2, bar_y + 55, "Net / routing", 24, anchor="middle", weight=600)
    svg.text(bar_x + logic_w + net_w / 2, bar_y + 88, f"{net:.3f} ns", 21, anchor="middle")
    svg.text(bar_x, 220, "0 ns", 18, fill=MUTED)
    svg.text(bar_x + bar_w, 220, f"{total:.3f} ns datapath", 18, anchor="end", fill=MUTED)
    svg.text(280, 445, f"{logic / total * 100:.1f}%", 46, anchor="middle", fill=BLUE, weight=600)
    svg.text(280, 480, "logic contribution", 19, anchor="middle")
    svg.text(800, 445, f"{net / total * 100:.1f}%", 46, anchor="middle", fill=INK, weight=600)
    svg.text(800, 480, "routing contribution", 19, anchor="middle")
    svg.text(1320, 445, metrics["logic_levels"], 46, anchor="middle", fill=INK, weight=600)
    svg.text(1320, 480, "logic levels", 19, anchor="middle")
    svg.rect(110, 545, 1380, 185, fill=WHITE, stroke=GRID)
    svg.text(140, 585, "Startpoint", 18, fill=MUTED)
    svg.text(140, 620, metrics["setup_startpoint"], 20, weight=600)
    svg.line(770, 585, 770, 700, stroke=GRID)
    svg.text(800, 585, "Endpoint", 18, fill=MUTED)
    svg.text(800, 620, metrics["setup_endpoint"], 20, weight=600)
    svg.text(140, 680, "Interpretation: routing contributes most of the datapath delay; WNS also includes clock skew and uncertainty.", 18)
    svg.text(70, 805, "Source: vivado_critical_path_timing.rpt and routed DCP timing-path properties", 16, fill=MUTED)
    svg.write(path)


def resource_figure(path: Path, manifest: dict) -> None:
    util = manifest["implementation"]["utilization"]
    resources = [
        ("Total LUT", util["lut_total"], 63400),
        ("Logic LUT", util["lut_logic"], 63400),
        ("LUTRAM", util["lutram"], 19000),
        ("Flip-flop", util["ff"], 126800),
        ("RAMB18", util["ramb18"], 270),
        ("DSP48", util["dsp"], 240),
        ("BUFGCTRL", 2, 32),
    ]
    svg = Svg(1600, 980)
    svg.title(
        "Final routed resource utilization",
        "XC7A100T; used values from hierarchical Vivado utilization and clock reports",
    )
    x0, max_w = 390, 820
    for index, (name, used, capacity) in enumerate(resources):
        y = 175 + index * 102
        pct = used / capacity * 100 if capacity else 0
        svg.text(90, y + 31, name, 22, weight=600)
        svg.rect(x0, y, max_w, 42, fill=PALE, stroke="none")
        svg.rect(x0, y, max_w * pct / 25.0, 42, fill=BLUE, stroke="none")
        svg.text(1450, y + 30, f"{used:,} / {capacity:,}", 20, anchor="end")
        svg.text(1560, y + 30, f"{pct:.2f}%", 20, anchor="end", weight=600)
    for tick in [0, 5, 10, 15, 20, 25]:
        x = x0 + max_w * tick / 25
        svg.line(x, 870, x, 886, stroke=INK)
        svg.text(x, 912, str(tick), 17, anchor="middle", fill=MUTED)
    svg.line(x0, 870, x0 + max_w, 870, stroke=INK)
    svg.text(x0 + max_w / 2, 950, "Device utilization (%) — scale limited to 25%", 18, anchor="middle", fill=MUTED)
    svg.write(path)


def placement_zoom_figure(path: Path, cells: list[dict[str, str]]) -> None:
    svg = Svg(1700, 980)
    svg.title(
        "Final critical-path placement zoom",
        "Seven routed cells in the UART bridge; numbered in data-path order",
    )
    coords = [(int(row["grid_x"]), int(row["grid_y"])) for row in cells]
    min_x, max_x = min(x for x, _ in coords) - 2, max(x for x, _ in coords) + 2
    min_y, max_y = min(y for _, y in coords) - 2, max(y for _, y in coords) + 2
    left, top, width, height = 95, 165, 900, 650

    def px(x: float) -> float:
        return left + (x - min_x) / (max_x - min_x) * width

    def py(y: float) -> float:
        return top + (y - min_y) / (max_y - min_y) * height

    for x in range(min_x, max_x + 1):
        svg.line(px(x), top, px(x), top + height, stroke=GRID, width=0.8)
    for y in range(min_y, max_y + 1):
        svg.line(left, py(y), left + width, py(y), stroke=GRID, width=0.8)
    svg.rect(left, top, width, height, fill="none", stroke=INK)
    plotted: list[tuple[float, float]] = []
    occupied: dict[tuple[int, int], int] = {}
    for row in cells:
        key = (int(row["grid_x"]), int(row["grid_y"]))
        count = occupied.get(key, 0)
        occupied[key] = count + 1
        plotted.append((px(key[0]) + count * 28 - 14 * min(count, 1), py(key[1]) + count * 28))
    svg.polyline(plotted, stroke=BLUE, width=3)
    for index, (x, y) in enumerate(plotted, start=1):
        svg.circle(x, y, 18, fill=WHITE, stroke=BLUE, width=3)
        svg.text(x, y + 7, index, 18, anchor="middle", fill=BLUE, weight=600)
    svg.text(left + width / 2, 855, "Vivado device GRID_POINT_X", 18, anchor="middle", fill=MUTED)
    svg.text(45, top + height / 2, "GRID_POINT_Y", 18, anchor="middle", fill=MUTED, rotate=-90)

    table_x = 1060
    svg.text(table_x, 175, "Stage / primitive / placement", 22, weight=600)
    for index, row in enumerate(cells, start=1):
        y = 220 + (index - 1) * 94
        svg.circle(table_x + 15, y - 6, 14, fill=WHITE, stroke=BLUE, width=2)
        svg.text(table_x + 15, y, index, 15, anchor="middle", fill=BLUE, weight=600)
        svg.text(table_x + 45, y, f'{row["ref_name"]}  @  {row["loc"]}', 18, weight=600)
        cell_name = row["cell"]
        if len(cell_name) > 53:
            cell_name = "…" + cell_name[-52:]
        svg.text(table_x + 45, y + 29, cell_name, 16, fill=MUTED)
    svg.text(70, 935, "Source: routed DCP cell LOC/BEL/tile coordinates", 16, fill=MUTED)
    svg.write(path)


def throughput_figure(path: Path) -> None:
    rows = [
        ("AES-128 Encrypt", 1.065398, 16820),
        ("AES-128 Decrypt", 1.051705, 17039),
        ("AES-192 Encrypt", 1.065398, 16820),
        ("AES-192 Decrypt", 1.051705, 17039),
        ("AES-256 Encrypt", 1.065398, 16820),
        ("AES-256 Decrypt", 1.051705, 17039),
    ]
    svg = Svg(1600, 960)
    svg.title(
        "Six-mode simulated throughput at 175 MHz",
        "100 × 1024-bit records per mode; core RTL throughput, not UART/board transport throughput",
    )
    x0, bar_w = 390, 980
    scale_max = 1.10
    target_x = x0 + bar_w * 1.0 / scale_max
    svg.line(target_x, 180, target_x, 790, stroke=RED, width=2.5, dash="8 6")
    svg.text(target_x, 165, "1.000 Gbit/s target", 18, anchor="middle", fill=RED, weight=600)
    for index, (name, gbps, cycles) in enumerate(rows):
        y = 175 + index * 102
        svg.text(80, y + 30, name, 21, weight=600)
        svg.rect(x0, y, bar_w, 44, fill=PALE, stroke="none")
        svg.rect(x0, y, bar_w * gbps / scale_max, 44, fill=BLUE, stroke="none")
        svg.text(x0 + bar_w * gbps / scale_max - 12, y + 30, f"{gbps:.6f}", 18, anchor="end", fill=WHITE, weight=600)
        svg.text(1510, y + 30, f"{cycles:,} cycles", 18, anchor="end")
    for tick in [0, 0.25, 0.5, 0.75, 1.0]:
        x = x0 + bar_w * tick / scale_max
        svg.line(x, 790, x, 804, stroke=INK)
        svg.text(x, 830, f"{tick:.2f}", 16, anchor="middle", fill=MUTED)
    svg.line(x0, 790, x0 + bar_w, 790, stroke=INK)
    svg.text(x0 + bar_w / 2, 895, "Throughput (Gbit/s)", 19, anchor="middle")
    svg.text(70, 930, "Source: directed_175 throughput_xsim.log; all six modes PASS", 16, fill=MUTED)
    svg.write(path)


def density_congestion_figure(
    path: Path,
    placement: list[dict[str, str]],
    tiles: list[dict[str, str]],
) -> None:
    bin_size = 4
    density: dict[tuple[int, int], int] = {}
    for row in placement:
        key = (int(row["grid_x"]) // bin_size, int(row["grid_y"]) // bin_size)
        density[key] = density.get(key, 0) + 1
    valid_tiles = [row for row in tiles if row["tile_type"] != "NULL"]
    max_x = max(int(row["grid_x"]) for row in valid_tiles) // bin_size
    max_y = max(int(row["grid_y"]) for row in valid_tiles) // bin_size
    max_count = max(density.values())
    svg = Svg(1650, 1000)
    svg.title(
        "Placed primitive density and Vivado congestion gate",
        "Heatmap shows placement density only; routed report found no congestion windows above level 5",
    )
    left, top, width, height = 95, 160, 1120, 720
    cell_w = width / (max_x + 1)
    cell_h = height / (max_y + 1)
    occupied_bins = {
        (int(row["grid_x"]) // bin_size, int(row["grid_y"]) // bin_size)
        for row in valid_tiles
    }
    for bx, by in occupied_bins:
        svg.rect(left + bx * cell_w, top + by * cell_h, cell_w, cell_h, fill=WHITE, stroke=GRID, width=0.25)
    for (bx, by), count in density.items():
        strength = math.log1p(count) / math.log1p(max_count)
        shade = int(238 - 190 * strength)
        fill = f"#{shade:02x}{shade:02x}{shade:02x}"
        svg.rect(left + bx * cell_w, top + by * cell_h, cell_w, cell_h, fill=fill, stroke="none")
    svg.rect(left, top, width, height, fill="none", stroke=INK)
    panel_x = 1280
    svg.rect(panel_x, 170, 300, 160, fill=GREEN_PALE, stroke=GREEN, width=2)
    svg.text(panel_x + 150, 220, "CONGESTION PASS", 24, anchor="middle", fill=GREEN, weight=600)
    svg.text(panel_x + 150, 260, "No windows", 21, anchor="middle")
    svg.text(panel_x + 150, 292, "above level 5", 21, anchor="middle")
    svg.text(panel_x, 390, "Placement evidence", 22, weight=600)
    svg.text(panel_x, 430, f"{len(placement):,} primitive cells", 20)
    svg.text(panel_x, 462, f"{len(density):,} occupied bins", 20)
    svg.text(panel_x, 494, f"{bin_size} × {bin_size} GRID bins", 20)
    svg.text(panel_x, 560, "Density legend", 22, weight=600)
    for index in range(10):
        shade = int(238 - 190 * index / 9)
        svg.rect(panel_x + index * 28, 585, 28, 30, fill=f"#{shade:02x}{shade:02x}{shade:02x}", stroke="none")
    svg.text(panel_x, 645, "low", 17, fill=MUTED)
    svg.text(panel_x + 280, 645, "high", 17, anchor="end", fill=MUTED)
    svg.multiline(
        panel_x,
        710,
        ["Important:", "dark regions are cell density,", "not route-capacity utilization."],
        18,
        fill=MUTED,
    )
    svg.text(70, 945, "Sources: routed DCP placement GRID_POINT data and report_design_analysis -congestion", 16, fill=MUTED)
    svg.write(path)


def power_figure(path: Path, manifest: dict) -> None:
    power = manifest["implementation"]["vectorless_power"]
    rows = [
        ("Signals", 0.113),
        ("Static", 0.099),
        ("MMCM", 0.090),
        ("Slice logic", 0.078),
        ("Clocks", 0.041),
        ("Block RAM", 0.035),
        ("I/O", 0.005),
    ]
    svg = Svg(1600, 970)
    svg.title(
        "Vivado routed vectorless power estimate",
        "Medium confidence; estimate only, not measured board power",
    )
    svg.text(1380, 75, f'{power["total_w"]:.3f} W total', 30, anchor="end", fill=BLUE, weight=600)
    x0, bar_w, scale_max = 360, 980, 0.12
    for index, (name, watts) in enumerate(rows):
        y = 165 + index * 96
        svg.text(90, y + 30, name, 22, weight=600)
        svg.rect(x0, y, bar_w, 42, fill=PALE, stroke="none")
        svg.rect(x0, y, bar_w * watts / scale_max, 42, fill=BLUE if name != "Static" else MUTED, stroke="none")
        svg.text(1480, y + 30, f"{watts:.3f} W", 20, anchor="end", weight=600)
        svg.text(1560, y + 30, f"{watts / power['total_w'] * 100:.1f}%", 18, anchor="end", fill=MUTED)
    for tick in [0.00, 0.03, 0.06, 0.09, 0.12]:
        x = x0 + bar_w * tick / scale_max
        svg.line(x, 835, x, 850, stroke=INK)
        svg.text(x, 878, f"{tick:.2f}", 17, anchor="middle", fill=MUTED)
    svg.line(x0, 835, x0 + bar_w, 835, stroke=INK)
    svg.text(x0 + bar_w / 2, 920, "Power (W)", 19, anchor="middle")
    svg.text(70, 950, "Source: power_vectorless_routed.rpt; rounded components sum may differ by 0.001 W", 16, fill=MUTED)
    svg.write(path)


def verification_matrix_figure(path: Path) -> None:
    rows = [
        ("GHASH smoke", "PASS", "66 tests; digit latency 8; external II 9"),
        ("AXI smoke", "PASS", "7,676 cycles; 0 assertion failures"),
        ("Directed 175 MHz", "PASS", "8 / 8 applicable regressions"),
        ("SVA", "PASS", "37 properties; 0 failures"),
        ("XSim UVM 1.2", "PASS", "3 seeds; scoreboard 24 / 0; maintained bins 100%"),
        ("ModelSim UVM 1.2", "PASS", "deterministic smoke 1 / 0; Starter license scope"),
        ("Formal", "PARTIAL PASS", "19 combinational assertions; sequential closure unclaimed"),
        ("Simulated NIST", "PASS", "47,250 / 47,250; 0 fail"),
        ("Implementation", "PASS", "WNS +0.029; WHS +0.044; DRC/CDC gates clean"),
        ("Board program + smoke", "PASS", "Hardware Manager PASS; six modes 6 / 0"),
        ("Hardware NIST", "PASS", "47,250 / 47,250; 0 fail; reconciliation PASS"),
        ("OOC PartPin replay", "NOT RUN", "no approved identity-matched production map"),
    ]
    svg = Svg(1700, 1110)
    svg.title(
        "Verification and signoff evidence matrix",
        "Exact-current 175 MHz candidate; status boundaries are preserved",
    )
    x_name, x_status, x_evidence = 90, 650, 920
    svg.text(x_name, 165, "Verification layer", 21, weight=600)
    svg.text(x_status, 165, "Status", 21, weight=600)
    svg.text(x_evidence, 165, "Retained evidence", 21, weight=600)
    svg.line(70, 185, 1630, 185, stroke=INK)
    for index, (name, status, evidence) in enumerate(rows):
        y = 215 + index * 70
        svg.line(70, y + 43, 1630, y + 43, stroke=GRID)
        svg.text(x_name, y + 26, name, 19, weight=600)
        if status == "PASS":
            fill, stroke = GREEN_PALE, GREEN
        elif status == "PARTIAL PASS":
            fill, stroke = ORANGE_PALE, ORANGE
        else:
            fill, stroke = PALE, MUTED
        svg.rect(x_status, y, 210, 40, fill=fill, stroke=stroke, rx=4)
        svg.text(x_status + 105, y + 27, status, 17, anchor="middle", fill=stroke, weight=600)
        svg.text(x_evidence, y + 26, evidence, 17)
    svg.text(70, 1080, "Source: verification/results/exact_current_manifest.json and compact verification summaries", 16, fill=MUTED)
    svg.write(path)


def waveform_figure(path: Path) -> None:
    svg = Svg(1800, 1120)
    svg.title(
        "SVA/UVM AXI-Stream tag transaction timing",
        "Protocol relationship illustration from implemented properties and monitor behavior; not a captured waveform",
    )
    cycles = 12
    x0, cw = 360, 105
    top, row_h = 190, 82
    signals: list[tuple[str, list[int | str]]] = [
        ("tagq_valid", [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0]),
        ("m_axis_tag_tvalid", [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0]),
        ("m_axis_tag_tready", [1, 1, 1, 1, 0, 0, 1, 1, 0, 1, 1, 1]),
        ("tag_stream_fire", [0, 0, 0, 1, 0, 0, 1, 1, 0, 1, 1, 0]),
        ("m_axis_tag_tlast", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0]),
        ("tag_out_index", ["–", "–", "0", "0", "1", "1", "1", "2", "3", "3", "4", "–"]),
        ("m_axis_tag_tdata", ["–", "–", "–", "T0", "T1", "T1", "T1", "T2", "T3", "T3", "T4", "–"]),
    ]
    for cycle in range(cycles + 1):
        x = x0 + cycle * cw
        svg.line(x, top - 35, x, top + row_h * len(signals), stroke=GRID, width=1)
        if cycle < cycles:
            svg.text(x + cw / 2, top - 50, f"C{cycle}", 17, anchor="middle", fill=MUTED)
    for row_index, (name, values) in enumerate(signals):
        y_mid = top + row_index * row_h + row_h / 2
        svg.text(75, y_mid + 7, name, 19, weight=600)
        if all(isinstance(value, int) for value in values):
            high, low = y_mid - 20, y_mid + 20
            points: list[tuple[float, float]] = []
            for index, value in enumerate(values):
                x_left = x0 + index * cw
                level = high if value else low
                if index:
                    points.append((x_left, points[-1][1]))
                points.extend([(x_left, level), (x_left + cw, level)])
            svg.polyline(points, stroke=BLUE if name == "tag_stream_fire" else INK, width=3)
        else:
            for index, value in enumerate(values):
                svg.rect(x0 + index * cw + 3, y_mid - 24, cw - 6, 48, fill=PALE, stroke=GRID)
                svg.text(x0 + index * cw + cw / 2, y_mid + 7, value, 17, anchor="middle")
        svg.line(60, y_mid + row_h / 2, 1730, y_mid + row_h / 2, stroke=GRID, width=0.8)

    stall_x = x0 + 4 * cw
    svg.rect(stall_x, top + row_h, 2 * cw, row_h * 6, fill=ORANGE_PALE, stroke=ORANGE, width=1.5, opacity=0.45)
    svg.text(stall_x + cw, top + row_h * 7 + 45, "Backpressure: VALID=1, READY=0 → data/index hold", 18, anchor="middle", fill=ORANGE, weight=600)
    svg.line(x0 + 3.5 * cw, top + row_h * 7 + 85, x0 + 3.5 * cw, top + row_h * 7 + 125, stroke=BLUE, arrow=True)
    svg.text(x0 + 3.5 * cw, top + row_h * 7 + 155, "UVM monitor samples T0", 17, anchor="middle", fill=BLUE)
    svg.line(x0 + 10.5 * cw, top + row_h * 7 + 85, x0 + 10.5 * cw, top + row_h * 7 + 125, stroke=BLUE, arrow=True)
    svg.text(x0 + 10.5 * cw, top + row_h * 7 + 155, "Final beat: TLAST with remaining=1", 17, anchor="middle", fill=BLUE)
    svg.text(70, 1085, "SVA checks stability, index advance, decrement, TLAST legality; UVM reconstructs handshakes and scoreboards payload/tag/result.", 17, fill=MUTED)
    svg.write(path)


def export_png(svg_path: Path, png_path: Path, inkscape: Path) -> None:
    started = time.time()
    command = [
        str(inkscape),
        "--batch-process",
        str(svg_path),
        "--export-type=png",
        f"--export-filename={png_path}",
        "--export-width=3200",
        "--export-background=#ffffff",
        "--export-background-opacity=255",
    ]
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 30
    while time.time() < deadline:
        if png_path.is_file() and png_path.stat().st_size > 0 and png_path.stat().st_mtime >= started - 1:
            return
        time.sleep(0.25)
    raise RuntimeError(f"PNG export did not complete: {png_path}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    manifest = read_manifest()
    metrics = {row["metric"]: row["value"] for row in read_tsv(VIVADO_DIR / "vivado_figure_metrics.tsv")}
    path_cells = read_tsv(VIVADO_DIR / "vivado_critical_path_cells.tsv")
    placement = read_tsv(VIVADO_DIR / "vivado_placement_cells.tsv")
    tiles = read_tsv(VIVADO_DIR / "vivado_device_tiles.tsv")

    congestion_report = OUTPUT_DIR / "vivado_congestion_analysis.rpt"
    if not congestion_report.is_file() or "No congestion windows are found above level 5" not in congestion_report.read_text(encoding="utf-8", errors="replace"):
        raise SystemExit("The routed Vivado congestion report is missing or does not contain the expected gate")

    figures = {
        "01_timing_closure_progress": lambda p: timing_closure_figure(p),
        "02_critical_path_delay_breakdown": lambda p: delay_breakdown_figure(p, metrics),
        "03_resource_utilization": lambda p: resource_figure(p, manifest),
        "04_critical_path_placement_zoom": lambda p: placement_zoom_figure(p, path_cells),
        "07_throughput_175mhz": lambda p: throughput_figure(p),
        "08_placement_density_congestion": lambda p: density_congestion_figure(p, placement, tiles),
        "09_power_breakdown": lambda p: power_figure(p, manifest),
        "11_verification_matrix": lambda p: verification_matrix_figure(p),
        "12_sva_uvm_transaction_timing": lambda p: waveform_figure(p),
    }
    for stem, generator in figures.items():
        generator(OUTPUT_DIR / f"{stem}.svg")

    dot_exe = find_graphviz()
    dot_figures = {
        "05_clock_reset_architecture": write_clock_reset_dot,
        "06_aes_gcm_pipeline": write_pipeline_dot,
        "10_verification_flow": write_verification_flow_dot,
    }
    for stem, writer in dot_figures.items():
        dot_path = OUTPUT_DIR / f"{stem}.dot"
        writer(dot_path)
        render_dot(dot_path, OUTPUT_DIR / f"{stem}.svg", dot_exe)

    inkscape = find_inkscape()
    stems = sorted(list(figures) + list(dot_figures))
    for stem in stems:
        export_png(OUTPUT_DIR / f"{stem}.svg", OUTPUT_DIR / f"{stem}.png", inkscape)

    evidence = {
        "generated_figures": stems,
        "graphviz_version": EXPECTED_GRAPHVIZ,
        "vivado_version": "2021.1 SW Build 3247384",
        "target_clock_mhz": 175,
        "manifest": str(MANIFEST_PATH.relative_to(REPO_ROOT)).replace("\\", "/"),
        "manifest_sha256": sha256(MANIFEST_PATH),
        "routed_dcp_sha256": manifest["implementation"]["checkpoints"]["routed"]["sha256"],
        "limitations": [
            "Power is a medium-confidence vectorless estimate, not a board measurement.",
            "Placement density is not route-capacity utilization; Vivado congestion status is reported separately.",
            "The SVA/UVM timing diagram illustrates implemented protocol relationships and is not a captured waveform.",
            "Throughput values are RTL simulation measurements, not UART or board transport throughput.",
            "Formal is a partial combinational subset; sequential/whole-design formal closure is not claimed.",
        ],
    }
    (OUTPUT_DIR / "figure_evidence.json").write_text(
        json.dumps(evidence, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"RECOMMENDED_VISUALS_PASS figures={len(stems)} output={OUTPUT_DIR}")


if __name__ == "__main__":
    main()
