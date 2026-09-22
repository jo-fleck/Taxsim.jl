"""
    TaxsimVersion

The per-version data needed to talk to one TAXSIM release. This is deliberately plain data
rather than a behavioural abstraction: the response-parsing differences between versions are
handled generically in `output.jl`, because NBER rebuilds these binaries without version bumps
and a hardcoded per-version layout is one server-side insertion away from mislabelling every
column after it.
"""
struct TaxsimVersion
    number::Int
    account::String            # SSH account name
    http_url::String           # multipart CGI endpoint
    inputs::Vector{String}     # accepted data variable names
end

# Accepted input names come from `txpyvars` in NBER's own .ado files, which are more complete
# than the web pages. TAXSIM 32 takes 36; TAXSIM 35 takes those plus nine more, for 45.
const TAXSIM32_VARS = [
    "taxsimid", "year", "state", "mstat", "page", "sage",
    "depx", "dep6", "dep13", "dep17", "dep18", "dep19",
    "pwages", "swages", "dividends", "intrec", "stcg", "ltcg", "otherprop", "nonprop",
    "pensions", "gssi", "ui", "pui", "sui", "transfers",
    "rentpaid", "proptax", "otheritem", "childcare", "mortgage",
    "scorp", "pbusinc", "pprofinc", "sbusinc", "sprofinc",
]

const TAXSIM35_ONLY_VARS = ["psemp", "ssemp", "age1", "age2", "age3", "opt1", "opt1v", "opt2", "opt2v"]
const TAXSIM35_VARS = vcat(TAXSIM32_VARS, TAXSIM35_ONLY_VARS)

# Control columns: not data, but they travel in the same CSV.
const CONTROL_VARS = ["idtl", "mtr"]

const TAXSIM32 = TaxsimVersion(32, "taxsimssh", "https://taxsim.nber.org/uptest/webfile.cgi", TAXSIM32_VARS)
const TAXSIM35 = TaxsimVersion(35, "taxsim35", "https://taxsim.nber.org/uptest/webfile.good.cgi", TAXSIM35_VARS)

# Marginal tax rate margins. NBER's taxsim35.ado exposes only 85/86/11/14/70/56; the rest come
# from the web form's `mtr` radios and were verified against both endpoints. Unlike `idtl`,
# `mtr` may vary per record.
const MTR_CODES = Dict{Symbol,Int}(
    :taxpayer     => 85,   # default: with respect to taxpayer earnings
    :secondary    => 86,   # spouse earnings
    :wages        => 11,   # weighted primary + secondary wages
    :dividends    => 12,
    :interest     => 14,
    :other_income => 17,
    :mortgage     => 56,
    :deductions   => 66,   # other deductions
    :ltcg         => 70,   # long term capital gains
    # Code 0 is labelled "Don't bother" on NBER's web form. Measured behaviour is NOT a skip:
    # submitted alone it returns exactly what omitting `mtr` returns, so it is exposed for
    # completeness but must not be documented as a speed optimisation.
    :none         => 0,
)

const DEFAULT_MTR = :taxpayer

# Federal law coverage, checked locally so a multi-million-row job is not wasted on a round trip
# that the server will reject record by record.
const FEDERAL_YEARS = 1960:2023
const STATE_FIRST_YEAR = 1977      # "state must be zero if year is before 1977"
const MAX_STATE_CODE = 51          # SOI codes run 1 (Alabama) to 51 (Wyoming); 0 means no state

# Long labels keyed by the column name the server returns. Renaming by name rather than by
# position means an unrecognised column keeps the server's own name instead of shifting every
# label after it.
const LABELS = Dict{String,String}(
    "taxsimid" => "Case ID",
    "year"     => "Year",
    "state"    => "State",
    "fiitax"   => "Federal income tax liability including capital gains rates, surtaxes, AMT and refundable and non-refundable credits",
    "siitax"   => "State income tax liability",
    "fica"     => "FICA (OADSI and HI, sum of employee AND employer)",
    "frate"    => "federal marginal rate",
    "srate"    => "state marginal rate",
    "ficar"    => "FICA rate",
    # TAXSIM 35 additions. `tfica`, `credits` and `staxbc` are undocumented on NBER's page and
    # unlabelled in taxsim35.ado; these readings are taken from the idtl=5 text output, where
    # they print immediately after the corresponding concepts.
    "tfica"    => "Taxpayer share of FICA",
    "credits"  => "Federal Total Credits",
    "staxbc"   => "State tax before credits",
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

# Response widths, used to derive expectations rather than hardcoding magic numbers in tests.
const NCOL_DEFAULT = Dict(32 => 9, 35 => 10)
const NCOL_FULL = Dict(32 => 45, 35 => 48)
