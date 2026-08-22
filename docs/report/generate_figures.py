#!/usr/bin/env python3
"""Generate evidence-backed figures for the FPGA3 AES-GCM LaTeX report."""

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


HERE = Path(__file__).resolve().parent
FIG = HERE / "figures"
FIG.mkdir(parents=True, exist_ok=True)

COLORS = {
    "navy": "#17365D",
    "blue": "#2F75B5",
    "cyan": "#5B9BD5",
    "green": "#70AD47",
    "orange": "#ED7D31",
    "red": "#C00000",
    "grey": "#A5A5A5",
}


def finish(name: str):
    plt.tight_layout()
    plt.savefig(FIG / name, dpi=240, bbox_inches="tight", facecolor="white")
    plt.close()


def resource_utilization():
    labels = ["LUT", "FF", "BRAM36 eq.", "DSP"]
    used = np.array([12411, 9029, 5, 0], dtype=float)
    available = np.array([63400, 126800, 135, 240], dtype=float)
    pct = used / available * 100.0
    fig, ax = plt.subplots(figsize=(8.4, 4.4))
    bars = ax.barh(labels, pct, color=[COLORS["blue"], COLORS["green"], COLORS["orange"], COLORS["grey"]])
    ax.set_xlim(0, 25)
    ax.set_xlabel("Device utilization (%)")
    ax.set_title("Arty A7-100T routed resource utilization")
    ax.grid(axis="x", alpha=0.25)
    ax.invert_yaxis()
    for bar, value, total, percentage in zip(bars, used, available, pct):
        ax.text(
            bar.get_width() + 0.35,
            bar.get_y() + bar.get_height() / 2,
            f"{int(value):,}/{int(total):,}  ({percentage:.2f}%)",
            va="center",
            fontsize=9,
        )
    finish("resource_utilization.png")


def timing_iterations():
    stages = ["v3 synth", "v8 synth", "v8 placed\n+ phys_opt", "v8c strict\naudit"]
    wns = [-1.192, -0.298, 0.075, 0.029]
    fep = [1489, 292, 0, 0]
    fig, axes = plt.subplots(1, 2, figsize=(10.2, 4.4))
    colors = [COLORS["red"] if value < 0 else COLORS["green"] for value in wns]
    axes[0].bar(stages, wns, color=colors)
    axes[0].axhline(0, color="black", linewidth=0.8)
    axes[0].set_ylabel("WNS (ns)")
    axes[0].set_title("Setup timing convergence")
    axes[0].grid(axis="y", alpha=0.25)
    for idx, value in enumerate(wns):
        axes[0].text(
            idx,
            value + (0.035 if value >= 0 else 0.025),
            f"{value:+.3f}",
            ha="center",
            va="bottom",
            fontsize=9,
        )

    axes[1].bar(stages, fep, color=[COLORS["orange"], COLORS["cyan"], COLORS["green"], COLORS["green"]])
    axes[1].set_ylabel("Failing endpoints")
    axes[1].set_title("Failing endpoints eliminated")
    axes[1].grid(axis="y", alpha=0.25)
    for idx, value in enumerate(fep):
        axes[1].text(idx, value + 25, f"{value:,}", ha="center", fontsize=9)
    finish("timing_iterations.png")


def throughput():
    modes = ["AES-128", "AES-192", "AES-256"]
    enc = [1.065398, 1.065398, 1.065398]
    dec = [1.051705, 1.051705, 1.051705]
    x = np.arange(len(modes))
    width = 0.34
    fig, ax = plt.subplots(figsize=(8.4, 4.5))
    b1 = ax.bar(x - width / 2, enc, width, label="Encrypt", color=COLORS["blue"])
    b2 = ax.bar(x + width / 2, dec, width, label="Decrypt", color=COLORS["green"])
    ax.axhline(1.0, color=COLORS["red"], linestyle="--", linewidth=1.2, label="1 Gbit/s target")
    ax.set_ylim(0.95, 1.085)
    ax.set_ylabel("Measured RTL throughput (Gbit/s)")
    ax.set_title("100 x 1024-bit records at 175 MHz")
    ax.set_xticks(x, modes)
    ax.legend(loc="lower left", ncol=3, fontsize=8)
    ax.grid(axis="y", alpha=0.25)
    for bars in (b1, b2):
        for bar in bars:
            ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.002, f"{bar.get_height():.3f}", ha="center", fontsize=8)
    finish("throughput.png")


def power_breakdown():
    labels = ["Signals", "MMCM", "Slice logic", "Clocks", "BRAM", "I/O", "Static"]
    values = [0.113, 0.090, 0.078, 0.041, 0.035, 0.005, 0.099]
    fig, ax = plt.subplots(figsize=(8.4, 4.7))
    bars = ax.bar(labels, values, color=[COLORS["blue"], COLORS["orange"], COLORS["green"], COLORS["cyan"], COLORS["navy"], COLORS["grey"], "#7F6000"])
    ax.set_ylabel("Power (W)")
    ax.set_title("Vivado routed vectorless estimate: 0.461 W total")
    ax.grid(axis="y", alpha=0.25)
    ax.tick_params(axis="x", rotation=25)
    for bar, value in zip(bars, values):
        ax.text(bar.get_x() + bar.get_width() / 2, value + 0.003, f"{value:.3f}", ha="center", fontsize=8)
    finish("power_breakdown.png")


def placement_regions():
    # Actual clock-region counts from clock_utilization_routed.rpt.
    regions = [["X0Y3", "X1Y3"], ["X0Y2", "X1Y2"]]
    ff = np.array([[2881, 676], [4071, 1401]], dtype=float)
    lutm = np.array([[660, 276], [892, 438]], dtype=int)
    ramb = np.array([[0, 0], [4, 0]], dtype=int)
    mmcm = np.array([[0, 0], [0, 1]], dtype=int)
    fig, ax = plt.subplots(figsize=(7.2, 5.2))
    image = ax.imshow(ff, cmap="Blues", vmin=0, vmax=4200)
    for row in range(2):
        for col in range(2):
            ax.text(col, row - 0.12, regions[row][col], ha="center", va="center", color="black", fontsize=12, fontweight="bold")
            ax.text(
                col,
                row + 0.14,
                f"FF {int(ff[row, col]):,}\nLUTM {lutm[row, col]:,} | RAMB {ramb[row, col]} | MMCM {mmcm[row, col]}",
                ha="center",
                va="center",
                color="black",
                fontsize=8.5,
            )
    ax.set_xticks([])
    ax.set_yticks([])
    ax.set_title("Actual routed placement across active clock regions")
    cbar = fig.colorbar(image, ax=ax, fraction=0.046, pad=0.04)
    cbar.set_label("FF clock loads")
    finish("placement_regions.png")


def nist_validation():
    sources = [
        "gcmEncryptExtIV128",
        "gcmEncryptExtIV192",
        "gcmEncryptExtIV256",
        "gcmDecrypt128",
        "gcmDecrypt192",
        "gcmDecrypt256",
    ]
    source_counts = np.full(len(sources), 7875)
    latency_labels = ["Min", "Mean", "Median", "P95", "P99", "Max"]
    latency_ms = np.array([9.101, 25.376, 31.440, 32.289, 47.797, 49.779])

    fig, axes = plt.subplots(1, 2, figsize=(12.2, 4.8), gridspec_kw={"width_ratios": [1.35, 1.25]})

    bars = axes[0].barh(sources, source_counts, color=COLORS["blue"], edgecolor=COLORS["navy"], linewidth=0.8)
    axes[0].set_xlim(0, 9000)
    axes[0].set_xlabel("Executed and passed cases")
    axes[0].set_title("NIST RSP source coverage\n47,250 pass, 0 fail")
    axes[0].grid(axis="x", alpha=0.25)
    axes[0].invert_yaxis()
    for bar, value in zip(bars, source_counts):
        axes[0].text(value + 120, bar.get_y() + bar.get_height() / 2, f"{value:,}", va="center", fontsize=9)

    x = np.arange(len(latency_labels))
    axes[1].vlines(x, 0, latency_ms, color="#D9E2F3", linewidth=2.0)
    quantile_mask = np.array([True, False, True, True, True, True])
    axes[1].scatter(x[quantile_mask], latency_ms[quantile_mask], s=70, color=COLORS["blue"], edgecolor=COLORS["navy"], zorder=3)
    axes[1].scatter(x[~quantile_mask], latency_ms[~quantile_mask], s=78, marker="D", color=COLORS["orange"], edgecolor="#7F4120", zorder=3)
    axes[1].set_xticks(x, latency_labels)
    axes[1].set_ylim(0, 56)
    axes[1].set_ylabel("Latency (ms per case)")
    axes[1].set_title("Host-observed transaction latency\nCOM4 at 115200 baud")
    axes[1].grid(axis="y", alpha=0.25)
    for idx, value in enumerate(latency_ms):
        axes[1].text(idx, value + 1.4, f"{value:.3f}", ha="center", fontsize=8)

    finish("nist_validation.png")

if __name__ == "__main__":
    plt.rcParams.update({"font.family": "DejaVu Sans", "axes.titleweight": "bold"})
    resource_utilization()
    timing_iterations()
    throughput()
    power_breakdown()
    placement_regions()
    nist_validation()
