# AES-GCM verification status

- Production RTL content under test:
  `a6f19472ecc619925b373b1db801911c54062a90`
- Production simulation/implementation top: `aes_gcm_axi_top`
- Production GHASH: `engrenring/rtl/source/stream_ghash/ghash16.v`
- Legacy `engrenring/rtl/source/AESGCM_IO/GHASH.v`: excluded
- Production timing target: 175 MHz, 5.714 ns
- Primary tool: XSim/Vivado 2021.1, SW Build 3247384, IP Build 3246043

Tool inventory:

- XSim/Vivado: 2021.1, available and used
- ModelSim Starter: 10.5b, used with its bundled UVM 1.2 source
- Questa and VCS: not found
- JasperGold/`jg`, `qverify`, and OneSpin: not found

| Verification item | Status | Actual evidence |
|---|---:|---|
| GHASH baseline | PASS | 66 tests, digit latency 8, external II 9 |
| AXI smoke baseline | PASS | 7,676 cycles |
| Six-mode throughput at 175 MHz | PASS | 1.051705--1.065398 Gbit/s |
| Promoted non-D directed regression | PASS | 8/8 applicable tests; Round48/49/53 plus current FIFO clear/refill gates |
| Limited NIST cycle signatures | PASS | 525/0 at 145,808 cycles; 5,255/0 at 1,594,798 cycles |
| Full NIST RSP regression | PASS | 47,250 pass, 0 fail |
| SVA smoke | PASS | 37 properties, 0 assertion failures |
| Independent AES-GCM reference model | PASS | FIPS-197 AES and SP 800-38D GCM |
| Deterministic ModelSim UVM 1.2 smoke | PASS | one fixed AES-128 record; scoreboard checked 1, failed 0; UVM error/fatal 0/0 |
| Constrained-random UVM regression | NOT RUN | ModelSim Starter verification license unavailable; scenario classes are scaffolding |
| Formal proof | NOT RUN | no supported formal tool installed |
| Board shell compile/elaboration | PASS | production RTL elaborated in XSim |
| Generic board-shell 175 MHz OOC synthesis | PASS | required input/output RAMB18 mapping 1/1; DCP `1F47062D...F710`; not timing signoff |
| Fresh 175 MHz internal implementation | PASS | WNS +0.056 ns, TNS/FEP 0; internal WHS +0.053 ns, THS/FEP 0 |
| Parent/board boundary hold signoff | NOT RUN | identity-matched PartPin map and parent timing model unavailable |
| Retained 175 MHz Arty bitstream (`63824ad`) | PASS | setup WNS +0.010 ns; hold WHS +0.011 ns; DRC error/critical warning 0/0 |
| Retained hardware NIST (`63824ad`) | PASS | COM4, 47,250 pass / 0 fail |
| Current `a6f1947` board rebuild/program | NOT RUN | current source differs only by declaration order, but exact-hash board rerun is pending |

Execution/coverage counts:

| Evidence type | Passed | Failed | Inconclusive/not collected |
|---|---:|---:|---:|
| Current 175 MHz NIST vectors | 47,250 | 0 | 0 |
| Applicable 175 MHz directed tests | 8 | 0 | 0 |
| Rejected Round54-D specialization comparison | 0 | 0 | N/A for promoted non-D RTL |
| SVA smoke properties | 37 | 0 | 0 |
| Deterministic UVM tests | 1 | 0 | 0 |
| Constrained-random UVM tests | 0 | 0 | NOT RUN |
| Formal properties | 0 | 0 | all NOT RUN (tool unavailable) |
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

The promoted non-D directed profile also passed every applicable Round48,
Round49, and Round53 test, including repeated prep-tag ZEROIZE, key scrub,
non-96-bit IV/GHASH interruption, GHASH-slot stall, descriptor admission,
abort cardinality, and public-output visibility. The current FIFO bench also
passes abort/ZEROIZE clear, clear priority, immediate refill, stale-fire
prevention, and global head scrub. Only Round54-D's rejected
`CLEAR_HEAD_ON_CLEAR` specialization comparison remains N/A.

The fresh 175 MHz routed implementation uses 11,600 LUTs (10,636 logic and 964
LUTRAM), 8,410 FFs, 10 RAMB18, and zero DSPs. Vectorless total power is 0.389 W
(0.304 W dynamic, 0.085 W static) at Medium confidence. This is an
implementation estimate, not a board power measurement.

Internal timing is closed: setup WNS is +0.056 ns with zero TNS/failing
endpoints, and register-to-register WHS is +0.053 ns with zero internal
THS/failing endpoints. All 16,327 routable nets are fully routed, routing
errors are zero, DRC Error/Critical Warning is 0/0, methodology
Error/Critical Warning is 0/0, and all 12 `check_timing` critical categories
are zero.

The standalone OOC boundary timing report still has WHS -1.216 ns, THS
-916.429 ns, and 966 failing endpoints starting at external input ports with
0.000 ns minimum delay. Without approved `HD.PARTPIN_LOCS` and the exact parent
clock/routing model, these values are not board-signoff evidence. PartPin is
therefore **NO** for this standalone OOC DCP.

A separate retained production Arty UART/RSP build from commit `63824ad` is
fully routed at 175 MHz with setup WNS +0.010 ns, hold WHS +0.011 ns, and zero
DRC Error/Critical Warning. Its bitstream SHA-256 is
`FE57A4276FD63656CAE6618BFAE1B677844A26F75BB5093CA0151A10C21E7586`.
That bitstream was exercised on COM4 against all 47,250 NIST vectors with zero
failures in 1,190.304 s. Current commit `a6f1947` differs from that board RTL
only by a behavior-neutral declaration move, but exact-current-hash board
rebuild/programming is still **NOT RUN** and is not inferred from the retained
result.

Open issues are an approved identity-matched PartPin map for standalone OOC
reuse, a board-wrapper XDC and exact-current-hash board rebuild/programming, a
fully licensed constrained-random/coverage simulator plus implementation of
the named randomized scenarios, and an installed supported formal tool.

The reusable verification deliverables are under `verification/sva/`,
`verification/uvm/`, `verification/formal/`, `verification/board/`,
`verification/vivado/`, and `verification/scripts/`. Compact tracked summaries
live under `verification/results/`; latest raw work products remain local and
are ignored by Git.
