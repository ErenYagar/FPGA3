# Vivado 2021.1 native report visuals

This directory contains native Vivado views and reports for the retained
175 MHz Arty A7-100T AES-GCM implementation. The GUI images are captures of
Vivado's own Device, Package, Schematic, Timing, Clock, Utilization, Power,
Congestion, and DRC windows. They are not Graphviz or matplotlib redrawings.

## Identity and signoff

- Vivado: 2021.1, SW Build 3247384
- Top: `arty_a7_100t_aes_gcm_uart_rsp_top`
- Part: `xc7a100tcsg324-1`
- Clock: 175 MHz
- Synthesis DCP SHA-256:
  `C5D9858BDD097622C7AA76A1843CB3D49EF7646470BC4ACDAF9BDB27882914E6`
- Routed DCP SHA-256:
  `A91758ED87EB56648EEF0CAB67B2C50D198D00A2D5088E624B507687D99C016B`
- Routed timing: WNS `+0.029 ns`, TNS `0`, WHS `+0.044 ns`, THS `0`
- Routing: 17,758 of 17,758 routable nets fully routed; route errors `0`
- DRC: violations `0`

## Recommended figure order

| Figure | Vivado-native content | Recommended use |
|---|---|---|
| `18_implementation_device_placement_gui.png` | Full Device placement with the critical path highlighted | Main implementation figure |
| `20_routing_resources_detail_gui.png` | Tile-level routing resources | Routing/physical-design discussion |
| `21_routed_worst_setup_schematic_gui.png` | Routed critical-path schematic | Critical-path logic discussion |
| `28_timing_summary_gui.png` | Design Timing Summary | Timing signoff evidence |
| `31_worst_setup_path_details_gui.png` | Detailed setup path and delay breakdown | Explain logic versus net delay |
| `24_clock_networks_gui.png` | 100 MHz input, MMCM, 175 MHz core clock, BUFG, and loads | Clock architecture |
| `23_clock_interaction_gui.png` | Clock Interaction matrix | Clock-domain/CDC evidence |
| `25_utilization_gui.png` | Vivado utilization summary and native bar chart | Resource results |
| `26_power_gui.png` | Vivado power summary and component breakdown | Power estimate |
| `27_congestion_gui.png` | Vivado congestion analysis | Placement/routing risk |
| `32_package_io_gui.png` | Package and I/O assignment view | Board interface/pin planning |
| `33_drc_no_violations_gui.png` | Vivado `No Violations Found` result | Implementation legality |

Additional useful figures are the tile-level placement detail, worst setup and
hold timing tables, and Vivado's native SVG/PDF schematic exports.

## Native vector and interactive files

- `01_synthesis_worst_setup_schematic.svg/.pdf/.png`
- `02_routed_worst_setup_schematic.svg/.pdf/.png`
- `03_routed_worst_hold_schematic.svg/.pdf/.png`
- `01_synthesis_timing_summary.rpx`
- `04_routed_timing_summary.rpx`
- `13_power.rpx`
- `14_drc.rpx`
- `15_methodology.rpx`

The SVG/PDF files are exported directly by Vivado `write_schematic`. RPX files
are interactive Vivado reports and can be reopened with `open_report`.

## Evidence boundaries

- `26_power_gui` is Vivado vectorless power estimation: total on-chip power
  `0.461 W`, confidence `Medium`. It is not measured board power.
- Congestion analysis reports no congestion windows above level 3. The GUI
  table shows the retained level-3 placer window for engineering context.
- Package/I/O and routing images are GUI captures because Vivado 2021.1 does
  not provide a native Device-view SVG export. Native SVG export is supported
  for Schematic windows.

## Reproduce

Run:

```powershell
powershell -ExecutionPolicy Bypass -File C:\project\FPGA3\docs\report\run_vivado_native_visuals.ps1
```

Add `-OpenGui` to prepare the same routed checkpoint and named native GUI
reports for capture.
