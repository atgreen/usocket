;;;; Run after ASDF:LOAD-SYSTEM :USOCKET. See LICENSE for licensing information.

(deftype server-test-octet () '(unsigned-byte 8))

#+egcl
(dolist (element-type '((unsigned-byte 8) server-test-octet))
  (let* ((listener (usocket:socket-listen "127.0.0.1" 0
                                         :element-type element-type
                                         :reuse-address t :backlog 2))
         (port (usocket:get-local-port listener)))
    (unwind-protect
         (let* ((worker
                  (egcl-thread:make-thread
                   (lambda ()
                     (assert (= port (usocket:get-local-port listener)))
                     (let ((peer (usocket:socket-accept listener)))
                       (unwind-protect
                            (let ((stream (usocket:socket-stream peer)))
                              (assert (equal '(unsigned-byte 8) (stream-element-type stream)))
                              (assert (= 255 (read-byte stream)))
                              (write-byte 42 stream)
                              (finish-output stream))
                         (usocket:socket-close peer)))
                     (usocket:socket-close listener)
                     :served)))
                (client (usocket:socket-connect "127.0.0.1" port
                                                :element-type '(unsigned-byte 8))))
           (unwind-protect
                (let ((stream (usocket:socket-stream client)))
                  (setf (usocket:socket-option client :receive-timeout) 5)
                  (write-byte 255 stream)
                  (finish-output stream)
                  (assert (= 42 (read-byte stream)))
                  (assert (eq :eof (read-byte stream nil :eof)))
                  (assert (eq :served (egcl-thread:join-thread worker))))
             (usocket:socket-close client)))
      (usocket:socket-close listener))))

#+egcl
(dolist (element-type '((unsigned-byte 16)))
  (assert (handler-case
              (progn (usocket:socket-listen "127.0.0.1" 0 :element-type element-type) nil)
            (usocket:unimplemented () t))))

#+egcl
;;; A character listener -- the default -- binds, reports its port and closes,
;;; which is all a port probe needs. Accepting a character stream from it is
;;; still refused rather than silently handing back octets.
(dolist (options '(() (:element-type character)))
  (let ((listener (apply #'usocket:socket-listen "127.0.0.1" 0 options)))
    (unwind-protect
         (let* ((port (usocket:get-local-port listener))
                (client (usocket:socket-connect "127.0.0.1" port
                                                :element-type '(unsigned-byte 8))))
           (unwind-protect
                (progn
                  (assert (plusp port))
                  (assert (handler-case
                              (progn (usocket:socket-accept listener) nil)
                            (usocket:unimplemented () t)))
                  (usocket:socket-close
                   (usocket:socket-accept listener
                                          :element-type '(unsigned-byte 8))))
             (usocket:socket-close client)))
      (usocket:socket-close listener))))

#+egcl
;;; OS errors arrive as their usocket conditions, not as UNKNOWN-ERROR with
;;; errno 0: a second bind of a live port is ADDRESS-IN-USE-ERROR, and a
;;; connection to a port nobody listens on is CONNECTION-REFUSED-ERROR.
(let* ((listener (usocket:socket-listen "127.0.0.1" 0
                                        :element-type '(unsigned-byte 8)))
       (port (usocket:get-local-port listener)))
  (unwind-protect
       (assert (handler-case
                   (progn (usocket:socket-close
                           (usocket:socket-listen "127.0.0.1" port
                                                  :element-type '(unsigned-byte 8)))
                          nil)
                 (usocket:address-in-use-error () t)))
    (usocket:socket-close listener))
  (assert (handler-case
              (progn (usocket:socket-close
                      (usocket:socket-connect "127.0.0.1" port
                                              :element-type '(unsigned-byte 8)))
                     nil)
            (usocket:connection-refused-error () t))))

#+egcl
(let ((listener (usocket:socket-listen "127.0.0.1" 0
                                      :element-type '(unsigned-byte 8))))
  (unwind-protect
       (progn
         (assert (handler-case
                     (progn (usocket:socket-accept listener :element-type 'character) nil)
                   (usocket:unimplemented () t)))
         (let* ((port (usocket:get-local-port listener))
                (client (usocket:socket-connect "127.0.0.1" port
                                                :element-type '(unsigned-byte 8)))
                (peer (usocket:socket-accept listener :element-type 'server-test-octet)))
           (usocket:socket-close peer)
           (usocket:socket-close client)))
    (usocket:socket-close listener)))

#+egcl
(let ((listener (usocket:socket-listen nil nil :element-type '(unsigned-byte 8))))
  (unwind-protect
       (assert (plusp (usocket:get-local-port listener)))
    (usocket:socket-close listener)))

#+(and egcl linux)
(dolist (case '((t (:reuseaddress t))
                (t (:reuseaddress nil :reuse-address t))
                (nil (:reuseaddress t :reuse-address nil))))
  (destructuring-bind (reusable options) case
    (let* ((listener (apply #'usocket:socket-listen "127.0.0.1" 0
                            :element-type '(unsigned-byte 8) options))
           (port (usocket:get-local-port listener))
           (client nil)
           (peer nil))
      (unwind-protect
           (progn
             (setf client (usocket:socket-connect "127.0.0.1" port
                                                  :element-type '(unsigned-byte 8))
                   peer (usocket:socket-accept listener))
             (usocket:socket-close peer)
             (setf peer nil)
             (assert (eq :eof (read-byte (usocket:socket-stream client) nil :eof)))
             (usocket:socket-close client)
             (setf client nil)
             (usocket:socket-close listener)
             (let ((rebound
                     (handler-case
                         (let ((replacement (usocket:socket-listen
                                             "127.0.0.1" port :reuse-address t
                                             :element-type '(unsigned-byte 8))))
                           (usocket:socket-close replacement)
                           t)
                       (usocket:address-in-use-error () nil))))
               (assert (eq reusable rebound))))
        (when peer (usocket:socket-close peer))
        (when client (usocket:socket-close client))
        (usocket:socket-close listener)))))

#+egcl
;;; Address queries on a listener and on both ends of a connection.
;;;
;;; The cross-checks are the point: the client's PEER port must be the
;;; listener's port, and the server's PEER port must be the client's LOCAL
;;; port. A backend that answered the local address for both ends would satisfy
;;; a shape check and fail both of these.
(let* ((listener (usocket:socket-listen "127.0.0.1" 0 :element-type '(unsigned-byte 8)
                                        :reuse-address t :backlog 2))
       (port (usocket:get-local-port listener))
       (peer nil)
       (client nil))
  (unwind-protect
       (progn
         ;; A listener reports the address it is bound to, and GET-LOCAL-NAME
         ;; answers both halves at once.
         (assert (equalp #(127 0 0 1) (usocket:get-local-address listener)))
         (multiple-value-bind (address listener-port) (usocket:get-local-name listener)
           (assert (equalp #(127 0 0 1) address))
           (assert (= port listener-port)))
         (let ((worker (egcl-thread:make-thread
                        (lambda () (setf peer (usocket:socket-accept listener)) :ok))))
           (setf client (usocket:socket-connect "127.0.0.1" port
                                                :element-type '(unsigned-byte 8)))
           (egcl-thread:join-thread worker))
         (dolist (socket (list peer client))
           (assert (equalp #(127 0 0 1) (usocket:get-local-address socket)))
           (assert (equalp #(127 0 0 1) (usocket:get-peer-address socket)))
           (assert (plusp (usocket:get-local-port socket)))
           (assert (plusp (usocket:get-peer-port socket))))
         ;; The accepted socket is bound to the listener's port.
         (assert (= port (usocket:get-local-port peer)))
         ;; Opposite ends, not the same one twice.
         (assert (= port (usocket:get-peer-port client)))
         (assert (= (usocket:get-local-port client) (usocket:get-peer-port peer)))
         ;; usocket's own helper consumes the octet vector.
         (assert (string= "127.0.0.1"
                          (usocket:host-to-hostname
                           (usocket:get-peer-address client)))))
    (when peer (usocket:socket-close peer))
    (when client (usocket:socket-close client))
    (usocket:socket-close listener))
  ;; A closed listener signals rather than answering a stale address.
  (assert (eq :invalid
              (handler-case (progn (usocket:get-local-name listener) :no-error)
                (usocket:invalid-socket-error () :invalid)))))

#+egcl (format t "USOCKET-NATIVE-SERVER-OK~%")

#+egcl
;;; WAIT-FOR-INPUT over a listener, a connected stream, and a mixed wait-list.
;;;
;;; The assertion that matters most is that the waited-on data SURVIVES: a
;;; readiness check that consumed an octet would still satisfy every "is it
;;; ready" assertion while silently corrupting the stream, which is what a
;;; LISTEN-based check does on EGCL (atgreen/evergreen bliss-ep1b7).
(let* ((listener (usocket:socket-listen "127.0.0.1" 0 :element-type '(unsigned-byte 8)
                                        :reuse-address t :backlog 2))
       (port (usocket:get-local-port listener))
       (client nil)
       (peer nil))
  (unwind-protect
       (progn
         ;; An idle listener times out rather than reporting a connection.
         (assert (null (usocket:wait-for-input listener :timeout 1 :ready-only t)))
         (setf client (usocket:socket-connect "127.0.0.1" port
                                              :element-type '(unsigned-byte 8)))
         ;; A pending connection is reported.
         (assert (usocket:wait-for-input listener :timeout 5 :ready-only t))
         (setf peer (usocket:socket-accept listener))
         ;; An idle connected stream times out.
         (assert (null (usocket:wait-for-input peer :timeout 1 :ready-only t)))
         (write-byte 42 (usocket:socket-stream client))
         (force-output (usocket:socket-stream client))
         (assert (usocket:wait-for-input peer :timeout 5 :ready-only t))
         ;; The octet the wait reported must still be there to read.
         (assert (= 42 (read-byte (usocket:socket-stream peer))))
         ;; A mixed wait-list exercises the round-robin path.
         (let ((wait-list (usocket:make-wait-list (list listener peer))))
           (assert (null (usocket:wait-for-input wait-list :timeout 1 :ready-only t)))
           (write-byte 7 (usocket:socket-stream client))
           (force-output (usocket:socket-stream client))
           (let ((ready (usocket:wait-for-input wait-list :timeout 5 :ready-only t)))
             (assert (= 1 (length ready)))
             (assert (eq peer (first ready))))
           ;; And again, nothing was consumed by the wait.
           (assert (= 7 (read-byte (usocket:socket-stream peer))))))
    (when peer (usocket:socket-close peer))
    (when client (usocket:socket-close client))
    (usocket:socket-close listener)))

#+egcl (format t "USOCKET-WAIT-FOR-INPUT-OK~%")
