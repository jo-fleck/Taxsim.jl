
[![Build Status](https://github.com/jo-fleck/Taxsim.jl/workflows/CI/badge.svg)](https://github.com/jo-fleck/Taxsim.jl/actions)
[![Coverage](https://codecov.io/gh/jo-fleck/Taxsim.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/jo-fleck/Taxsim.jl)

<!-- [![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://jo-fleck.github.io/Taxsim.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://jo-fleck.github.io/Taxsim.jl/dev) -->


# Taxsim.jl

[TAXSIM](https://taxsim.nber.org) is a program of the National Bureau of Economic Research (NBER) which calculates liabilities under US federal and state income tax laws. It can be accessed by uploading tax filer information to the NBER's TAXSIM server. The program then computes a number of variables (income taxes, tax credits, etc.) and returns them.

`Taxsim.jl` exchanges data between the Julia workspace and the server. Its function `taxsim32` supports the latest [TAXSIM version 32](https://taxsim.nber.org/taxsim32/). Future versions will be included.

#### Acknowledgments

Daniel Feenberg develops and maintains TAXSIM. He and his collaborators provide [helpful materials](http://users.nber.org/~taxsim/) including codes to prepare input files from household datasets (CPS, SCF, PSID).

Reach out to Daniel with questions on TAXSIM and follow his request on citation (see bottom of this [webpage](https://taxsim.nber.org/taxsim32/)).

### Installation and Instructions

`Taxsim.jl` can be installed via Julia's package manager using one of two options:

- REPL: `] add Taxsim`
- Pkg functions: `using Pkg; Pkg.add("Taxsim")`

Before using `taxsim32`, please make yourself familiar with [Internet TAXSIM 32](https://taxsim.nber.org/taxsim32/). Submit a few individual observations and upload an entire csv file.

#### Syntax

`taxsim32(df; kwargs...)`

- `df` has to be a DataFrame object with at least one observation.
    - Included columns have to be named exactly as in the Internet TAXSIM 32 variable list (bold names after boxes) but can be in any order. `taxsim32` returns typos and case errors.
    - Non-provided input variables are set to zero by the TAXSIM server but `" "` (blanks as strings) or `missing` lead to non-response as the server only accepts Integers or Floats. `taxsim32` returns type errors.

#### Keyword Arguments

- `connection`: choose either `"FTP"` or `"SSH"`. `"FTP"` uses the [FTPClient Package](https://github.com/invenia/FTPClient.jl) while `"SSH"` issues a system curl command. Defaults to `"FTP"` (which is faster).
- `full`: request the full list of TAXSIM return variables v1 to v41. Defaults to `false` which returns v1 to v9.
- `long_names`: name all return variables with their long TAXSIM names. Defaults to `false` which returns abbreviated names for v1 to v9 and no names for v10 to v41.

#### Output

- Data frame with requested TAXSIM return variables. Column types are either Integer or Float.
- If `df` does not include `state` or if `state = 0`, the data frame returned by a `full` request does not include v30 to v41.
- Observations are ordered as in `df` so `hcat(df, df_output, makeunique=true)` merges all variables of the input and output data frames.

### Examples

````
using DataFrames, Taxsim

df_small_input = DataFrame(year=1980, mstat=2, ltcg=100000)
1×3 DataFrame
│ Row │ year  │ mstat │ ltcg   │
│     │ Int64 │ Int64 │ Int64  │
├─────┼───────┼───────┼────────┤
│ 1   │ 1980  │ 2     │ 100000 │

df_small_output_default = taxsim32(df_small_input)
1×9 DataFrame
│ Row │ taxsimid │ year  │ state │ fiitax  │ siitax  │ fica    │ frate   │ srate   │ ficar   │
│     │ Float64  │ Int64 │ Int64 │ Float64 │ Float64 │ Float64 │ Float64 │ Float64 │ Float64 │
├─────┼──────────┼───────┼───────┼─────────┼─────────┼─────────┼─────────┼─────────┼─────────┤
│ 1   │ 0.0      │ 1980  │ 0     │ 10920.0 │ 0.0     │ 0.0     │ 20.0    │ 0.0     │ 12.0    │

df_small_output_full = taxsim32(df_small_input, connection = "SSH", full=true)
1×29 DataFrame
│ Row │ taxsimid │ year  │ state │ fiitax  │ siitax  │ fica    │ frate   │ srate   │ ficar   │ v10     │ v11     │ ... | v25     │
│     │ Float64  │ Int64 │ Int64 │ Float64 │ Float64 │ Float64 │ Float64 │ Float64 │ Float64 │ Float64 │ Float64 │ ... │ Float64 │
├─────┼──────────┼───────┼───────┼─────────┼─────────┼─────────┼─────────┼─────────┼─────────┼─────────┼─────────┼─────┼─────────┼
│ 1   │ 0.0      │ 1980  │ 0     │ 10920.0 │ 0.0     │ 0.0     │ 20.0    │ 0.0     │ 12.26   │ 40000.0 │ 0.0     │ ... | 0.0     │

df_small_output_names = taxsim32(df_small_input, long_names=true)
1×9 DataFrame
│ Row │ Case ID │ Year  │ State │ Federal income tax liability including capital gains rates, surtaxes, AMT and refundable and non-refundable credits │ ... │ federal marginal rate │
│     │ Float64 │ Int64 │ Int64 │ Float64                                                                                                             │ ... │ Float64               │
├─────┼─────────┼───────┼───────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┼─────────────────────────────┼─
│ 1   │ 0.0     │ 1980  │ 0     │ 10920.0                                                                                                             │ ...  │ 20.0                 │

N = 10000
df_small_stateN = DataFrame(year=repeat([1980],inner=N), mstat=repeat([2],inner=N), ltcg=repeat([100000],inner=N), state=repeat([1],inner=N))
df_small_stateN_out = taxsim32(df_small_stateN)
10000×9 DataFrame
   Row │ taxsimid  year   state  fiitax   siitax   fica     frate    srate    ficar   
       │ Float64   Int64  Int64  Float64  Float64  Float64  Float64  Float64  Float64
───────┼──────────────────────────────────────────────────────────────────────────────
     1 │      1.0   1980      1  10920.0   1119.0      0.0     20.0      4.0     12.0
     2 │      2.0   1980      1  10920.0   1119.0      0.0     20.0      4.0     12.0
     3 │      3.0   1980      1  10920.0   1119.0      0.0     20.0      4.0     12.0
     4 │      4.0   1980      1  10920.0   1119.0      0.0     20.0      4.0     12.0
   ⋮   │    ⋮        ⋮      ⋮       ⋮        ⋮        ⋮        ⋮        ⋮        ⋮
  9998 │   9998.0   1980      1  10920.0   1119.0      0.0     20.0      4.0     12.0
  9999 │   9999.0   1980      1  10920.0   1119.0      0.0     20.0      4.0     12.0
 10000 │  10000.0   1980      1  10920.0   1119.0      0.0     20.0      4.0     12.0
````

### Troubleshooting

Expect three different kinds of errors

1. **Input Error** Adjust `df` so it meets the required column types and names.
2. **Connection Error** Indicates that `taxsim32` cannot connect to the TAXSIM server. Try a different connection option. If this does not help, check your internet and network settings and contact your network administrator - you're probably behind a restrictive firewall.
3. **Server Error** Forwarded from the TAXSIM server. Either a faulty `df` passed the input tests or TAXSIM cannot compute the tax variables for some other reason (which the error message hopefully helps to identify).

Please file an issue if you experience problems with large input data frames (server non-response, truncated return data frames, etc).

### Scheduled Updates

- For `request = full` the TAXSIM server currently returns more variables than listed as TAXSIM 32 outputs. At the moment, `taxsim32` only keeps returned variables until v41 (State Bracket Rate). I will clarify with Dan Feenberg and adjust this behavior.
- `taxsim32` currently returns marginal tax rates computed with respect to taxpayer earnings. Marginal rates for "Wage Income", "Spouse Earning", etc. will be included as keyword options in future versions.
- HTTP connection will be included as another connection option in future versions.
