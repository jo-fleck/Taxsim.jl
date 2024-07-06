using Taxsim
using Test
using DataFrames

@testset "TAXSIM32" begin
    include("taxsim32.jl")
end

@testset "TAXSIM35" begin
    include("taxsim35.jl")
end