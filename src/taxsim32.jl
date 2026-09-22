
# TAXSIM 32 input variables, taken from `txpyvars` in NBER's taxsim32.ado (the web page's
# list is incomplete). `idtl` and `mtr` are control columns rather than data, but they travel
# in the same CSV, so a user may legitimately supply them.
const TAXSIM32_VARS = [
    "taxsimid", "year", "state", "mstat", "page", "sage",
    "depx", "dep6", "dep13", "dep17", "dep18", "dep19",
    "pwages", "swages", "dividends", "intrec", "stcg", "ltcg", "otherprop", "nonprop",
    "pensions", "gssi", "ui", "pui", "sui", "transfers",
    "rentpaid", "proptax", "otheritem", "childcare", "mortgage",
    "scorp", "pbusinc", "pprofinc", "sbusinc", "sprofinc",
    "idtl", "mtr",
]

# Long labels keyed by the column name the server actually returns, so renaming can never
# misalign with the returned width (the previous positional list threw DimensionMismatch
# whenever the server's column count changed).
const TAXSIM32_LABELS = Dict{String,String}(
    "taxsimid" => "Case ID",
    "year"     => "Year",
    "state"    => "State",
    "fiitax"   => "Federal income tax liability including capital gains rates, surtaxes, AMT and refundable and non-refundable credits",
    "siitax"   => "State income tax liability",
    "fica"     => "FICA (OADSI and HI, sum of employee AND employer)",
    "frate"    => "federal marginal rate",
    "srate"    => "state marginal rate",
    "ficar"    => "FICA rate",
    "v10" => "Federal AGI",
    "v11" => "UI in AGI",
    "v12" => "Social Security in AGI",
    "v13" => "Zero Bracket Amount",
    "v14" => "Personal Exemptions",
    "v15" => "Exemption Phaseout",
    "v16" => "Deduction Phaseout",
    "v17" => "Deductions Allowed (Zero for non-itemizers)",
    "v18" => "Federal Taxable Income",
    "v19" => "Tax on Taxable Income (no special capital gains rates)",
    "v20" => "Exemption Surtax",
    "v21" => "General Tax Credit",
    "v22" => "Child Tax Credit (as adjusted)",
    "v23" => "Additional Child Tax Credit (refundable)",
    "v24" => "Child Care Credit",
    "v25" => "Earned Income Credit (total federal)",
    "v26" => "Income for the Alternative Minimum Tax",
    "v27" => "AMT Liability after credit for regular tax and other allowed credits",
    "v28" => "Federal Income Tax Before Credits (includes special treatment of Capital gains, exemption surtax (1988-1996) and 15% rate phaseout (1988-1990) but not AMT)",
    "v29" => "FICA",
    "v30" => "State Household Income (imputation for property tax credit)",
    "v31" => "State Rent Expense (imputation for property tax credit)",
    "v32" => "State AGI",
    "v33" => "State Exemption amount",
    "v34" => "State Standard Deduction",
    "v35" => "State Itemized Deductions",
    "v36" => "State Taxable Income",
    "v37" => "State Property Tax Credit",
    "v38" => "State Child Care Credit",
    "v39" => "State EIC",
    "v40" => "State Total Credits",
    "v41" => "State Bracket Rate",
    "v42" => "Earned Self-Employment Income for FICA",
    "v43" => "Medicare Tax on Unearned Income",
    "v44" => "Medicare Tax on Earned Income",
    "v45" => "CARES act Recovery Rebates",
)

# Number of columns the v32 server returns, used to derive test expectations rather than
# hardcoding magic numbers.
const TAXSIM32_NCOL_DEFAULT = 9
const TAXSIM32_NCOL_FULL = 45

const _SSH_HOSTS = ("taxsimssh.nber.org", "taxsim35.nber.org")
const _SSH_PORTS = (22, 443)

"""
    _check_input(df)

Validate `df` against what the TAXSIM 32 server accepts. Reports every offending column at
once rather than throwing on the first one.
"""
function _check_input(df)
    df isa DataFrame || error("Input must be a data frame")
    isempty(df) && error("Input data frame is empty")

    for (name, col) in pairs(eachcol(df))
        var = String(name)
        var in TAXSIM32_VARS ||
            error("Input contains \"" * var * "\" which is not an allowed TAXSIM 32 variable name")

        bad = findall(ismissing, col)
        isempty(bad) ||
            error("Input contains \"" * var * "\" with missing(s) which TAXSIM does not accept" *
                  " (row(s) " * join(first(bad, 5), ", ") * (length(bad) > 5 ? ", …" : "") * ")")

        # `Union{Missing,T}` is what every column read from real survey data looks like, so the
        # eltype test has to see through Missing. Bool and Rational are Real but do not
        # serialize to anything TAXSIM accepts, so they are excluded deliberately.
        T = nonmissingtype(eltype(col))
        (T <: Union{Integer,AbstractFloat} && !(T <: Bool)) ||
            error("Input contains \"" * var * "\" which is a neiter an Integer nor a Float variable as required by TAXSIM")
    end
    return nothing
end

"""
    _payload(df_in, full) -> IOBuffer

Build the CSV submitted to the server: adds `taxsimid` if absent and sets `idtl`, with `+10`
on the final record to mark end-of-file.
"""
function _payload(df_in, full::Bool)
    df = deepcopy(df_in)
    n = nrow(df)

    # Exact match, not `occursin`: the previous substring test meant a column named e.g.
    # `hh_taxsimid` silently suppressed ID generation and corrupted the caller's join.
    "taxsimid" in names(df) || insertcols!(df, 1, :taxsimid => 1:n)

    idtl = fill(full ? 2 : 0, n)
    idtl[end] += 10
    insertcols!(df, ncol(df) + 1, :idtl => idtl; makeunique = false)

    return CSV.write(IOBuffer(), df)
end

"""
    _ssh(payload) -> String

Submit `payload` over SSH, trying each host and port until one answers. Throws on failure
rather than returning an empty buffer for the caller to misparse.
"""
function _ssh(payload)
    Sys.which("ssh") === nothing &&
        error("Cannot find an `ssh` executable on PATH, which taxsim32 requires. " *
              "On Windows, enable OpenSSH under Apps > Optional Features.")

    failures = String[]
    for port in _SSH_PORTS, host in _SSH_HOSTS
        out, err = IOBuffer(), IOBuffer()
        # NOTE: do not add `-o BatchMode=yes` or `-o NumberOfPasswordPrompts=0` here. The NBER
        # account authenticates by keyboard-interactive with an empty response, and either
        # option disables that path and breaks the connection outright.
        cmd = `ssh -p $port -T -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new taxsimssh@$host`
        thrown = nothing
        try
            run(pipeline(cmd, stdin = seekstart(payload), stdout = out, stderr = err))
        catch e
            thrown = e
        end
        res = String(take!(out))

        # TAXSIM exits non-zero when it rejects the input (STOP 901 on an unknown variable,
        # STOP 1 on an out-of-range year), so a thrown process error is not by itself a
        # transport failure. If the server said something, hand it to `_normalize` to report
        # rather than retrying the same rejected payload against three more endpoints.
        _looks_like_server_message(res) && return res
        isempty(strip(res)) || return res

        detail = thrown === nothing ? "returned an empty response" :
                 "failed (" * first(replace(strip(String(take!(err))), '\n' => "; "), 200) * ")"
        push!(failures, "$host:$port " * detail)
    end
    error("Cannot reach the TAXSIM server over SSH. Tried:\n  " * join(failures, "\n  ") *
          "\nCheck your internet connection and firewall settings.")
end

_looks_like_server_message(s::AbstractString) =
    occursin("TAXSIM:", s) || occursin(r"^\s*STOP\b"m, s)

"""
    _normalize(raw) -> String

Turn a raw server response into well-formed CSV, and surface server-side errors.

Handles two measured quirks without hardcoding either as a per-version flag: TAXSIM 32's full
output appends a trailing comma to every data row (46 fields against a 45-field header), and
TAXSIM pads some header names with spaces. A width mismatch of any other shape is an error,
so a future change in the server's layout cannot silently drop real data.
"""
function _normalize(raw::AbstractString)
    txt = replace(raw, "\r\n" => "\n", "\r" => "\n")
    lines = [l for l in split(txt, '\n') if !isempty(strip(l))]
    isempty(lines) && error("TAXSIM returned an empty response")

    # v32 emits the header first and then its error lines; v35 emits no header at all. Scanning
    # the raw text catches both before parsing turns them into a garbage frame.
    errs = filter(l -> occursin("TAXSIM:", l) || occursin(r"^\s*STOP\b", l), lines)
    isempty(errs) || error("TAXSIM server error:\n  " * join(strip.(errs), "\n  "))

    header = strip.(split(lines[1], ','))
    data = lines[2:end]
    isempty(data) && error("TAXSIM returned a header but no results")

    nh = length(header)
    widths = [count(==(','), l) + 1 for l in data]

    if all(==(nh), widths)
        # nothing to do
    elseif all(==(nh + 1), widths) && all(l -> endswith(rstrip(l), ","), data)
        data = [chop(rstrip(l)) for l in data]   # drop exactly one trailing delimiter
    else
        error("TAXSIM returned $nh header fields but data rows with " *
              join(sort(unique(widths)), ", ") * " fields. Refusing to guess which columns " *
              "these are; please report this with the input that produced it.")
    end

    return join(header, ',') * "\n" * join(data, "\n") * "\n"
end

"""
    _apply_long_names!(df)

Rename by column name, not by position, so unknown columns keep the server's own name instead
of throwing or shifting every label after them.
"""
function _apply_long_names!(df)
    pairs_ = [n => TAXSIM32_LABELS[n] for n in names(df) if haskey(TAXSIM32_LABELS, n)]
    isempty(pairs_) || rename!(df, pairs_)
    return df
end

"""
Before using `taxsim32`, please make yourself familiar with [Internet TAXSIM 32](https://taxsim.nber.org/taxsim32/).

!!! warning "TAXSIM 32 is a frozen 2022 build"
    The hosted TAXSIM 32 calculator is dated 11/03/22 and its state tax law is coded only
    through 2020. It returns materially different results from TAXSIM 35 for 2022 and 2023 —
    on one test record, 2023 federal tax differs by over \$12,000. `taxsim32` is retained so
    that published work computed against this endpoint stays reproducible; it is not a
    supported calculator for recent tax years.

#### Syntax

`taxsim32(df; kwargs...)`

- `df` has to be a DataFrame object with at least one observation.
    - Included columns have to be named exactly as in NBER's TAXSIM 32 variable list but can
      be in any order. `taxsim32` reports typos and case errors.
    - Non-provided input variables are set to zero by the TAXSIM server. `missing` values are
      rejected, with the offending rows named.

#### Keyword Arguments

- `connection`: currently only `"SSH"`. Passing `"FTP"` raises an explanatory error: NBER's
  FTP compute service accepts uploads but no longer returns results.
- `full`: request the full list of TAXSIM return variables. Defaults to `false`, which
  returns the nine standard columns.
- `long_names`: name the return variables with their long TAXSIM names. Defaults to `false`.

#### Output

- Data frame with the requested TAXSIM return variables, in the same row order as `df`, so
  `hcat(df, df_output, makeunique=true)` merges input and output.
- A `full` request always returns every column the server sent. Earlier versions of this
  package dropped v30–v41 when no state was given; that was a client-side convenience which
  discarded a populated `v30`, and it has been removed.
"""
function taxsim32(df_in; connection = "SSH", full = false, long_names = false, checks = true)

    conn = lowercase(String(connection))
    conn == "ftp" && error(
        "The FTP connection has been removed. NBER's FTP server still accepts uploads but no " *
        "longer returns results (the compute daemon is gone), and FTPClient.jl is unmaintained. " *
        "Use the default connection = \"SSH\".")
    conn == "ssh" || error("Unknown connection \"$connection\"; the only supported value is \"SSH\"")

    checks && _check_input(df_in)

    raw = _ssh(_payload(df_in, full))
    df_res = CSV.read(IOBuffer(_normalize(raw)), DataFrame; delim = ',')

    nrow(df_res) == nrow(df_in) || error(
        "Sent $(nrow(df_in)) records but TAXSIM returned $(nrow(df_res)). The response was " *
        "truncated; do not use these results.")

    long_names && _apply_long_names!(df_res)

    return df_res
end
