using Taxsim
using Test
using DataFrames
using CSV

const T = Taxsim
const FIX = joinpath(@__DIR__, "fixtures")
fixture(name) = read(joinpath(FIX, name), String)

# Network tests are opt-in: they need NBER to be reachable over SSH, which no CI runner can be
# relied on for. Everything else runs offline against recorded responses.
const LIVE = get(ENV, "TAXSIM_LIVE_TESTS", "") == "true"

@testset "Taxsim.jl" begin

    @testset "input validation" begin
        @test_throws ErrorException("Input must be a data frame") taxsim32(Array{Int64,2}(undef, 2, 3))
        @test_throws ErrorException("Input data frame is empty") taxsim32(DataFrame(year=[], mstat=[], ltcg=[]))
        @test_throws ErrorException("Input contains \"yyear\" which is not an allowed TAXSIM 32 variable name") taxsim32(DataFrame(yyear=1980, mstat=2, ltcg=100000))
        @test_throws ErrorException("Input contains \"mstat\" which is a neiter an Integer nor a Float variable as required by TAXSIM") taxsim32(DataFrame(year=1980, mstat="married", ltcg=100000))

        # missings are still rejected, but the offending rows are now named
        err = try taxsim32(DataFrame(year=[1980,1980], mstat=[2,2], ltcg=[100000,missing])); catch e; e end
        @test occursin("ltcg", err.msg) && occursin("row(s) 2", err.msg)

        # `Union{Missing,T}` with no actual missings is what every column read from real survey
        # data looks like; the old eltype whitelist rejected it outright.
        @test T._check_input(CSV.read(IOBuffer("year,mstat,ltcg\n1980,2,100000\n"), DataFrame)) === nothing
        @test T._check_input(DataFrame(year=Int32[1980], mstat=Int32[2])) === nothing

        # Bool and Rational are <: Real but do not serialize to anything TAXSIM accepts
        @test_throws ErrorException T._check_input(DataFrame(year=1980, mstat=2, ltcg=true))
        @test_throws ErrorException T._check_input(DataFrame(year=1980, mstat=2, ltcg=1//3))

        # variables NBER's taxsim32.ado accepts that the old whitelist was missing
        for v in ("proptax", "sui", "pui", "dep6", "dep19")
            @test v in T.TAXSIM32_VARS
        end
        @test count(==("rentpaid"), T.TAXSIM32_VARS) == 1
    end

    @testset "payload construction" begin
        payload(df, full) = String(take!(copy(seekstart(T._payload(df, full)))))

        # taxsimid added when absent; idtl carries +10 on the final record only
        @test payload(DataFrame(year=1980, mstat=2), false) == "taxsimid,year,mstat,idtl\n1,1980,2,10\n"
        @test payload(DataFrame(year=1980, mstat=2), true) == "taxsimid,year,mstat,idtl\n1,1980,2,12\n"

        multi = payload(DataFrame(year=[1980,1981,1982], mstat=[2,2,2]), true)
        @test [split(l, ',')[end] for l in split(chomp(multi), '\n')[2:end]] == ["2", "2", "12"]
        multi0 = payload(DataFrame(year=[1980,1981,1982], mstat=[2,2,2]), false)
        @test [split(l, ',')[end] for l in split(chomp(multi0), '\n')[2:end]] == ["0", "0", "10"]

        # a caller-supplied taxsimid is respected
        @test startswith(payload(DataFrame(taxsimid=[7,8], year=[1980,1980], mstat=[2,2]), false),
                         "taxsimid,year,mstat,idtl\n7,1980,2,0\n8,")

        # exact-match lookup: a column merely *containing* "taxsimid" must not suppress the id
        @test occursin("taxsimid,hh_taxsimid", payload(DataFrame(hh_taxsimid=[5], year=[1980], mstat=[2]), false))
    end

    @testset "response normalization" begin
        parse_fix(name) = CSV.read(IOBuffer(T._normalize(fixture(name))), DataFrame; delim=',')

        # TAXSIM 32 full output appends a trailing comma to every data row (46 fields against a
        # 45-field header). Previously this produced a spurious all-missing `Column46`.
        @test ncol(parse_fix("v32_full_nostate.csv")) == T.TAXSIM32_NCOL_FULL
        @test ncol(parse_fix("v32_full_state.csv")) == T.TAXSIM32_NCOL_FULL
        @test ncol(parse_fix("v32_full_2rows.csv")) == T.TAXSIM32_NCOL_FULL
        @test nrow(parse_fix("v32_full_2rows.csv")) == 2
        @test ncol(parse_fix("v32_default_nostate.csv")) == T.TAXSIM32_NCOL_DEFAULT
        for name in ("v32_full_nostate.csv", "v32_full_state.csv", "v32_default_nostate.csv")
            @test !any(startswith.(names(parse_fix(name)), "Column"))
        end

        # v30 is populated even with no state, which is why the old drop of v30:v41 was lossy
        @test parse_fix("v32_full_nostate.csv").v30[1] != 0

        # TAXSIM 35 pads two header names with spaces
        d35 = parse_fix("v35_full_state.csv")
        @test ncol(d35) == 48
        @test names(d35)[23] == "v21" && names(d35)[37] == "v35"
        @test names(d35)[10] == "tfica" && names(d35)[11] == "credits" && names(d35)[44] == "staxbc"

        # server-side errors are surfaced, not parsed into a garbage frame
        err = try T._normalize(fixture("v32_error_badyear.csv")); catch e; e end
        @test err isa ErrorException
        @test occursin("Federal tax calculator available 1960 - 2023 only", err.msg)

        # a width mismatch of any other shape must not be silently guessed at
        @test_throws ErrorException T._normalize("a,b,c\n1,2,3,4,5\n")
        @test_throws ErrorException T._normalize("")
        @test_throws ErrorException T._normalize("a,b,c\n")
    end

    @testset "long names" begin
        d = CSV.read(IOBuffer(T._normalize(fixture("v32_full_state.csv"))), DataFrame; delim=',')
        n = names(T._apply_long_names!(copy(d)))
        @test n[9] == "FICA rate"
        @test n[end] == "CARES act Recovery Rebates"
        @test length(n) == length(unique(n))

        # renaming is keyed by name, so an unknown column keeps the server's own name instead
        # of throwing or shifting every label after it
        extra = hcat(copy(d), DataFrame(v99=[0.0]))
        @test names(T._apply_long_names!(extra))[end] == "v99"
    end

    @testset "connection argument" begin
        df = DataFrame(year=1980, mstat=2, ltcg=100000)
        for ftp in ("FTP", "ftp", :ftp)
            e = try taxsim32(df, connection=ftp); catch e; e end
            @test e isa ErrorException && occursin("FTP connection has been removed", e.msg)
        end
        e = try taxsim32(df, connection="carrier pigeon"); catch e; e end
        @test e isa ErrorException && occursin("Unknown connection", e.msg)
    end

    if LIVE
        @testset "live: SSH round trip" begin
            df  = DataFrame(year=1980, mstat=2, ltcg=100000)
            dfs = DataFrame(year=1980, mstat=2, pwages=0, ltcg=100000, state=1)

            out = taxsim32(df)
            @test out isa DataFrame
            @test ncol(out) == T.TAXSIM32_NCOL_DEFAULT
            @test out.fiitax[1] == 10920.0
            @test out.frate[1] == 20.0

            outs = taxsim32(dfs)
            @test outs.siitax[1] == 1119.0
            @test outs.srate[1] == 4.0

            # state columns are retained whether or not a state was supplied
            @test ncol(taxsim32(df, full=true)) == T.TAXSIM32_NCOL_FULL
            @test ncol(taxsim32(dfs, full=true)) == T.TAXSIM32_NCOL_FULL
            @test ncol(taxsim32(dfs, full=true, long_names=true)) == T.TAXSIM32_NCOL_FULL

            df2 = DataFrame(year=[1980,1981], mstat=[2,1], pwages=[0,100000], ltcg=[100000,0], state=[1,5])
            o2 = taxsim32(df2, full=true)
            @test nrow(o2) == 2
            @test o2.fiitax == [10920.0, 38344.85]
            @test o2.siitax == [1119.0, 9559.5]

            N = 100
            dfN = DataFrame(year=fill(1980,N), mstat=fill(2,N), ltcg=fill(100000,N), state=fill(1,N))
            oN = taxsim32(dfN, full=true)
            @test nrow(oN) == N
            @test oN.fiitax[N] == 10920.0

            # server-side rejection surfaces as the server's own message
            e = try taxsim32(DataFrame(year=2025, mstat=2, pwages=100000)); catch e; e end
            @test e isa ErrorException && occursin("TAXSIM", e.msg)
        end

        @testset "live: fixtures still match the server" begin
            # A canary, not a unit test: if this fails, NBER changed the layout and the
            # recorded fixtures (and probably the parsing) need revisiting.
            got = T._ssh(T._payload(DataFrame(year=1980, mstat=2, ltcg=100000), true))
            @test split(chomp(fixture("v32_full_nostate.csv")), '\n')[1] == split(chomp(got), '\n')[1]
        end
    end
end
