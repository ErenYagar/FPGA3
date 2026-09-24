# AES-GCM 175 MHz RTL Slidev report

This is a browser-native engineering presentation built from the production
RTL and retained FPGA3 evidence. It is intentionally separate from the LaTeX
report and the image-first executive slides.

## Run

From this directory:

```powershell
pnpm install
pnpm dev
```

The deck opens in a browser with presenter mode, code line highlighting,
Mermaid diagrams, and speaker notes.

## Build and export

```powershell
pnpm build
pnpm export:pdf
pnpm export:pptx
```

The PPTX export is image-based; use the HTML build for selectable code and
interactive highlighting. PDF/PPTX export uses the installed Google Chrome on
this Windows workstation through Playwright Chromium.

## Evidence scope

- RTL baseline: `4246ebc7a72ce8eb1a49d56969aae6e151578c11`
- Current repository HEAD when authored: `a0e8531e4e886d103b2a51d6b9fae682d50bf451`
- Target: `xc7a100tcsg324-1`, 175 MHz
- Full-board routed DCP SHA-256:
  `A91758ED87EB56648EEF0CAB67B2C50D198D00A2D5088E624B507687D99C016B`

The deck distinguishes simulated core throughput from UART board throughput,
vectorless power from board measurement, and partial combinational formal
proof from whole-design formal closure.
