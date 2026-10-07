;;;; Native EGCL TCP byte-stream backend.
;;;; See LICENSE for licensing information.

(in-package :usocket)

(defun egcl-timeout-milliseconds (seconds)
  (when seconds
    (check-type seconds (real (0) *))
    (ceiling (* seconds 1000))))

(defun handle-condition (condition &optional socket host-or-ip)
  (declare (ignore host-or-ip))
  (typecase condition
    (egcl-ext:io-timeout
     (error 'timeout-error :socket socket))
    ((or file-error stream-error)
     (error 'unknown-error :socket socket :real-error condition))))

(defun socket-connect-internal
    (host &key port (protocol :stream) (element-type 'character)
               timeout (connection-timeout nil connection-timeout-p)
               (read-timeout nil read-timeout-p)
               deadline (nodelay nil nodelay-p)
               (local-host nil local-host-p) (local-port nil local-port-p))
  (declare (ignore local-host local-port))
  ;; Reject unsupported requests before opening a descriptor; never silently
  ;; substitute octets for a requested character stream or ignore local binding.
  (unless (eq protocol :stream)
    (error 'unimplemented :feature protocol :context 'socket-connect))
  (unless (equal (egcl-internal::%expand-type-spec element-type)
                 '(unsigned-byte 8))
    (error 'unimplemented :feature element-type :context 'socket-connect))
  (when deadline
    (error 'unimplemented :feature :deadline :context 'socket-connect))
  (when local-host-p
    (error 'unimplemented :feature :local-host :context 'socket-connect))
  (when local-port-p
    (error 'unimplemented :feature :local-port :context 'socket-connect))
  (when (and nodelay-p (not (member nodelay '(t :if-supported))))
    (error 'unimplemented :feature :nodelay :context 'socket-connect))
  (with-mapped-conditions ()
    (let* ((connect-ms (egcl-timeout-milliseconds
                        (if connection-timeout-p connection-timeout timeout)))
           (read-ms (egcl-timeout-milliseconds
                     (if read-timeout-p read-timeout timeout)))
           (stream (egcl::%socket-connect (host-to-hostname host) port connect-ms))
           (socket nil))
      (unwind-protect
           (progn
             (egcl::%socket-read-timeout stream read-ms)
             (setf socket (make-stream-socket :socket stream :stream stream)))
        (unless socket (close stream :abort t))))))

(defmethod socket-close ((socket stream-usocket))
  (close (socket-stream socket)))

(defun socket-listen-internal
    (host &key port reuseaddress (reuse-address nil reuse-address-p)
               (backlog 5) (element-type 'character))
  (unless (equal (egcl-internal::%expand-type-spec element-type)
                 '(unsigned-byte 8))
    (error 'unimplemented :feature element-type :context 'socket-listen))
  (when (pathnamep host)
    (error 'unimplemented :feature :unix-domain-socket :context 'socket-listen))
  (with-mapped-conditions (nil host)
    (let ((listener (egcl::%socket-listen
                     (host-to-hostname host)
                     (or port *auto-port*) backlog
                     (if reuse-address-p reuse-address reuseaddress)))
          (server nil))
      (unwind-protect
           (setf server (make-stream-server-socket listener :element-type element-type))
        (unless server (egcl::%socket-close listener))))))

(defmethod socket-accept ((server stream-server-usocket) &key element-type)
  (unless (equal (egcl-internal::%expand-type-spec
                   (or element-type (element-type server)))
                 '(unsigned-byte 8))
    (error 'unimplemented :feature element-type :context 'socket-accept))
  (with-mapped-conditions (server)
    (let ((stream (egcl::%socket-accept (socket server)))
          (peer nil))
      (unwind-protect
           (setf peer (make-stream-socket :socket stream :stream stream))
        (unless peer (close stream))))))

(defmethod socket-close ((server stream-server-usocket))
  (egcl::%socket-close (socket server)))

(defmethod get-local-port ((server stream-server-usocket))
  (or (egcl::%socket-local-port (socket server))
      (error 'invalid-socket-error :socket server)))
