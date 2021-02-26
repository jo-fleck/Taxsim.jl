using Taxsim
using Test
using DataFrames


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
