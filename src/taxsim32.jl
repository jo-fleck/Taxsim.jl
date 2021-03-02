
"""
Before using `taxsim32`, please make yourself familiar with [Internet TAXSIM 32](https://taxsim.nber.org/taxsim32/). Submit a few individual observations and upload an entire csv file.

#### Syntax

`taxsim32(df; kwargs...)`

- `df` has to be a DataFrame object with at least one observation.
    - Included columns have to be named exactly as in the Internet TAXSIM 32 variable list (bold names after boxes) but can be in any order. `taxsim32` returns typos and case errors.
    - Non-provided input variables are set to zero by the TAXSIM server but `" "` (blanks as strings) or `missing` lead to non-response as the server only accepts Integers or Floats. `taxsim32` returns type errors.

#### Keyword Arguments

- `connection`: choose either `"FTP"` or `"SSH"`. `"FTP"` uses the [FTPClient Package](https://github.com/invenia/FTPClient.jl) while `"SSH"` issues a system curl command. Defaults to `"FTP"`.
- `full`: request the full list of TAXSIM return variables v1 to v41. Defaults to `false` which returns v1 to v9.
- `long_names`: name all return variables with their long TAXSIM names (as opposed to abbreviated names for v1 to v9 and no names for v10 to v41). Defaults to `false`.

#### Output

- Data frame with requested TAXSIM return variables. Column types are either Integer or Float.
- If `df` does not include `state` or if `state = 0`, the data frame returned by a `full` request does not include v30 to v41.
- Observations are ordered as in `df` so `hcat(df, df_output, makeunique=true)` merges all variables of the input and output data frames.

### Examples

```julia-repl
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

    # Add taxsimid column if not included and specify result request
    if sum(occursin.("taxsimid", names(df))) == 0 insertcols!(df, 1, :taxsimid => 1:size(df,1)) end

    insertcols!(df, size(df,2)+1, :idtl => 0)
    if full == true
        df[end, :idtl] = 12
    else
        df[end, :idtl] = 10
    end

    if connection == "SSH"
        io_out = IOBuffer();
        if Sys.isapple() == true || Sys.islinux() == true
            try
                run(pipeline(`ssh -T -o ConnectTimeout=60 -o StrictHostKeyChecking=no taxsimssh@taxsimssh.nber.org`, stdin=seekstart(CSV.write(IOBuffer(), df)), stdout=io_out))
            catch
                @error "Cannot connect to the TAXSIM server via SSH"
            end
        end
        if Sys.iswindows() == true
            try
                run(pipeline(`! ssh -T -o ConnectTimeout=60 -o StrictHostKeyChecking=no taxsimssh@taxsimssh.nber.org`, stdin=seekstart(CSV.write(IOBuffer(), df)), stdout=io_out))
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

    select!(df, Not([:taxsimid, :idtl]))

    if sum(occursin.("state", names(df))) == 0 || (sum(occursin.("state", names(df))) == 1 && df[1, :state] == 0) select!(df_res, Not(names(df_res)[30:end])) end # Drop empty state if no state or state = 0 in df

    return df_res
end
