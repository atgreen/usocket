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

Address queries are supported on listeners and connected streams:
`get-local-name`, `get-local-address`, `get-local-port`, `get-peer-name`,
`get-peer-address` and `get-peer-port`. The address is an octet vector -- four
elements for IPv4, sixteen for IPv6 -- which is what `host-to-hostname` and
`vector-to-ipv6-host` already accept, so no conversion happens here. This
requires an EGCL build providing `egcl::%socket-local-name` and
`egcl::%socket-peer-name`; a closed listener signals
`usocket:invalid-socket-error`.

`wait-for-input` is supported on listeners, connected streams and mixed
wait-lists. EGCL answers readiness one descriptor at a time, so a wait-list
holding several sockets is served by rounds of short polls; a single socket --
an accept loop on one listener, which is what zacl and AllegroServe do -- takes
one call with the whole budget and does not poll. This requires an EGCL build
providing `egcl::%socket-listener-ready-p` and
`egcl::%socket-wait-for-input`.

Note that the readiness check does **not** use `LISTEN`. On EGCL a `LISTEN` on
a connected socket loses one octet of pending input
(atgreen/evergreen `bliss-ep1b7`), which would silently corrupt the request
being waited for, so this branch excludes EGCL from the portable `LISTEN`
pre-check in `wait-for-input` alongside the implementations that already cannot
rely on it. Remove that exclusion once the runtime bug is fixed.

This is not yet a complete usocket backend. Character sockets, UDP, Unix-domain
sockets, explicit client local binding, deadlines, and disabling TCP_NODELAY
are not implemented. Unsupported connection options signal `usocket:unimplemented`;
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
