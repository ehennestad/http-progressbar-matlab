# AGENTS.md

Repo-specific guidance for agents working on `webprogress`, the MATLAB toolbox in this repository. The global and MATLAB-level instructions still apply.

## Provenance of the HTTP transfer layers

The resumable download, byte-range upload, multipart progress, progress-callback and data-timeout layers (PRs #25–#31, October 2026) were written by an agent. The maintainer reviewed them for structure, naming and tests, not for HTTP semantics. Their HTTP behaviour is verified by the test suite against the local fixture server rather than by a protocol review. Treat it as test-verified, not as settled.

When you change these layers, the sources of truth are, in this order:

1. The tests in `tests/`, which run against `tests/fixtures/http_status_server.py`. The server's docstring lists its query options: byte ranges, ETags, truncation, delays, redirects, stalled uploads. Extend the server rather than mock the HTTP client.
2. The RFC 9110 sections cited in the comments next to each decision.
3. The observed behaviour of the MATLAB HTTP stack, probed against the fixture server. Established so far (R2025b):
   - `ProgressMonitor.CancelFcn` ends `send` the way Ctrl+C does; no `catch` sees it. A cancel therefore has to be raised as an error from the monitor's progress report.
   - No callback runs while `send` waits for data: not the dialog's, not a timer's, not the monitor's. Only `HTTPOptions.DataTimeout` ends a stalled transfer.
   - A data timeout and a connection timeout share the identifier `MATLAB:webservices:Timeout`; only the message names the `HTTPOptions` property to raise.
   - An error raised inside a progress monitor reaches the caller of `send` as the cause of `MATLAB:http:UncaughtException`. An error raised inside a content consumer's `initialize` reaches it unwrapped.
   - `matlab.net.http.HeaderField` keeps the quotes of an ETag in `If-Range`.

Do not reason about HTTP semantics or the HTTP stack from memory. When a question cannot be answered from these sources, add a knob to the fixture server and a test, or write a probe script against the server, and record the result in this list.

## Tests

Shared test functions live in `tests/helpers`; `tests/fixtures` holds the server fixture, the test spy and the server script. The suite needs `python3` and a Unix shell for the server-backed classes, and CI runs it on the latest MATLAB release. Tests tagged `Graphical` need a display and are skipped on GitHub Actions.
