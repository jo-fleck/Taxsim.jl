# Recorded TAXSIM server responses

Raw bytes exactly as the NBER server returned them — **not** parsed frames. The quirks these
fixtures exist to pin (TAXSIM 32's trailing comma on full-detail rows, TAXSIM 35's
space-padded header names) are invisible once parsed, so storing frames would defeat the
purpose.

Recorded 2026-09-22 over SSH to `taxsimssh.nber.org`.

The last two pin the finding that TAXSIM 32 and 35 are different frozen builds: they agree on
2022 federal tax and disagree on California state tax (`siitax` 3988.85 vs 11234.35, `srate`
6.00 vs 9.30). If that stops being true, one of the two server builds changed.

| file | account | submission | server layout |
|---|---|---|---|
| `v32_default_nostate.csv` | `taxsimssh` | `idtl=10` | 9 header / 9 row |
| `v32_full_nostate.csv` | `taxsimssh` | `idtl=12` | 45 header / **46** row |
| `v32_full_state.csv` | `taxsimssh` | `idtl=12`, `state=1` | 45 header / **46** row |
| `v32_full_2rows.csv` | `taxsimssh` | `idtl=2,12` | 45 header / **46** row |
| `v35_full_state.csv` | `taxsim35` | `idtl=12`, `state=1` | 48 header / 48 row, `"   v21"` and `"          v35"` padded |
| `v35_default_nostate.csv` | `taxsim35` | `idtl=10` | 10 header / 10 row, incl. `tfica` |
| `v35_full_nostate.csv` | `taxsim35` | `idtl=12` | 48 header / 48 row — v35 returns v30–v41 even with no state |
| `v32_2022_ca.csv` | `taxsimssh` | `year=2022`, `state=5`, `pwages=200000` | pins the v32/v35 divergence |
| `v35_2022_ca.csv` | `taxsim35` | same submission | same, for comparison |
| `v32_error_badyear.csv` | `taxsimssh` | `year=2025` | header, then `TAXSIM:` lines — note v32 emits its header *before* the error |

Server builds at time of recording: TAXSIM 32 = `11/03/22` (state law through 2020),
TAXSIM 35 = `03/22/24` (state law through 2021). Both are frozen builds and NBER rebuilds
without version bumps, so if these fixtures ever stop matching the live server, that is a
real change to investigate, not a test to relax.

Re-record with `TAXSIM_LIVE_TESTS=true` and the commands in this file's git history.
