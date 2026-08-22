# AES-GCM verification status

- RTL under test: unmodified git SHA
  `4a215983f3774c49e833cfe3715a019748200c73`
- Production simulation/implementation top: `aes_gcm_axi_top`
- Production GHASH: `engrenring/rtl/source/stream_ghash/ghash16.v`
- Legacy `engrenring/rtl/source/AESGCM_IO/GHASH.v`: excluded
- Primary tool: XSim/Vivado 2021.1, SW Build 3247384, IP Build 3246043

Tool inventory:

- XSim/Vivado: 2021.1, available and used
- ModelSim Starter: 10.5b, available but not used for these results
- Questa and VCS: not found
- JasperGold/`jg`, `qverify`, and OneSpin: not found

| Verification item | Status | Actual evidence |
|---|---:|---|
| GHASH baseline | PASS | 66 tests, digit latency 8, external II 9 |
| AXI smoke baseline | PASS | 7,676 cycles |
| Six-mode throughput at 175 MHz | PASS | 1.051705--1.065398 Gbit/s |
| Full NIST RSP regression | PASS | 47,250 pass, 0 fail |
| SVA smoke | PASS | 37 properties, 0 assertion failures |
| Independent AES-GCM reference model | PASS | FIPS-197 AES and SP 800-38D GCM |
| Full UVM regression | NOT RUN | no UVM 1.2 library available |
| Formal proof | NOT RUN | no supported formal tool installed |
| Board shell compile/elaboration | PASS | production RTL elaborated in XSim |
| Board shell OOC synthesis | PASS | input/output storage each mapped to one RAMB18E1 |
| Fresh 200 MHz implementation | FAIL | WNS -0.615 ns, TNS -131.872 ns, FEP 1,462 |
| Bitstream / board programming | NOT RUN | approved board wrapper/XDC not available |
| Board NIST vectors | NOT RUN | board was not programmed by this flow |

Execution/coverage counts:

| Evidence type | Passed | Failed | Inconclusive/not collected |
|---|---:|---:|---:|
| Baseline NIST vectors | 47,250 | 0 | 0 |
| SVA smoke properties | 37 | 0 | 0 |
| Full UVM tests | 0 | 0 | NOT RUN |
| Formal properties | 0 | 0 | 0 (tool unavailable; all NOT RUN) |
| Functional coverage | -- | -- | NOT COLLECTED |
| Code coverage | -- | -- | NOT COLLECTED |
| UVM assertion coverage | -- | -- | NOT COLLECTED |

The full NIST run processed six files with 7,875 passing vectors each and
completed in 17,740,527 simulated cycles. The 175 MHz throughput test measured
16,820 cycles / 1.065398 Gbit/s for each AES-128/192/256 encrypt record and
17,039 cycles / 1.051705 Gbit/s for each decrypt record. The standalone GHASH
test measured eight digit cycles and a minimum external request interval of
nine cycles. These are test-level measured cycles; no unmeasured board latency
or throughput is inferred.

Routed utilization is 11,792 total LUTs (10,828 logic and 964 LUTRAM), 8,447
FFs, 10 RAMB18, and zero DSPs. The 200 MHz report has WNS -0.615 ns, TNS
-131.872 ns, and 1,462 failing setup endpoints. Vectorless total power is
0.446 W at Medium confidence; this is an implementation estimate, not a board
power measurement.

The routed 200 MHz design is legal (16,434/16,434 routable nets fully routed,
zero routing errors, and zero DRC Error/Critical Warning violations), but it
does **not** meet setup timing. Synthesis, placement, route legality, or OOC
synthesis success must not be interpreted as 200 MHz timing closure.

Open issues are 200 MHz setup closure, an approved identity-matched PartPin
map/board wrapper and XDC, full bitstream generation and board vectors, an
installed UVM 1.2 library, and an installed supported formal tool. The OOC hold
violations begin at external input ports with zero input delay and require the
real board integration to sign off; they do not conceal the independent
internal setup failure.

The reusable verification deliverables are under `verification/sva/`,
`verification/uvm/`, `verification/formal/`, `verification/board/`,
`verification/vivado/`, and `verification/scripts/`. Committed Markdown
summaries live under `verification/results/`; raw work products remain local
and are ignored by Git.
