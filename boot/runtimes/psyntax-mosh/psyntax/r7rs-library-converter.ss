; Converter from R7RS library to R6RS library.
;
;   Copyright (c) 2022 Higepon(Taro Minowa)  <higepon@users.sourceforge.jp>
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

; N.B. For testablity. This library should not depend on other psyntax files.
(library (psyntax r7rs-library-converter)
  (export rewrite-define-library rewrite-lib-decl* rewrite-program
          rewrite-export path-dirname);; todo clean this up!
  (import (rnrs)
          (rnrs mutable-pairs)
          (except (mosh) available-libraries)
          (match))

  ;; Move this when 0.2.8.rc6 is out.
  (define (available-libraries)
    `((srfi 0) (srfi 1) (srfi 11) (srfi 13) (srfi 133) (srfi 14) (srfi 158) (srfi 16) (srfi 176) (srfi 19) (srfi 194) (srfi 2) (srfi 23) (srfi 26) (srfi 27) (srfi 31) (srfi 37) (srfi 38) (srfi 39) (srfi 41) (srfi 42) (srfi 43) (srfi 48) (srfi 6) (srfi 61) (srfi 64) (srfi 67) (srfi 78) (srfi 8) (srfi 9) (srfi 98) (srfi 99) (srfi 151)
      (mosh)))

  ;; Convert R7RS define-library to R6RS library.
  ;;
  ;; Returns (expanded-library-form and included-file).
  ;; We track included-file for library cache.
  (define (rewrite-define-library dirname exp)
    (match exp
           [('define-library (name* ...) lib-decl* ...)
            (let-values (((lib-decl* export* import* included-file*) (rewrite-lib-decl* dirname lib-decl*)))
              (values `(library ,name* (export ,@export*) (import ,@import*) ,@lib-decl*)
                      included-file*))]
           [else
            (assertion-violation 'rewrite-define-library "malformed library" `(,exp))]))

  ;; Convert R7RS Scheme program to R6RS Scheme program.
  ;;   R7RS small 5.1 Programs.
  ;;   A Scheme program consists of one or more import declarations followed by a sequence of expressions and definitions.
  ;;   We expand cond-expand, include and include-ci in a Scheme program and pass expaneded code to psyntax.
  ;;
  ;; Returns a list of (import ...) + expressions and definitions.
  (define (rewrite-program dirname exp*)
    (let-values (([expanded-exp* import*] (rewrite-program-exp* dirname exp*)))
      `[(import ,@import*) ,@expanded-exp*]))

  (define copy-src-info
    (case-lambda
     [(sexp src-info)
      (copy-src-info sexp src-info (make-eq-hashtable))]
     [(sexp src-info seen)
      (cond
       [(hashtable-ref seen sexp #f) => (lambda (x) x)]
       ;; Don't overwrrite src-info.
       [(and (annotated-pair? sexp) (get-annotation sexp))
        (hashtable-set! seen sexp sexp)
        sexp]
       [(pair? sexp)
        (let ([annotated (annotated-cons '() '())])
          (hashtable-set! seen sexp annotated)
          (set-annotation! annotated src-info)
          (set-car! annotated (copy-src-info (car sexp) src-info seen))
          (set-cdr! annotated (copy-src-info (cdr sexp) src-info seen))
          annotated)]
       [else
        (hashtable-set! seen sexp sexp)
        sexp])]))

  (define rewrite-program-exp*
    (case-lambda
     [(dirname exp*)
      (rewrite-program-exp* dirname exp* '())]
     [(dirname sexp* import*)
      (let loop ([ret '()]
                 [exp* sexp*]
                 [import* import*])
                                        ;(format #t "exp*=~a import=~a ret=~a\n" exp* import* ret)
        (if (null? exp*)
            (values ret import*)
            (let* ([exp (car exp*)]
                   [src-info (and (annotated-pair? exp) (get-annotation exp))])
              (match exp
                     ;; (import <import spec> ... )
                     ;; In R7RS import can appears multiple times but not in R6RS. We have to merge them into one.
                     [('import spec* ...)
                      (loop ret (cdr exp*) (append import* (copy-src-info spec* src-info)))]
                     [('cond-expand clause* ...)
                      (let ([new-exp* (rewrite-cond-expand (car exp*))])
                        (let-values (((new-exp* new-import*) (rewrite-program-exp* dirname new-exp* import*)))
                          (loop (append ret (copy-src-info new-exp* src-info))
                                (cdr exp*) new-import*)))]
                     [((and (or 'include 'include-ci) include-variant) path* ...)
                      ;; Expand it to multiple include and pass it to psyntax later.
                      ;; Note we append dirname to path so that (include "foo.scm") works.
                      (let ([new-exp* (map (lambda (path) `(,include-variant ,(string-append dirname path))) path*)])
                        (loop (append ret (copy-src-info new-exp* src-info)) (cdr exp*) import*))]
                     ;; (define <variable> <expression>)
                     ;; (set! <variable> <expression>)
                     [((and (or 'define 'set!) op) var exp)
                      (let-values (((new-exp* new-import*) (rewrite-program-exp* dirname (list exp) import*)))
                        (loop (append ret (copy-src-info `((,op ,var ,@new-exp*)) src-info))
                              (cdr exp*) new-import*))]
                     ;; (define (<variable> <formals>) <body>
                     ;; (lambda <formals> <body>)
                     [((and (or 'define 'lambda) op) (name . remainder*) body* ...)
                      (let-values (((new-exp* new-import*) (rewrite-program-exp* dirname body* import*)))
                        (loop (append ret (copy-src-info `((,op (,name ,@remainder*) ,@new-exp*)) src-info))
                              (cdr exp*) new-import*))]
                     [('lambda arg body* ...)
                      (let-values (((new-exp* new-import*) (rewrite-program-exp* dirname body* import*)))
                        (loop (append ret (copy-src-info `((lambda ,arg ,@new-exp*)) src-info))
                              (cdr exp*) new-import*))]
                     ;; (cond <clause1> <clause2> ... )
                     [('cond (test* exp** ...) ...)
                      (let-values (((test-exp* new-import*) (rewrite-program-exp* dirname test* import*)))
                        (let-values (((new-exp** new-import*) (rewrite-program-exp** dirname exp** new-import*)))
                          (loop (append ret (copy-src-info `((cond ,@(map (lambda (test-exp new-exp*) `(,test-exp ,@new-exp*)) test-exp* new-exp**))) src-info))
                                (cdr exp*) new-import*)))]
                     ;; (case <key> <clause1> <clause2> ... )
                     [('case key (datum* exp** ...) ...)
                      (let-values (((key-exp* new-import*) (rewrite-program-exp* dirname (list key) import*)))
                        (let-values (((new-exp** new-import*) (rewrite-program-exp** dirname exp** new-import*)))
                          (loop (append ret (copy-src-info `((case ,@key-exp* ,@(map (lambda (datum new-exp*) `(,datum ,@new-exp*)) datum* new-exp**))) src-info))
                                (cdr exp*) new-import*)))]
                     ;; (if <test> <consequent> <alternate>) syntax
                     ;; (if <test> <consequent>) syntax
                     [((and (or 'if 'and 'or 'when 'unless 'begin) if-variant) if-exp* ...)
                      (let-values (((new-exp* new-import*) (rewrite-program-exp* dirname if-exp* import*)))
                        (loop (append ret (copy-src-info `((,if-variant ,@new-exp*)) src-info))
                              (cdr exp*) new-import*))]
                     ;; (let <bindings> <body>)
                     [((and (or 'let 'let* 'letrec 'letrec* 'parameterize) let-variant) ([var* init*] ...) body* ...)
                      (let*-values ([(init-exp* new-import*) (rewrite-program-exp* dirname init* import*)]
                                    [(body-exp* new-import*) (rewrite-program-exp* dirname body* new-import*)])
                        (loop (append ret (copy-src-info `((,let-variant ,(map (lambda (var init) `(,var ,init)) var* init-exp*) ,@body-exp*)) src-info))
                              (cdr exp*) new-import*))]
                     ;; (let <variable> <bindings> <body>)
                     [((and (or 'let 'let* 'letrec 'letrec*) let-variant) name ([var* init*] ...) body* ...)
                      (let*-values ([(init-exp* new-import*) (rewrite-program-exp* dirname init* import*)]
                                    [(body-exp* new-import*) (rewrite-program-exp* dirname body* new-import*)])
                        (loop (append ret (copy-src-info `((,let-variant ,name ,(map (lambda (var init) `(,var ,init)) var* init-exp*) ,@body-exp*)) src-info))
                              (cdr exp*) new-import*))]
                     ;; (let-values <mv binding spec> <body>)
                     ;;   <mv binding spec>: ((<formals> <init>) ...)
                     [((and (or 'let-values 'let*-values) let-values-variant) ([(var** ...) init*] ...) body* ...)
                      (let*-values ([(init-exp* new-import*) (rewrite-program-exp* dirname init* import*)]
                                    [(body-exp* new-import*) (rewrite-program-exp* dirname body* new-import*)])
                        (loop (append ret (copy-src-info `((,let-values-variant (,@(map (lambda (var* init) `(,var* ,init)) var** init-exp*)) ,@body-exp*)) src-info))
                              (cdr exp*) new-import*))]
                     ;; (do ((<variable1> <init1> <step1>) ...)
                     ;;   (<test> <expression> ...)
                     ;;   <command> ...)
                     [('do ((var* init** ...) ...) (test* ...) body* ...)
                      (let*-values ([(init-exp** new-import*) (rewrite-program-exp** dirname init** import*)]
                                    [(test-exp* new-import*) (rewrite-program-exp* dirname test* new-import*)]
                                    [(body-exp* new-import*) (rewrite-program-exp* dirname body* new-import*)])
                        (loop (append ret (copy-src-info `((do (,@(map (lambda (var init*) `(,var ,@init*)) var* init-exp**))
                                                               (,@test-exp*)
                                                             ,@body-exp*)) src-info))
                              (cdr exp*) new-import*))]
                     [('case-lambda ((var** ...) body** ...) ...)
                      (let*-values ([(var-exp** new-import*) (rewrite-program-exp** dirname var** import*)]
                                    [(body-exp** new-import*) (rewrite-program-exp** dirname body** import*)])
                        (loop (append ret (copy-src-info `((case-lambda ,@(map (lambda (var-exp* body-exp*) `(,var-exp* ,@body-exp*)) var-exp** body-exp**))) src-info))
                              (cdr exp*) new-import*))]
                     ;; (quote <datum>)
                     [((or 'quote 'quasiquote) datum)
                      (loop (append ret (list (car exp*)))
                            (cdr exp*) import*)]
                     ;; Procedure call.
                     [(proc arg* ...)
                      (let-values (((new-exp* new-import*) (rewrite-program-exp* dirname (cons proc arg*) import*)))
                        (loop (append ret (copy-src-info `((,@new-exp*)) src-info))
                              (cdr exp*) new-import*))]
                     [any (loop (append ret `(,any)) (cdr exp*) import*)]))))]))

  (define (rewrite-program-exp** dirname exp** import*)
    (let loop ([exp** exp**]
               [new-exp** '()]
               [new-import* import*])
      (if (null? exp**)
          (values new-exp** new-import*)
          (let-values (((new-exp* new-import*) (rewrite-program-exp* dirname (car exp**) new-import*)))
            (loop (cdr exp**) (append new-exp** (list new-exp*)) new-import*)))))

  ;; Rewrite list of <library declaration>and return list of <library declaration>.
  ;;  <library declaration> is any of:
  ;;     (export <export spec> ... )
  ;;     (import <import set> ... )
  ;;     (begin <command or definition> ... )
  ;;     (include <filename1> <filename2> ... )
  ;;     (include-ci <filename1> <filename2> ... )
  ;;     (include-library-declarations <filename1><filename2> ... )
  ;;     (cond-expand <ce-clause1> <ce-clause2> ... )
  (define rewrite-lib-decl*
    (case-lambda
     [(dirname lib-decl*)
      (rewrite-lib-decl* dirname lib-decl* '() '() '())]
     [(dirname lib-decl* export* import* included-file*)
      (let loop ([ret '()]
                 [decl* lib-decl*]
                 [export* export*]
                 [import* import*]
                 [included-file* included-file*])
                                        ;(format #t "decl=~a export=~a import=~a ret=~a\n" decl* export* import* ret)
        (if (null? decl*)
            (values ret (map rewrite-export export*) import* included-file*)
            (match (car decl*)
                   ;; (import <import spec> ... )
                   ;; In R7RS import can appears multiple times but not in R6RS. We have to merge them into one.
                   [('import spec* ...)
                    (loop ret (cdr decl*) export* (append import* spec*) included-file*)]
                   ;; (export <export spec> ... )
                   [('export spec* ...)
                    (loop ret (cdr decl*) (append export* spec*) import* included-file*)]
                   ;; (include <filename1><filename2> ... )
                   [((and (or 'include 'include-ci) include-variant) path* ...)
                    ;; Expand it to multiple include and pass it to psyntax later.
                    ;; Note we append dirname to path so that (include "foo.scm") works.
                    (let ([include-path* (map (lambda (path) (string-append dirname path)) path*)]
                          [new-decl* (map (lambda (path) `(,include-variant ,(string-append dirname path))) path*)])
                      (loop (append ret new-decl*) (cdr decl*) export* import* (append included-file* include-path*)))]
                   ;; (include-library-declarations <filename>)
                   [('include-library-declarations path)
                    (let* ([include-path (string-append dirname path)]
                           [new-decl* (file->sexp-list include-path)])
                      (let-values (((new-decl2* new-export* new-import* new-included*) (rewrite-lib-decl* dirname new-decl* export* import* (append included-file* (list include-path )))))
                        ;; We call rewrite-lib-decl* because expanded include may have something we care about.
                        (loop (append ret new-decl2*)
                              (cdr decl*) new-export* new-import* new-included*)))]
                   ;; (include-library-declarations <filename1><filename2> ... )
                   [('include-library-declarations path* ...)
                    (let ([new-decl* (map (lambda (path) `(include-library-declarations ,path)) path*)])
                      (let-values (((new-decl2* new-export* new-import* new-included*) (rewrite-lib-decl* dirname new-decl* export* import* included-file*)))
                        (loop (append ret new-decl2*)
                              (cdr decl*) new-export* new-import* new-included*)))]
                   [('cond-expand clause* ...)
                    (let ([new-decl* (rewrite-cond-expand (car decl*))])
                      (let-values (((new-decl2* new-export* new-import* new-included*) (rewrite-lib-decl* dirname new-decl* export* import* included-file*)))
                        (loop (append ret new-decl2*)
                              (cdr decl*) new-export* new-import* new-included*)))]
                   [any
                    (loop (append ret `(,any)) (cdr decl*) export* import* included-file*)])))]))

  ;; Returns list of<library declaration>.
  (define (rewrite-cond-expand expr)
                                        ;(format #t "expr=~a\n" expr)
    (match expr
           [(_)
            (assertion-violation 'cond-expand "Unfulfilled cond-expand" expr)]
           [(_ ('else lib-decl* ...))
            lib-decl*]
           [(_ (('and) lib-decl* ...) more-clause* ...)
            lib-decl*]
           [(_ (('and feature1 feature2 ...) lib-decl* ...) more-clause* ...)
            `((cond-expand
               (,feature1
                (cond-expand
                 ((and ,@feature2) ,@lib-decl*) ,@more-clause*))
               ,@more-clause*))]
           [(_ (('or) lib-decl* ...) more-clause* ...)
            `((cond-expand ,@more-clause*))]
           [(_ (('or feature1 feature2 ...) lib-decl* ...) more-clause* ...)
            `((cond-expand
               (,feature1 ,@lib-decl*)
               (else
                (cond-expand
                 ((or ,@feature2) ,@lib-decl*) ,@more-clause*))))]
           [(_ (('not feature) lib-decl* ...) more-clause* ...)
            `((cond-expand (,feature
                            (cond-expand ,@more-clause*))
                           (else ,@lib-decl*)))]
           [(_ ((? symbol? feature) lib-decl* ...) more-clause* ...)
            ;; This feature is available.
            (if (member feature (available-features))
                lib-decl*
                `((cond-expand ,@more-clause*)))]
           [(_ (('library name* ...) lib-decl* ...) more-clause* ...)
            ;; This library is available.
            (if (member (car name*) (available-libraries))
                lib-decl*
                `((cond-expand ,@more-clause*)))]
           [else
            (assertion-violation 'cond-expand "malformed cond-expand" expr)]))

  (define (rewrite-export exp)
    (match exp
           [('rename from to)
            `(rename (,from ,to))]
           [name name]))

  ;; Utilities.
  (define (file->sexp-list file)
    (with-input-from-file file
      (lambda ()
        (let loop ([line (read)]
                   [ret '()])
          (cond
           [(eof-object? line) (reverse ret)]
           [else
            (loop (read) (cons line ret))])))))

  (define (fold1 kons knil lst)
    (if (null? lst)
        knil
        (fold1 kons (kons (car lst) knil) (cdr lst))))


  (define (flatten lists)
    (fold1 (lambda (right left)
             (append left right))
           '() lists))

  ;; from pathutils-nmosh.ss
  (define (path-dirname pth)
    (car (split-dir+base pth)))

  (define (split-dir+base pth)
    (define (itr cur rest)
      (if (pair? rest)
          (if (char=? (car rest) #\/)
              (cons
               (list->string (reverse rest))
               (list->string cur)) ;basename
              (itr (cons (car rest) cur) (cdr rest)))
          (cons "" pth)))
    (let ((p (pathfilter pth)))
      (itr '() (reverse  (string->list p)))))

  (define (run-win32-np?) (string=? "win32" (host-os)))

  (define pathfilter
    (if (run-win32-np?)
        (lambda (str)
          (and (string? str)
               (list->string (map (lambda (e) (if (char=? e #\\) #\/ e)) (string->list str)))))
        (lambda (str) str)))
  )