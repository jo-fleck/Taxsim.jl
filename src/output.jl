"""
    _normalize(raw) -> String

Turn a raw server response into well-formed CSV, and surface server-side errors.

Handles the measured quirks generically rather than per version, because NBER rebuilds these
binaries without version bumps: TAXSIM 32's full output appends a trailing comma to every data
row (46 fields against a 45-field header), TAXSIM 35 pads two header names with spaces, and the
HTTP endpoint prefixes the body with a blank line. A width mismatch of any other shape is an
error, so a future layout change cannot silently drop real data.
"""
function _normalize(raw::AbstractString)
    txt = replace(raw, "\r\n" => "\n", "\r" => "\n")
    lines = [l for l in split(txt, '\n') if !isempty(strip(l))]
    isempty(lines) && throw(TaxsimServerError("TAXSIM returned an empty response"))

    # TAXSIM 32 emits its header before any error lines while TAXSIM 35 emits no header at all,
    # so scanning the raw text catches both before parsing turns them into a garbage frame.
    errs = filter(l -> occursin("TAXSIM:", l) || occursin(r"^\s*STOP\b", l), lines)
    isempty(errs) || throw(TaxsimServerError("TAXSIM server error:\n  " * join(strip.(errs), "\n  ")))

    header = strip.(split(lines[1], ','))
    data = lines[2:end]
    isempty(data) && throw(TaxsimServerError("TAXSIM returned a header but no results"))

    nh = length(header)
    widths = [count(==(','), l) + 1 for l in data]

    if all(==(nh), widths)
        # nothing to do
    elseif all(==(nh + 1), widths) && all(l -> endswith(rstrip(l), ","), data)
        data = [chop(rstrip(l)) for l in data]   # drop exactly one trailing delimiter
    else
        throw(TaxsimServerError(
            "TAXSIM returned $nh header fields but data rows with " *
            join(sort(unique(widths)), ", ") * " fields. Refusing to guess which columns " *
            "these are; please report this with the input that produced it."))
    end

    return join(header, ',') * "\n" * join(data, "\n") * "\n"
end

"""
    _apply_long_names!(df)

Rename by column name, not by position, so an unrecognised column keeps the server's own name
instead of throwing or shifting every label after it.
"""
function _apply_long_names!(df)
    ren = [n => LABELS[n] for n in names(df) if haskey(LABELS, n)]
    isempty(ren) || rename!(df, ren)
    return df
end

"""
    _restore_taxsimid!(df_res, df_in)

The server returns `taxsimid` as a float (`1.`). Callers who supplied integer person-ids and
then `leftjoin` on it would hit a type mismatch, so put the input's type back when the values
are integral.
"""
function _restore_taxsimid!(df_res, df_in)
    "taxsimid" in names(df_res) || return df_res
    col = df_res[!, "taxsimid"]
    all(isinteger, skipmissing(col)) || return df_res

    T = ("taxsimid" in names(df_in)) ? nonmissingtype(eltype(df_in[!, "taxsimid"])) : Int
    T <: Integer || return df_res
    df_res[!, "taxsimid"] = convert.(T, col)
    return df_res
end
