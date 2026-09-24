;;; Run after ASDF:LOAD-SYSTEM :USOCKET, with a loopback fixture port in the environment.
(let* ((port (parse-integer (uiop:getenv "USOCKET_TEST_PORT")))
       (socket (usocket:socket-connect "127.0.0.1" port
                                       :element-type '(unsigned-byte 8)
                                       :timeout 2))
       (stream (usocket:socket-stream socket)))
  (unwind-protect
       (progn
         (assert (equal '(unsigned-byte 8) (stream-element-type stream)))
         (setf (usocket:socket-option socket :receive-timeout) 3)
         (assert (>= (usocket:socket-option socket :receive-timeout) 3))
         (assert (= 65 (read-byte stream)))
         ;; The peer does not send the rest until this byte arrives.
         (write-byte 42 stream)
         (finish-output stream)
         (assert (= 200 (read-byte stream)))
         (assert (= 255 (read-byte stream)))
         (assert (eq :end (read-byte stream nil :end))))
    (usocket:socket-close socket))
  (assert (not (open-stream-p stream))))
#+torcl
(dolist (options '((:protocol :datagram)
                   (:element-type character)
                   (:element-type (unsigned-byte 8) :deadline 1)
                   (:element-type (unsigned-byte 8) :local-host "127.0.0.1")
                   (:element-type (unsigned-byte 8) :local-port 0)
                   (:element-type (unsigned-byte 8) :nodelay nil)))
  (assert (handler-case
              (progn (apply #'usocket:socket-connect "127.0.0.1" 1 options) nil)
            (usocket:unimplemented () t))))
(format t "USOCKET-NATIVE-CLIENT-OK~%")
