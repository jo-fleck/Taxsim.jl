using Taxsim
using Test
using DataFrames


# Input tests

array = Array{Int64,2}(undef, 2, 3)
df_empty = DataFrame(year=[], mstat=[], ltcg=[])
df_faulty_name = DataFrame(yyear=1970, mstat=2, ltcg=100000)
df_missing = DataFrame(year=1970, mstat=2, ltcg=missing)
df_string = DataFrame(year=1970, mstat="married", ltcg=100000)

@testset "Inputs" begin
    @test_throws ErrorException("Input must be a data frame") taxsim32(array)
    @test_throws ErrorException("Input data frame is empty") taxsim32(df_empty)
    @test_throws ErrorException("Input contains \"yyear\" which is not an allowed TAXSIM 32 variable name") taxsim32(df_faulty_name)
    @test_throws ErrorException("Input contains \"ltcg\" with missing(s) which TAXSIM does not accept") taxsim32(df_missing)
    @test_throws ErrorException("Input contains \"mstat\" which is a neiter an Integer nor a Float variable as required by TAXSIM") taxsim32(df_string)
end

# Connection tests

df_small = DataFrame(year=1970, mstat=2, ltcg=100000)

@testset "SSH connection" begin
    df_default_out_ssh = taxsim32(df_small, connection = "SSH")
    @test typeof(df_default_out_ssh) == DataFrame
    df_full_out_ssh = taxsim32(df_small, connection = "SSH", full = true)
    @test typeof(df_full_out_ssh) == DataFrame
end

@testset "FTP connection" begin
    df_default_out_ftp = taxsim32(df_small)
    @test typeof(df_default_out_ftp) == DataFrame
    df_full_out_ftp = taxsim32(df_small, full = true)
    @test typeof(df_full_out_ftp) == DataFrame
end

# Output tests

df_small_state = DataFrame(year=1980, mstat=2, pwages=0, ltcg=100000, state=1)

@testset "1 filer output" begin
    df_small_out = taxsim32(df_small)
    @test df_small_out.fiitax[1] == 16700.04
    @test df_small_out.frate[1] == 46.12
    @test df_small_out.ficar[1] == 10.0
    df_small_state_out = taxsim32(df_small_state)
    @test df_small_state_out.fiitax[1] == 10920.0
    @test df_small_state_out.frate[1] == 20.0
    @test df_small_state_out.siitax[1] == 1119.0
    @test df_small_state_out.srate[1] == 4.0
end

df_small_state2 = DataFrame(year=[1980, 1981], mstat=[2,1], pwages=[0,100000], ltcg=[100000,0], state=[1,5])

@testset "2 filer output" begin
    df_small_state2_out = taxsim32(df_small_state2)
    @test df_small_state2_out.fiitax[1] == 10920.0
    @test df_small_state2_out.siitax[1] == 1119.0
    @test df_small_state2_out.fiitax[2] == 38344.85
    @test df_small_state2_out.siitax[2] == 9559.5
end

N = 10
df_small_stateN = DataFrame(year=repeat([1980],inner=N), mstat=repeat([2],inner=N), ltcg=repeat([100000],inner=N), state=repeat([1],inner=N))

@testset "N filer output: SSH connection" begin
    df_small_stateN_out_ssh = taxsim32(df_small_stateN, connection = "SSH")
    @test df_small_stateN_out_ssh.fiitax[N] == 10920.0
    @test df_small_stateN_out_ssh.siitax[N] == 1119.0
end

@testset "N filer output: FTP connection" begin
    df_small_stateN_out_ftp = taxsim32(df_small_stateN)
    @test df_small_stateN_out_ftp.fiitax[N] == 10920.0
    @test df_small_stateN_out_ftp.siitax[N] == 1119.0
end
