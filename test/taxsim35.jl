using Taxsim
using Test
using DataFrames

# Input tests

array = Array{Int64,2}(undef, 2, 3)
df_empty = DataFrame(year=[], mstat=[], ltcg=[])
df_faulty_name = DataFrame(yyear=1980, mstat=2, ltcg=100000)
df_missing = DataFrame(year=1980, mstat=2, ltcg=missing)
df_string = DataFrame(year=1980, mstat="married", ltcg=100000)

@testset "Inputs" begin
    @test_throws ErrorException("Input must be a data frame") taxsim35(array)
    @test_throws ErrorException("Input data frame is empty") taxsim35(df_empty)
    @test_throws ErrorException("Input contains \"yyear\" which is not an allowed TAXSIM 35 variable name") taxsim35(df_faulty_name)
    @test_throws ErrorException("Input contains \"ltcg\" with missing(s) which TAXSIM does not accept") taxsim35(df_missing)
    @test_throws ErrorException("Input contains \"mstat\" which is a neiter an Integer nor a Float variable as required by TAXSIM") taxsim35(df_string)
end

# Connection tests

df_small = DataFrame(year=1980, mstat=2, ltcg=100000)

@testset "SSH connection" begin
    df_default_out_ssh = taxsim35(df_small)
    @test typeof(df_default_out_ssh) == DataFrame
end

@testset "FTP connection" begin
    df_default_out_ftp = taxsim35(df_small, connection = "FTP")
    @test typeof(df_default_out_ftp) == DataFrame
end

# Output tests

df_small_state = DataFrame(year=1980, mstat=2, pwages=0, ltcg=100000, state=1)

@testset "1 filer output" begin

    df_small_out = taxsim35(df_small)
    @test df_small_out.fiitax[1] == 10920.0
    @test df_small_out.frate[1] == 20.0
    @test df_small_out.ficar[1] == 12.0
    @test size(df_small_out,2) == 10

    df_small_full_out = taxsim35(df_small, full = true)
    @test size(df_small_full_out,2) == 36

    df_small_state_out = taxsim35(df_small_state)
    @test df_small_state_out.fiitax[1] == 10920.0
    @test df_small_state_out.frate[1] == 20.0
    @test df_small_state_out.siitax[1] == 1119.0
    @test df_small_state_out.srate[1] == 4.0
    @test size(df_small_state_out,2) == 10

    df_small_state_full_out = taxsim35(df_small_state, full = true)
    @test size(df_small_state_full_out,2) == 48

end

df_small_state2 = DataFrame(year=[1980, 1981], mstat=[2,1], pwages=[0,100000], ltcg=[100000,0], state=[1,5])

@testset "2 filer output" begin

    df_small_state2_out = taxsim35(df_small_state2)
    @test size(df_small_state2_out,2) == 10
    @test size(df_small_state2_out,1) == 2

    df_small_state2_full_out = taxsim35(df_small_state2, full = true)
    @test df_small_state2_full_out.fiitax[1] == 10920.0
    @test df_small_state2_full_out.siitax[1] == 1119.0
    @test df_small_state2_full_out.fiitax[2] == 38344.85
    @test df_small_state2_full_out.siitax[2] == 9559.5
    @test size(df_small_state2_full_out,2) == 48
end

N = 100
df_small_stateN = DataFrame(year=repeat([1980],inner=N), mstat=repeat([2],inner=N), ltcg=repeat([100000],inner=N), state=repeat([1],inner=N))

@testset "N filer output: SSH connection" begin
    df_small_stateN_full_out_ssh = taxsim35(df_small_stateN, full = true)
    @test df_small_stateN_full_out_ssh.fiitax[N] == 10920.0
    @test df_small_stateN_full_out_ssh.siitax[N] == 1119.0
    @test size(df_small_stateN_full_out_ssh,2) == 48
end

@testset "N filer output: FTP connection" begin
    df_small_stateN_full_out_ftp = taxsim35(df_small_stateN, connection = "FTP", full = true)
    @test df_small_stateN_full_out_ftp.fiitax[N] == 10920.0
    @test df_small_stateN_full_out_ftp.siitax[N] == 1119.0
    @test size(df_small_stateN_full_out_ftp,2) == 48
end

# Long names tests

@testset "Long names" begin

    df_small_out_long_names = taxsim35(df_small, long_names = true)
    @test names(df_small_out_long_names)[9] == "FICA rate"

    df_small_full_out_long_names = taxsim35(df_small, full = true, long_names = true)
    @test names(df_small_full_out_long_names)[29] == "FICA"
    @test names(df_small_full_out_long_names)[33] == "CARES act Recovery Rebates"

    df_small_state_out_long_names = taxsim35(df_small_state, long_names = true)
    @test names(df_small_state_out_long_names)[9] == "FICA rate"

    df_small_state_full_out_long_names = taxsim35(df_small_state, full = true, long_names = true)
    @test names(df_small_state_full_out_long_names)[45] == "CARES act Recovery Rebates"

end


# # Performance Tests:
#
# # 1 filer
#
# @timev taxsim35(df_small);
# @timev taxsim35(df_small, connection = "FTP");
#
# # N filer
#
# N_perf = 100000;
# df_small_stateN_perf = DataFrame(year=repeat([1980],inner=N_perf), mstat=repeat([2],inner=N_perf), ltcg=repeat([100000],inner=N_perf), state=repeat([1],inner=N_perf));
#
# @timev taxsim35(df_small_stateN_perf, full = true);
# @timev taxsim35(df_small_stateN_perf, connection = "FTP", full = true);
# @timev taxsim35(df_small_stateN_perf, full = true, checks = false);
#
# @code_native taxsim35(df_small_stateN_perf, full = true);
# @code_native taxsim35(df_small_stateN_perf, connection = "FTP", full = true);
# @code_native taxsim35(df_small_stateN_perf, full = true, checks = false);
#
# @profiler taxsim35(df_small_stateN_perf, full = true);
# @profiler taxsim35(df_small_stateN_perf, connection = "FTP", full = true);
# @profiler taxsim35(df_small_stateN_perf, full = true, checks = false);
