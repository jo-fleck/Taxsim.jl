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
