const SSH_HOSTS = ("taxsimssh.nber.org", "taxsim35.nber.org")
const SSH_PORTS = (22, 443)
const DEFAULT_TIMEOUT = 600

"""
    _run_capture(cmd, stdin_io, timeout) -> (stdout, stderr, ok)

Run `cmd` with an overall watchdog. `ConnectTimeout` only covers the SSH handshake, so a
stalled transfer would otherwise block Julia indefinitely.
"""
function _run_capture(cmd, stdin_io, timeout)
    out, err = IOBuffer(), IOBuffer()
    proc = try
        run(pipeline(cmd, stdin = stdin_io, stdout = out, stderr = err); wait = false)
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
        wait(proc)
    catch
        # a killed or failed process is reported through `ok` below
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
    _submit_ssh(v, payload; timeout) -> String

Try both NBER hosts on ports 22 and 443, first success wins. Port 443 matters for networks
that block 22.
"""
function _submit_ssh(v::TaxsimVersion, payload; timeout = DEFAULT_TIMEOUT)
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
        out, err, ok = _run_capture(cmd, seekstart(payload), timeout)

        _looks_like_server_message(out) && return out
        (ok && !isempty(strip(out))) && return out

        detail = isempty(strip(err)) ? "returned an empty response" :
                 first(replace(strip(err), '\n' => "; "), 200)
        push!(failures, "$host:$port — $detail")
    end
    throw(TaxsimTransportError(
        "Cannot reach TAXSIM $(v.number) over SSH. Tried:\n  " * join(failures, "\n  ")))
end

"""
    _submit_http(v, payload; timeout) -> String

Multipart POST to NBER's CGI endpoint. Needs no `ssh` binary, which is the point: it is the
fallback for Windows machines without OpenSSH and for firewalls that block 22 and 443 alike.

NBER's help file warns that http submissions have failed above roughly 5,000 records.
"""
function _submit_http(v::TaxsimVersion, payload; timeout = DEFAULT_TIMEOUT)
    Sys.which("curl") === nothing && throw(TaxsimTransportError(
        "No `curl` executable on PATH, which the HTTP connection requires."))

    # The CGI rejects a streamed body: it needs a real multipart filename.
    path, io = mktemp()
    try
        write(io, take!(copy(seekstart(payload))))
        close(io)
        cmd = `curl -sS --max-time $timeout -F txpydata=@$path $(v.http_url)`
        out, err, ok = _run_capture(cmd, devnull, timeout + 5)

        _looks_like_server_message(out) && return out
        (ok && !isempty(strip(out))) && return out
        throw(TaxsimTransportError("HTTP submission to $(v.http_url) failed: " *
                                   (isempty(strip(err)) ? "empty response" : strip(err))))
    finally
        isfile(path) && rm(path; force = true)
    end
end

"""
    _submit(v, payload; connection, timeout) -> String

Dispatch to a transport. `:ssh` falls back to HTTP when every SSH endpoint fails, warning when
it does so — the HTTP TAXSIM 35 endpoint is an older build than the SSH one and can return
slightly different values, so the substitution must never be silent.
"""
function _submit(v::TaxsimVersion, payload; connection::Symbol = :ssh, timeout = DEFAULT_TIMEOUT)
    if connection === :http
        return _submit_http(v, payload; timeout)
    elseif connection === :ssh
        try
            return _submit_ssh(v, payload; timeout)
        catch e
            e isa TaxsimTransportError || rethrow()
            @warn "SSH transport failed; falling back to HTTP. Note NBER's HTTP endpoint for " *
                  "TAXSIM $(v.number) may be an older build than the SSH one, so results can " *
                  "differ slightly. Pass connection = :ssh_only to disable this fallback." exception = e
            return _submit_http(v, payload; timeout)
        end
    elseif connection === :ssh_only
        return _submit_ssh(v, payload; timeout)
    else
        throw(ArgumentError("Unknown connection $(repr(connection)); use :ssh, :ssh_only or :http"))
    end
end
