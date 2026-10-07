# EGCL native TCP backend

This branch adds a conditional EGCL backend to usocket 0.8.8. It currently
supports the binary TCP client operations needed by Dexador: hostnames and
numeric addresses, connection timeouts, receive timeouts, incremental duplex
octet streams, and close. It requires an EGCL build providing
`egcl::%socket-connect` and `egcl::%socket-read-timeout`.

Binary TCP servers support `socket-listen`, `socket-accept`, `socket-close`,
and `get-local-port` on listeners. Listening supports ephemeral ports, backlog,
and the `reuse-address` option (including the older `reuseaddress` spelling).
Accepted streams inherit the listener's octet element type unless explicitly
overridden with an equivalent octet type. DEFTYPE aliases are accepted.
Listeners can be accepted and closed from another EGCL thread. This requires
an EGCL build with shared native listeners and the four-argument
`egcl::%socket-listen`, plus `%socket-accept`, `%socket-close`, and
`%socket-local-port`.

This is not yet a complete usocket backend. Character sockets, UDP, Unix-domain
sockets, `wait-for-input`, address queries, connected-socket port queries,
explicit client local binding, deadlines, and disabling TCP_NODELAY are
not implemented. Unsupported connection options signal `usocket:unimplemented`;
they are not silently ignored. Connection errors are currently reported as
`usocket:unknown-error` retaining the original condition. DNS resolution is
performed before the connection timeout starts. TLS belongs to the layer above
usocket and is not provided here.

`tests/egcl-client.lisp` exercises real socket I/O after loading usocket.
`tests/egcl-client-fixture.py` runs a supplied Lisp command against a loopback
server and supplies `USOCKET_TEST_PORT` in its environment. The server withholds
the rest of its response until the Lisp client acknowledges the first byte,
so a client that waits for EOF before returning data cannot pass. The same
fixture runs on SBCL; implementation-specific rejection checks are conditional.

`tests/egcl-server.lisp` runs after loading usocket on EGCL. It checks binary
loopback exchanges with cross-thread accept and close, inherited and explicitly
selected octet aliases, EOF, and rejection of unsupported stream element types.
Use a process timeout when running either test so a stalled peer cannot hang
the test invocation indefinitely. These checks exercise TCP, not TLS.
