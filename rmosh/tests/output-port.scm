; output-port.scm - Tests for <output port>
;
;   Copyright (c) 2009  Higepon(Taro Minowa)  <higepon@users.sourceforge.jp>
;
;   Redistribution and use in source and binary forms, with or without
;   modification, are permitted provided that the following conditions
;   are met:
;
;   1. Redistributions of source code must retain the above copyright
;      notice, this list of conditions and the following disclaimer.
;
;   2. Redistributions in binary form must reproduce the above copyright
;      notice, this list of conditions and the following disclaimer in the
;      documentation and/or other materials provided with the distribution.
;
;   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
;   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
;   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
;   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
;   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
;   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
;   TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
;   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
;   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
;   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;
;  $Id$


(import (rnrs)
        (mosh)
        (mosh test)
        (mosh shell)
        (mosh process))

(define (mona?) (string=? (host-os) "mona"))

(define test-txt (if (mona?) "/APPS/MOSH.APP/tests/test.txt" "./tests/test.txt"))
(define test-txt-tmp (if (mona?) "/MEM/test.txt.temp" "./tests/test.txt.temp"))
(define test-utf16 (if (mona?) "/MEM/utf16.txt" "./tests/utf16.txt"))
(define not-exist (if (mona?) "/MEM/not-exist" "./not-exist"))

(define (rm file-name)
  (when (file-exists? file-name)
    (delete-file file-name)))

(define (cp from to)
  (call-with-port (open-file-output-port to (file-options no-fail) (buffer-mode none))
    (lambda (out)
      (call-with-port (open-file-input-port from (file-options no-fail) (buffer-mode none))
        (lambda (in)
          (let ([bv (get-bytevector-all in)])
;            (format #t "cp bv length = ~a\n" (bytevector-length bv))
            (put-bytevector out bv)
            (close-port in)
            (close-port out)))))))

(cp test-txt test-txt-tmp)
(when (mona?)
  (cp "/APPS/MOSH.APP/tests/utf16.txt" test-utf16))

(define (with-all-buffer-mode file proc)
  (let ([tmp-file (format "~a.temp" file)])
    (for-each (lambda (mode)
                (cp file tmp-file)
                (proc mode tmp-file))
              (list (buffer-mode none) (buffer-mode block) (buffer-mode line)))))

(define (empty-file-exists? path)
  (let ([port (open-file-input-port path (file-options))])
    (let ([ret (eof-object? (get-u8 port))])
      (close-port port)
      ret)))

(define (with-all-buffer-mode-simple proc)
    (for-each (lambda (mode)
                (proc mode))
              (list (buffer-mode none) (buffer-mode block) (buffer-mode line))))




(test-false (output-port? (standard-input-port)))
(test-true (output-port? (standard-output-port)))
(test-true (output-port? (standard-error-port)))
(test-false (output-port? (current-input-port)))
(test-true (output-port? (current-output-port)))

(test-equal (output-port-buffer-mode (standard-output-port)) 'line)
(test-equal (output-port-buffer-mode (standard-error-port)) 'none)

;; custom output-port
(let* ([accum '()]
       [p (make-custom-binary-output-port
           "custom out"
           (lambda (bv start count)
             (let ([bv2 (make-bytevector count)])
               (bytevector-copy! bv start bv2 0 count)
               (set! accum (append
                            (reverse (bytevector->u8-list bv2))
                            accum))
               count))
           (lambda () (length accum))
           (lambda (pos) (set! accum (list-tail accum (- (length accum) pos))))
           (lambda () 'ok))])
  (test-true (port-has-port-position? p))
  (test-true (port-has-set-port-position!? p))
  (test-equal (port-position p) 0)
  (put-bytevector p #vu8(2 4 6))
  (flush-output-port p)
  (test-equal accum '(6 4 2))
  (test-equal (port-position p) 3)
  (set-port-position! p 2)
  (test-equal (port-position p) 2)
  (test-equal accum '(4 2))
  (put-bytevector p #vu8(3 7 9 11) 2 1)
  (flush-output-port p)
  (test-equal accum '(9 4 2))
  (close-port p)
  )

#|
(let* ([accum '()]
       [p (make-custom-textual-output-port
           "custom out"
           (lambda (str start count)
             (let ([str (substring str start count)])
               (set! accum (append
                            (reverse (string->list str))
                            accum))
               count))
           (lambda () (length accum))
           (lambda (pos) (set! accum (list-tail accum (- (length accum) pos))))
           (lambda () 'ok))])
  (test-true (port-has-port-position? p))
  (test-true (port-has-set-port-position!? p))
  (test-equal (port-position p) 0)
  (put-string p "ab")
  (test-equal (port-position p) 2)
  (put-string p "c")
  (flush-output-port p)
  (test-equal accum '(#\c #\b #\a))
  (test-equal (port-position p) 3)
  (set-port-position! p 2)
  (test-equal (port-position p) 2)
  (test-equal accum '(#\b #\a))
  (put-string p "xyzw" 2 1)
  (flush-output-port p)
  (test-equal accum '(#\z #\b #\a))
  (close-port p))
|#


;; string-output-port
(let-values (([port get-string] (open-string-output-port)))
;  (test-true (port-has-set-port-position!? port))
 ; (test-true (port-has-port-position? port))
  ;(test-equal (port-position port) 0)
  (display #\a port)
  (test-equal (port-position port) 1)
  (set-port-position! port 2)
  ;(display "cd" port)
  (put-string port "cd")
  (test-equal (port-position port) 4)
  (set-port-position! port 1)
  (display #\b port)
  (test-equal (get-string) "abcd")
  (test-equal (port-position port) 0)
  (test-equal (get-string) "")
  (display #\a port)
  (test-equal (get-string) "a")
  (test-equal (port-position port) 0)
)




(test-results)
