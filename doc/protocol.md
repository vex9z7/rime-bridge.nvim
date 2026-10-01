# Worker protocol 1

Transport: newline-delimited JSON on stdin/stdout, maximum 64 KiB per frame.
Stderr is diagnostics only. No network listener or LSP. Each process owns one
engine/session. EOF or shutdown ends the process and releases the directory lock.

Requests contain increasing nonnegative integer `id`, nonnegative `generation`
and string `op`. Responses echo id/generation with `ok` and either `result` or
`error`. Invalid frames/transport can terminate the worker; callers must restore
ordinary editing and must not replay uncertain commits automatically.

Operations: init, info, deploy, schemas, schema, key, select, clear, shutdown.
Init requires an absolute user_dir; optional shared_dir, lua_plugin and require_lua
configure installed resources. Lua paths are trusted native code, not sandboxed.
Info returns protocol=1, worker runtime version, engine version, loaded library,
extensions and resource paths. The editor client rejects protocol mismatches.

Key takes an integer key and optional mask; select takes a zero-based current-page
index. Context returns preedit, ordered candidates, selected index, page/last_page,
handled and an exactly-once consumed commit. Clear advances/retains generation;
other session requests must match it. Frontends must also reject stale responses
against editor anchors. Deploy is explicit and invalidates the native session.

Limitations: API deployment success does not prove every schema component loaded.
Inspect diagnostics and validate actual candidates. Native startup dependency
errors can occur before a JSON response; clients must handle exit/stderr too.

The editor classifies stderr into a bounded set of fixed diagnostic hints; raw
stderr is not persisted or shown. A transient 4 KiB framing tail recognizes split
messages. This is deliberately lossy and does not prove component functionality.
Use actual candidate tests after deployment. Library/API errors, explicit Lua
requirements, missing schemas and writer locks also have framed protocol errors
when startup has reached the protocol loop.

Worker scope stays deliberately narrow: protocol validation, system-engine
lifecycle, one-writer locking and C API/result translation. Candidate ranking,
scheme logic and learning remain in Rime; buffer editing, completion isolation
and display remain in Lua. Initialization and redeployment use the same session
setup path; schema-list allocations are freed by one shared implementation.
Malformed JSON and JSON field-type errors return a fixed message rather than
echoing parser excerpts. Engine/path failures retain actionable diagnostics.
