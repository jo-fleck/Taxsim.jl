_mtr_code(x::Symbol) = get(MTR_CODES, x) do
    throw(TaxsimInputError("Unknown mtr $(repr(x)). Valid margins: " *
                           join(sort(string.(collect(keys(MTR_CODES)))), ", ")))
end
_mtr_code(x::Integer) = Int(x) in values(MTR_CODES) ? Int(x) :
    throw(TaxsimInputError("Unknown mtr code $x. Valid codes: " *
                           join(sort(collect(values(MTR_CODES))), ", ")))

function _mtr_column(mtr, n::Int)
    mtr === DEFAULT_MTR && return nothing        # keep the default submission byte-identical
    if mtr isa AbstractVector
        length(mtr) == n || throw(TaxsimInputError(
            "`mtr` has $(length(mtr)) entries but the input has $n rows"))
        return _mtr_code.(mtr)
    end
    return fill(_mtr_code(mtr), n)
end

"""
    _payload(df_in, v, full, mtr) -> IOBuffer

Build the CSV submitted to the server: adds `taxsimid` if absent, optionally an `mtr` column,
and `idtl` with `+10` on the final record to mark end-of-file.
"""
function _payload(df_in, v::TaxsimVersion, full::Bool, mtr)
    df = deepcopy(df_in)
    n = nrow(df)

    "idtl" in names(df) && throw(TaxsimInputError(
        "Do not supply an `idtl` column; use the `full` keyword. TAXSIM requires one detail " *
        "level per submission and silently returns ragged output when it varies."))

    # Exact match, not `occursin`: a substring test meant a column named e.g. `hh_taxsimid`
    # silently suppressed id generation and corrupted the caller's join.
    "taxsimid" in names(df) || insertcols!(df, 1, :taxsimid => 1:n)

    mcol = _mtr_column(mtr, n)
    if mcol !== nothing
        "mtr" in names(df) && throw(TaxsimInputError(
            "Both an `mtr` column and a non-default `mtr` keyword were given; use one or the other."))
        insertcols!(df, ncol(df) + 1, :mtr => mcol)
    end

    idtl = fill(full ? 2 : 0, n)
    idtl[end] += 10
    insertcols!(df, ncol(df) + 1, :idtl => idtl)

    return CSV.write(IOBuffer(), df)
end

_conn_check(c::Symbol) =
    c === :ftp ? throw(TaxsimTransportError(
        "The FTP connection has been removed. NBER's FTP server still accepts uploads but no " *
        "longer returns any results, and FTPClient.jl is unmaintained. Use :ssh or :http.")) :
    c in (:ssh, :ssh_only, :http) ? c :
    throw(ArgumentError("Unknown connection $(repr(c)); use :ssh, :ssh_only or :http"))

_normalize_connection(c::Symbol) = _conn_check(c)
function _normalize_connection(c::AbstractString)
    Base.depwarn("connection = \"$c\" is deprecated; pass connection = :$(lowercase(c)) instead. " *
                 "String values will be removed in a future breaking release.", :taxsim)
    return _conn_check(Symbol(lowercase(c)))
end

function _taxsim(df_in, v::TaxsimVersion; full = false, long_names = false, mtr = DEFAULT_MTR,
                 checks = true, connection = :ssh, timeout = DEFAULT_TIMEOUT,
                 _transport = _submit)

    conn = _normalize_connection(connection)
    checks && _check_input(df_in, v)

    raw = _transport(v, _payload(df_in, v, full, mtr); connection = conn, timeout = timeout)
    df_res = CSV.read(IOBuffer(_normalize(raw)), DataFrame; delim = ',')

    nrow(df_res) == nrow(df_in) || throw(TaxsimServerError(
        "Sent $(nrow(df_in)) records but TAXSIM returned $(nrow(df_res)). The response was " *
        "truncated; do not use these results."))

    _restore_taxsimid!(df_res, df_in)
    long_names && _apply_long_names!(df_res)

    # Provenance: which calculator produced these numbers. NBER runs several builds
    # concurrently and rebuilds without version bumps, so a replication package needs this.
    metadata!(df_res, "taxsim_version", v.number; style = :note)
    metadata!(df_res, "taxsim_connection", String(conn); style = :note)

    return df_res
end

const _KWDOC = """
#### Keyword Arguments

- `full`: request the full set of TAXSIM return variables. Defaults to `false`.
- `long_names`: label the return variables with their long TAXSIM names. Defaults to `false`.
- `mtr`: the margin the returned marginal tax rates are computed with respect to. One of
  `:taxpayer` (default), `:secondary`, `:wages`, `:dividends`, `:interest`, `:other_income`,
  `:mortgage`, `:deductions`, `:ltcg` or `:none`. May also be a vector, one entry per row,
  since TAXSIM accepts `mtr` per record. Note `:none` (NBER's "Don't bother" code 0) was
  measured to return the same rates as the default rather than skipping the calculation, so
  do not rely on it to speed up large jobs.
- `connection`: `:ssh` (default) tries both NBER hosts on ports 22 and 443 and falls back to
  HTTP with a warning if all fail; `:ssh_only` disables that fallback; `:http` posts to NBER's
  CGI endpoint, which needs no `ssh` binary but is reported to fail above ~5,000 records.
- `timeout`: seconds before the transfer is abandoned. Defaults to $(DEFAULT_TIMEOUT).
- `checks`: validate the input before submitting. Defaults to `true`.

#### Output

A `DataFrame` of the requested TAXSIM return variables, in the same row order as the input, so
`hcat(df, out, makeunique=true)` merges input and output. The TAXSIM version and transport used
are attached as DataFrame metadata.
"""

"""
    taxsim35(df; kwargs...)

Compute federal and state income tax liabilities with [TAXSIM
35](https://taxsim.nber.org/taxsim35/), NBER's current release.

`df` must be a `DataFrame` with at least one row, whose columns are named exactly as in NBER's
TAXSIM 35 variable list (45 names; order does not matter). Unsupplied variables are treated as
zero by the server. `missing` values are rejected, naming the offending rows.

!!! warning "state uses SOI codes, not FIPS"
    TAXSIM numbers states 1 Alabama, 2 Alaska, 3 Arizona, 4 Arkansas, 5 California, … CPS, ACS
    and IPUMS ship FIPS codes, which diverge from Arizona onward. Passing FIPS produces no
    error and the wrong state's tax — convert with [`fips_to_taxsim`](@ref).

Federal law is coded for 1960–2023 and state law from 1977, with 2022 onward extrapolated from
2021 at an assumed 2.5% inflation.

$(_KWDOC)

# Examples
```julia
using DataFrames, Taxsim

df = DataFrame(year = 1980, mstat = 2, ltcg = 100_000)
taxsim35(df)

# marginal rate with respect to the secondary earner, full detail
taxsim35(df, full = true, mtr = :secondary)
```
"""
taxsim35(df; kwargs...) = _taxsim(df, TAXSIM35; kwargs...)

"""
    taxsim32(df; kwargs...)

Compute federal and state income tax liabilities with [TAXSIM
32](https://taxsim.nber.org/taxsim32/).

!!! warning "TAXSIM 32 is a frozen 2022 build"
    The hosted TAXSIM 32 calculator is dated 11/03/22 and its state tax law is coded only
    through 2020. It diverges materially from TAXSIM 35 for 2022 and 2023 — on one test record
    (married joint, California, \$200,000 of wages) 2023 federal tax differs by over \$12,000
    and the 2022 state marginal rate by 3.3 points.

    `taxsim32` exists so that work published against this endpoint stays reproducible. For new
    work use [`taxsim35`](@ref).

Accepts the 36 TAXSIM 32 input variables. Otherwise identical to [`taxsim35`](@ref).

$(_KWDOC)
"""
function taxsim32(df; kwargs...)
    _warn_stale_v32(df)
    return _taxsim(df, TAXSIM32; kwargs...)
end

function _warn_stale_v32(df)
    (df isa DataFrame && "year" in names(df)) || return nothing
    yrs = skipmissing(df[!, "year"])
    any(>=(2022), yrs) && @warn(
        "TAXSIM 32 is a frozen 11/03/22 build with state law coded only through 2020, and it " *
        "returns materially different results from TAXSIM 35 for 2022 onward. Use taxsim35 " *
        "unless you are reproducing earlier results.", maxlog = 1)
    return nothing
end

"""
    taxsim_server_version(version = 35; connection = :ssh, timeout = 60) -> String

Ask the server which build it is running, e.g.
`"NBER TAXSIM Model v35 (03/22/24) With TCJA"`.

NBER runs several builds concurrently and rebuilds them without changing the version number, so
a replication package should record this alongside its results.
"""
function taxsim_server_version(version::Integer = 35; connection = :ssh, timeout = 60)
    v = version == 32 ? TAXSIM32 :
        version == 35 ? TAXSIM35 :
        throw(ArgumentError("Only TAXSIM 32 and 35 are reachable; got $version"))

    probe = DataFrame(taxsimid = [1], year = [2020], mstat = [1], idtl = [15])
    raw = _submit(v, CSV.write(IOBuffer(), probe);
                  connection = _normalize_connection(connection), timeout = timeout)
    for line in split(raw, '\n')
        occursin("NBER TAXSIM Model", line) && return String(strip(line))
    end
    throw(TaxsimServerError("Could not find a version banner in the server's response"))
end
