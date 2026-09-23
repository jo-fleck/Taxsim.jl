using Taxsim
using Test
using DataFrames
using CSV
using Tables
using Aqua
using TOML

const T = Taxsim
const FIX = joinpath(@__DIR__, "fixtures")
fixture(name) = read(joinpath(FIX, name), String)

# A stand-in transport, so the whole pipeline can be exercised offline against recorded bytes.
replay(name) = (v, payload; kwargs...) -> fixture(name)

# Network tests are opt-in: they need NBER reachable over SSH, which no CI runner can be relied
# on for. Everything else runs offline.
const LIVE = get(ENV, "TAXSIM_LIVE_TESTS", "") == "true"

@testset "Taxsim.jl" begin

    @testset "package quality (Aqua)" begin
        # Catches stale or undeclared dependencies - which is exactly how the unused FTPClient
        # would have been flagged - plus missing [compat] entries, which are a prerequisite for
        # registration in General. Better as a local test failure than a registration rejection.
        Aqua.test_all(Taxsim; ambiguities = false)
    end

    @testset "fixture sidecars" begin
        # Every fixture must have a sidecar, and the sidecar's recorded shape must match the
        # bytes actually on disk - so a hand-edited fixture is caught.
        csvs = filter(f -> endswith(f, ".csv"), readdir(FIX))
        @test !isempty(csvs)
        for f in csvs
            side = joinpath(FIX, replace(f, ".csv" => ".toml"))
            @test isfile(side)
            meta = TOML.parsefile(side)
            lines = [l for l in split(replace(fixture(f), "\r\n" => "\n"), '\n') if !isempty(strip(l))]
            @test meta["header_fields"] == count(==(','), lines[1]) + 1
            length(lines) >= 2 && @test meta["row_fields"] == count(==(','), lines[2]) + 1
            @test occursin("NBER TAXSIM Model", meta["server_banner"])
            @test meta["taxsim_version"] in (32, 35)
        end
    end

    @testset "version data" begin
        @test length(T.TAXSIM32_VARS) == 36
        @test length(T.TAXSIM35_VARS) == 45
        @test T.TAXSIM32_VARS ⊆ T.TAXSIM35_VARS          # v35 input is a strict superset
        @test length(unique(T.TAXSIM32_VARS)) == length(T.TAXSIM32_VARS)
        # names NBER's taxsim32.ado accepts that the old whitelist was missing
        @test all(v -> v in T.TAXSIM32_VARS, ("proptax", "sui", "pui", "dep6", "dep19"))
        @test !any(v -> v in T.TAXSIM32_VARS, T.TAXSIM35_ONLY_VARS)
    end

    @testset "input validation" begin
        bad(f) = try f(); nothing catch e; e end

        @test bad(() -> taxsim35(Array{Int64,2}(undef, 2, 3))) isa TaxsimInputError
        @test bad(() -> taxsim35(DataFrame(year=[], mstat=[]))) isa TaxsimInputError
        @test bad(() -> taxsim35("not a table")) isa TaxsimInputError

        e = bad(() -> taxsim35(DataFrame(yyear=1980, mstat=2)))
        @test e isa TaxsimInputError && occursin("not an allowed TAXSIM 35 variable", e.msg)
        @test occursin("did you mean \"year\"", e.msg)

        e = bad(() -> taxsim35(DataFrame(year=[1980,1980], mstat=[2,2], ltcg=[1,missing])))
        @test e isa TaxsimInputError && occursin("row(s) 2", e.msg)

        e = bad(() -> taxsim35(DataFrame(year=1980, mstat="married")))
        @test e isa TaxsimInputError && occursin("TAXSIM requires Integer or Float", e.msg)

        # every offending column is reported at once, not just the first
        e = bad(() -> taxsim35(DataFrame(aaa=1, bbb=2)))
        @test occursin("aaa", e.msg) && occursin("bbb", e.msg)

        # Union{Missing,T} with no actual missings is what real survey data looks like
        @test T._check_input(CSV.read(IOBuffer("year,mstat\n1980,2\n"), DataFrame), T.TAXSIM35) === nothing
        @test T._check_input(DataFrame(year=Int32[1980], mstat=Int32[2]), T.TAXSIM35) === nothing
        # Bool and Rational are <: Real but do not serialise to anything TAXSIM accepts
        @test bad(() -> T._check_input(DataFrame(year=1980, mstat=true), T.TAXSIM35)) isa TaxsimInputError
        @test bad(() -> T._check_input(DataFrame(year=1980, mstat=1//3), T.TAXSIM35)) isa TaxsimInputError

        # v35-only names are rejected by v32
        @test bad(() -> T._check_input(DataFrame(year=2015, mstat=2, psemp=100), T.TAXSIM32)) isa TaxsimInputError
        @test T._check_input(DataFrame(year=2015, mstat=2, psemp=100), T.TAXSIM35) === nothing
    end

    @testset "coverage checks" begin
        bad(f) = try f(); nothing catch e; e end
        e = bad(() -> taxsim35(DataFrame(year=2025, mstat=2)))
        @test e isa TaxsimInputError && occursin("1960", e.msg)
        @test bad(() -> taxsim35(DataFrame(year=1959, mstat=2))) isa TaxsimInputError
        # state law starts in 1977
        e = bad(() -> taxsim35(DataFrame(year=[1970], mstat=[2], state=[5])))
        @test e isa TaxsimInputError && occursin("1977", e.msg)
        @test T._check_input(DataFrame(year=[1970], mstat=[2], state=[0]), T.TAXSIM35) === nothing
        # `state = -1` asks for every state and is valid. Regression: 1.0.0 rejected it here
        # AND would have failed the row-count check, breaking a feature 0.3.1 supported.
        @test T._check_input(DataFrame(year=[2015], mstat=[2], state=[-1]), T.TAXSIM35) === nothing
        @test T._check_input(DataFrame(year=[2015,2015], mstat=[2,2], state=[-1,5]), T.TAXSIM35) === nothing
        @test_throws TaxsimInputError T._check_input(DataFrame(year=[2015], mstat=[2], state=[-2]), T.TAXSIM35)

        # SOI code range, with the FIPS trap named
        e = bad(() -> taxsim35(DataFrame(year=2015, mstat=2, state=99)))
        @test e isa TaxsimInputError && occursin("FIPS", e.msg)

        # spouse wages / spouse age on a non-joint return - TAXSIM abandons the record.
        # Verified against both endpoints: ONLY swages and sage are policed this way.
        for m in (1, 6, 8)
            e = bad(() -> taxsim35(DataFrame(year=[2019], mstat=[m], pwages=[50000], swages=[20000])))
            @test e isa TaxsimInputError && occursin("mstat", e.msg)
            e = bad(() -> taxsim35(DataFrame(year=[2019], mstat=[m], pwages=[50000], sage=[40])))
            @test e isa TaxsimInputError
        end
        @test T._check_input(DataFrame(year=[2019], mstat=[2], pwages=[50000], swages=[20000]), T.TAXSIM35) === nothing
        @test T._check_input(DataFrame(year=[2019], mstat=[1], pwages=[50000], swages=[0]), T.TAXSIM35) === nothing
        # these ARE accepted by the server on a non-joint return, so must not be rejected here
        for v in (:ssemp, :sui, :sbusinc, :sprofinc)
            d = DataFrame(year=[2019], mstat=[1], pwages=[50000])
            d[!, v] = [20000]
            @test T._check_input(d, T.TAXSIM35) === nothing
        end
    end

    @testset "fips_to_taxsim" begin
        @test fips_to_taxsim(1) == 1 && fips_to_taxsim(2) == 2     # AL, AK agree
        @test fips_to_taxsim(4) == 3                                # FIPS AZ -> SOI AZ
        @test fips_to_taxsim(6) == 5                                # FIPS CA -> SOI CA, not 6
        @test fips_to_taxsim(56) == 51                              # WY
        @test fips_to_taxsim(0) == 0
        @test fips_to_taxsim([6, 36, 48]) == [5, 33, 44]
        @test ismissing(fips_to_taxsim(missing))
        @test_throws TaxsimInputError fips_to_taxsim(3)             # unused FIPS code
    end

    @testset "payload construction" begin
        pay(df; v=T.TAXSIM35, full=false, mtr=T.DEFAULT_MTR) =
            T._payload_string(T._table(df, v, full, mtr))

        @test pay(DataFrame(year=1980, mstat=2)) == "taxsimid,year,mstat,idtl\n1,1980,2,10\n"
        @test pay(DataFrame(year=1980, mstat=2); full=true) == "taxsimid,year,mstat,idtl\n1,1980,2,12\n"

        three = DataFrame(year=[1980,1981,1982], mstat=[2,2,2])
        last_col(s) = [split(l, ',')[end] for l in split(chomp(s), '\n')[2:end]]
        @test last_col(pay(three; full=true)) == ["2", "2", "12"]
        @test last_col(pay(three)) == ["0", "0", "10"]

        # the default mtr emits no column at all, so the default submission is unchanged
        @test !occursin("mtr", pay(DataFrame(year=1980, mstat=2)))
        @test occursin("mtr,idtl\n1,1980,2,86,10", pay(DataFrame(year=1980, mstat=2); mtr=:secondary))
        # mtr may vary per record
        @test last_col(pay(three; mtr=[:taxpayer, :interest, :none])) == ["0", "0", "10"]
        @test [split(l, ',')[end-1] for l in split(chomp(pay(three; mtr=[:taxpayer,:interest,:none])), '\n')[2:end]] == ["85", "14", "0"]

        # a state = -1 record expands to 51 result rows, so the expected count must too
        @test T._expected_rows((; idtl=[10]), 1) == 1
        @test T._expected_rows((; state=[-1], idtl=[10]), 1) == 51
        @test T._expected_rows((; state=[-1,-1], idtl=[0,10]), 2) == 102
        @test T._expected_rows((; state=[-1,5], idtl=[0,10]), 2) == 52
        @test T._expected_rows((; state=[5,5], idtl=[0,10]), 2) == 2

        @test_throws TaxsimInputError T._table(three, T.TAXSIM35, false, [:taxpayer])
        @test_throws TaxsimInputError T._table(three, T.TAXSIM35, false, :nonsense)
        @test_throws TaxsimInputError T._table(DataFrame(year=1980, mstat=2, idtl=2), T.TAXSIM35, false, T.DEFAULT_MTR)

        # a caller-supplied taxsimid is respected; a column merely containing the substring is not
        @test startswith(pay(DataFrame(taxsimid=[7,8], year=[1980,1980], mstat=[2,2])), "taxsimid,year,mstat,idtl\n7,")
        @test occursin("taxsimid,hh_taxsimid", pay(DataFrame(hh_taxsimid=[5], year=[1980], mstat=[2])))
    end

    @testset "response normalization" begin
        parse_fix(name) = CSV.read(IOBuffer(T._normalize(fixture(name))), DataFrame; delim=',')

        # TAXSIM 32 appends a trailing comma to every full-detail row (46 against 45)
        for name in ("v32_full_nostate.csv", "v32_full_state.csv", "v32_full_2rows.csv")
            d = parse_fix(name)
            @test ncol(d) == T.NCOL_FULL[32]
            @test !any(startswith.(names(d), "Column"))
        end
        @test nrow(parse_fix("v32_full_2rows.csv")) == 2
        @test ncol(parse_fix("v32_default_nostate.csv")) == T.NCOL_DEFAULT[32]
        @test ncol(parse_fix("v35_default_nostate.csv")) == T.NCOL_DEFAULT[35]

        # v35 is wider, interleaves named columns, and pads two header names
        d35 = parse_fix("v35_full_state.csv")
        @test ncol(d35) == T.NCOL_FULL[35]
        @test names(d35)[[10, 11, 44]] == ["tfica", "credits", "staxbc"]
        @test names(d35)[23] == "v21" && names(d35)[37] == "v35"

        # neither server drops state columns when no state is given, and v30 is populated -
        # which is why the old client-side drop of v30:v41 was lossy
        @test ncol(parse_fix("v35_full_nostate.csv")) == T.NCOL_FULL[35]
        @test parse_fix("v32_full_nostate.csv").v30[1] != 0

        err = try T._normalize(fixture("v32_error_badyear.csv")); catch e; e end
        @test err isa TaxsimServerError
        @test occursin("1960 - 2023 only", err.msg)

        @test_throws TaxsimServerError T._normalize("a,b,c\n1,2,3,4,5\n")
        @test_throws TaxsimServerError T._normalize("")
        @test_throws TaxsimServerError T._normalize("a,b,c\n")
        # the HTTP endpoint prefixes the body with a blank line
        @test ncol(CSV.read(IOBuffer(T._normalize("\n" * fixture("v32_default_nostate.csv"))), DataFrame)) == T.NCOL_DEFAULT[32]
    end

    @testset "offline end-to-end" begin
        df = DataFrame(year=1980, mstat=2, ltcg=100000)

        o32 = T._taxsim(df, T.TAXSIM32; _transport=replay("v32_default_nostate.csv"))
        @test ncol(o32) == T.NCOL_DEFAULT[32] && o32.fiitax[1] == 10920.0
        @test metadata(o32, "taxsim_version") == 32

        o35 = T._taxsim(df, T.TAXSIM35; _transport=replay("v35_default_nostate.csv"))
        @test ncol(o35) == T.NCOL_DEFAULT[35] && "tfica" in names(o35)
        @test metadata(o35, "taxsim_version") == 35

        # long names are applied by name, so an unknown column keeps the server's own
        ol = T._taxsim(df, T.TAXSIM35; long_names=true, _transport=replay("v35_full_state.csv"))
        @test ncol(ol) == T.NCOL_FULL[35]
        @test names(ol)[10] == "Taxpayer share of FICA"
        @test length(names(ol)) == length(unique(names(ol)))

        # taxsimid comes back as the input's integer type rather than the server's Float64
        oi = T._taxsim(DataFrame(taxsimid=Int32[1], year=[1980], mstat=[2]), T.TAXSIM35;
                       _transport=replay("v35_default_nostate.csv"))
        @test eltype(oi.taxsimid) == Int32

        # a truncated response must not be returned as if it were complete
        two = DataFrame(year=[1980,1981], mstat=[2,1])
        @test_throws TaxsimServerError T._taxsim(two, T.TAXSIM32; _transport=replay("v32_default_nostate.csv"))
    end

    @testset "v32 is a frozen build" begin
        # The two versions agree through 2021 and diverge afterwards; these fixtures pin that so
        # it is caught by the suite rather than discovered in a referee report.
        p(n) = CSV.read(IOBuffer(T._normalize(fixture(n))), DataFrame; delim=',')
        a, b = p("v32_2022_ca.csv"), p("v35_2022_ca.csv")
        @test a.fiitax[1] == b.fiitax[1]        # federal 2022 agrees
        @test a.siitax[1] != b.siitax[1]        # state 2022 does not
        @test a.srate[1] == 6.00 && b.srate[1] == 9.30

        @test_logs (:warn, r"frozen") match_mode=:any T._warn_stale_v32(DataFrame(year=[2022], mstat=[2]))
        @test T._warn_stale_v32(DataFrame(year=[2019], mstat=[2])) === nothing
    end

    @testset "Tables.jl sources and missing_action" begin
        df = DataFrame(year=1980, mstat=2, ltcg=100000)
        expected = T._payload_string(T._table(df, T.TAXSIM35, false, T.DEFAULT_MTR))

        # any Tables.jl source produces the same submission as the equivalent DataFrame
        for src in ((; year=[1980], mstat=[2], ltcg=[100000]),
                    Tables.rowtable((; year=[1980], mstat=[2], ltcg=[100000])),
                    CSV.File(IOBuffer("year,mstat,ltcg\n1980,2,100000\n")))
            @test T._payload_string(T._table(src, T.TAXSIM35, false, T.DEFAULT_MTR)) == expected
        end

        # the augmented table shares the caller's column vectors instead of copying them
        big = DataFrame(year=fill(1980, 10_000), mstat=fill(2, 10_000))
        tbl = T._table(big, T.TAXSIM35, false, T.DEFAULT_MTR)
        @test tbl.year === big.year && tbl.mstat === big.mstat
        @test Tables.istable(tbl)

        # missing_action
        dm = DataFrame(year=[1980,1980], mstat=[2,2], ltcg=[100000,missing])
        @test_throws TaxsimInputError T._check_input(dm, T.TAXSIM35)
        @test T._check_input(dm, T.TAXSIM35; missing_action=:zero) === nothing
        zeroed = T._payload_string(T._table(dm, T.TAXSIM35, false, T.DEFAULT_MTR, :zero))
        @test occursin("1980,2,0,", zeroed)
        # a column with no missings is still shared, not rebuilt
        @test T._table(dm, T.TAXSIM35, false, T.DEFAULT_MTR, :zero).year === dm.year
    end

    @testset "transport failure classification" begin
        v = T.TAXSIM35

        # A rejected record is a server error, not a transport failure. TAXSIM writes `STOP n`
        # to stderr and an unprefixed diagnostic to stdout, so checking stdout alone made a bad
        # record look like a dead endpoint - and the payload was resubmitted to every remaining
        # host and port, then over HTTP.
        e = try T._raise_if_server_rejected(v, " Bad mstat   9.0000  x= 1.0", "STOP 4"); catch e; e end
        @test e isa TaxsimServerError && occursin("Bad mstat", e.msg)
        e = try T._raise_if_server_rejected(v, " TAXSIM: Federal tax calculator available 1960 - 2023 only.", ""); catch e; e end
        @test e isa TaxsimServerError
        e = try T._raise_if_server_rejected(v, "", " TAXSIM: Non-joint return with spousal income"); catch e; e end
        @test e isa TaxsimServerError

        # ... and must not fire on a good response or on ssh's own chatter
        @test T._raise_if_server_rejected(v, "taxsimid,year\n1,1980\n", "") === nothing
        @test T._raise_if_server_rejected(v, "taxsimid,year\n1,1980\n",
                  "Warning: Permanently added 'taxsimssh.nber.org' (ED25519) to the list of known hosts.") === nothing
        @test T._raise_if_server_rejected(v, "", "") === nothing

        # curl exits 0 on a 404, so an HTML error page arrives looking like a response
        @test T._looks_like_html("<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\">\n<html>")
        @test T._looks_like_html("\n  <html><head><title>404</title>")
        @test !T._looks_like_html("taxsimid,year,state\n1.,1980,0\n")
        @test !T._looks_like_html("")
    end

    @testset "transport failure paths (offline)" begin
        # These are the paths the two pre-release bugs lived in. They were verified by hand
        # during validation but nothing in the suite covered them, so a regression would have
        # gone unnoticed. All of these run without touching the network.

        # the watchdog: ConnectTimeout only covers the handshake, so a stalled transfer needs
        # an external kill or Julia blocks indefinitely
        el = @elapsed begin
            out, err, ok = T._run_stream(`sleep 30`, nothing, 2)
            @test !ok
            @test occursin("timed out", err)
            @test isempty(out)
        end
        @test el < 10          # killed at ~2s, not run to completion at 30s

        # a command that cannot be spawned at all is reported, not thrown through
        out, err, ok = T._run_stream(`__taxsim_no_such_executable__`, nothing, 5)
        @test !ok && isempty(out) && !isempty(err)

        # every endpoint failing is a transport error that names each attempt. Port 1 on
        # localhost refuses immediately, so this costs nothing.
        e = try
            T._submit_ssh(T.TAXSIM35, (; taxsimid=[1], year=[1980], mstat=[2], idtl=[10]);
                          timeout=20, hosts=("127.0.0.1",), ports=(1, 2))
        catch e; e end
        @test e isa TaxsimTransportError
        @test occursin("127.0.0.1:1", e.msg) && occursin("127.0.0.1:2", e.msg)
        @test occursin("Cannot reach TAXSIM 35 over SSH", e.msg)

        # an unrecognised transport is rejected at the dispatch point
        @test_throws ArgumentError T._submit(T.TAXSIM35, (; idtl=[10]); connection=:carrier_pigeon)
    end

    @testset "connection argument" begin
        @test T._normalize_connection(:ssh) === :ssh
        @test T._normalize_connection(:http) === :http
        @test T._normalize_connection(:ssh_only) === :ssh_only
        for ftp in (:ftp,)
            e = try T._normalize_connection(ftp); catch e; e end
            @test e isa TaxsimTransportError && occursin("FTP connection has been removed", e.msg)
        end
        @test_throws ArgumentError T._normalize_connection(:carrier_pigeon)
        # string values still work, deprecated
        @test T._normalize_connection("SSH") === :ssh
        @test T._normalize_connection("http") === :http
    end

    if LIVE
        @testset "live: both versions over SSH" begin
            df  = DataFrame(year=1980, mstat=2, ltcg=100000)
            dfs = DataFrame(year=1980, mstat=2, pwages=0, ltcg=100000, state=1)

            o = taxsim32(df)
            @test ncol(o) == T.NCOL_DEFAULT[32] && o.fiitax[1] == 10920.0 && o.frate[1] == 20.0
            @test ncol(taxsim35(df)) == T.NCOL_DEFAULT[35]

            @test ncol(taxsim32(dfs, full=true)) == T.NCOL_FULL[32]
            @test ncol(taxsim35(dfs, full=true)) == T.NCOL_FULL[35]
            @test ncol(taxsim35(dfs, full=true, long_names=true)) == T.NCOL_FULL[35]

            os = taxsim32(dfs)
            @test os.siitax[1] == 1119.0 && os.srate[1] == 4.0

            df2 = DataFrame(year=[1980,1981], mstat=[2,1], pwages=[0,100000], ltcg=[100000,0], state=[1,5])
            o2 = taxsim32(df2, full=true)
            @test nrow(o2) == 2 && o2.fiitax == [10920.0, 38344.85]

            N = 100
            dfN = DataFrame(year=fill(1980,N), mstat=fill(2,N), ltcg=fill(100000,N), state=fill(1,N))
            @test nrow(taxsim35(dfN, full=true)) == N
        end

        @testset "live: state = -1 expands to every state" begin
            o = taxsim35(DataFrame(taxsimid=[7], year=[2015], mstat=[2], pwages=[80000], state=[-1]))
            @test nrow(o) == 51
            @test sort(o.state) == collect(1:51)
            @test all(==(7), o.taxsimid)             # the submitted id is carried through
            @test nrow(taxsim35(DataFrame(year=[2015], mstat=[2], pwages=[80000], state=[-1]), full=true)) == 51
            # mixed submissions
            m = DataFrame(year=[2015,2015], mstat=[2,2], pwages=[80000,90000], state=[-1,5])
            @test nrow(taxsim35(m)) == 52
            @test nrow(taxsim32(m)) == 52
        end

        @testset "live: mtr margins" begin
            d = DataFrame(year=2015, mstat=2, pwages=100000, swages=20000, intrec=5000)
            # the FICA marginal rate is zero at a margin that is not FICA-taxable
            @test taxsim35(d, mtr=:taxpayer).ficar[1] > 0
            @test taxsim35(d, mtr=:interest).ficar[1] == 0
        end

        @testset "live: HTTP transport" begin
            df = DataFrame(year=1980, mstat=2, ltcg=100000)
            @test ncol(taxsim32(df, connection=:http)) == T.NCOL_DEFAULT[32]
            @test ncol(taxsim35(df, connection=:http)) == T.NCOL_DEFAULT[35]
        end

        @testset "live: provenance" begin
            @test occursin("v35", taxsim_server_version(35))
            @test occursin("v32", taxsim_server_version(32))
        end

        @testset "live: fixtures still match the server" begin
            # A canary, not a unit test: a failure here means NBER changed the layout and the
            # fixtures (and probably the parsing) need revisiting.
            for (v, name, full) in ((T.TAXSIM32, "v32_full_nostate.csv", true),
                                    (T.TAXSIM35, "v35_full_nostate.csv", true))
                got = T._submit(v, T._table(DataFrame(year=1980, mstat=2, ltcg=100000), v, full, T.DEFAULT_MTR))
                @test split(chomp(fixture(name)), '\n')[1] == split(chomp(got), '\n')[1]
            end
        end
    end
end
