(library (nmosh io core)
         (export 
           io-dispatch-loop
           io-dispatch
           cleanup
           with-cleanup
           nmosh-io-master-queue

           ;; process
           launch!
           do-launch!
           )
         (import (nmosh io master-queue)
                 (nmosh aio platform win32)
                 (nmosh win32 util) ;; mbcs
                 (yuni core)
                 (yuni util invalid-form)
                 (shorten)
                 (rnrs))

(define-invalid-forms cleanup)

(define Q nmosh-io-master-queue)

(define-syntax with-cleanup
  (syntax-rules (cleanup)
    ((_ form0 ... (cleanup cleanup-form ...))
     (guard (c (#t (let ((result (let () cleanup-form ...)))
                     (when result
                       (raise c)))))
            form0 ...))))

(define (io-dispatch-loop)
  (io-dispatch)
  (io-dispatch-loop))

(define io-dispatch
  (case-lambda
    (() 
     (queue-wait Q)
     (queue-dispatch Q))
    ((timeout) 
     (queue-wait/timeout Q timeout)
     (queue-dispatch Q timeout))))

(define (do-plet-lookup obj sym default)
  (let ((p (assoc sym obj)))
    (if p 
      (cdr p)
      default)))

(define-syntax plet-bind
  (syntax-rules ()
    ((_ obj (prop default))
     (plet-bind obj (prop prop default)))
    ((_ obj (name prop default))
     (define name (do-plet-lookup obj 'prop default)))
    ((_ obj prop)
     (plet-bind obj (prop prop #f)))))

(define-syntax plet
  (syntax-rules ()
    ((_ obj (bind0 ...) body ...)
     (let ()
       (plet-bind obj bind0) ...
       body ...))))

(define-syntax prop-list
  (syntax-rules ()
    ((_) '())
    ((_ (name . prop) next ...)
     (cons (cons 'name prop)
           (prop-list next ...)))))

(define-syntax launch!
  (syntax-rules ()
    ((_ (propent0 propent1 ...))
     (do-launch! (prop-list propent0 propent1 ...)))
    ((_ name (propent0 propent1 ...))
     (letrec ((name (launch! (propent0 propent1 ...))))
       name))))

(define (prop-append prop sym value)
  ;; FIXME: check dupe.
  (append prop
          (list (list sym value))))
(define (prop-replace prop sym value)
  (define (item-name ent) (if (pair? ent) (car ent) ent))
  (if (pair? prop)
    (let ((item (item-name (car prop)))
          (rest (cdr prop)))
      (if (eq? item sym)
        (cons (list sym value) rest)
        (cons (car prop)
              (prop-replace rest sym value))))
    (list (list sym value))))

;; FIXME:stub
(define (fold-launch-prop prop)
  (define (generate-finish finish-clause prop)
    (define (create-g+s/binary)
      (define buffer-list '())
      (define (make-buffer)
        (let ((bv (make-bytevector 4096)))
          (set! buffer-list (cons bv buffer-list))
          (set! current-buffer bv)
          (set! ptr 0)
          bv)) 
      (define (buffer-size) (bytevector-length current-buffer))
      (define (enough-space? size) (< (+ size ptr) (buffer-size)))

      ;; buffer
      (define current-buffer)
      (define ptr)
      
      (define (recv buf offset count) ;; => 0
        ;(display (list 'recv recv offset count))(newline)
        (cond
          (buf
            (cond 
              ((enough-space? count)
               (bytevector-copy! buf offset current-buffer ptr count)
               (set! ptr (+ ptr count))
               0)
              (else
                (let* ((remain (- (buffer-size) ptr))
                       (rest (- count remain)))
                  (bytevector-copy! buf offset current-buffer ptr remain)
                  (make-buffer)
                  (bytevector-copy! buf (+ offset remain) current-buffer 0 rest)
                  (set! ptr rest)
                  0))))
          (else
            (assertion-violation 'aio-receive
                                 "invalid argument"
                                 buf))))

      (define (finish/phase1) ;; => bv
        (define total-size
          (fold-left + 0 (map bytevector-length buffer-list)))
        (define bv (make-bytevector total-size))
        (define (copy-loop ptr cur)
          (when (pair? cur)
            (let* ((rest (cdr cur))
                   (buf (car cur))
                   (size (bytevector-length buf))
                   (next (- ptr size)))
              (bytevector-copy! buf 0 bv next size)
              (copy-loop next rest))))
        (copy-loop total-size buffer-list)
        (set! buffer-list #f) ;; invalidate buffer
        bv)
      (define (finish)
        (cond
          ((= 0 ptr)
           (set! buffer-list (cdr buffer-list)))
          (else
            (let ((rest (cdr buffer-list))
                  (new-buf (make-bytevector ptr)))
              (bytevector-copy! current-buffer 0 new-buf 0 ptr)
              (set! buffer-list (cons new-buf rest)))))
        (finish/phase1))
      (make-buffer) ;; generate first buffer
      (cons recv finish))
    (define (create-g+s/string)
      (let* ((bin (create-g+s/binary))
             (recv/bin (car bin))
             (finish/bin (cdr bin)))
        (define (finish)
          (mbcs->string (finish/bin)))
        (cons recv/bin finish)))
    (define (create-g+s type)
      (define (string-type? x)
        (case x
          ((stdout/bin stderr/bin) #f)
          ((stdout stderr) #t)
          (else (assertion-violation 'launch!
                                     "invalid argument"
                                     x))))
      (if (string-type? type)
        (create-g+s/string)
        (create-g+s/binary)))
    (define (name-bin x)
      (case x
        ((stdout stdout/bin) 'stdout/bin)
        ((stderr stderr/bin) 'stderr/bin)
        (else (assertion-violation 'launch!
                                   "invalid argument"
                                   x))))
    (let ((args (cdar finish-clause))
          (orig-finish (cadr finish-clause)))
      (let ((args-generator+getter (map create-g+s args)))
        (define (invoke p) ((cdr p)))
        (define (finish status)
          (apply orig-finish (cons status 
                                   (map invoke args-generator+getter))))
        (fold-left (^[cur sym e]
                     (prop-append cur (name-bin sym) (car e)))
                   (prop-replace prop 'finish finish)
                   args
                   args-generator+getter))))
  (define (find-finish prop)
    (find (^e (and (pair? (car e)) (eq? (caar e) 'finish)))
                   prop))
  (define (fold-finish prop)
    (let ((finish-clause (find-finish prop)))
      (if finish-clause
        (generate-finish finish-clause prop)
        prop)))
  (fold-finish prop))

;; base property set..
;;  exec = argv[1..]
;;  chdir = string(chdir)
;;  stdout/bin = (^[buf offset count] ...)
;;  stderr/bin = (^[buf offset count] ...)
;;  finish = (^[status] ...)
(define (do-launch! prop)
  (define (pass/in x)
    (if x
      (pipe/in (car x))
      (discard)))
  (define (pass/result x)
    (if x
      (car x)
      (lambda (bogus) 0)))
  (let ((base-prop (fold-launch-prop prop)))
    (plet base-prop (exec chdir stdout/bin stderr/bin finish)
          (queue-process-launch
            Q
            (car exec) ;; FIXME: ...
            chdir
            #f ;; FIXME: implement env*
            (discard) ;; FIXME: implement input
            (pass/in stdout/bin)
            (pass/in stderr/bin)
            (pass/result finish)))))

)
