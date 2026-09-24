;;;; Native TorCL TCP byte-stream client backend.
;;;; See LICENSE for licensing information.

(in-package :usocket)

(defun torcl-timeout-milliseconds (seconds)
  (when seconds
    (check-type seconds (real (0) *))
    (ceiling (* seconds 1000))))

(defun handle-condition (condition &optional socket host-or-ip)
  (declare (ignore host-or-ip))
  (when (typep condition '(or file-error stream-error))
    (error 'unknown-error :socket socket :real-error condition)))

(defun socket-connect-internal
    (host &key port (protocol :stream) (element-type 'character)
               timeout deadline (nodelay nil nodelay-p)
               (local-host nil local-host-p) (local-port nil local-port-p))
  (declare (ignore local-host local-port))
  ;; Reject unsupported requests before opening a descriptor; never silently
  ;; substitute octets for a requested character stream or ignore local binding.
  (unless (eq protocol :stream)
    (error 'unimplemented :feature protocol :context 'socket-connect))
  (unless (equal element-type '(unsigned-byte 8))
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
    (let ((stream (torcl::%socket-connect (host-to-hostname host) port
                                         (torcl-timeout-milliseconds timeout))))
      (make-stream-socket :socket stream :stream stream))))

(defmethod socket-close ((socket stream-usocket))
  (close (socket-stream socket)))
