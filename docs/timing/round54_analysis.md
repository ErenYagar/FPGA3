# Round54 200 MHz internal timing closure

## Locked starting point

Round54 starts from clean commit
`fc77b1224f36925e4ec661a40edd3ece112d1992` on the retained R53-C source.
The core SHA-256 is
`EB905D71345AA93E1D64C8B47D0BEEF50BF1CFF8FE77C3E80594D610BF7B0E5E`.

The local checkpoints passed the required identity gate:

| Stage | SHA-256 |
|---|---|
| synth | `5875BEAFB0A217C9D8CE7062FA27849BF5D41DC5FD8FF8C2031B20E35AEA0789` |
| placed | `09F1A704115CD6C7474438A21A62092798FA2748FDCA6480EAFE8B8991A86D21` |
| routed | `2C2DEAAA2DAAF6CC538BCB336B293030C2AD7791CB8BDCBBC902849BCD611C78` |

Retained routed internal timing is WNS `-0.523 ns`, TNS `-26.673 ns`, 273
failing endpoints, WHS `+0.051 ns`, and THS 0.  Routing is complete and the
DRC/check-timing critical categories are clean.

## Routed family decode

The hash-matched routed DCP was opened in Vivado 2021.1 and all 273 negative
internal register-to-register paths were queried directly.  The ciphertext
family is not inferred from FIFO width:

| Family | Primitive/pin | Paths | TNS (ns) | Worst (ns) |
|---|---:|---:|---:|---:|
| ciphertext head | `FDRE/CE` | 87 | -13.404 | -0.362 |
| ciphertext LUTRAM | `RAMD32/WE` | 28 | -0.492 | -0.034 |
| ciphertext LUTRAM | `RAMS32/WE` | 8 | -0.132 | -0.016 |
| prep tag | `FDRE/R` | 5 | -2.615 | -0.523 |
| round-key main control | `FDRE/CE` | 62 | -5.004 | -0.187 |
| round-key residual | `FDRE/D` | 1 | -0.076 | -0.076 |

All 123 ciphertext failures launch from the physical
`u_registers/zeroize_pulse_o_reg` FDRE.  Its Q net is
`u_registers/zeroize_pulse`, has 342 leaf loads, and is placed at
`SLICE_X32Y122`.  Representative CE and WE fanin cones include both raw
ZEROIZE and `abort_queue_clear`; the WE cone also includes FIFO count and
producer-valid state.

The complete ZEROIZE-source distribution is:

| Endpoint class | Paths | TNS (ns) | Worst (ns) | Average levels | Net/logic |
|---|---:|---:|---:|---:|---:|
| ciphertext head CE | 87 | -13.404 | -0.362 | 4.0 | 4.10 |
| ciphertext LUTRAM WE | 36 | -0.624 | -0.034 | 2.0 | 5.18 |
| prep-tag R | 5 | -2.615 | -0.523 | 4.0 | 4.29 |
| tag-mismatch D | 5 | -0.467 | -0.163 | 4.0 | 4.25 |
| state/control R | 1 | -0.070 | -0.070 | 3.0 | 4.42 |

## Experiment ledger

Results are recorded in `round54_results.csv`.  No experiment is promoted
unless WNS, TNS magnitude, and failing endpoint count all improve relative to
the retained routed C checkpoint and all functional/security gates pass.

### R54-A fresh reproducibility baseline

R54-A rebuilt the retained RTL from source with Vivado 2021.1 build 3247384
and the locked directives `ExploreWithRemap`, `ExtraNetDelay_high`,
`AggressiveExplore`, and `Explore`.  The regenerated checkpoints are:

| Stage | SHA-256 |
|---|---|
| synth | `848E00E57697609246F8F4AF243C90137AAACFC8625337B4E16C8C9FA900CF23` |
| placed | `B98A90503BDA7D5B35309A9C97FC7651C7F5FA8FB5F0B7EEAB347BC1C1304E40` |
| routed | `EA4511B5676C9475FB8E6F9A0D8B0B7660C8766CD1922F04E263F8B712B0AE85` |

The DCP container hashes differ from the retained artifacts, but the fresh
implementation reproduces the retained design exactly at the signoff level:
WNS `-0.523 ns`, TNS `-26.673 ns`, FEP 273, WHS `+0.051 ns`, THS 0,
309 control sets, 8,586 LUTs, 7,296 FFs, and 13,269/13,269 routed nets.
The endpoint-family counts and TNS values are also identical.  DRC errors,
critical warnings, route errors, CDC failures, latches, multiple drivers, and
critical `check_timing` categories are all zero.  R54-A therefore passes the
fresh-flow provenance gate and remains the comparison baseline; it does not
pass setup closure.

### R54-B local prep-tag clear (not promoted)

The first inferred-register implementation passed simulation but failed the
structural gate: Vivado folded the descriptor-load logic into the reset cone,
so `zeroize_sequence_active_r` remained in the mapped `prep_tag_bytes` R-pin
fanin.  That failed synth checkpoint is retained with abbreviated SHA-256
`ECA0...1955` as a negative experiment and was not routed.

The corrected implementation used five explicit FDREs.  Raw reset/ZEROIZE
drive R, `take_descriptor` drives CE, and only the decoded descriptor value
drives D.  The routed DCP gate found five mapped bits, five direct raw-ZEROIZE
R-pin paths, and zero zseq nodes in the reset cones.  Checkpoint hashes are:

| Stage | SHA-256 |
|---|---|
| synth | `4F65C79BEDC975E0EBB404EA181169E4567A1471B313ACC6BF3AA0F8AA0E0056` |
| placed | `1AE3619394A01E9E6CD3FAE72D200B73E54271AF0C776E136F64518A6BF71932` |
| routed | `59A1D230057BB8F1BF64F319660537445313B0AD306D1E7698E36A6B5ECC10B6` |

Synthesis improved to WNS `-0.238 ns`, TNS `-0.476 ns`, and 2 failing
endpoints.  Routing, however, finished at WNS `-0.442 ns`, TNS `-33.434 ns`,
358 failing endpoints, WHS `+0.052 ns`, and THS 0.  It used 8,569 LUTs,
7,310 FFs, 407 control sets, and routed all 13,314 nets.  The source ZEROIZE
net fanout fell from 342 to 326, and the ciphertext family fell from
123/-14.028 ns to 13/-0.793 ns, but the round-key control family grew from
62/-5.004 ns to 126/-17.224 ns.  The raw-ZEROIZE negative family was
33/-3.866 ns.

R54-B therefore fails the three-metric promotion rule: only WNS improved;
TNS magnitude and FEP regressed.  Per the isolation plan, no B2 and no
B-derived combination are run.  The new round-key dominance is recorded for
a subsequent round and is not expanded in Round54.

### R54-C targeted control-set remap (stopped before route)

R54-C opened the immutable retained synth DCP (SHA-256 `5875...0789`) and
applied `CONTROL_SET_REMAP RESET` to exactly the five
`prep_tag_bytes_reg[0:4]` cells.  The property-only optimization reported ten
created cells, after which the baseline opt/place/phys-opt directives were
used.  The placed checkpoint SHA-256 is
`E6ED749ED3E430A091E379B9CFE2872D8154B5F699E91D42E3A0032CE1E4EF92`.

The requested remap did not occur.  All five placed cells remained FDREs with
R pins, raw ZEROIZE reached both D and R (10 pin paths), and each D path had
five logic levels.  The placed control-set count increased from 309 to 367;
utilization was 8,548 LUTs and 7,303 FFs.  Although the transient placed setup
estimate was positive (`+0.101 ns`), the hard gate rejected the structural
result before routing.  No C route or B+C combination exists.

### R54-D ciphertext FIFO logical clear (not promoted)

R54-D set `CLEAR_HEAD_ON_CLEAR=0` only on `u_ciphertext_fifo`.  Global reset
still scrubs the 134-bit head; logical clear atomically clears FIFO count and
pointers while the physically stale head remains unobservable.  The final
synthesis implementation uses 134 explicit FDREs with CE tied high and moves
the hold behavior into D, eliminating the raw-ZEROIZE CE cone without changing
the 4x134 LUTRAM body.  The checkpoint hashes are:

| Stage | SHA-256 |
|---|---|
| synth | `59A36389DD7CB6D8CFA3610A511C1D98095839CA1C54E9B98B874CDE8E1F6456` |
| placed | `3D522696725B18961F73F84C279BBF4BE4DB5A4B536A88D7224412BA62D2D792` |
| routed | `2C68A17238F92D0E94825A45B52E702885B17EBEFA2F293A968B306BFE688CC6` |

The synth and placed gates found 134 head FDREs, zero raw-ZEROIZE reachability
to their CE pins, and 180 LUTRAM WE pins with logical raw-ZEROIZE reachability.
Baseline `AggressiveExplore` produced two equivalent ZEROIZE FF replicas.  The
gate verifies their FDRE INIT, clock, CE, reset, D-driver primitive/INIT, and
all D-cone startpoints against the primary.  Routed mapping was primary fanout
359 at `SLICE_X35Y91/BFF`, replica fanout 21 at `SLICE_X35Y85/DFF`, and
replica fanout 1 at `SLICE_X36Y111/A5FF`.

Placement reached setup WNS `+0.024 ns`, TNS 0, and FEP 0, with transient hold
WHS `-0.059 ns`.  The independent Explore route repaired hold to WHS
`+0.050 ns` and THS 0, routed all 13,412 nets, and passed route, DRC, CDC,
latch, multiple-driver, and security gates.  Routed setup was WNS
`-0.457 ns`, TNS `-40.010 ns`, and FEP 339.  The direct ciphertext negative
family fell from 123/-14.028 ns to 0/0, but the round-key family grew to
109/-19.039 ns; direct ZEROIZE failures were 9/-0.370 ns.  Utilization was
8,735 LUTs, 7,300 FFs, and 376 control sets.

All functional tests passed, including the exact smoke/throughput signatures,
Round48/49, all Round53 ZEROIZE/stall/capacity tests, directed abort and
ZEROIZE clear, clear priority, immediate refill, stale-head non-observability,
global scrub, NIST525, and NIST5255.  D nevertheless fails promotion because
TNS magnitude and FEP regress.  No D combination or D final-mile directive is
eligible.

Two stopped D variants are retained as negative evidence.  Commit `08023da`
left the 134-bit head CE cone intact; its synth DCP is
`5E2E2F4E04F061DF316BC05F8B966A46D73239DA843B0CB46C5444C94F77C8B7`.
Commit `e0c90b8` isolated pop-ready from clear but again left all 134 CE paths;
its synth DCP is
`B021CF755699D75D3004CBB9C25DB3DB1BF223640524456701DA8FF7488E7F1E`.
An explicit-FDRE simulation run before the behavioral simulation branch was
stopped after excessive idle self-assignment events; the final source removed
those simulation-only events and then passed the full regression.

### R54-E forced ZEROIZE replication (not promoted)

R54-E opened the immutable retained-C placed checkpoint and applied
`phys_opt_design -force_replication_on_nets` only to the exact
`u_registers/zeroize_pulse` net.  Before the command the primary FDRE was at
`SLICE_X32Y122/DFF`, had fanout 342, and had no replicas.  The command created
nine equivalent FDRE replicas (18 cells including their D LUTs).  The
post-replication placed checkpoint SHA-256 is
`7331BBFA4CF87A408370D549A26BF7321AD037FCF2F1B5F783A088686D0C59C9`.

| Source | LOC/BEL | Fanout |
|---|---|---:|
| primary | `SLICE_X32Y122/DFF` | 1 |
| replica 0 | `SLICE_X32Y123/C5FF` | 273 |
| replica 1 | `SLICE_X7Y136/AFF` | 19 |
| replica 2 | `SLICE_X29Y127/CFF` | 16 |
| replica 3 | `SLICE_X12Y138/BFF` | 2 |
| replica 4 | `SLICE_X13Y142/AFF` | 1 |
| replica 5 | `SLICE_X32Y137/AFF` | 10 |
| replica 6 | `SLICE_X37Y133/AFF` | 16 |
| replica 7 | `SLICE_X12Y138/CFF` | 2 |
| replica 8 | `SLICE_X12Y138/DFF` | 2 |

The fanouts sum to the original 342 loads.  The hard gate verifies every
source's FDRE INIT, C/CE/R/S nets, D-driver primitive and INIT, D-cone
startpoints, LOC/BEL, fanout, and complete load mapping.  No BUFG, LOC,
Pblock, `DONT_TOUCH`, or `MAX_FANOUT` constraint was added.

The replicated placed design estimated WNS `-0.211 ns`, TNS `-6.721 ns`, and
FEP 79, with transient WHS `-0.142 ns`, THS `-0.953 ns`, and 24 hold failing
endpoints.  The independent Explore route repaired hold and routed all 13,287
nets without errors, but signoff setup regressed to WNS `-0.640 ns`, TNS
`-76.238 ns`, and FEP 464.  The routed checkpoint SHA-256 is
`66C18BB8B8C6774DE7B85A296E33BE428DE34E79C7FC6C8661F7295ECE962BD1`.
WHS is `+0.051 ns`, THS is 0, and DRC/check-timing/security gates pass.
Utilization is 8,595 LUTs, 7,305 FFs, and 311 control sets.

The corrected path decoder recorded exactly 2,000 routed candidates and
recomputed all 464 negative endpoints and `-76.238 ns` TNS exactly.  Replica
launches dominate the new failures: ciphertext head CE is 133/-36.051 ns,
ciphertext LUTRAM WE is 100/-13.416 ns, all direct ZEROIZE is 312/-62.182 ns,
and round-key control is 41/-5.202 ns.  The decoder fix is commit `740f16c`;
it changes reporting only and was validated by an audit-only run against the
immutable routed hash.

R54-E fails every setup promotion metric relative to retained C.  It is not a
stable structural candidate, so the three remaining routing directives are
not run.

## Round54 disposition

| Experiment | WNS (ns) | TNS (ns) | FEP | WHS (ns) | THS (ns) | Control sets | LUT | FF | Disposition |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| A | -0.523 | -26.673 | 273 | +0.051 | 0 | 309 | 8,586 | 7,296 | reproducible baseline |
| B | -0.442 | -33.434 | 358 | +0.052 | 0 | 407 | 8,569 | rejected |
| C | not routed | not routed | not routed | not routed | not routed | 367 placed | 8,548 | 7,303 | remap absent; stopped |
| D | -0.457 | -40.010 | 339 | +0.050 | 0 | 376 | 8,735 | 7,300 | rejected |
| E | -0.640 | -76.238 | 464 | +0.051 | 0 | 311 | 8,595 | 7,305 | rejected |
| combined | not run | not run | not run | not run | not run | not run | not run | not run | B/C/D failed promotion |

No isolated structural experiment passes the required three setup metrics.
Consequently no B/C+D combination, final-mile directive sweep, manual pulse
FF study, or 47,250-vector final-candidate NIST run is eligible.  Retained
R53-C remains the best legal implementation, but internal 200 MHz timing is
open; Round54 final internal PASS is **NO**.

PartPin is also **NO**.  No approved production map matches the retained
placed-DCP identity, and the Round46 maps remain discovery candidates only.

## Continued control-locality experiments (F/G)

This section supersedes the earlier Round54 disposition.  R54-F commit
`cfff841394a06e58e7d4a675dc3aa137e2aa297d` replaces the state-dependent,
indexed round-key array write with 60 registered one-hot word enables and
constant-slice writes.  It preserves the core source hash
`EB905D71345AA93E1D64C8B47D0BEEF50BF1CFF8FE77C3E80594D610BF7B0E5E`.
Fresh synthesis improved to WNS/TNS/FEP `-0.235/-2.291/14`; its placed DCP
`EBF9C119CD6D9F4E087B34ADE8C3A55E57010E9F372A0C817A93499B43BDE6BB`
had setup WNS `+0.107 ns`.

The route directive sweep from that immutable placed checkpoint produced:

| Candidate | WNS (ns) | TNS (ns) | FEP | WHS (ns) | THS | Routed DCP SHA-256 |
|---|---:|---:|---:|---:|---:|---|
| F Explore | -0.432 | -95.464 | 677 | +0.050 | 0 | `6F3303FB...CB1920F` |
| F MoreGlobalIterations | -0.445 | -36.125 | 259 | +0.050 | 0 | `7264A0B3...BA273A8` |
| F AggressiveExplore | -0.468 | -5.835 | 108 | +0.054 | 0 | `6FE53A7B...EF82767` |
| F HigherDelayCost | -0.544 | -34.085 | 251 | +0.050 | 0 | `243B36CA...1F77C6A` |
| G AggressiveExplore | **-0.379** | **-4.579** | **86** | **+0.058** | **0** | `6E065570...D741F` |

F removes the former round-key setup family as a dominant contributor.
On F-Aggressive, 80 of 108 negative paths launched from
`input_field_mode_r[2]`, contributing `-2.790 ns` TNS.  R54-G commit
`e940299` therefore force-replicates only that exact placed net.  Vivado
created two equivalent physical register replicas.  The post-replication
placed DCP SHA-256 is
`CCA973F67FEDD7EFE52D36DCAD757DA63EE5BE6E336E2DD43B9CC4C8D722ED51`.
AggressiveExplore then improved every promotion metric over retained C and
F-Aggressive.  Its routed utilization is 8,357 LUTs, 7,352 FFs, and 234
control sets; all 13,511 routable nets are fully routed.

| Input-mode source | LOC/BEL | Mapped loads |
|---|---|---:|
| primary | `SLICE_X45Y95/SLICEL.BFF` | 3 |
| replica 0 | `SLICE_X43Y93/SLICEL.AFF` | 26 |
| replica 1 | `SLICE_X39Y98/SLICEL.AFF` | 11 |

The 40 mapped input loads plus the driver pin correspond to Vivado's original
`FLAT_PIN_COUNT=41`.  The G hard gate compares primitive/INIT, clock and
control pins, D-cone startpoints, and the complete per-net load mapping.

G is the current best legal implementation, but it is not internal closure:
86 setup endpoints remain and WNS is `-0.379 ns`.  Its largest residual
groups are 42 AES-result FIFO RAM-WE paths (`-1.880 ns` TNS), 19 paths from
one input-mode replica (`-0.870 ns`), and the WNS path from
`aes_result_out[140]` to `state_reg[1]/D`.  Hold, route, DRC, methodology,
CDC, latch, multiple-driver, and ZEROIZE gates pass.  Internal PASS remains
**NO**, and PartPin remains **NO** pending an approved identity-matched map.

## Continued R54-H/I/GI/J/EGI/K experiments

This section supersedes the F/G best-candidate statement above.  No result in
this section is called closed unless routed WNS is non-negative and routed
TNS/FEP/THS are zero.

### R54-H FIFO full locality

R54-H commit `af62da4ca97b19e4fcfde8b479e2a6bb6eef5a0f` replaces the
wide equality expression used for FIFO full detection with the count MSB.
It is combined with F and does not change the FIFO state or push/pop priority.
Fresh synthesis was `-0.114/-1.104/10`, and the placed checkpoint was setup
clean at `+0.049 ns`.  The immutable placed DCP SHA-256 is
`0529620C18FBFF1FC8B7854088DD51F35976F218BD3FE299BCC5D1D1854F96C1`.

| Directive | WNS | TNS | FEP | WHS | THS | Routed DCP SHA-256 |
|---|---:|---:|---:|---:|---:|---|
| Explore | -0.675 | -10.490 | 71 | +0.060 | 0 | `0AE1248EFFB2ADF5139D4EC844FD0016BD9F80D01B60ECC37A8E05FD6A52F389` |
| AggressiveExplore | -0.647 | -15.125 | 84 | +0.060 | 0 | `33BE024D2BDD0100C98523442A5BAC46499FEE19E3A3982A93B7D522ED55AE9A` |
| MoreGlobalIterations | -0.802 | -26.205 | 240 | +0.055 | 0 | `4B0DCDEFF67729535EFC3257FDDF77913EFB7A899F07A191AEFF1EDBEA7B0C8B` |
| HigherDelayCost | -0.799 | -9.529 | 43 | +0.063 | 0 | `F5413D0F33140369FCA51C14B3B746A0D13001124019092E1B7E15E59EC0068F` |

No H route improves all three promotion metrics.  H is retained only as an
RTL component of the later I/GI candidate.

### R54-I prep-tag locality and R54-GI physical input-mode replication

R54-I moves `prep_tag_bytes[4:0]` into five explicit FDRE writers on top of
F+H.  Reset and raw ZEROIZE drive R, `take_descriptor` drives CE, and the
descriptor value is the only D writer.  Synthesis is setup clean at
`+0.086/0/0`; the synth and placed hashes are respectively
`F0D3654E35E62A8A613413F965DC3C7D77B171A1934779190F1AE95FD2E4B806`
and `93D5A75B2246985A0C03555E12A4D71DA42CB6A83BDBF8B7550E4A2371F97009`.
All five physical bits retain same-edge raw-ZEROIZE reachability, have one
logical writer, and have no zseq decode in the reset cone.

| Candidate | WNS | TNS | FEP | WHS | THS | Routed DCP SHA-256 |
|---|---:|---:|---:|---:|---:|---|
| I Explore | -0.528 | -74.776 | 567 | +0.050 | 0 | `1177EE4DFFB62F433ED9D5B83C6201114D37EAACFBEC0D102D53D3EE8C9BA151` |
| I AggressiveExplore | -0.422 | -22.967 | 278 | +0.050 | 0 | `524A07487CDEF75BA7164286427F13F471700A2F09AAD9D31A0ACC63496225AE` |
| I MoreGlobalIterations | -0.480 | -32.462 | 343 | +0.050 | 0 | `8D70C88FD7691795BE6AC73E2D832521E77C76804C370652E0A158B551349910` |
| I HigherDelayCost | -0.502 | -73.020 | 451 | +0.054 | 0 | `D550FC697BD6A13C26D42F57EDA38F77EFC9B323E38B401E4D925E19DD2A9695` |
| **GI AggressiveExplore** | **-0.146** | **-0.540** | **19** | **+0.050** | **0** | `2C10BCA0BAD8A8ED3407B2F3FF6FC0FFD378A9FDB6FF2ED65F0293150573433A` |

I-Aggressive misses the retained-C promotion rule by five FEP.  GI therefore
starts from the exact I placed hash and force-replicates only
`u_core/input_field_mode_r[2]`.  Vivado creates one equivalent FDRE replica;
the post-replication placed DCP hash is
`CA482687CB00A75D541C01A8B512AACD43073E8AA881255B808DD0EF475BBCBA`.

| Input-mode source | LOC/BEL | Loads |
|---|---|---:|
| primary | `SLICE_X46Y68/SLICEM.CFF` | 1 |
| replica | `SLICE_X45Y65/SLICEL.BFF` | 35 |

The hard gate verifies primitive/INIT, clock and every control pin, D-cone
startpoints, disjoint/nonempty load partitions, and all 36 mapped loads.  GI
improves WNS, TNS and FEP over retained C and is the current best legal
implementation.  Its 19 residual paths total only `-0.540 ns`: 12 include
the input-mode control cone (`-0.437 ns`), the WNS path is descriptor FIFO
count to state (`-0.146 ns`), four are `field_bytes_remaining` CE paths, and
two are round-key R paths (`-0.046 ns`).  No prep-tag path is negative.

### R54-J and R54-EGI final-mile attempts

All J routes start independently from the same hash-matched GI placed DCP.

| Candidate | WNS | TNS | FEP | WHS | THS | Routed DCP SHA-256 |
|---|---:|---:|---:|---:|---:|---|
| J Explore | -0.403 | -43.696 | 224 | +0.050 | 0 | `2D96957AAE635B8516722E9F1097CBD246293B64D6B0E90EE7880E38A7CAA556` |
| J MoreGlobalIterations | -0.406 | -40.434 | 291 | +0.050 | 0 | `7554043733817CA7B62F2A14EAAABC9D33CC1DBF8B08F78134B04F213C0E6D22` |
| J HigherDelayCost | -0.353 | -56.148 | 449 | +0.057 | 0 | `AF4DF589845733B024B91687FE0471D7669FD5E079209DDBDAB7817086ECE344` |

None beats GI.  EGI then force-replicates only the exact ZEROIZE net in the
same GI placed DCP.  Vivado creates 11 physical ZEROIZE replicas; the routed
result regresses to `-0.422/-38.597/287`, WHS `+0.050 ns`, THS 0.  The routed
DCP SHA-256 is
`E7DB7D18704B53DF4D109EE5AEFD3B62C99CC99863FB08DF548D44198BBF495C`.
EGI is rejected and no replica mapping is promoted.

### R54-K manual same-edge ZEROIZE locality

R54-K commit `22e6fac7587f2e9cc0671852b144660d21f2bc49` implements the
plan's final permitted manual pulse FF.  Boundary/public/FIFO logic remains on
`zeroize_pulse_o`; only `u_core.zeroize` uses `zeroize_core_pulse_o`.  Both
FDREs are written directly from the same accepted AXI control write and the
same `requested_control[2]` value.  There is no registered pulse-to-pulse
copy.  The full functional regression passes, but synth timing regresses to
`-0.226/-30.736/136`.  The synth and placed hashes are
`DAA6DB3E0AF5E15BA29AF970F7867001B899AC0E8CAAF42EA84D751ED405D908`
and `27D0D56E3131AF74E657DF81BECCBFB670EE7DCCCFB26746AC6322B89BBA4736`.

| Directive | WNS | TNS | FEP | WHS | THS | Routed DCP SHA-256 |
|---|---:|---:|---:|---:|---:|---|
| Explore | -0.632 | -108.082 | 570 | +0.051 | 0 | `7183F0DDEB432D1860F2C9622D5D8E6FA17B5D90A40850012B1452B8118741D6` |
| AggressiveExplore | -0.720 | -73.738 | 520 | +0.051 | 0 | `CBAE426F95C011877B660AA29AC680959097E0628748FEBEF5AC043908F0DF97` |
| MoreGlobalIterations | -0.528 | -128.195 | 668 | +0.050 | 0 | `793EDACACBDCDB2198126C91B80EE298BA5F467651A8FE77028C5F26725383EC` |
| HigherDelayCost | -0.587 | -106.487 | 757 | +0.050 | 0 | `0810DAC036417473214AC9B81D0C946C5D71911E2E57AF6210F7C54FF505660F` |

All four routes pass legality/security/hold gates and fail setup promotion.
The GK combination probe starts from the exact K placed hash and asks Vivado
to replicate `input_field_mode_r[2]`.  K changes its pre-force fanout from 37
to 25, and the same command now creates seven replicas.  The post-force
placed result immediately regresses from `+0.004/0/0` to
`-0.621/-2.564/8`; the topology gate expected the proven GI mapping and stops
the run before a checkpoint is written or routing begins.  The gate is not
relaxed because the timing evidence already rejects the topology.

The additional physical audits accept automatically created replicas only
when canonical/replica naming, primitive INIT, clock, every control pin,
D-driver primitive/INIT, fanin signature, and disjoint load mapping match.
This covers both the public-idle FDSE and each logical prep-tag bit and avoids
silently treating physical replication as a new RTL writer.

## Current Round54 promotion status

| Candidate | WNS | TNS | FEP | WHS | THS | Control sets | LUT | FF | Status |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| retained C | -0.523 | -26.673 | 273 | +0.051 | 0 | 309 | 8,586 | 7,296 | reference |
| G | -0.379 | -4.579 | 86 | +0.058 | 0 | 234 | 8,357 | 7,352 | superseded |
| I AggressiveExplore | -0.422 | -22.967 | 278 | +0.050 | 0 | 462 | 8,369 | 7,363 | FEP promotion fail |
| **GI AggressiveExplore** | **-0.146** | **-0.540** | **19** | **+0.050** | **0** | **462** | **8,370** | **7,364** | **best legal; setup open** |
| J best WNS | -0.353 | -56.148 | 449 | +0.057 | 0 | 462 | 8,370 | 7,364 | rejected |
| EGI | -0.422 | -38.597 | 287 | +0.050 | 0 | 466 | 8,380 | 7,374 | rejected |
| K best WNS | -0.528 | -128.195 | 668 | +0.050 | 0 | 368 | 8,440 | 7,373 | rejected |
| GK | not routed | not routed | not routed | transient -0.097 | transient -1.606 | not promoted | not promoted | not promoted | stopped after phys-opt |

GI is `0.146 ns` and 19 endpoints short of the 200 MHz internal setup goal.
Compared with retained C it removes 254 failing endpoints and 98.0% of the
TNS magnitude while preserving positive hold slack.  It is promoted as the
best available Round54 implementation, not as internal closure.  The final
47,250-vector NIST run remains gated on actual closure.  Internal PASS is
**NO** and PartPin is **NO** until an approved identity-matched production map
exists and passes strict replay.

Promotion was reverified from the final integration branch at commit
`839ebdede1473afd51a41c72261a34264d51f007`.  Audit-only reopened the exact
GI routed hash and again recomputed `-0.146/-0.540/19`, positive hold, all
13,583 routable nets complete, and every hard gate passing.  The final
non-D regression profile (`promotion_final_v2`) passed compile/elaboration,
smoke, throughput, Round48/49/53, repeated-ZEROIZE prep-tag clear, NIST525,
and NIST5255.  The R54-D-only FIFO testbench was excluded because it
intentionally instantiates D's rejected `CLEAR_HEAD_ON_CLEAR` parameter;
the retained FIFO clear/security regressions remain in the passing R53 set.

## 175 MHz timing experiment

The user-selected 175 MHz profile uses `5.714 ns`, which is slightly stricter
than the exact 175 MHz period of `5.714285... ns`.  It preserves the original
1 ns input/output boundary budgets and adds no false path, multicycle, clock
group, max/min delay, case analysis, or disabled-timing exception.

The exact promoted GI routed DCP
`2C10BCA0BAD8A8ED3407B2F3FF6FC0FFD378A9FDB6FF2ED65F0293150573433A`
was reopened, reset to the complete 175 MHz XDC, and audited without changing
placement or routing.  Internal timing closes at WNS `+0.568 ns`, TNS `0`,
FEP `0`, WHS `+0.050 ns`, THS `0`.  All 13,583 routable nets remain fully
routed; route errors, DRC Error/Critical Warning, critical check_timing
categories, CDC failures, latches, and multiple drivers are zero.  The full
Round53/Round54 security and replica-mapping hard gates pass.  The archived
175 MHz routed DCP SHA-256 is
`EC5C296177A30C3268A20B30A419A8ADC7B284EE49EC443CC0969ADA3165AA9B`.

This is a valid **175 MHz internal timing PASS**, not a 200 MHz closure and
not a fresh 175 MHz placement/route.  Reusing the already-routed 200 MHz DCP
is conservative for implementation and the clock was recomputed by Vivado,
not estimated from the former slack.

Vivado's unfiltered OOC timing summary still reports 1,143 input-boundary
hold failures (WHS `-1.101 ns`).  The reported examples are input ports such
as `s_axi_wdata`, `s_axis_tdata`, and `aresetn` into internal FDRE/RAMD32
pins, with zero source-clock delay in the standalone OOC model.  They are not
register-to-register paths and therefore do not contradict the explicitly
scoped internal closure result.  No exception is used to hide them; external
I/O hold closure remains an integration/production-clock and PartPin task.

The original overall promotion gate still requires every mode above
1 Gbit/s.  Cycle signatures are unchanged, but at 175 MHz the six measured
rates are approximately `0.947/0.936`, `0.918/0.908`, and `0.891/0.881`
Gbit/s.  Therefore timing passes while the original throughput gate fails.
The full 47,250-vector NIST run remains unnecessary until that remaining
system-level gate is resolved or the >1 Gbit/s requirement is explicitly
changed.

## Round55 175 MHz throughput closure

Round55-T commit `94aa57628bdadd42756c4be5c3426c05f55d6c48` resolves the
remaining 175 MHz throughput failure without increasing the clock.  A
two-entry sensitive data-block queue decouples byte admission from the first
keystream result.  Two dedicated one-round-per-clock AES engines service CTR
block indices 0 and 1; the existing registered-S-box engine retains H, tag
mask, and subsequent CTR work.  Ordered queue indices pair each data block
with the corresponding keystream FIFO head, so the change does not reorder
ciphertext, plaintext, GHASH, or final-length processing.

At the strict 175 MHz testbench clock, all six modes now exceed the original
1 Gbit/s gate:

| Mode | Encrypt cycles / Gbit/s | Decrypt cycles / Gbit/s |
|---|---:|---:|
| AES-128 | 16,820 / 1.065398 | 17,039 / 1.051705 |
| AES-192 | 16,820 / 1.065398 | 17,039 / 1.051705 |
| AES-256 | 16,820 / 1.065398 | 17,039 / 1.051705 |

This is a fresh synth/place/route using the baseline directives, not a
reclocked or reused lucky route.  The core SHA-256 is
`5503394198EA4662BC065D5BBE07040C693BEEEB417D1B88B8CCD04DBDED80CA`.
Checkpoint identities are:

| Stage | SHA-256 |
|---|---|
| synth | `7AEED1908BD6D8EDBBB0C51C82A9BEE0FF5865C2580A279090E329200498AF6F` |
| placed | `72ADBBFF762D1296235D0D6783B86877E88B23E4A251E9B24EA3BDF34498272A` |
| routed | `1A48461B9047E2967B9836E34B8809DF0CB2605508428F6DB2944F01B0DB9765` |

Routed internal timing closes at WNS `+0.056 ns`, TNS `0`, FEP `0`, WHS
`+0.053 ns`, and THS `0`.  All 16,327 routable nets are complete; route
errors, DRC Error/Critical Warning, critical check-timing categories, CDC
failures, latches, and multiple drivers are zero.  The candidate uses 11,600
LUTs, 8,410 FFs, 10 RAMB18s, and 227 control sets.  Compared with the prior
175 MHz source, this spends 3,230 additional LUTs and 1,046 additional FFs
to remove the first-block latency bottleneck; RAMB18 use remains unchanged.

The final non-D regression profile passes compile/elaboration, smoke at 7,676
cycles, Round48, Round49, every applicable Round53 ZEROIZE/stall/capacity
test, dedicated data-queue and fast-AES ZEROIZE clearing, NIST525 at 145,808
cycles, and NIST5255 at 1,594,798 cycles.  After internal closure, the full
six-file NIST run passes 47,250/47,250 with zero failures at 17,740,527
cycles.  The rejected R54-D-only FIFO specialization test remains explicitly
N/A; the retained abort, ZEROIZE, FIFO visibility, and queue-clear gates pass.

Round55-T therefore passes the 175 MHz internal timing and >1 Gbit/s
throughput gates.  It is not a 1 GHz clock implementation.  PartPin remains
**NO** until an approved production map matches this placed-DCP identity and
passes strict replay.
