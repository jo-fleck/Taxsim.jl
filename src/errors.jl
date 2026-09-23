"""
    TaxsimError

Supertype for every error this package raises deliberately. Callers looping over survey years
can retry a [`TaxsimTransportError`](@ref) while letting a [`TaxsimInputError`](@ref) through,
which was impossible when everything was an `ErrorException`.
"""
abstract type TaxsimError <: Exception end

"""
    TaxsimInputError

The submitted data frame is not something TAXSIM will accept. Not worth retrying.
"""
struct TaxsimInputError <: TaxsimError
    msg::String
end

"""
    TaxsimTransportError

The NBER server could not be reached, or the connection failed mid-transfer. Worth retrying.
"""
struct TaxsimTransportError <: TaxsimError
    msg::String
end

"""
    TaxsimServerError

TAXSIM itself rejected the submission. Carries the server's own message text. Not worth
retrying without changing the input.
"""
struct TaxsimServerError <: TaxsimError
    msg::String
end

Base.showerror(io::IO, e::TaxsimError) = print(io, e.msg)
