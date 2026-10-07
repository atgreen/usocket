;;;; See LICENSE for licensing information.
;;;; Load after USOCKET on EGCL; uses only local loopback sockets.

(defun check-egcl-read-timeout (options expected-timeout)
  (let ((server (usocket:socket-listen "127.0.0.1" 0
                                     :element-type '(unsigned-byte 8)))
        (client nil)
        (peer nil))
    (unwind-protect
         (progn
           (setf client (apply #'usocket:socket-connect "127.0.0.1"
                               (usocket:get-local-port server)
                               :element-type '(unsigned-byte 8) options)
                 peer (usocket:socket-accept server))
           (let ((stream (usocket:socket-stream client)))
             (assert (eql expected-timeout (egcl::%socket-read-timeout stream)))
             (when expected-timeout
               (dotimes (attempt 2)
                 (let ((started (get-internal-real-time)))
                   (assert
                    (handler-case (progn (read-byte stream) nil)
                      (stream-error () t)))
                   (let ((elapsed (/ (- (get-internal-real-time) started)
                                     internal-time-units-per-second)))
                     (assert (>= elapsed (/ expected-timeout 2000)))
                     (assert (< elapsed 2)))))
               (assert
                (handler-case
                    (usocket:with-mapped-conditions (client)
                      (read-byte stream)
                      nil)
                  (usocket:timeout-error (condition)
                    (eq client (usocket:usocket-socket condition))))))
             (write-byte 42 (usocket:socket-stream peer))
             (force-output (usocket:socket-stream peer))
             (assert (= 42 (read-byte stream)))))
      (when client (usocket:socket-close client))
      (when peer (usocket:socket-close peer))
      (usocket:socket-close server))))

(check-egcl-read-timeout '(:timeout 1/20) 50)
(check-egcl-read-timeout '(:timeout 1 :connection-timeout 1/2 :read-timeout 1/20) 50)
(check-egcl-read-timeout '(:timeout 1/20 :read-timeout nil) nil)
(check-egcl-read-timeout '(:read-timeout 1/20) 50)
(check-egcl-read-timeout nil nil)
(format t "USOCKET-READ-TIMEOUT-PASS~%")
(finish-output)
