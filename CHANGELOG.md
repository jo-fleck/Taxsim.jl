# Changelog

## v1.0.1

### Fixed

- **`state = -1` works again.** Submitting `-1` asks TAXSIM to compute a record for every
  state, returning 51 rows. v1.0.0 broke this twice over: the new state range check rejected
  `-1` outright, and the new row-count assertion read the 51-row response as a truncated reply
  to a 1-row submission. Both guards were individually reasonable and together they removed a
  feature v0.3.1 supported. The expected row count now accounts for the expansion, and the
  behaviour is documented and covered by tests.

## v1.0.0

First release since 2021. The package did not work on current Julia before this release.

### Scope of semantic versioning

Semantic versioning applies to **this package's Julia API**. The set of columns NBER's servers
return, and the values in them, are not part of it. NBER runs several TAXSIM builds
concurrently and rebuilds them without changing the version number, so a change in results is a
change on their side — use `taxsim_server_version()` to record which build produced yours.

### Breaking

- **`connection = "FTP"` now raises an error** and `FTPClient.jl` is no longer a dependency.
  NBER's FTP server still accepts uploads but returns no results — the compute daemon behind it
  is gone. Use the default `:ssh` or the new `:http`.
- **`full = true` returns every column the server sent.** Previously v30–v41 were dropped when
  no state was supplied. That was a client-side convenience, not server behaviour; it used the
  wrong range (NBER zeroes v31–v41), it discarded a populated `v30`, and it decided from row 1
  alone, so a frame mixing `state = 0` and `state = 1` lost twelve columns for every row.
- **Errors are typed**: `TaxsimInputError`, `TaxsimTransportError` and `TaxsimServerError`,
  under a `TaxsimError` supertype. Code matching on `ErrorException` message text must change.
- **`connection` takes a `Symbol`.** Strings still work but emit a deprecation warning.
- **Julia 1.10 or newer is required.** This is forced rather than chosen: DataFrames ≥ 1.8
  declares `julia = "1.10.0 - 1"`.
- **`Manifest.toml` is no longer committed.**

### Added

- **`taxsim35`** for TAXSIM 35, NBER's current release: 45 input variables, 10 standard or 48
  full output columns.
- **`mtr`** selects the margin marginal rates are computed with respect to — all ten codes, and
  it accepts a vector because TAXSIM honours `mtr` per record.
- **`connection = :http`** posts to NBER's CGI endpoint and needs no `ssh` binary, which is the
  fix for Windows machines without OpenSSH. `:ssh` falls back to it automatically, with a
  warning, because NBER's HTTP endpoint for v35 is an older build than its SSH one.
- **`fips_to_taxsim`** converts the FIPS state codes CPS, ACS and IPUMS ship to the SOI codes
  TAXSIM expects. See the warning below.
- **`taxsim_server_version()`** returns the server's build banner; the TAXSIM version and
  transport are also attached to every result as DataFrame metadata.
- **`missing_action = :zero`** sends zeros for `missing` values, which is how TAXSIM treats
  absent inputs anyway. The default remains `:error`.
- **`timeout`**, enforced by a watchdog. `ConnectTimeout` covers only the SSH handshake.
- Input is checked for **spouse wages or a spouse age on a non-joint return**, which TAXSIM
  abandons the record over. This is the most common way a survey extract fails partway
  through a large job. Verified against both endpoints that only `swages` and `sage` are
  policed this way — `ssemp`, `sui`, `sbusinc` and `sprofinc` are accepted with
  `mstat != 2`, so they are deliberately not rejected.
- Any **Tables.jl** source is accepted, not only a `DataFrame`.
- SSH now tries both NBER hosts on ports 22 and 443.

### Fixed

- **`full = true` returned a junk all-`missing` column.** TAXSIM 32 appends a trailing comma to
  every full-detail data row (46 fields against a 45-field header).
- **`full = true, long_names = true` threw `DimensionMismatch`** as a direct consequence.
  Renaming is now keyed by column name rather than position.
- **Columns of type `Union{Missing,T}` were rejected** even with no missing values — which is
  every column read from a real survey extract via CSV.jl or ReadStat.
- **Five valid TAXSIM 32 inputs were rejected**: `proptax`, `sui`, `pui`, `dep6`, `dep19`.
- **Server errors produced a garbage frame.** They are now raised with the server's own text.
- **Truncated responses were invisible.** The returned row count is checked against the input.
- **A failed connection fell through into parsing an empty buffer** instead of raising.
- **A column whose name merely contained `taxsimid` suppressed id generation** (substring rather
  than exact matching), corrupting the caller's join. Same bug for `state`.
- Submissions no longer copy the input: augmenting a million-row frame allocates about a
  kilobyte beyond the `idtl` column, against roughly 80 MB before, and is streamed rather than
  buffered.

### Two things to know before upgrading

- **`state` takes IRS SOI codes, not FIPS.** They agree only for Alabama and Alaska. Passing
  FIPS produces no error and the wrong state's tax — FIPS 6, California, computes as SOI 6,
  Colorado. Convert with `fips_to_taxsim`.
- **TAXSIM 32 is a frozen 11/03/22 build** with state law coded through 2020, and it diverges
  materially from TAXSIM 35 for 2022 onward — over $12,000 of 2023 federal tax on one test
  record. `taxsim32` is kept for reproducing earlier work and warns for `year >= 2022`. Use
  `taxsim35` for new work.
