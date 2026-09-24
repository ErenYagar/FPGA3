# Vivado 175 MHz report figures

These figures come from the retained 175 MHz Arty A7-100T checkpoints. The
schematics are native Vivado 2021.1 `write_schematic` SVG exports. The physical
figures are vector renderings of Vivado device-grid, placement, and ordered
routed-PIP data extracted from the routed DCP.

## Recommended report figures

1. `vivado_synthesis_critical_path_schematic.svg` — post-synthesis worst setup
   path. Use in the synthesis/timing-problem discussion. Slack: -0.298 ns.
2. `vivado_implementation_device_placement.svg` — full-device placement map,
   grouped by AES, GHASH, FIFOs, wrapper, UART bridge, and board logic. Use as
   the main implementation figure.
3. `vivado_implementation_critical_path_schematic.svg` — final routed worst
   setup logic cone. Use beside the implementation timing table.
4. `vivado_critical_path_routing.svg` — the same final critical path drawn from
   its six ordered routed-net branches. Use to explain physical net delay.

The PNG files are 3200-pixel previews for slides and quick viewing. Prefer the
SVG versions in LaTeX or convert them to PDF to retain vector quality. A full
flattened synthesis schematic was intentionally not selected for the report:
at this design size it is too dense to communicate useful engineering detail.

## Signoff identity

- Vivado: 2021.1, SW Build 3247384
- Top: `arty_a7_100t_aes_gcm_uart_rsp_top`
- Part: `xc7a100tcsg324-1`
- Clock: 175 MHz
- Synthesis DCP SHA-256:
  `C5D9858BDD097622C7AA76A1843CB3D49EF7646470BC4ACDAF9BDB27882914E6`
- Routed DCP SHA-256:
  `A91758ED87EB56648EEF0CAB67B2C50D198D00A2D5088E624B507687D99C016B`
- Final routed setup WNS: +0.029 ns

Exact paths and source data are recorded in `vivado_figure_manifest.txt`,
`vivado_figure_metrics.tsv`, and the timing/TSV files in this directory.

## Reproduce

Run from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File C:\project\FPGA3\docs\report\run_vivado_report_figures.ps1
```

The script invokes Vivado in batch mode. Vivado briefly initializes its IDE
graphics engine internally because Vivado 2021.1 requires it for native SVG
schematic export; no manual GUI interaction is needed.
