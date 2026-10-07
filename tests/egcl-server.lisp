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
(dolist (element-type '(character (unsigned-byte 16)))
  (assert (handler-case
              (progn (usocket:socket-listen "127.0.0.1" 0 :element-type element-type) nil)
            (usocket:unimplemented () t))))

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
                       (usocket:unknown-error () nil))))
               (assert (eq reusable rebound))))
        (when peer (usocket:socket-close peer))
        (when client (usocket:socket-close client))
        (usocket:socket-close listener)))))

#+egcl (format t "USOCKET-NATIVE-SERVER-OK~%")
