```@meta
CurrentModule = Taxsim
```

# Taxsim.jl

Julia interface to the NBER's [TAXSIM](https://taxsim.nber.org) calculator for US federal and
state income tax liabilities.

See the [README](https://github.com/jo-fleck/Taxsim.jl) for installation, worked examples and
two warnings worth reading before you start: `state` takes IRS SOI codes rather than the FIPS
codes CPS, ACS and IPUMS ship, and `taxsim32` is a frozen 2022 build whose results diverge from
`taxsim35` for recent years.

## Submitting returns

```@docs
taxsim35
taxsim32
```

## Helpers

```@docs
fips_to_taxsim
taxsim_server_version
```

## Errors

```@docs
TaxsimError
TaxsimInputError
TaxsimTransportError
TaxsimServerError
```
