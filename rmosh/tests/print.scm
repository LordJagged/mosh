(import (rnrs)
        (mosh)
        (only (mosh pp) pp)
        (rnrs mutable-pairs)
        (mosh test))

(define-syntax test-print
  (lambda (x)
    (syntax-case x ()
      [(_ expected expr write-proc)
       (regexp? (syntax->datum #'expected))
       #'(test-true (expected (call-with-values open-string-output-port (lambda (port proc) (write-proc expr port) (proc)))))]
      [(_ expected expr write-proc)
       #'(test-equal expected (call-with-values open-string-output-port (lambda (port proc) (write-proc expr port) (proc))))])))

(define-syntax test-print*
  (lambda (x)
    (syntax-case x ()
      [(_ (expr expected) more ...)
       #'(test-print* (expr expected expected expected) more ...)]
      [(_ (expr display-expected write-expected) more ...)
       #'(test-print* (expr display-expected write-expected write-expected) more ...)]
      [(_ (expr display-expected write-expected pp-expected) more ...)
       #'(begin
           (test-print display-expected expr display)
           (test-print write-expected expr write)
           (test-print (if (string? pp-expected) (string-append pp-expected "\n") pp-expected) expr pp)
           (test-print* more ...))]
      [(_) #'#f])))

(define test-file (if (string=? (host-os) "mona") "/APPS/MOSH.APP/tests/test.txt" "tests/test.txt"))


(test-print* ['(a b) "(a b)"]
             ['(a . b) "(a . b)"]
             [1 "1"]
             [222222222222222222222222222 "222222222222222222222222222"]
             [3.141592 "3.141592"]
             [#\a "a" "#\\a"]
             ['#(a b c) "#(a b c)"]
             ["abc" "abc" "\"abc\""]
             [(open-file-input-port test-file) (format "#<binary-file-input-port ~a>" test-file) (format "#<binary-file-input-port ~a>" test-file) "#[input-port]"]
             [(open-input-file test-file) (format "#<transcoded-textual-input-port #<binary-file-input-port ~a>>" test-file) (format "#<transcoded-textual-input-port #<binary-file-input-port ~a>>" test-file) "#[input-port]"]
             [(open-string-output-port) "#<string-output-port>" "#<string-output-port>" "#[output-port]"]
             [(make-custom-textual-output-port
               "custom out"
               (lambda (str start count) #f)
               (lambda () #f)
               (lambda (pos) #f)
               (lambda () 'ok)) "#<custom-textual-output-port custom out>" "#<custom-textual-output-port custom out>" "#[output-port]"]
             [car #/#<procedure car>/ #/<procedure car>/ "#[procedure]"]
             ['a "a"]
             [(make-eq-hashtable) "#<eq-hashtable>" "#<eq-hashtable>" "#[hashtable]"]
             [(make-eqv-hashtable) "#<eqv-hashtable>" "#<eqv-hashtable>" "#[hashtable]"]
             [(make-hashtable (lambda () '()) eqv?) "#<hashtable>" "#<hashtable>" "#[hashtable]"]
             [#vu8(1 2 3) "#vu8(1 2 3)"]
             [#t "#t"]
             [#f "#f"]
             [#/1/ "#/1/" "#/1/" "#[regexp]"]
             [(#/\d+/ "123") "#<reg-match>" "#<reg-match>" "#[procedure]"]
             [(utf-8-codec) "#<codec utf-8-codec>" "#<codec utf-8-codec>" "#[unknown]"]
             [1/2 "1/2"]
             [1+2i "1+2i"]
             ['() "()"]
;;             [#'a #/.*/ #/.*/ "#[identifier]"]
             ['(quote 3) "'3"]
             ['(QUOTE 3) "'3"]
             ['(quasiquote 3) "`3"]
             ['(QUASIQUOTE 3) "`3"]
             ['(unquote 3) ",3"]
             ['(UNQUOTE 3) ",3"]
             ['(unquote-splicing 3) ",@3"]
             ['(UNQUOTE-SPLICING 3) ",@3"]
;;              ['(syntax a) "#'a"]
;;              ['(SYNTAX a) "#'a"]
;;              ['(quasisyntax 3) "#`3"]
;;              ['(QUASISYNTAX 3) "#`3"]
;;              ['(unsyntax a) "#,a"]
;;              ['(UNSYNTAX a) "#,a"]
;;              ['(unsyntax-splicing a) "#,@a"]
;;              ['(UNSYNTAX-SPLICING a) "#,@a"]
             [(eof-object) "#<eof-object>" "#<eof-object>" "#[eof-object]"]
;             [1.0e99 "1e99"]
             [(if #f #t) "#<unspecified>" "#<unspecified>" "#[unspecified]"] ;; unspecified

)

;; pp can't handle circular structure!
#;(test-print "#1=(val1 . #1#)" (let ([x (cons 'val1 'val2)])
                                (set-cdr! x x)
                                x) write/ss)
#;(test-equal "#1=(val1 . #1#)" (let ([x (cons 'val1 'val2)])
                                (set-cdr! x x)
                                (format "~w" x)))

;; mosh only. Use display/ss
#;(test-equal "#1=(val1 . #1#)" (let ([x (cons 'val1 'val2)])
                                (set-cdr! x x)
                                (format "~e" x)))

(test-equal "+inf.0" (number->string +inf.0))
(test-equal "-inf.0" (number->string -inf.0))
(test-equal "+nan.0" (number->string +nan.0))

(test-equal "\n" (format "~%"))

;; write/ss
#;(let* ([a '(1 2)]
       [x `(,a ,a)])
  (define (write-to-string write-proc obj)
    (call-with-values open-string-output-port (lambda (port proc) (write-proc obj port) (proc))))
  (test-equal "((1 2) (1 2))" (write-to-string write x))
  (test-equal "(#1=(1 2) #1#)" (write-to-string write/ss x))
)

(let-values (((port getter) (open-string-output-port)))
  (display #\alarm port)
  (display #\backspace port)
  (display #\vtab port)
  (display #\page port)
  (test-equal "\a\b\v\f" (getter)))


(test-results)
