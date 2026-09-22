const SSH_HOSTS = ("taxsimssh.nber.org", "taxsim35.nber.org")
const SSH_PORTS = (22, 443)
const DEFAULT_TIMEOUT = 600

"""
    _run_stream(cmd, table, timeout) -> (stdout, stderr, ok)

Serialise `table` straight into the process's stdin rather than materialising the whole
submission in memory first, and enforce an overall watchdog: `ConnectTimeout` covers only the
SSH handshake, so a stalled transfer would otherwise block Julia indefinitely.

`table` rather than a buffer, because a retry against the next host has to re-serialise anyway
and buffering a multi-million-row submission is the thing this avoids.
"""
function _run_stream(cmd, table, timeout)
    out, err = IOBuffer(), IOBuffer()
    proc = try
        open(pipeline(cmd, stdout = out, stderr = err), "w")
    catch e
        return "", sprint(showerror, e), false
    end

    killed = Ref(false)
    timer = Timer(timeout) do _
        if process_running(proc)
            killed[] = true
            kill(proc)
        end
    end
    try
        table === nothing || CSV.write(proc.in, table)
        close(proc.in)
        wait(proc)
    catch
        # a dead process gives EPIPE here; the outcome is reported through `ok` below
        try close(proc.in) catch end
    finally
        close(timer)
    end

    killed[] && return "", "timed out after $(timeout)s", false
    return String(take!(out)), String(take!(err)), success(proc)
end

"""
    _looks_like_server_message(s)

TAXSIM exits non-zero when it rejects input, so a failed process is not by itself a transport
failure. If the server said something, that message is the useful error.
"""
_looks_like_server_message(s::AbstractString) =
    occursin("TAXSIM:", s) || occursin(r"^\s*STOP\b"m, s)

"""
    _raise_if_server_rejected(v, out, err)

Raise a [`TaxsimServerError`](@ref) when either stream carries a TAXSIM diagnostic, so the
caller is told what the server objected to instead of watching the same rejected payload be
retried against every other endpoint.
"""
function _raise_if_server_rejected(v::TaxsimVersion, out::AbstractString, err::AbstractString)
    (_looks_like_server_message(out) || _looks_like_server_message(err)) || return nothing

    lines = filter(!isempty, strip.(split(string(out, "\n", err), '\n')))
    # The diagnostic often repeats on both streams; keep it readable.
    shown = first(unique(lines), 12)
    throw(TaxsimServerError("TAXSIM $(v.number) rejected the submission:\n  " *
                            join(map(l -> first(l, 200), shown), "\n  ")))
end

"""
    _looks_like_html(s)

`curl` exits 0 on a 404, so an HTTP error page arrives looking like a successful response.
Without this check a proxy error, a captive portal or a moved endpoint would be handed to the
CSV parser and surface as a baffling width mismatch instead of a transport failure.
"""
function _looks_like_html(s::AbstractString)
    t = lstrip(s)
    isempty(t) && return false
    return startswith(t, "<") || occursin(r"<html"i, first(t, 500))
end

"""
    _submit_ssh(v, table; timeout) -> String

Try both NBER hosts on ports 22 and 443, first success wins. Port 443 matters for networks
that block 22.
"""
function _submit_ssh(v::TaxsimVersion, table; timeout = DEFAULT_TIMEOUT)
    Sys.which("ssh") === nothing && throw(TaxsimTransportError(
        "No `ssh` executable on PATH. On Windows, enable OpenSSH under " *
        "Apps > Optional Features, or pass connection = :http."))

    failures = String[]
    for port in SSH_PORTS, host in SSH_HOSTS
        # NOTE: do not add `-o BatchMode=yes` or `-o NumberOfPasswordPrompts=0`. The NBER
        # accounts authenticate by keyboard-interactive with an empty response, and either
        # option disables that path and breaks the connection outright. Hang protection is the
        # watchdog in `_run_capture`, not an ssh flag.
        cmd = `ssh -p $port -T -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new $(v.account)@$host`
        out, err, ok = _run_stream(cmd, table, timeout)

        # A server rejection is NOT a transport failure. TAXSIM aborts with a Fortran `STOP n`
        # on stderr while its diagnostic may land on either stream, so both must be inspected:
        # checking stdout alone made a bad record look like a dead endpoint, and the payload was
        # then resubmitted to every remaining host and port and finally over HTTP.
        _raise_if_server_rejected(v, out, err)
        (ok && !isempty(strip(out))) && return out

        detail = isempty(strip(err)) ? "returned an empty response" :
                 first(replace(strip(err), '\n' => "; "), 200)
        push!(failures, "$host:$port — $detail")
    end
    throw(TaxsimTransportError(
        "Cannot reach TAXSIM $(v.number) over SSH. Tried:\n  " * join(failures, "\n  ")))
end

"""
    _submit_http(v, table; timeout) -> String

Multipart POST to NBER's CGI endpoint. Needs no `ssh` binary, which is the point: it is the
fallback for Windows machines without OpenSSH and for firewalls that block 22 and 443 alike.

NBER's help file warns that http submissions have failed above roughly 5,000 records.
"""
function _submit_http(v::TaxsimVersion, table; timeout = DEFAULT_TIMEOUT)
    Sys.which("curl") === nothing && throw(TaxsimTransportError(
        "No `curl` executable on PATH, which the HTTP connection requires."))

    # The CGI rejects a streamed body: it needs a real multipart filename.
    path, io = mktemp()
    try
        close(io)
        CSV.write(path, table)
        cmd = `curl -sS --max-time $timeout -F txpydata=@$path $(v.http_url)`
        out, err, ok = _run_stream(cmd, nothing, timeout + 5)

        if _looks_like_html(out)
            first_line = first(something(findfirst(!isempty, strip.(split(out, '\n'))), 1), 1)
            throw(TaxsimTransportError(
                "$(v.http_url) returned an HTML page rather than TAXSIM output — the endpoint " *
                "may have moved, or a proxy intercepted the request. Response began: " *
                first(replace(strip(out), '\n' => " "), 160)))
        end
        _raise_if_server_rejected(v, out, err)
        (ok && !isempty(strip(out))) && return out
        throw(TaxsimTransportError("HTTP submission to $(v.http_url) failed: " *
                                   (isempty(strip(err)) ? "empty response" : strip(err))))
    finally
        isfile(path) && rm(path; force = true)
    end
end

"""
    _submit(v, table; connection, timeout) -> String

Dispatch to a transport. `:ssh` falls back to HTTP when every SSH endpoint fails, warning when
it does so — the HTTP TAXSIM 35 endpoint is an older build than the SSH one and can return
slightly different values, so the substitution must never be silent.
"""
function _submit(v::TaxsimVersion, table; connection::Symbol = :ssh, timeout = DEFAULT_TIMEOUT)
    if connection === :http
        return _submit_http(v, table; timeout)
    elseif connection === :ssh
        try
            return _submit_ssh(v, table; timeout)
        catch e
            e isa TaxsimTransportError || rethrow()
            @warn "SSH transport failed; falling back to HTTP. Note NBER's HTTP endpoint for " *
                  "TAXSIM $(v.number) may be an older build than the SSH one, so results can " *
                  "differ slightly. Pass connection = :ssh_only to disable this fallback." exception = e
            return _submit_http(v, table; timeout)
        end
    elseif connection === :ssh_only
        return _submit_ssh(v, table; timeout)
    else
        throw(ArgumentError("Unknown connection $(repr(connection)); use :ssh, :ssh_only or :http"))
    end
end
