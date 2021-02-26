var documenterSearchIndex = {"docs":
[{"location":"","page":"Home","title":"Home","text":"CurrentModule = Taxsim","category":"page"},{"location":"#Taxsim","page":"Home","title":"Taxsim","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"","category":"page"},{"location":"","page":"Home","title":"Home","text":"Modules = [Taxsim]","category":"page"},{"location":"#Taxsim.taxsim32-Tuple{Any}","page":"Home","title":"Taxsim.taxsim32","text":"Before using taxsim32, please make yourself familiar with Internet TAXSIM 32. Submit a few individual observations and upload an entire csv file.\n\nSyntax\n\ntaxsim32(df; kwargs...)\n\ndf has to be a DataFrame object with at least one observation.\nIncluded columns have to be named exactly as in the Internet TAXSIM 32 variable list (bold names after boxes) but can be in any order. taxsim32 returns typos and case errors.\nNon-provided input variables are set to zero by the TAXSIM server but \" \" (blanks as strings) or missing lead to non-response as the server only accepts Integers or Floats. taxsim32 returns type errors.\n\nKeyword Arguments\n\nconnection: choose either \"FTP\" or \"SSH\". Defaults to \"FTP\".\nfull: request the full list of TAXSIM return variables v1 to v42. Defaults to false which returns v1 to v9.\nlong_names: name all return variables with their long TAXSIM names (as opposed to abbreviated names for v1 to v9 and no names for v10 to v42). Defaults to false.\n\nOutput\n\nData frame with requested TAXSIM return variables. Column types are either Integer or Float.\nIf df does not include state or if state = 0, then the returned data frame does not include v30 to v42.\nObservations are ordered as in df so hcat(df, df_output, makeunique=true) merges all variables of the input and output data frames.\n\nExamples\n\nusing DataFrames, Taxsim\n\ndf_input_small = DataFrame(year=1980, state=5, mstat=2, ltcg=100000)\n1×4 DataFrame\n│ Row │ year  │ state │ mstat │ ltcg   │\n│     │ Int64 │ Int64 │ Int64 │ Int64  │\n├─────┼───────┼───────┼───────┼────────┤\n│ 1   │ 1980  │ 5     │ 2     │ 100000 │\n\ndf_output1 = taxsim32(df_input_small)\n1×9 DataFrame\n│ Row │ taxsimid │ year  │ state │ fiitax  │ siitax  │ fica    │ frate   │ srate   │ ficar   │\n│     │ Float64  │ Int64 │ Int64 │ Float64 │ Float64 │ Float64 │ Float64 │ Float64 │ Float64 │\n├─────┼──────────┼───────┼───────┼─────────┼─────────┼─────────┼─────────┼─────────┼─────────┤\n│ 1   │ 0.0      │ 1980  │ 5     │ 10701.2 │ 4493.8  │ 0.0     │ 17.8    │ 11.0    │ 12.0    │\n\ndf_output2 = taxsim32(df_input_small, connection=\"SSH\", full=true, long_lables=true);\n\n\n\n\n\n\n","category":"method"}]
}
