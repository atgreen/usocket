;;;; Native EGCL TCP byte-stream backend.
;;;; See LICENSE for licensing information.

(in-package :usocket)

(defun egcl-timeout-milliseconds (seconds)
  (when seconds
    (check-type seconds (real (0) *))
    (ceiling (* seconds 1000))))

;;; A failed socket call carries its OS errno, so EADDRINUSE becomes
;;; ADDRESS-IN-USE-ERROR, ECONNREFUSED CONNECTION-REFUSED-ERROR, and so on;
;;; before, every one was an UNKNOWN-ERROR with errno 0 (evergreen #427).
;;; Looked up at run time rather than read as EGCL-EXT:SOCKET-OS-ERROR, so
;;; this backend still loads on an EGCL that predates it and keeps the old
;;; UNKNOWN-ERROR there.
(defun egcl-socket-errno (condition)
  "The OS errno CONDITION carries, or NIL."
  (let ((type (find-symbol "SOCKET-OS-ERROR" "EGCL-EXT"))
        (reader (find-symbol "SOCKET-OS-ERROR-ERRNO" "EGCL-EXT")))
    (when (and type reader (typep condition type))
      (funcall reader condition))))

(defun handle-condition (condition &optional socket host-or-ip)
  (declare (ignore host-or-ip))
  (typecase condition
    (egcl-ext:io-timeout
     (error 'timeout-error :socket socket))
    ((or file-error stream-error)
     (let* ((errno (egcl-socket-errno condition))
            (usock-error (and errno (map-errno-error errno))))
       (if usock-error
           (error usock-error :socket socket)
           (error 'unknown-error :socket socket :real-error condition
                                 :errno (or errno 0)))))))

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
  ;; A listener carries no data, so a character listener -- usocket's default,
  ;; and what a port probe that only listens and closes asks for -- is fine
  ;; here. SOCKET-ACCEPT is where a character stream would be needed, and it
  ;; still refuses one.
  (unless (member (egcl-internal::%expand-type-spec element-type)
                  '(character (unsigned-byte 8)) :test #'equal)
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

;;; Address queries.
;;;
;;; EGCL reports an endpoint as a two-element list of an octet vector and a
;;; port, so one call answers both halves, the way
;;; `sb-bsd-sockets:socket-name' returns them as multiple values. usocket's
;;; HOST-TO-HOSTNAME already accepts a 4-octet vector for IPv4 and a 16-octet
;;; vector for IPv6, which is exactly what the primitive produces, so no
;;; conversion is needed for either family.
;;;
;;; A listener and a connection are different things to EGCL -- a listener is
;;; an integer id, a connection a stream -- and each has its own primitive:
;;; `egcl::%socket-listener-local-name' for the server socket,
;;; `egcl::%socket-local-name' and `egcl::%socket-peer-name' for a connection.
;;; So GET-LOCAL-NAME specializes on the two usocket classes rather than
;;; switching on what `socket' happens to hold.
;;;
;;; GET-LOCAL-NAME and GET-PEER-NAME are the primary operations and the
;;; single-value accessors read off them, as the SBCL backend does.

(defun egcl-endpoint-values (name socket)
  "Spread EGCL's (OCTETS PORT) endpoint list into two values."
  (unless name
    ;; A closed listener answers NIL, matching %SOCKET-LOCAL-PORT.
    (error 'invalid-socket-error :socket socket))
  (values (first name) (second name)))

(defmethod get-local-name ((usocket stream-usocket))
  (with-mapped-conditions (usocket)
    (egcl-endpoint-values (egcl::%socket-local-name (socket usocket)) usocket)))

(defmethod get-local-name ((usocket stream-server-usocket))
  (with-mapped-conditions (usocket)
    (egcl-endpoint-values (egcl::%socket-listener-local-name (socket usocket))
                          usocket)))

(defmethod get-peer-name ((usocket stream-usocket))
  (with-mapped-conditions (usocket)
    (egcl-endpoint-values (egcl::%socket-peer-name (socket usocket)) usocket)))

(defmethod get-local-address ((usocket usocket))
  (nth-value 0 (get-local-name usocket)))

(defmethod get-peer-address ((usocket stream-usocket))
  (nth-value 0 (get-peer-name usocket)))

(defmethod get-peer-port ((usocket stream-usocket))
  (nth-value 1 (get-peer-name usocket)))

;;; Connected sockets had no port query at all; listeners keep the cheaper
;;; %SOCKET-LOCAL-PORT path through the more specific method above.
(defmethod get-local-port ((usocket usocket))
  (nth-value 1 (get-local-name usocket)))

;;; WAIT-FOR-INPUT.
;;;
;;; usocket owns the wait-list struct, its `map' hash table and WAIT-FOR-INPUT
;;; itself; a backend supplies %SETUP-WAIT-LIST, %ADD-WAITER, %REMOVE-WAITER
;;; and WAIT-FOR-INPUT-INTERNAL, which reports readiness by setting each
;;; usocket's STATE to :READ rather than by returning anything.
;;;
;;; EGCL answers readiness one socket at a time -- `%socket-listener-ready-p'
;;; for a listener and `%socket-wait-for-input' for a connected stream, both
;;; taking a millisecond timeout where zero polls and a negative value waits
;;; indefinitely. There is no primitive that waits on several descriptors at
;;; once, so a wait-list holding more than one socket is served by rounds of
;;; short polls over its members. That is the shape the EGCL issue anticipated;
;;; the common case -- an accept loop waiting on a single listener, which is
;;; what zacl and AllegroServe do -- takes one call with the whole budget and
;;; no polling at all.
;;;
;;; WAIT-FOR-INPUT pre-checks stream sockets with LISTEN and passes :timeout 0
;;; when any is already ready, so a zero timeout must poll and return rather
;;; than wait.

(defconstant +egcl-wait-poll-ms+ 20
  "Slice given to each socket per round when a wait-list holds several.
Bounds how long a multi-socket wait can overshoot its deadline, and how often
an idle wait wakes.")

(defun %setup-wait-list (wait-list)
  ;; Nothing implementation-specific to carry: the portable WAIT-LIST-WAITERS
  ;; list is all this backend needs.
  (declare (ignore wait-list))
  nil)

(defun %add-waiter (wait-list waiter)
  (pushnew waiter (wait-list-%wait wait-list)))

(defun %remove-waiter (wait-list waiter)
  (setf (wait-list-%wait wait-list)
        (remove waiter (wait-list-%wait wait-list))))

(defun egcl-socket-ready-p (waiter timeout-ms)
  "Whether WAITER has input available, waiting at most TIMEOUT-MS."
  (etypecase waiter
    (stream-server-usocket
     (and (egcl::%socket-listener-ready-p (socket waiter) timeout-ms) t))
    (stream-usocket
     ;; Deliberately NOT (listen stream): on EGCL a LISTEN on a connected
     ;; socket loses one octet of pending input (atgreen/evergreen
     ;; bliss-ep1b7 -- measured: write 10,20,30 then LISTEN, and the stream
     ;; reads back 20,30). %socket-wait-for-input answers the same question by
     ;; polling a duplicate of the descriptor and consumes nothing, and it
     ;; already reports buffered input as ready, so nothing is lost by
     ;; skipping LISTEN here.
     (and (egcl::%socket-wait-for-input (socket-stream waiter) timeout-ms) t))))

(defun wait-for-input-internal (wait-list &key timeout)
  (with-mapped-conditions ()
    (let* ((waiters (wait-list-%wait wait-list))
           (deadline (when timeout
                       (+ (get-internal-real-time)
                          (* timeout internal-time-units-per-second)))))
      (cond
        ((null waiters) nil)
        ;; One socket: hand it the whole budget, so an accept loop blocks in
        ;; the runtime rather than spinning here. A NIL timeout means wait
        ;; indefinitely, which these primitives spell as a negative value.
        ((null (rest waiters))
         (let ((waiter (first waiters)))
           (when (egcl-socket-ready-p
                  waiter (if timeout (ceiling (* timeout 1000)) -1))
             (setf (state waiter) :read))))
        ;; Several sockets and no primitive that waits on all of them at once:
        ;; poll each in turn until one is ready or the deadline passes. A zero
        ;; timeout makes this exactly one non-blocking pass.
        (t
         (loop
           (let ((ready nil))
             (dolist (waiter waiters)
               (when (egcl-socket-ready-p
                      waiter (if (and timeout (zerop timeout))
                                 0
                                 +egcl-wait-poll-ms+))
                 (setf (state waiter) :read
                       ready t)))
             (when (or ready
                       (and timeout (zerop timeout))
                       (and deadline (>= (get-internal-real-time) deadline)))
               (return ready)))))))))
