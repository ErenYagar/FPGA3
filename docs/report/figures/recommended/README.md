# Recommended 175 MHz FPGA report visuals

This directory contains twelve source-backed report figures for the retained
175 MHz Arty A7-100T AES-GCM candidate. Every figure is available as SVG and a
3200-pixel PNG preview. DOT source is retained for the three architecture/flow
figures.

## Figure index

| Figure | Best report use | Primary evidence |
|---|---|---|
| `01_timing_closure_progress` | Timing-closure chapter | synth/placed/routed timing reports |
| `02_critical_path_delay_breakdown` | Explain the final routing bottleneck | routed critical-path report |
| `03_resource_utilization` | Synthesis/implementation utilization | routed utilization + clock reports |
| `04_critical_path_placement_zoom` | Physical implementation discussion | routed cell LOC/BEL/tile data |
| `05_clock_reset_architecture` | Clock, reset, and CDC architecture | clock utilization + reset/CDC audit |
| `06_aes_gcm_pipeline` | RTL microarchitecture and parallelization | production RTL + verified latency/II evidence |
| `07_throughput_175mhz` | Performance results | six-mode directed RTL simulation |
| `08_placement_density_congestion` | Placement density and congestion gate | routed placement + Vivado congestion report |
| `09_power_breakdown` | Power section | routed vectorless power report |
| `10_verification_flow` | Verification methodology | exact-current evidence manifest |
| `11_verification_matrix` | Verification/signoff summary | exact-current evidence manifest |
| `12_sva_uvm_transaction_timing` | Explain SVA and UVM responsibilities | production SVA properties + UVM monitor behavior |

## Important evidence boundaries

- Power is a Medium-confidence Vivado vectorless estimate, not measured board
  power.
- The density heatmap counts placed primitives. It is not presented as
  routing-capacity utilization; the same figure separately reports Vivado's
  finding that no congestion window exists above level 5.
- The SVA/UVM timing figure is a protocol-relationship illustration derived
  from implemented properties and monitor behavior, not a captured waveform.
- Throughput is the 175 MHz RTL simulation result for 100 × 1024-bit records;
  it is not UART or end-to-end board transport throughput.
- Formal remains a PARTIAL PASS combinational subset. Sequential and
  whole-design formal closure are not claimed.

Machine-readable provenance and limitations are in `figure_evidence.json`.
The routed DCP SHA-256 is
`A91758ED87EB56648EEF0CAB67B2C50D198D00A2D5088E624B507687D99C016B`.

## Reproduce

Run from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File C:\project\FPGA3\docs\report\run_recommended_visuals.ps1
```

The flow verifies the routed-DCP hash, uses Vivado 2021.1 batch mode for the
congestion report, requires Graphviz 14.1.3 for DOT rendering, and uses
Inkscape only for SVG-to-PNG conversion. It does not use image generation or
matplotlib.
