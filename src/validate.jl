"""
    _check_input(x, v::TaxsimVersion; missing_action = :error)

Validate `x` against what the given TAXSIM version accepts, reporting every offending column at
once rather than throwing on the first. Accepts any Tables.jl source, not only a `DataFrame`.
"""
function _check_input(x, v::TaxsimVersion; missing_action::Symbol = :error)
    Tables.istable(x) || throw(TaxsimInputError(
        "Input must be a table such as a DataFrame, but got $(typeof(x))"))

    cols = Tables.columns(x)
    Tables.rowcount(cols) == 0 && throw(TaxsimInputError("Input table is empty"))

    allowed = vcat(v.inputs, CONTROL_VARS)
    problems = String[]

    for name in Tables.columnnames(cols)
        var = String(name)
        col = Tables.getcolumn(cols, name)

        if !(var in allowed)
            push!(problems, "\"$var\" is not an allowed TAXSIM $(v.number) variable name" *
                            _did_you_mean(var, allowed))
            continue
        end

        if missing_action === :error
            bad = findall(ismissing, col)
            if !isempty(bad)
                shown = join(first(bad, 5), ", ") * (length(bad) > 5 ? ", …" : "")
                push!(problems, "\"$var\" has missing value(s) in row(s) $shown. TAXSIM does " *
                                "not accept them; pass missing_action = :zero to send zeros " *
                                "instead, which is how TAXSIM treats absent inputs anyway")
                continue
            end
        end

        # `Union{Missing,T}` is what every column read from real survey data looks like, so the
        # eltype test has to see through Missing. Bool and Rational are <: Real but neither
        # serialises to anything TAXSIM accepts, so they are excluded deliberately.
        T = nonmissingtype(eltype(col))
        if !(T <: Union{Integer,AbstractFloat}) || T <: Bool
            push!(problems, "\"$var\" is $(eltype(col)), but TAXSIM requires Integer or Float values")
        end
    end

    isempty(problems) || throw(TaxsimInputError(
        "Input is not acceptable to TAXSIM $(v.number):\n  " * join(problems, "\n  ")))

    _check_coverage(cols, v)
    return nothing
end

"Suggest the closest allowed name, for the common case of a typo or a case error."
function _did_you_mean(var, allowed)
    lower = lowercase(var)
    for a in allowed
        (lowercase(a) == lower || _edit1(lower, a)) && return " (did you mean \"$a\"?)"
    end
    return ""
end

"True when `a` and `b` differ by at most one insertion, deletion or substitution."
function _edit1(a::AbstractString, b::AbstractString)
    A, B = collect(a), collect(b)
    la, lb = length(A), length(B)
    abs(la - lb) <= 1 || return false

    i = j = 1
    edits = 0
    while i <= la && j <= lb
        if A[i] == B[j]
            i += 1
            j += 1
        else
            edits += 1
            edits > 1 && return false
            la == lb ? (i += 1; j += 1) : la > lb ? (i += 1) : (j += 1)
        end
    end
    return edits + (la - i + 1) + (lb - j + 1) <= 1
end

"""
    _check_coverage(cols, v)

Catch out-of-range years and state codes locally. The server rejects these record by record,
which on a large submission wastes the whole round trip.
"""
function _check_coverage(cols, v::TaxsimVersion)
    names_ = String.(Tables.columnnames(cols))
    col(n) = Tables.getcolumn(cols, Symbol(n))

    if "year" in names_
        yrs = col("year")
        bad = unique(y for y in yrs if !ismissing(y) && !(floor(Int, y) in FEDERAL_YEARS))
        isempty(bad) || throw(TaxsimInputError(
            "TAXSIM computes federal law for $(first(FEDERAL_YEARS))–$(last(FEDERAL_YEARS)) only, " *
            "but `year` contains $(join(sort(collect(bad)), ", ")). " *
            "State law is coded from $STATE_FIRST_YEAR and extrapolated after 2021."))

        if "state" in names_
            st = col("state")
            early = findall(i -> !ismissing(yrs[i]) && !ismissing(st[i]) &&
                                 yrs[i] < STATE_FIRST_YEAR && st[i] != 0, eachindex(yrs))
            isempty(early) || throw(TaxsimInputError(
                "TAXSIM has no state law before $STATE_FIRST_YEAR, so `state` must be 0 for " *
                "earlier years. Offending row(s): $(join(first(early, 5), ", "))."))
        end
    end

    # TAXSIM aborts a record that reports spouse wages or a spouse age on a non-joint return,
    # which is the most common way a survey extract fails partway through a large job. Measured
    # on both v32 and v35: only `swages` and `sage` are policed this way - `ssemp`, `sui`,
    # `sbusinc` and `sprofinc` are all accepted with mstat != 2, so they are deliberately not
    # checked here. Do not widen this without re-probing the server.
    if "mstat" in names_
        ms = col("mstat")
        for (var, label) in (("swages", "spouse wages"), ("sage", "spouse age"))
            var in names_ || continue
            vals = col(var)
            bad = findall(i -> !ismissing(ms[i]) && !ismissing(vals[i]) &&
                               ms[i] != 2 && vals[i] != 0, eachindex(ms))
            isempty(bad) || throw(TaxsimInputError(
                "`$var` ($label) must be 0 unless `mstat` is 2 (married filing jointly) — " *
                "TAXSIM abandons the record otherwise. Offending row(s): " *
                join(first(bad, 5), ", ") * (length(bad) > 5 ? ", …" : "") * ". " *
                "(TAXSIM does accept ssemp, sui, sbusinc and sprofinc on a non-joint return.)"))
        end
    end

    if "state" in names_
        bad = unique(s for s in col("state") if !ismissing(s) && !(0 <= s <= MAX_STATE_CODE))
        isempty(bad) || throw(TaxsimInputError(
            "`state` must be an SOI code between 0 and $MAX_STATE_CODE, but contains " *
            "$(join(sort(collect(bad)), ", ")). Note TAXSIM uses SOI codes (1 Alabama, " *
            "2 Alaska, 3 Arizona, 4 Arkansas, 5 California, …), NOT FIPS codes — see " *
            "`fips_to_taxsim`."))
    end
    return nothing
end

# FIPS -> SOI. They agree only for Alabama and Alaska and then diverge permanently, because
# SOI is gapless alphabetical while FIPS is not. CPS, ACS and IPUMS all ship FIPS, so feeding
# them straight into `state` silently computes the wrong state's tax.
const _FIPS_TO_SOI = Dict(
     1 =>  1,  2 =>  2,  4 =>  3,  5 =>  4,  6 =>  5,  8 =>  6,  9 =>  7, 10 =>  8,
    11 =>  9, 12 => 10, 13 => 11, 15 => 12, 16 => 13, 17 => 14, 18 => 15, 19 => 16,
    20 => 17, 21 => 18, 22 => 19, 23 => 20, 24 => 21, 25 => 22, 26 => 23, 27 => 24,
    28 => 25, 29 => 26, 30 => 27, 31 => 28, 32 => 29, 33 => 30, 34 => 31, 35 => 32,
    36 => 33, 37 => 34, 38 => 35, 39 => 36, 40 => 37, 41 => 38, 42 => 39, 44 => 40,
    45 => 41, 46 => 42, 47 => 43, 48 => 44, 49 => 45, 50 => 46, 51 => 47, 53 => 48,
    54 => 49, 55 => 50, 56 => 51,
)

"""
    fips_to_taxsim(fips)

Convert FIPS state codes — what CPS, ACS and IPUMS extracts contain — to the SOI codes TAXSIM
expects. Accepts a number or any iterable; `0` and `missing` pass through unchanged.

The two schemes agree only for Alabama and Alaska: FIPS 6 is California but SOI 6 is Colorado,
so passing FIPS codes directly to `state` produces no error and the wrong state's tax.

```jldoctest
julia> fips_to_taxsim(6)          # FIPS California is SOI California
5

julia> fips_to_taxsim(6) == 6     # ... but not SOI 6, which is Colorado
false

julia> fips_to_taxsim([1, 4, 6])
3-element Vector{Int64}:
 1
 3
 5
```

In practice:

```julia
df.state = fips_to_taxsim(df.statefip)
```
"""
fips_to_taxsim(x::Missing) = missing
function fips_to_taxsim(x::Real)
    x == 0 && return zero(x)
    haskey(_FIPS_TO_SOI, Int(x)) ||
        throw(TaxsimInputError("$x is not a valid FIPS state code"))
    return _FIPS_TO_SOI[Int(x)]
end
fips_to_taxsim(xs) = map(fips_to_taxsim, xs)
