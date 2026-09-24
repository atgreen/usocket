# TorCL native client backend

This branch adds a conditional TorCL backend to usocket 0.8.8. It currently
supports the binary TCP client operations needed by Dexador: hostnames and
numeric addresses, connection timeouts, receive timeouts, incremental duplex
octet streams, and close. It requires a TorCL build providing
`torcl::%socket-connect` and `torcl::%socket-read-timeout`.

This is not yet a complete usocket backend. Character sockets, UDP, listener
operations, explicit local binding, deadlines, and disabling TCP_NODELAY are
not implemented. Unsupported connection options signal `usocket:unimplemented`;
they are not silently ignored. Connection errors are currently reported as
`usocket:unknown-error` retaining the original condition. DNS resolution is
performed before the connection timeout starts. TLS belongs to the layer above
usocket and is not provided here.

`tests/torcl-client.lisp` exercises real socket I/O after loading usocket.
`tests/torcl-client-fixture.py` runs a supplied Lisp command against a loopback
server and supplies `USOCKET_TEST_PORT` in its environment. The server withholds
the rest of its response until the Lisp client acknowledges the first byte,
so a client that waits for EOF before returning data cannot pass. The same
fixture runs on SBCL; implementation-specific rejection checks are conditional.
