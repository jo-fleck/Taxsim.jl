
"""
Before using `taxsim32`, please make yourself familiar with [Internet TAXSIM 32](https://taxsim.nber.org/taxsim32/). Submit a few individual observations and upload an entire csv file.

#### Syntax

`taxsim32(df; kwargs...)`

- `df` has to be a DataFrame object with at least one observation.
    - Included columns have to be named exactly as in the Internet TAXSIM 32 variable list (bold names after boxes) but can be in any order. `taxsim32` returns typos and case errors.
    - Non-provided input variables are set to zero by the TAXSIM server but `" "` (blanks as strings) or `missing` lead to non-response as the server only accepts Integers or Floats. `taxsim32` returns type errors.

#### Keyword Arguments

- `connection`: choose either `"FTP"` or `"SSH"`. Defaults to `"FTP"`.
- `full`: request the full list of TAXSIM return variables v1 to v42. Defaults to `false` which returns v1 to v9.
- `long_names`: name all return variables with their long TAXSIM names (as opposed to abbreviated names for v1 to v9 and no names for v10 to v42). Defaults to `false`.

#### Output

- Data frame with requested TAXSIM return variables. Column types are either Integer or Float.
- If `df` does not include `state` or if `state = 0`, then the returned data frame does not include v30 to v42.
- Observations are ordered as in `df` so `hcat(df, df_output, makeunique=true)` merges all variables of the input and output data frames.

#### Examples

```julia-repl
using DataFrames, Taxsim

df_input_small = DataFrame(year=1980, state=5, mstat=2, ltcg=100000)
1×4 DataFrame
│ Row │ year  │ state │ mstat │ ltcg   │
│     │ Int64 │ Int64 │ Int64 │ Int64  │
├─────┼───────┼───────┼───────┼────────┤
│ 1   │ 1980  │ 5     │ 2     │ 100000 │

df_output1 = taxsim32(df_input_small)
1×9 DataFrame
│ Row │ taxsimid │ year  │ state │ fiitax  │ siitax  │ fica    │ frate   │ srate   │ ficar   │
│     │ Float64  │ Int64 │ Int64 │ Float64 │ Float64 │ Float64 │ Float64 │ Float64 │ Float64 │
├─────┼──────────┼───────┼───────┼─────────┼─────────┼─────────┼─────────┼─────────┼─────────┤
│ 1   │ 0.0      │ 1980  │ 5     │ 10701.2 │ 4493.8  │ 0.0     │ 17.8    │ 11.0    │ 12.0    │

df_output2 = taxsim32(df_input_small, connection="SSH", full=true, long_lables=true);

```
"""
function taxsim32(df; connection = "FTP", full = false, long_names = false)

    # Input checks
    if typeof(df) != DataFrame error("Input must be a data frame") end
    if isempty(df) == true error("Input data frame is empty") end
    TAXSIM32_vars = ["taxsimid","year","state","mstat","page","sage","depx","dep13","dep17","dep18","pwages","swages","dividends","intrec","stcg","ltcg","otherprop","nonprop","pensions","gssi","ui","transfers","rentpaid","rentpaid","otheritem","childcare","mortgage","scorp","pbusinc","pprofinc","sbusinc","sprofinc"];
    for (i, input_var) in enumerate(names(df))
        if (input_var in TAXSIM32_vars) == false error("Input contains \"" * input_var *"\" which is not an allowed TAXSIM 32 variable name") end
        if any(ismissing.(df[!, i])) == true error("Input contains \"" * input_var *"\" with missing(s) which TAXSIM does not accept") end
        if (eltype(df[!, i]) == Int || eltype(df[!, i]) == Float64 || eltype(df[!, i]) == Float32 || eltype(df[!, i]) == Float16) == false error("Input contains \"" * input_var *"\" which is a neiter an Integer nor a Float variable as required by TAXSIM") end
    end

    if full == true
        insertcols!(df, size(df,2)+1, :idtl => 12)
    else
        insertcols!(df, size(df,2)+1, :idtl => 10)
    end

    if connection == "SSH"
        io_out = IOBuffer();
        if Sys.isapple() == true || Sys.islinux() == true
            try
                run(pipeline(`ssh -T -o ConnectTimeout=10 -o StrictHostKeyChecking=no taxsimssh@taxsimssh.nber.org`, stdin=seekstart(CSV.write(IOBuffer(), df)), stdout=io_out))
            catch
                @error "Cannot connect to the TAXSIM server via SSH"
            end
        end
        if Sys.iswindows() == true
            try
                run(pipeline(`! ssh -T -o ConnectTimeout=10 -o StrictHostKeyChecking=no taxsimssh@taxsimssh.nber.org`, stdin=seekstart(CSV.write(IOBuffer(), df)), stdout=io_out))
            catch
                @error "Cannot connect to the TAXSIM server via SSH"
            end
        end
        df_res = CSV.read(seekstart(io_out), DataFrame; silencewarnings=true)
    else
        ftp = FTP(hostname="taxsimftp.nber.org", username="taxsim", password="02138")
        try
            cd(ftp, "tmp")
        catch
            @error "Cannot connect to the TAXSIM server via FTP"
        end
        upload(ftp, CSV.write(IOBuffer(), df), "/userid")
        df_res = CSV.read(seekstart(download(ftp, "/userid.txm32")), DataFrame; silencewarnings=true)
    end

    if long_names == true
        ll_default = ["Case ID","Year","State","Federal income tax liability including capital gains rates, surtaxes, AMT and refundable and non-refundable credits","State income tax liability","FICA (OADSI and HI, sum of employee AND employer)","federal marginal rate","state marginal rate","FICA rate"];
        ll_full = ["Federal AGI","UI in AGI","Social Security in AGI","Zero Bracket Amount","Personal Exemptions","Exemption Phaseout","Deduction Phaseout","Deductions Allowed (Zero for non-itemizers)","Federal Taxable Income","Tax on Taxable Income (no special capital gains rates)","Exemption Surtax","General Tax Credit","Child Tax Credit (as adjusted)","Additional Child Tax Credit (refundable)","Child Care Credit","Earned Income Credit (total federal)","Income for the Alternative Minimum Tax","AMT Liability after credit for regular tax and other allowed credits","Federal Income Tax Before Credits (includes special treatment of Capital gains, exemption surtax (1988-1996) and 15% rate phaseout (1988-1990) but not AMT)","FICA"];
        ll_state = ["State Household Income (imputation for property tax credit)","State Rent Expense (imputation for property tax credit)","State AGI","State Exemption amount","State Standard Deduction","State Itemized Deductions","State Taxable Income","State Property Tax Credit","State Child Care Credit","State EIC","State Total Credits","State Bracket Rate"];
        if full == false
            rename!(df_res, ll_default)
        else
            rename!(df_res, [ll_default; ll_full; ll_state])
        end
    end

    select!(df, Not(:idtl))

    if sum(contains.("state", names(df))) == 0 select!(df_res, Not(names(df_res)[30:end])) end # Drop empty state vars

    return df_res
end
