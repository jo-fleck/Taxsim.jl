# Taxsim.jl modernization plan → v1.0.0

Status: **revision 2** — incorporates three independent reviews (TAXSIM protocol, Julia
engineering, feasibility audit). Every factual claim below was measured against the live
NBER endpoints or NBER's own `.ado`/`.hlp` sources; claims that survived review unchanged are
marked where useful. Revision history at the end.

Date: 2026-09-22
Target: update `Taxsim.jl` for current Julia/package versions and extend it to cover every
reachable NBER TAXSIM version since 32.

---

## 1. Findings: the state of NBER TAXSIM

Verified 2026-09-21/22 by submitting synthetic records to the live endpoints, and by reading
NBER's `taxsim35.ado`, `taxsim32.ado`, `taxsim33.ado`, `taxsim27.ado` and `taxsim35.hlp`.

### 1.1 Only two versions are reachable

| version | SSH account | files | usable? |
|---|---|---|---|
| v9  | none | `/stata/taxsim9.ado`; `/stata/taxsim9/` is 403; no web page | no |
| v27 | refused | `/stata/taxsim27/{.ado,.hlp}` | no — FTP-only transport, FTP compute is dead (§1.5) |
| v32 | `taxsimssh@` | flat `/stata/taxsim32.{ado,hlp,pkg}` + `taxsim32-{osx,unix,windows}.exe` | **yes** — SSH and HTTP |
| v33 | refused | `/stata/taxsim33.{ado,hlp,pkg}` **do exist** | no — its `.ado` ships to the *v32* server with `businc`/`profinc`, which that server rejects |
| v34 | refused | none | never released |
| v35 | `taxsim35@` | `/stata/taxsim35/` — `.ado`, `.hlp`, 6 binaries, `taxsimlocal35.*` | **yes** — SSH and HTTP |
| v36 | refused | none | does not exist yet |

Refused accounts (`taxsim9/27/30/31/32/33/34/36/taxsim@`) were tested with the *exact* flag
set that works for the live accounts, so these are true negatives — see the BatchMode trap in
§1.9.

Both live accounts are reachable on **both** hosts and **both** ports:

- hosts `taxsimssh.nber.org` (198.71.6.138) and `taxsim35.nber.org` (198.71.6.131) — two
  distinct machines, so the fallback is genuine redundancy, not a CNAME
- ports **22** and **443**
- all four combinations verified for each account, including `taxsimssh@taxsim35.nber.org`

`taxsim9/27/32/33/34/36/37/40.nber.org` and `taxsimssh2` are all NXDOMAIN.

**Conclusion:** "compatible with all TAXSIM versions since 32" is fully satisfied by {32, 35}.
v27 and v9 are not a Julia-side gap — there is no server behind them by any protocol.

### 1.2 v32 and v35 are DIFFERENT FROZEN BUILDS — not the same calculator

They share a FORTRAN lineage, but they are separately frozen binaries with different coded
tax law:

| | v32 | v35 |
|---|---|---|
| banner (`idtl=5`) | `NBER TAXSIM Model v32 (11/03/22)` | `NBER TAXSIM Model v35 (03/22/24) With TCJA` |
| state law coded through | **2020** | **2021** |

Measured divergence — married-joint, California (`state=5`), `pwages=200000`:

| year | v32 `fiitax` | v35 `fiitax` | v32 `siitax` | v35 `siitax` | v32/v35 `frate` | v32/v35 `srate` |
|---|---|---|---|---|---|---|
| 2019 | 30493.00 | 30493.00 | 11849.02 | 11849.02 | 24.00 / 24.00 | 9.30 / 9.30 |
| 2021 | 30018.00 | 30018.00 | 11456.70 | 11456.70 | 24.00 / 24.00 | 9.30 / 9.30 |
| 2022 | 29536.00 | 29536.00 | **3988.85** | **11234.35** | 22.00 / 22.00 | **6.00 / 9.30** |
| 2023 | **40776.03** | **28521.00** | 9785.60 | 10712.87 | **29.02 / 22.00** | 9.30 / 9.30 |

They agree through 2021 and then diverge badly: **$12,255 of federal tax for 2023** and a
3.3pp state rate error for 2022. **v32 gives materially wrong answers for 2022–2023.**

This is the single most important fact for a user of this package, and it determines the v32
policy in §3.

A third live build exists behind the HTTP v35 endpoint: `v35 (10/24/22)`, which returns
`ficar=12.26` where SSH v35 returns `11.21`. Three concurrent builds are in production.

**Separately, v32's 9-column writer truncates.** It prints `ficar=12.` where its own *full*
output prints `12.26`, and `3.` where v35 prints `2.90` — a Fortran format-width defect, i.e.
real precision loss, not a definitional difference. (v32 also writes `.00` where v35 writes
`0.00`, and v32 space-pads `taxsimid` to 30 chars in full output; CSV.jl parses both fine.)

`tfica` is a genuine addition, not a redefinition: the `idtl=5` text shows `FICA` and
`Taxpayer share of FICA` as separate concepts.

### 1.3 Input variables: v32 = 36 names, v35 = 45 (9 new)

Source of truth is `txpyvars` in each `.ado`, not the web page.

**v32 (36):** `taxsimid year state mstat page sage depx dep13 dep17 dep18 pwages swages
dividends intrec stcg ltcg otherprop nonprop pensions gssi ui transfers rentpaid proptax
otheritem childcare mortgage pbusinc sbusinc pprofinc sprofinc scorp sui pui dep6 dep19`

**v35 adds exactly 9:** `psemp ssemp age1 age2 age3 opt1 opt1v opt2 opt2v`

36 + 9 = 45, matching NBER's "45 input variables". v35 accepts every v32 name; v32 rejects
the 9 new ones with `TAXSIM: ERROR psemp is not a taxsim35 input variable.` / `STOP 901`.

Note `proptax`, `sui`, `pui`, `dep6`, `dep19` **are valid v32 inputs** — sending them to v32
produces a *semantic* range check (`TAXSIM: More children under 6 than under 13`), proving
they parsed. `opt1/opt1v/opt2/opt2v` are the web form's "optional tax plans, usually zeroes";
accepted by v35, no observed effect, semantics undocumented upstream — whitelist them without
pretending to document them.

`idtl` and `mtr` are control columns, not data, but they travel in the same CSV and must be
in the accepted-name set (§4 Phase 1).

### 1.4 Output layouts

| request | v32 | v35 |
|---|---|---|
| default (`idtl=0`) | 9 columns | **10** (`tfica` added) |
| full (`idtl=2`) | 45-column header, **46 fields per data row** | 48 columns, header and rows agree |

v35 full layout — extra *named* columns are **interleaved**, not appended:

```
1-9   taxsimid, year, state, fiitax, siitax, fica, frate, srate, ficar
10    tfica
11    credits      <- federal Total Credits (undocumented upstream)
12-43 v10 … v41
44    staxbc       <- state tax before credits (undocumented upstream)
45-48 v42 … v45
```

`credits` and `staxbc` are absent from NBER's web page and unlabelled in `taxsim35.ado`;
their meaning was pinned from the `idtl=15` text output, where they print immediately after
v28 ("Income Tax Before Credits") and v36 ("State Taxable Income") respectively. `staxbc` is
not reliably populated for older years (0.00 for 1980 with `state=1` while state tax after
credits was 1119.00).

Two measured quirks:

- **v32 full data rows carry a trailing comma** — 46 fields against a 45-field header.
  Reproduced with 1 and 2 rows, with `state` absent, `state=0` and `state=1`, over both SSH
  and HTTP. This is what creates the `Column46` bug (§2.2).
- **v35's full header is space-padded** in exactly two fields: `"   v21"` (field 23) and
  `"          v35"` (field 37).

**Neither server ever drops columns when `state=0`.** Both return their full width with
`state` absent, `state=0` and `state=1`. The v30–v41 drop in `taxsim32.jl:147` is a purely
**client-side convenience**, and it is wrong twice over: NBER's page says the "next **11**"
columns are zeroed, i.e. `v31:v41`, and `v30` (State Household Income) came back **populated**
at `100000.01` with no state — so the package silently discards real data.

### 1.5 Transports: SSH and HTTP work; FTP is dead

| transport | status |
|---|---|
| **SSH** | works — 2 hosts × 2 ports, both accounts (§1.1) |
| **HTTP** | **works** — `https://taxsim.nber.org/uptest/webfile.cgi` (v32) and `https://taxsim.nber.org/uptest/webfile.good.cgi` (v35), both HTTP 200 with real results. `curl -F txpydata=@file`. `www.nber.org/uptest/webfile.cgi` 301-redirects here. |
| **FTP** | **dead** — upload succeeds (`226`, file visible in `/tmp`), but `.txm32`/`.txm35`/`.msg` all return `550`, immediately and 10 minutes later. A foreign upload from Sep 19 sits in `/tmp` with a `.msg` containing only a timestamp and no result: the daemon starts and dies. `FTPClient.jl` is also stuck at 1.2.1 under the defunct `invenia` org. |

The `wwwdev.nber.org` host hardcoded in `taxsim35.ado` is unreachable (it CNAMEs to
`mail1dev.nber.org`) — testing only that URL is what produced the earlier false conclusion
that HTTP was retired.

HTTP caveats to document: the CGI prefixes the body with one blank line; `taxsim35.hlp` warns
http and ftp failed in testing above ~5,000 records; and the HTTP v35 endpoint is an **older
build** than SSH v35 (§1.2), so it is a fallback, not an equivalent.

### 1.6 The `mtr` control variable — 10 codes, per-record, both versions

| `mtr` | marginal rate with respect to |
|---|---|
| 85 | taxpayer earnings (**default**) |
| 86 | spouse earnings |
| 11 | wage income (weighted primary + secondary) |
| 12 | dividends |
| 14 | interest received |
| 17 | other income |
| 56 | mortgage interest |
| 66 | other deductions |
| 70 | long-term capital gains |
| 0 | "don't bother" — skips the marginal-rate pass entirely |

`taxsim35.ado` exposes only 85/86/11/14/70/56; the other four come from NBER's web form
(`name="mtr"` radios) and were verified live. Measured on a two-earner 2015 record: `17` →
`frate` 23.23, `12` → 15.00, `66` → 0.00, `0` → 0.00, and `14` correctly drives `ficar` to
zero (interest is not FICA-taxable).

Two facts the `.ado` does not reveal:

- **`mtr` works on the v32 endpoint too** (verified: `mtr=70` moves `frate` 25.00 → 15.00),
  even though `taxsim32.ado` has no such option.
- **`mtr` may vary per record.** Four rows with different `mtr` in one submission returned
  four different rates. This is unlike `idtl` (§1.7).

`mtr=0` is a free throughput win for large jobs: it skips the +$1 re-run TAXSIM otherwise
performs to compute a numerical derivative.

### 1.7 `idtl` — and a hard rule that fails silently

`0` standard, `2` full, `5` with text description; `+10` on the **last** record marks
end-of-file (`replace idtl=idtl+10 if _n==_N`). `idtl=15` returns the long text description on
both versions.

**`idtl` may not vary within a submission, and violating it produces no error.** Submitting
`idtl=0` then `idtl=12` returns a 9-column header, one 9-column row and one **46-column row**
on v32; the v35 equivalent returns a 10-column header with one 10- and one 48-column row.
This is a hard input rule and belongs in the validator, not in a footnote.

### 1.8 Coverage limits, and the state-code trap

- **Federal law: 1960–2023.** 1959, 2024 and 2025 all return
  `TAXSIM: Federal tax calculator available 1960 - 2023 only.` + `STOP 1` on both versions.
- **State law begins 1977.** NBER: "state must be zero if year is before 1977".
- **State law 2022+ is extrapolated** from 2021 at an assumed 2.5% inflation — for v35. For
  **v32 state coverage stops at 2020** (§1.2).
- **`state` uses IRS SOI codes, 1–51**, gapless alphabetical:
  `1 Alabama, 2 Alaska, 3 Arizona, 4 Arkansas, 5 California, …` (per
  `https://taxsim.nber.org/statesoi.html`).

  **This is not FIPS.** FIPS has gaps: `4 Arizona, 5 Arkansas, 6 California`. The two agree
  only for Alabama and Alaska, then diverge permanently. CPS/ACS/IPUMS ship **FIPS**, so a
  user passing state codes straight from an IPUMS extract gets **no error and silently wrong
  state taxes** — FIPS 6 (California) computes as SOI 6 (Colorado). This is the most likely
  silent-wrong-answer path in the package and is addressed in §4 Phase 3.

### 1.9 Transport mechanics that must not be "fixed" later

- **Do not add `-o BatchMode=yes` or `-o NumberOfPasswordPrompts=0`.** Both were measured to
  **break the working endpoints** (`Permission denied (publickey,keyboard-interactive)`), because
  NBER's anonymous accounts authenticate by keyboard-interactive with an empty response and
  each flag disables that path. Two of three reviewers independently recommended `BatchMode`;
  it is wrong here. Hang protection must therefore be an **external watchdog** that kills the
  process on timeout, not an SSH flag.
- **`-o StrictHostKeyChecking=accept-new` works** and should replace the current `=no`, which
  disables host-key verification outright on a channel carrying income microdata.
- `ConnectTimeout` covers only the handshake, not a stalled transfer.

### 1.10 Error-response shapes differ by version

- **v32** emits the **header line first**, then `TAXSIM:` lines, then `STOP` — so `CSV.read`
  yields a non-empty, non-zero-row garbage frame.
- **v35** emits **no header at all**, so the first `TAXSIM:` line becomes the header.

Two classes: **fatal** (`STOP 901` unknown variable, `STOP 1` bad year) and **non-fatal range
checks** (`TAXSIM: More children under 6 than under 13`) that still abort the record. The
rows-sent == rows-received assertion is the reliable backstop for both.

### 1.11 Local execution exists for both versions

Static binaries reading CSV on stdin: `/stata/taxsim35/taxsim35-{osx,unix,windows,bsd}.exe`
**and** `/stata/taxsim32-{osx,unix,windows}.exe`. Also `taxsim.wasm` at `/taxsim35/taxsim.wasm`
(1,030,455 B) and `/wasm/taxsim.wasm` (918,848 B).

---

## 2. Findings: what is broken in Taxsim.jl today

Verified by copying the repo to a scratch directory and running it on Julia 1.11.2.

### 2.1 The committed `Manifest.toml` makes the package un-instantiable

```
Precompiling Pkg...  ✗ LibGit2
ERROR: LoadError: ArgumentError: Package MbedTLS_jll [c8ffd9c3-...] is required
but does not seem to be installed
```

The failure is in precompiling **`Pkg`'s own dependencies**: the manifest has no
`manifest_format` key (v1.0 format, written under Julia ~1.5) and records stdlibs without
their JLL deps, while Julia ≥1.11 resolves stdlibs from the manifest. **No `[compat]` change
can fix this — deletion is the only fix.** After deletion, resolution succeeds cleanly
(CSV 0.10.17 / DataFrames 1.8.2).

Scope note: this blocks **contributors and CI**, not end users, who `Pkg.add` and resolve
fresh.

**`docs/Manifest.toml` is broken identically** and `docs/Project.toml` has **no `[compat]`
section at all**, pinning Documenter 0.26.2 (current: 1.19.0). The docs job fails the same way.

### 2.2 `full=true` returns a junk column

v32's trailing comma (§1.4) gives 46 fields against a 45-field header, so `CSV.read` invents
`Column46`, entirely `missing`:

```julia
names(taxsim32(df2, full=true))[end]   # "Column46"
```

Observed today: 34 columns where the suite asserts 33, 46 where it asserts 45.
**The test suite fails as of today.**

`silencewarnings=true` at line 124/133 is actively suppressing the CSV.jl warning that would
have surfaced this years ago.

### 2.3 `full=true, long_names=true` throws

45 labels applied to 46 columns: `DimensionMismatch: Length of nms doesn't match length of x.`

### 2.4 Other defects

| # | location | defect |
|---|---|---|
| a | `taxsim32.jl:82` | allowed-name list has `"rentpaid"` **twice** and is missing **five** valid v32 inputs — `proptax`, `sui`, `pui`, `dep6`, `dep19` (§1.3) |
| b | `taxsim32.jl:110-123` | `Sys.isapple()` and `Sys.iswindows()` branches are byte-identical |
| c | `taxsim32.jl:112-124` | failed SSH only `@error`s, then falls through into `CSV.read` on an empty buffer |
| d | `taxsim32.jl:94,147` | `sum(occursin.("taxsimid", names(df))) == 0` does **substring** matching — a column named `hh_taxsimid` silently suppresses ID generation and corrupts the join. Same bug for `"state"` at 147 |
| e | — | server errors (§1.10) are undetected; they produce a garbage frame. Row-count truncation is likewise invisible — the README already apologizes for it |
| f | `taxsim32.jl:86` | eltype whitelist. Note `Int === Int64`, so `Int64` was never rejected; the real bug is that **`Union{Missing,Int64}` columns with no missing values** pass the missing-scan and then fail the eltype check. Every column read from real survey data via CSV.jl/ReadStat is `Union{Missing,T}`, so a CPS/ACS frame with zero actual missings is rejected today with a nonsense message. `Int32` is also genuinely rejected |
| g | `taxsim32.jl:91` | `deepcopy` duplicates the entire input frame to append two columns |
| h | `taxsim32.jl:79` | `typeof(df_in) != DataFrame` rejects any other Tables.jl source |
| i | `taxsim32.jl:147` | `sum(occursin.("state", ...)) == 1` matches a column named `statex`, after which `df_in[1, :state]` throws `KeyError` |
| j | `taxsim32.jl:147` | the state-drop decision reads **row 1 only**, so a frame mixing `state=0` and `state=1` silently loses 12 columns for every row |
| k | — | server returns `taxsimid` as `Float64` (`1.`), so users passing integer person-IDs hit a type mismatch on `leftjoin` |
| l | docstring | shows DataFrames 0.22-era `│ Row │` rendering and `taxsimid = 0.0`, which the server no longer returns (it returns `1.`) |
| m | `ci.yml` | `doctest(Taxsim)` runs **zero** doctests — the docstring block is fenced ` ```julia-repl `, not ` ```jldoctest `. It is a no-op, not a failure |

What still works: the v32 SSH transport, and `taxsim32(df)` default output.

---

## 3. Decisions

| # | decision | status |
|---|---|---|
| D1 | **`taxsim32` and `taxsim35` as two thin functions** over one shared core. Per-version data stays data, so a future v36 is one entry plus one wrapper. | confirmed |
| D2 | **SSH default with automatic HTTP fallback.** SSH across 2 hosts × 2 ports; on total failure, fall back to HTTPS **with a warning when the fallback fires** — never silent, because the HTTP v35 endpoint is an older build (§1.2, §1.5). FTP path and the `FTPClient.jl` dependency removed, replaced by an informative error. No local-executable support in 1.0. | confirmed |
| D3 | **Offline fixture tests by default; live tests opt-in**, plus a scheduled canary. | confirmed |
| D4 | **v1.0.0**, registration gated on explicit go-ahead. Semver covers the Julia API, **not** the set of columns NBER returns — stated in the CHANGELOG. | confirmed |
| D5 | **`taxsim32` warns once for `year >= 2022`**, naming the divergence and pointing at `taxsim35`. v32 is a **frozen-vintage replication shim**, not a supported calculator (§1.2). | confirmed |
| D6 | **The v30–v41 state-column drop is deleted.** Results always carry what the server sent. This is a documented breaking output change: `full=true` on a no-state frame gains 12 zero-filled columns, and populated `v30` stops being discarded. | confirmed |
| D7 | **Single release — no interim 0.4.0.** Phase A reaches a green baseline, the refactor and v35 land on top, the live suite runs green against both endpoints, then 1.0.0 is tagged once. | confirmed |
| D8 | **Feature branch off `master`, one commit per phase, `PLAN.md` tracked** in the repo as the design record. Nothing pushed or merged without explicit go-ahead. | confirmed |

D5 is the reframing that matters: v32 is kept so that work published on the v32 endpoint stays
reproducible for a referee report — not because "its columns differ".

"v35 becomes the default" means **the documented recommendation only**. `taxsim32` stays bound
to the v32 endpoint; its numbers must not change.

---

## 4. Plan

**Sequencing principle (from review):** the suite is red *today* (§2.2). Rewriting one
150-line file into four modules while the only oracle is a red suite makes "my refactor broke
it" indistinguishable from "it was already broken". So: **fix, get green, then refactor.**

Order: Phase 0 → Phase A (fixes on the existing file) → green → Phase 1 (refactor) →
Phase 2 → Phase 3 → Phase 4 → CI matrix → Phase 5 → Phase 6.

### Phase 0 — Unbreak the environment — **DONE** (`17e3558`)


| item | action |
|---|---|
| manifests | delete **both** `Manifest.toml` and `docs/Manifest.toml`; add both to `.gitignore` |
| `Project.toml` | drop `FTPClient`; add `Tables = "1"`; **`CSV = "0.10, 1"`** (CSV 1.0.0 and 1.1.0 exist — `"0.10"` alone pins a superseded series); **`DataFrames = "1"`** (current 1.8.2; the two-entry form buys nothing and goes stale on 1.9); `julia = "1.10"` |
| `docs/Project.toml` | add `[compat] Documenter = "1"` |

`julia = "1.10"` is forced, not chosen: DataFrames ≥1.8 declares `julia = "1.10.0 - 1"`, so a
lower floor is incompatible with current DataFrames. (1.10.12 is the LTS; 1.13.0 is stable.)

Before widening CSV to 1.x, re-verify `CSV.write(IOBuffer(), df)` returns a seekable buffer
and that `CSV.read(io; delim, stripwhitespace, silencewarnings)` keeps its signature.

### Phase A — Bug fixes on the existing file, to a green baseline — **DONE** (`4ccae94`, `3570f9b`)

46 offline tests pass in ~3 s; 62 with `TAXSIM_LIVE_TESTS=true`. Verified from a clean
clone with no local `Manifest.toml`.

Three deviations from the plan as written, all deliberate:

1. **`Tables` is not yet a dependency.** Phase 0 listed it, but nothing uses it until
   Phase 3, and an unused dependency is exactly what Aqua flags. It lands with its use.
2. **Response normalization replaced the CSV-kwarg approach.** `CSV.read(...;
   stripwhitespace=true, silencewarnings=true)` is not portable across the declared compat
   range: CSV 1.0 **removed `silencewarnings`**, and CSV 1.x **ignores** a trailing extra
   field with a warning where 0.10 **invents an all-missing column**. Depending on either
   behaviour would make the package's output a function of which CSV version resolved. The
   raw response is therefore normalized before parsing, which is version-independent and
   fully testable offline.
3. **Fixtures landed here rather than in Phase 4**, because a green *offline* run needs
   them. Phase 4's remaining work is the 2022/2023 divergence pair, the sidecar metadata
   files, the scheduled canary workflow and `record_fixtures.jl`.

One defect found during implementation that was not in §2: TAXSIM **exits non-zero when it
rejects input**, so treating a non-zero exit as a transport failure reported `year=2025` as
"cannot reach the TAXSIM server" and retried the rejected payload against three more
endpoints. The transport now inspects stdout before classifying the failure.

Superseded by D6: plan item 6 ("state-drop condition: test all rows, not row 1") became a
deletion of the drop entirely.


No new architecture. Just make it correct and green offline:

1. Trailing-column removal and long-name alignment (§2.2, §2.3).
2. Corrected input-name set (§2.4a) — adds the five missing v32 names.
3. eltype check (§2.4f).
4. `throw` instead of `@error`-then-parse-empty (§2.4c); collapse the duplicate OS branches.
5. Exact `in` for `taxsimid` and `state` (§2.4d, §2.4i).
6. State-drop condition: test all rows, not row 1 (§2.4j).
7. Server-error scan and `nrow(out) == nrow(in)` assertion (§2.4e, §1.10).
8. Drop `silencewarnings=true`.
9. Tests: delete the FTP testsets, derive counts from constants, gate network tests.

### Phase 1 — Refactor (NOT a version-parameterized framework) — **DONE** (`Phase 1+2`)


Review consensus, twice over: **`TaxsimSpec` with quirk flags is over-engineering, and the
generic approach is also more robust.** §1.4 is the argument against it — v35 *interleaves*
`tfica` at 10 and `staxbc` at 44, so any positional per-version layout is one server-side
insertion away from silently mislabelling everything downstream, which is §2.3 rebuilt with
more ceremony. NBER rebuilds these binaries without version bumps (three live builds, §1.2),
so a `trailing_comma = true` flag is a bet on the quirk persisting.

Instead:

- **`src/transport.jl`** — SSH across 2 hosts × 2 ports, first success wins; HTTP fallback
  with a warning (D2); `accept-new` host checking; `Sys.which("ssh") === nothing` → clear
  error; a `timeout` kwarg backed by an external watchdog (§1.9). Capture stderr separately
  from stdout. Make the transport an **injectable seam** so tests can assert payload bytes
  offline — awkward to retrofit, so design it in now.
- **`src/validate.jl`** — corrected name sets (§1.3) including `idtl`/`mtr`; eltype check
  `nonmissingtype(eltype(col)) <: Union{Integer,AbstractFloat} && !(… <: Bool)` — note
  `<: Real` alone is **too loose**, since `Rational` serializes as `1//3` and `Bool` as
  `true`, both rejected by the server; report **all** offending columns at once with row
  indices; enforce `idtl` homogeneity (§1.7); pre-flight `year` ∈ 1960:2023 and
  `year < 1977 ⟹ state == 0` (§1.8); `state` ∈ 0:51.
- **`src/output.jl`** — width-tolerant parsing, no quirk flags:
  - `CSV.read(...; stripwhitespace=true)` handles the padded headers — no hand-written
    `strip` pass needed
  - drop a column only if it matches `^Column\d+$` **and** its eltype is `Missing` **and**
    the count is exactly n+1; otherwise **throw** with both counts. Blind positional slicing
    would silently delete real data after the next rebuild
  - long names from a **`Dict` name→label**, applied with a filtered `rename!`. This makes
    `DimensionMismatch` structurally impossible, collapses the 32/35 label lists into one
    dict, and degrades unknown columns gracefully to the server's own names
- Per-version data that genuinely remains: the SSH account name and the valid-input-name set.
  Two `const` NamedTuples, not a struct with a quirk-flag protocol.
- **Delete the state-column drop** (D6). It is a client-side invention (§1.4), it is lossy
  (`v30` is populated), and it is the source of §2.4i and §2.4j. There is no
  `drop_state_columns` kwarg — results always carry what the server sent.

### Phase 2 — Public API — **DONE**

86 offline tests, 102 with `TAXSIM_LIVE_TESTS=true`. `src/taxsim32.jl` is replaced by
`errors.jl`, `versions.jl`, `validate.jl`, `transport.jl`, `output.jl` and `api.jl`.

One measured correction to §1.6: **`mtr = 0` does not skip the marginal-rate pass.**
Submitted on its own it returns exactly what omitting `mtr` returns. The "straight
throughput win" attributed to it in review does not hold, and the docs say so rather than
repeating the claim. The other nine margins are confirmed, including per-record vectors.


```julia
taxsim35(df; full=false, long_names=false, mtr=:taxpayer, timeout=…, checks=true, connection=:ssh)
taxsim32(df; full=false, long_names=false, mtr=:taxpayer, timeout=…, checks=true, connection=:ssh)
```

- **`mtr`** accepts a symbol, an integer, or a **vector** (it is per-record, §1.6), covering
  all 10 codes including `:none` → 0. When `mtr === :taxpayer`, **emit no `mtr` column at
  all**, so the default submission stays byte-identical to today's and is validated by the
  existing known-good results rather than by a new untested path.
- **`connection` accepts both `String` and `Symbol`**, normalized via `lowercase`, with
  `Base.depwarn` on the string form (respects `--depwarn`; removal in 2.0). A Symbol-only
  keyword would break the currently *documented* `connection="SSH"` — and my own earlier draft
  contradicted itself by promising `taxsim32` kept its exact signature two bullets later.
- `connection=:ftp` / `"FTP"` throws the informative retirement error.
- **Error hierarchy**, so a loop over survey years can retry transport failures without
  swallowing input errors:
  ```julia
  abstract type TaxsimError <: Exception end
  struct TaxsimInputError     <: TaxsimError … end
  struct TaxsimTransportError <: TaxsimError … end
  struct TaxsimServerError    <: TaxsimError … end   # carries the server's own text
  ```
  with `Base.showerror` methods. Note the existing suite asserts exact `ErrorException`
  message strings (`test/runtests.jl:15-19`) — those break by design.
- `taxsim32` is **source-compatible for documented usage**; output changes (no more
  `Column46`, state columns retained, `long_names` now working) are listed in the CHANGELOG.
  Do not claim "no change".
- Row order guaranteed to match input — by sorting on `taxsimid` and asserting, not by
  trusting the server.
- Return `taxsimid` in the input's type (§2.4k).

### Phase 3 — Robustness, correctness, efficiency

1. **Zero-copy payload.** Replace `deepcopy` + two `insertcols!` with a `NamedTuple` that
   *shares* the original column vectors:
   ```julia
   nt = (; taxsimid = ids, (Symbol(n) => df[!, n] for n in names(df))..., idtl = idtl_vec)
   ```
   Measured in review: **0 bytes** allocated, byte-identical CSV output, 0.057 s vs 0.400 s.
   Keep `ids` as a lazy `1:n`.

   This corrects a wrong premise in revision 1. On 1M rows the copy path I targeted allocates
   61 MB while **`CSV.write` allocates 783 MB** — I was aiming at 7% of the traffic. Hand-
   rolling a serializer was also the wrong fix: it would still materialize the whole payload.
2. **Stream into `ssh` stdin** rather than buffering: `open(pipeline(cmd, stdout=io), "w")`,
   `CSV.write(p, nt)`, `close(p.in)`, `wait(p)`. Verified in review: payload never
   materialized.
3. **State the real memory wall in the README.** 46M rows of full v35 output is 48 `Float64`
   columns ≈ **17.7 GB** in the returned frame. The *response*, not the request, is the limit,
   and neither streaming nor chunking the request touches it. Designing the request path for
   46M records while the response path OOMs at 5M is not coherent — either ship
   `output=path` streaming to CSV/Arrow (deferred, §5) or say plainly that in-memory
   operation is bounded by response size.
4. **SOI vs FIPS guard (§1.8).** A documented `state` note, a `state ∈ 0:51` range check, and
   an optional `fips_to_taxsim` helper. This is the most likely silent-wrong-answer path in
   the package.
5. **Provenance.** A `taxsim_server_version()` accessor returning the `idtl=5` banner, and the
   banner attached to results as column-set metadata (`metadata!(…, style=:note)`, available
   in DataFrames ≥1.4). A replication package that cannot record which of three live builds
   produced its numbers is not reproducible.
6. **`missing` policy.** `missing_action = :error | :zero` (TAXSIM treats absent inputs as
   zero anyway, so `:zero` is honest), always reporting offending column **and** row indices.
7. Accept any **Tables.jl** source (free — already a transitive dep three times over).
   `Tables.columns` + `Tables.columnnames` + `Tables.getcolumn` supply everything validation
   needs. Replace `isempty` with `Tables.rowcount` and guard with `Tables.istable`. Note
   row-oriented sources reintroduce a copy (`Tables.columnaccess == false`) — document or
   branch on it.
8. `fill(2, n)` over `2*ones(Int64, n)`; `pairs(eachcol(df))` over positional indexing.

### Phase 4 — Tests

- **Offline, default, deterministic.** Fixtures stored as **raw server bytes** — including
  the trailing comma and the `"   v21"` padding — never as parsed frames, which would have
  hidden §2.2 and §2.3 entirely. Each fixture gets a sidecar recording
  `{version, idtl, mtr, rows_sent, recorded_at, server_banner}`; the banner is the best
  staleness indicator available.
- **Fixture matrix:** v32 and v35 × default and full × `state` absent / `state=0` /
  `state=1` — **plus a `year=2022` and `year=2023` with-state pair from both endpoints**, so
  the §1.2 law divergence is pinned by the suite rather than discovered in a referee report.
- **Assert the payload, not just the response.** The `idtl`/`+10`-on-last-row logic is the
  highest-risk code in the package and is fully testable offline through the Phase 1
  transport seam.
- **Live tests** opt-in via `ENV["TAXSIM_LIVE_TESTS"]`, exercising both endpoints and the
  transport fallback.
- **Canary on a schedule, not opt-in.** An env-gated test nobody sets is a test that does not
  exist. A weekly `cron` workflow re-records into a temp dir and `diff`s against the committed
  fixtures, opening an issue on drift — kept out of the PR matrix, since GitHub runners
  reaching NBER over SSH will be flaky and would train everyone to ignore red CI. Ship
  `julia --project=test test/record_fixtures.jl` so re-recording is mechanical.
- Assert header **names and positions**, since layout drift is the unrecoverable regression.
- Add **Aqua.jl** (`Aqua = "0.8"`): it catches stale/undeclared deps — exactly how
  `FTPClient` would have been flagged — plus missing `[compat]` entries, which are an
  AutoMerge prerequisite, turning a registration rejection into a local test failure.
  **Skip JET.jl**: I/O-bound glue with no hot loops, version-sensitive against Julia
  internals, near-zero signal.

### Phase 5 — CI and documentation

**CI** — every action version in revision 1 was at least one major behind:

| | revision 1 said | current |
|---|---|---|
| `actions/checkout` | v4 | **v7.0.1** |
| `julia-actions/setup-julia` | v2 | **v3.0.2** |
| `julia-actions/cache` | v2 | **v3.3.0** |
| `codecov/codecov-action` | v5 | **v7.1.1** |

Two changes that would otherwise ship red jobs:

- **drop the `arch: x64` axis** — setup-julia v3 errors on x64 requests on aarch64 macOS
  runners, and `macos-latest` is Apple Silicon
- **`files: lcov.info`**, not `file:` (dead input since v4), plus
  `token: ${{ secrets.CODECOV_TOKEN }}`, required since v4 even for public repos — needs the
  secret added, or coverage silently never uploads

Use setup-julia's version aliases `lts`, `1`, `nightly`, and **`min`** (resolves the declared
compat floor — the only thing that actually proves `julia = "1.10"` is honest). `nightly` on
ubuntu only, `continue-on-error`. Add `permissions:`, `concurrency:`,
`julia-actions/julia-docdeploy@v1` in place of the hand-rolled `run:` steps, and
**`.github/dependabot.yml` for `github-actions`** — that is the structural fix for being three
majors behind, without which this review recurs.

**Keep `doctest(Taxsim)`** and give it something real. Revision 1's reason for dropping it was
a misdiagnosis (§2.4m): it currently runs zero doctests. After Phase 1, the pure offline
functions — validation messages, header stripping, trailing-column removal, dict rename over a
fixture — are ideal `jldoctest` blocks. Network-dependent end-to-end examples stay plain
` ```julia `.

**Docs/README:**

- rewrite for both versions; delete the "Scheduled Updates" section (`mtr` and HTTP both ship
  in 1.0) and the "supports the latest TAXSIM version 32" claim
- the **§1.2 divergence table** and the D5 policy
- coverage limits (§1.8): federal 1960–2023, state from 1977, 2022+ extrapolated at 2.5%,
  v32 state stopping at 2020
- the **SOI-vs-FIPS warning** (§1.8)
- a **restricted-data warning**: the transport is an unauthenticated channel carrying
  individual-level income microdata; check your DUA before pointing this at restricted-use
  extracts. One paragraph, highest value per character in the whole plan
- **survey weights**: TAXSIM has no weight input, so weights must be applied after merging —
  three lines and a worked example
- an **error table** mapping common `TAXSIM: …` strings to the input fix
- a note on polite submission sizes (NBER is a free academic service)
- `docs/make.jl`: `repo = Remotes.GitHub("jo-fleck", "Taxsim.jl")` (the `{commit}{path}` form
  is deprecated in Documenter 1.x)
- badges: switch to `actions/workflows/ci.yml/badge.svg`; keep the codecov badge on `master`
  (the default branch is `master`, not `main`); uncomment the two docs badges once green

### Phase 6 — Release

`v1.0.0` + CHANGELOG with (a) the migration notes, (b) the semver-scope sentence from D4.

Registration mechanics, verified against the General README and RegistryCI AutoMerge
guidelines:

- comment `@JuliaRegistrator register` on the release commit in `jo-fleck/Taxsim.jl` — **check
  the JuliaRegistrator app is still installed**, the last release was 2021
- no prerelease/build metadata (`1.0.0-rc1` cannot be registered); `0.3.1 → 1.0.0` is valid
- every non-JLL dep needs an **upper-bounded** `[compat]`, `julia` included — the Phase 0
  bounds satisfy this
- breaking releases must supply release notes explaining the break, in the Registrator comment
- 15-minute merge delay for an existing package
- AutoMerge runs `Pkg.add` + `import Taxsim` **without network access** — so never add an
  `__init__` that probes the server
- confirm `TagBot.yml` still works after five years

**Run the live suite green against both endpoints before tagging.** Going from a red suite to
1.0.0 in one hop would ship a default path (HTTP fallback, streaming transport, `mtr`) that
never touched the live server.

---

## 5. Deferred

- **`connection=:local`** wrapping NBER's static binaries — promoted from "maybe" to a **1.1
  target**. It solves timeouts, truncation, firewalls, throughput *and* reproducibility (a
  checksummed binary is a pinnable version) at once, and matters most for confidential
  microdata where shipping records to an external server is contractually prohibited.
  Binaries exist for **both** v32 and v35 (§1.11). Blockers: user-side download, per-platform
  path, checksum verification.
- **`output=path`** streaming the response to CSV/Arrow — the actual fix for large-N (§4.3).
- **Chunked submission** — deferred; all three reviews flagged it. Mechanically the `+10`
  marker is per-submission so chunks are arithmetically fine, but: response width is a
  function of the submitted data, so chunking a frame mixing `state=0` and `state=1` yields
  chunks of different widths and the `vcat` fails; auto-generated IDs must be sliced from a
  global vector, never regenerated per chunk; "one timeout does not lose the job" requires
  retry/resume/idempotency that was never specified; and N sequential handshakes to a research
  institution's server is plausible rate-limit territory with no backoff.
- **`taxsim.wasm`** — cut. No good Julia WASM host story.
- **`public` keyword** — cut. Introduced in Julia 1.11, a parse error on the 1.10 floor.
- **`PrecompileTools` `@compile_workload`** for the offline parse path — optional, minor.

---

## 6. Items requiring the maintainer's GitHub access

These cannot be done from this session and are listed against the phase that needs them.

| when | item |
|---|---|
| Phase 5 (CI) | Add the **`CODECOV_TOKEN`** repository secret. Required since codecov-action v4 even for public repos; without it coverage silently never uploads and the README badge stays stale. |
| Phase 5 (docs) | Confirm **`DOCUMENTER_KEY`** is still valid, or regenerate it. It was set up before 2021 and the docs deploy job depends on it. |
| Phase 6 | Confirm the **JuliaRegistrator GitHub App** is still installed on `jo-fleck/Taxsim.jl`. The last release was 2021, so it may have been removed. |
| Phase 6 | Trigger registration by commenting `@JuliaRegistrator register` with release notes on the release commit. Deliberately gated on explicit go-ahead (D4). |
| any time | Push the feature branch / open the PR (D8). |

---

## Revision history

**Revision 2** (2026-09-22) — after three independent reviews. Material corrections to
revision 1:

1. **HTTP is alive** (§1.5). Revision 1 tested only `wwwdev.nber.org`, the stale host in
   NBER's `.ado`, and wrongly concluded the transport was retired. This changed decision D2.
2. **v32 and v35 are different frozen builds** (§1.2), not "the same calculator" — revision 1
   rested on a single 1980 record. v32 is materially wrong for 2022–2023. This changed the
   rationale for keeping `taxsim32` and added D5.
3. **5 of 14 claimed v35-only inputs are valid v32 inputs** (§1.3), resolving revision 1's
   own contradiction between §1.3 and §2.4a in favour of §2.4a.
4. **`mtr` has 10 codes, varies per record, and works on v32** (§1.6) — revision 1 listed 6,
   scalar, v35-only.
5. **`TaxsimSpec` + quirk flags dropped** for width-tolerant generic parsing (Phase 1) — two
   reviewers converged on this independently.
6. **Phase 3's performance premise was wrong** — `CSV.write` dominates allocation, not the
   `deepcopy`; the fix is a zero-copy `NamedTuple` plus streaming, not a custom serializer.
7. **All four GitHub Action versions and the CSV bound were stale** (Phase 0, Phase 5) — the
   local registry copy was a July 2025 snapshot.
8. **Sequencing inverted** — fixes to a green baseline before the refactor.
9. **`BatchMode=yes`/`NumberOfPasswordPrompts=0` must not be used** (§1.9) — recommended by
   two reviewers, measured to break the working endpoints.
10. Added: SOI-vs-FIPS trap (§1.8), `idtl` homogeneity rule (§1.7), per-version error shapes
    (§1.10), `credits`/`staxbc` meanings (§1.4), state law from 1977, provenance accessor,
    `missing_action`, error hierarchy, Aqua, dependabot, restricted-data and weights docs,
    and defects §2.4i–m.

**Revision 3** (2026-09-22) — decisions D1, D6, D7 and D8 confirmed by the maintainer. The
state-column drop is now removed outright rather than optionally retained, and §6 records the
items that need the maintainer's GitHub access.

**Revision 4** (2026-09-22) — Phases 1 and 2 implemented. `mtr = 0` corrected (§1.6): it
is not a skip. Added beyond the plan: `fips_to_taxsim` and an SOI range check (§1.8),
local year/state coverage pre-flight, `taxsim_server_version`, DataFrame provenance metadata,
and the typed error hierarchy.
