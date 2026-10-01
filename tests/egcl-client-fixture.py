"""Run a Lisp client against a bounded, incremental loopback byte exchange."""
import os
import socket
import subprocess
import sys
import threading

errors = []
timeout = float(os.environ.get("USOCKET_TEST_TIMEOUT", "90"))
with socket.socket() as listener:
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(timeout)

    def serve():
        try:
            with listener.accept()[0] as peer:
                peer.settimeout(10)
                peer.sendall(bytes([65]))
                assert peer.recv(1) == bytes([42]), "missing client acknowledgement"
                peer.sendall(bytes([200, 255]))
        except Exception as error:
            errors.append(error)

    server = threading.Thread(target=serve, daemon=True)
    server.start()
    environment = dict(os.environ, USOCKET_TEST_PORT=str(listener.getsockname()[1]))
    result = subprocess.run(sys.argv[1:], env=environment, timeout=timeout, check=False)
    if result.returncode:
        sys.exit(result.returncode)
    server.join(timeout=12)
    assert not server.is_alive(), "loopback server did not complete"
    assert not errors, errors
print("USOCKET-LOOPBACK-FIXTURE-OK")
