[![Build Status](https://github.com/jo-fleck/Taxsim.jl/workflows/CI/badge.svg)](https://github.com/jo-fleck/Taxsim.jl/actions)
[![Coverage](https://codecov.io/gh/jo-fleck/Taxsim.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/jo-fleck/Taxsim.jl)

<!-- [![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://jo-fleck.github.io/Taxsim.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://jo-fleck.github.io/Taxsim.jl/dev) -->


# Taxsim.jl

[TAXSIM](https://taxsim.nber.org) is a program of the National Bureau of Economic Research (NBER) which calculates liabilities under US federal and state income tax laws. It can be accessed by uploading tax filer information to the NBER's TAXSIM server. The program then computes a number of variables (income taxes, tax credits, etc.) and returns them.

`Taxsim.jl` exchanges data between the Julia workspace and the server. It provides `taxsim35` for [TAXSIM 35](https://taxsim.nber.org/taxsim35/), NBER's current release, and `taxsim32` for [TAXSIM 32](https://taxsim.nber.org/taxsim32/).

#### Video Tutorial

Here is a [short video tutorial](https://www.youtube.com/watch?v=dc3iunpMA1o) I gave at JuliaCon2021. It illustrates how to use `Taxsim.jl` with Census and American Community Survey data (downloaded from [IPUMS](https://www.ipums.org)). Note it predates `taxsim35`, and see the state-code warning below.

#### Acknowledgments

Daniel Feenberg develops and maintains TAXSIM. He and his collaborators provide [helpful materials](http://users.nber.org/~taxsim/) including codes to prepare input files from household datasets (CPS, SCF, PSID).

Reach out to Daniel with questions on TAXSIM and follow his request on citation (see bottom of the TAXSIM webpage).

### Installation

- REPL: `] add Taxsim`
- Pkg functions: `using Pkg; Pkg.add("Taxsim")`

### Syntax

```julia
taxsim35(df; full=false, long_names=false, mtr=:taxpayer, connection=:ssh, timeout=600, checks=true)
taxsim32(df; ...)   # same keywords
```

`df` must be a `DataFrame` with at least one row. Columns have to be named exactly as in NBER's variable list (45 names for TAXSIM 35, 36 for TAXSIM 32) but may be in any order. Variables you do not supply are treated as zero by the server. `missing` values are rejected, naming the offending rows.

#### Keyword Arguments

| keyword | meaning |
|---|---|
| `full` | request the full set of return variables (48 columns for v35, 45 for v32) instead of the standard 10 (v35) or 9 (v32) |
| `long_names` | label the returned columns with their long TAXSIM names |
| `mtr` | which margin the marginal tax rates refer to — see below |
| `connection` | `:ssh` (default, with automatic HTTP fallback), `:ssh_only`, or `:http` |
| `timeout` | seconds before a transfer is abandoned |
| `checks` | validate the input before submitting |

#### Marginal tax rates

`mtr` selects the margin with respect to which `frate`, `srate` and `ficar` are computed. It may also be a vector with one entry per row, since TAXSIM accepts this per record.

| value | margin |
|---|---|
| `:taxpayer` | taxpayer earnings (default) |
| `:secondary` | spouse earnings |
| `:wages` | weighted primary and secondary wages |
| `:dividends` | dividend income |
| `:interest` | interest received |
| `:other_income` | other income |
| `:mortgage` | mortgage interest |
| `:deductions` | other deductions |
| `:ltcg` | long term capital gains |
| `:none` | NBER's "Don't bother" code 0 |

`:none` was measured to return the same rates as the default rather than skipping the calculation — do not rely on it to speed up large jobs.

#### Output

A `DataFrame` of the requested return variables, in the same row order as the input, so `hcat(df, out, makeunique=true)` merges input and output. The TAXSIM version and transport used are attached as DataFrame metadata.

A `full` request always returns every column the server sent. Versions before 1.0 dropped v30–v41 when no state was given; that was a client-side convenience which used the wrong range and discarded a populated `v30`, and it has been removed.

### ⚠️ `state` uses SOI codes, not FIPS

TAXSIM numbers states with IRS SOI codes, which are gapless and alphabetical:

```
1 Alabama   2 Alaska   3 Arizona   4 Arkansas   5 California   ...   51 Wyoming
```

FIPS codes — which CPS, ACS and IPUMS all ship — have gaps: `4 Arizona, 5 Arkansas, 6 California`. The two agree only for Alabama and Alaska and then diverge permanently. **Passing FIPS codes straight into `state` produces no error and the wrong state's tax** (FIPS 6, California, computes as SOI 6, Colorado).

```julia
df.state = fips_to_taxsim(df.statefip)
```

### ⚠️ TAXSIM 32 is a frozen 2022 build

The hosted TAXSIM 32 calculator is dated 11/03/22 and its state tax law is coded only through 2020. It diverges materially from TAXSIM 35 for recent years. Married joint, California, $200,000 of wages:

| year | v32 `fiitax` | v35 `fiitax` | v32 `siitax` | v35 `siitax` |
|---|---|---|---|---|
| 2019 | 30493.00 | 30493.00 | 11849.02 | 11849.02 |
| 2021 | 30018.00 | 30018.00 | 11456.70 | 11456.70 |
| 2022 | 29536.00 | 29536.00 | **3988.85** | **11234.35** |
| 2023 | **40776.03** | **28521.00** | 9785.60 | 10712.87 |

`taxsim32` exists so that work published against this endpoint stays reproducible. **For new work use `taxsim35`**, which warns if you call `taxsim32` with a year of 2022 or later.

### Coverage

- Federal law: **1960–2023**. Later years are rejected by the server.
- State law: from **1977** (`state` must be 0 for earlier years). Coded through 2021 for v35 and 2020 for v32; later years are extrapolated from the last coded year at an assumed 2.5% inflation.

`taxsim_server_version()` returns the exact build string, e.g. `NBER TAXSIM Model v35 (03/22/24) With TCJA`. NBER runs several builds concurrently and rebuilds them without changing the version number, so record this alongside published results.

### Survey weights

TAXSIM has no weight input and returns unweighted, per-return results. Apply your survey weights after merging:

```julia
out = taxsim35(df)
mean_tax = sum(out.fiitax .* df.wtsupp) / sum(df.wtsupp)
```

### Confidential data

The transport sends individual-level income records to an external server over a channel that does not verify NBER's host key beyond first use. **Check your data use agreement before submitting restricted-use microdata.** NBER also distributes standalone executables that run the same calculator locally; support for those is planned.

### Examples

```julia
using DataFrames, Taxsim

df = DataFrame(year = 1980, mstat = 2, ltcg = 100_000)

taxsim35(df)
# 1×10 DataFrame
#  Row │ taxsimid  year   state  fiitax   siitax   fica     frate    srate    ficar    tfica
#      │ Int64     Int64  Int64  Float64  Float64  Float64  Float64  Float64  Float64  Float64
# ─────┼───────────────────────────────────────────────────────────────────────────────────────
#    1 │        1   1980      0  10920.0      0.0      0.0     20.0      0.0    11.21      0.0

taxsim35(df, full = true)                    # 48 columns
taxsim35(df, long_names = true)              # descriptive column names
taxsim35(df, mtr = :secondary)               # rates w.r.t. the spouse's earnings
taxsim35(df, connection = :http)             # no ssh binary required

N = 10_000
big = DataFrame(year = fill(1980, N), mstat = fill(2, N), ltcg = fill(100_000, N), state = fill(1, N))
taxsim35(big)
```

### Troubleshooting

Errors are typed, so a loop over survey years can retry transport failures without swallowing input errors:

| error | meaning |
|---|---|
| `TaxsimInputError` | the data frame is not acceptable — wrong column name, a `missing`, a non-numeric column, an out-of-range year or state. Names every offending column at once. Not worth retrying. |
| `TaxsimTransportError` | the server could not be reached. Names every host and port tried. Worth retrying. |
| `TaxsimServerError` | TAXSIM rejected the submission, carrying the server's own message (e.g. `Non-joint return with 2 wage-earners`). Not worth retrying unchanged. |

```julia
try
    taxsim35(df)
catch e
    e isa TaxsimTransportError ? retry_later() : rethrow()
end
```

By default `:ssh` tries both NBER hosts on ports 22 and 443, then falls back to HTTP with a warning. Pass `connection = :ssh_only` to disable the fallback — NBER's HTTP endpoint for TAXSIM 35 is an older build than the SSH one and can return slightly different values. The FTP connection has been removed: NBER's FTP server still accepts uploads but no longer returns any results.

### Roadmap

See [PLAN.md](PLAN.md). Next up: local execution against NBER's standalone binaries, and streaming output for datasets too large to hold in memory.
