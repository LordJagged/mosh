;; Write Rust VM Ops as binary.
;(import (only (rust_jump) adjust-offset))
(import (match))
(import (mosh control))
(import (mosh test))
(import (only (mosh) format regexp-replace-all rxmatch))
(import (only (rnrs) set! bytevector-s64-native-set! bytevector-u32-native-set! bytevector-u16-native-set! open-bytevector-output-port put-u8 put-bytevector))
(import (only (rnrs) open-string-output-port string-titlecase bytevector->u8-list))
(import (rnrs arithmetic flonums))
(import (only (rnrs r5rs) modulo))
(import (only (srfi :1) list-ref))
(import (only (srfi :1) take drop))
(import (only (srfi :13) string-delete string-join))
(import (rnrs arithmetic fixnums))
(import (rust_sexp))
(import (scheme base))
(import (scheme case-lambda))
(import (scheme file))
(import (scheme process-context))
(import (scheme read))
(import (scheme write))

(define TAG_FIXNUM 0)
(define TAG_TRUE   1)
(define TAG_FALSE  2)
(define TAG_NIL    3)
(define TAG_CHAR   4)
(define TAG_SYMBOL 5)
(define TAG_STRING 6)
(define TAG_PAIR   7)
(define TAG_VECTOR 8)
(define TAG_COMPILER_INSN 9)

;; Generated by gen_insn_num.scm
(define COMPILE_ERROR 0)
(define BRANCH_NOT_LE 1)
(define BRANCH_NOT_GE 2)
(define BRANCH_NOT_LT 3)
(define BRANCH_NOT_GT 4)
(define BRANCH_NOT_NULL 5)
(define BRANCH_NOT_NUMBER_EQUAL 6)
(define BRANCH_NOT_EQ 7)
(define BRANCH_NOT_EQV 8)
(define BRANCH_NOT_EQUAL 9)
(define APPEND2 10)
(define CALL 11)
(define APPLY 12)
(define PUSH 13)
(define ASSIGN_FREE 14)
(define ASSIGN_GLOBAL 15)
(define ASSIGN_LOCAL 16)
(define BOX 17)
(define CAAR 18)
(define CADR 19)
(define CAR 20)
(define CDAR 21)
(define CDDR 22)
(define CDR 23)
(define CLOSURE 24)
(define CONS 25)
(define CONSTANT 26)
(define DEFINE_GLOBAL 27)
(define DISPLAY 28)
(define ENTER 29)
(define EQ 30)
(define EQV 31)
(define EQUAL 32)
(define FRAME 33)
(define INDIRECT 34)
(define LEAVE 35)
(define LET_FRAME 36)
(define LIST 37)
(define LOCAL_JMP 38)
(define MAKE_CONTINUATION 39)
(define MAKE_VECTOR 40)
(define NOP 41)
(define NOT 42)
(define NULL_P 43)
(define NUMBER_ADD 44)
(define NUMBER_EQUAL 45)
(define NUMBER_GE 46)
(define NUMBER_GT 47)
(define NUMBER_LE 48)
(define NUMBER_LT 49)
(define NUMBER_MUL 50)
(define NUMBER_DIV 51)
(define NUMBER_SUB 52)
(define PAIR_P 53)
(define READ 54)
(define READ_CHAR 55)
(define REDUCE 56)
(define REFER_FREE 57)
(define REFER_GLOBAL 58)
(define REFER_LOCAL 59)
(define RESTORE_CONTINUATION 60)
(define RETURN 61)
(define SET_CAR 62)
(define SET_CDR 63)
(define SHIFT 64)
(define SYMBOL_P 65)
(define TEST 66)
(define VALUES 67)
(define RECEIVE 68)
(define UNFIXED_JUMP 69)
(define STOP 70)
(define SHIFTJ 71)
(define UNDEF 72)
(define VECTOR_LENGTH 73)
(define VECTOR_P 74)
(define VECTOR_REF 75)
(define VECTOR_SET 76)
(define PUSH_ENTER 77)
(define HALT 78)
(define CONSTANT_PUSH 79)
(define NUMBER_SUB_PUSH 80)
(define NUMBER_ADD_PUSH 81)
(define PUSH_CONSTANT 82)
(define PUSH_FRAME 83)
(define CAR_PUSH 84)
(define CDR_PUSH 85)
(define SHIFT_CALL 86)
(define NOT_TEST 87)
(define REFER_GLOBAL_CALL 88)
(define REFER_FREE_PUSH 89)
(define REFER_LOCAL_PUSH 90)
(define REFER_LOCAL_PUSH_CONSTANT 91)
(define REFER_LOCAL_PUSH_CONSTANT_BRANCH_NOT_LE 92)
(define REFER_LOCAL_PUSH_CONSTANT_BRANCH_NOT_GE 93)
(define REFER_LOCAL_PUSH_CONSTANT_BRANCH_NOT_NUMBER_EQUAL 94)
(define REFER_LOCAL_BRANCH_NOT_NULL 95)
(define REFER_LOCAL_BRANCH_NOT_LT 96)
(define REFER_FREE_CALL 97)
(define REFER_GLOBAL_PUSH 98)
(define REFER_LOCAL_CALL 99)
(define LOCAL_CALL 100)
(define VECTOR 101)
(define SIMPLE_STRUCT_REF 102)
(define DYNAMIC_WINDERS 103)
(define TAIL_CALL 104)
(define LOCAL_TAIL_CALL 105)

  (define adjust-offset
    (case-lambda
      [(insn*)
        (adjust-offset insn* 0)]
      [(insn* start)
        (match (drop insn* start)
          ;; Closure size.
          [(('*insn* 24) size _arg-len _optional? _num-free-vars _stack-size _src . more)
            ;; size is based on postition of size we substruct len(_arglen _optional? _num-free-vars _starc-size _src).
            (let1 new-insn* (take more (- size 5 1))
              (+ (count-insn* new-insn*) 1))]          
          ;; Jump forward.
          [(('*insn* (? jump1-insn? _)) (? positive? offset) . more)
            (let1 new-insn* (take more (- offset 1))
              (+ (count-insn* new-insn*) 1))]
          [(('*insn* (? jump2-insn? _)) _arg1 (? positive? offset) . more)
            (let1 new-insn* (take more (- offset 1))
              (+ (count-insn* new-insn*) 1))]   
          [(('*insn* (? jump3-insn? _)) _arg1 _arg2 (? positive? offset) . more)
            (let1 new-insn* (take more (- offset 1))
              (+ (count-insn* new-insn*) 1))]                        
          ;; Jump backward.
          [(('*insn* (? jump1-insn? _)) (? negative? offset) . more)
            ;; new-insn*
            ;; [...] [destination] ... [jump] [...] => [destination] ...
            (let1 new-insn* (take (drop insn* (+ start offset 1)) (- (abs offset) -1))
              (* -1 (- (count-insn* new-insn*) 1)))]            
          [any
            (error (format "adjust-offset: no matching pattern ~a" (take any 3)))])]))
  
  ;; Count # of instructions in the sequence.
  (define (count-insn* insn*)
    (match insn*
      [() 0]
      [(('*insn*  (? arg0-insn? _)) . more)
        (+ 1 (count-insn* more))]      
      [(('*insn* (? arg1-insn? _)) _arg1 . more)
        (+ 1 (count-insn* more))]
      [(('*insn* (? arg2-insn? _)) _arg1 _arg2 . more)
        (+ 1 (count-insn* more))]       
      [(('*insn* (? arg3-insn? _)) _arg1 _arg2 _arg3 . more)
        (+ 1 (count-insn* more))]    
      [(('*insn* (? arg6-insn? _)) _arg1 _arg2 _arg3 _arg4 _arg5 _arg6 . more)
        (+ 1 (count-insn* more))]                
      [any
        (error (format "count-insn*: no matching pattern ~a" (and (pair? any) (car any))))]))          


  ;; Instruction with no argument.
  (define (arg0-insn? insn)
    (memq insn (list APPEND2 CAAR CADR CAR CAR_PUSH CDAR CDDR
                 CDR CDR_PUSH CONS EQ EQUAL EQV HALT
                 INDIRECT MAKE_VECTOR NOP NOT NULL_P
                 NUMBER_ADD NUMBER_ADD_PUSH
                 NUMBER_DIV NUMBER_EQUAL NUMBER_GE NUMBER_GT
                 NUMBER_LE NUMBER_LT NUMBER_MUL NUMBER_SUB NUMBER_SUB_PUSH
                 PAIR_P
                 PUSH READ_CHAR SET_CAR SET_CDR
                 SIMPLE_STRUCT_REF SYMBOL_P UNDEF
                 VECTOR_LENGTH VECTOR_P VECTOR_REF VECTOR_SET)))

  ;; Instruction with 1 argument.
  (define (arg1-insn? insn)
    (or (jump1-insn? insn)
        (memq insn (list ASSIGN_FREE ASSIGN_GLOBAL ASSIGN_LOCAL
                     BOX CALL CONSTANT CONSTANT_PUSH
                     DISPLAY ENTER LEAVE LET_FRAME LIST
                     LOCAL_CALL MAKE_CONTINUATION PUSH_CONSTANT
                     PUSH_ENTER REFER_FREE REFER_FREE_PUSH
                     REFER_GLOBAL REFER_GLOBAL_PUSH
                     REFER_LOCAL REFER_LOCAL_PUSH RETURN VALUES VECTOR))))

  ;; Jump instuction with 1 argument.
  (define (jump1-insn? insn)
    (memq insn (list BRANCH_NOT_EQ BRANCH_NOT_EQUAL BRANCH_NOT_EQV BRANCH_NOT_GE
                 BRANCH_NOT_GT BRANCH_NOT_LE BRANCH_NOT_LT BRANCH_NOT_NULL
                 BRANCH_NOT_NUMBER_EQUAL FRAME LOCAL_JMP NOT_TEST
                 PUSH_FRAME TEST)))

  ;; Instruction with 2 arguments.
  (define (arg2-insn? insn)
    (or (jump2-insn? insn)
        (memq insn (list LOCAL_TAIL_CALL RECEIVE REFER_FREE_CALL REFER_GLOBAL_CALL
                     REFER_LOCAL_CALL REFER_LOCAL_PUSH_CONSTANT TAIL_CALL)))) 

  ;; Jump instuction with 2 arguments.
  (define (jump2-insn? insn)
    (memq insn (list REFER_LOCAL_BRANCH_NOT_LT REFER_LOCAL_BRANCH_NOT_NULL)))

  ;; Instruction with 3 arguments.
  (define (arg3-insn? insn)
    (or (jump3-insn? insn)
        (memq insn (list SHIFTJ))))

  ;; Jump instuction with 3 arguments.
  (define (jump3-insn? insn)
    (memq insn (list REFER_LOCAL_PUSH_CONSTANT_BRANCH_NOT_LE
                REFER_LOCAL_PUSH_CONSTANT_BRANCH_NOT_GE)))    

  ;; Instruction with 6 arguments.
  (define (arg6-insn? insn)
    (memq insn (list CLOSURE)))    

(define (put-s64 port n)
  (let1 bv (make-bytevector 8)
     (bytevector-s64-native-set! bv 0 n)
     (put-bytevector port bv)))

(define (put-u32 port n)
  (let1 bv (make-bytevector 4)
     (bytevector-u32-native-set! bv 0 n)
     (put-bytevector port bv)))

(define (put-u16 port n)
  (let1 bv (make-bytevector 2)
     (bytevector-u16-native-set! bv 0 n)
     (put-bytevector port bv)))

(define write-sexp
  (case-lambda
    [(port c)
      (match c
        [('*compiler-insn* (? number? op))
          (put-u8 port TAG_COMPILER_INSN)
          (put-s64 port op)]
        [(? char? c)
          (put-u8 port TAG_CHAR)
          (put-u32 port (char->integer c))]
        [(? fixnum? n)
          (put-u8 port TAG_FIXNUM)
          (put-s64 port n)]
        [(? symbol? s)
          (put-u8 port TAG_SYMBOL)
          (let1 str (symbol->string s)
            (put-u16 port (string-length str))
            (for-each
              (lambda (c)
                (put-u32 port (char->integer c)))
              (string->list str)))]
        [(? string? str)
          (put-u8 port TAG_STRING)
          (put-u16 port (string-length str))
          (for-each
            (lambda (c)
              (put-u32 port (char->integer c)))
            (string->list str))]
        [(first . second)
          (put-u8 port TAG_PAIR)
          (write-sexp port first)
          (write-sexp port second)]
        [#t
          (put-u8 port TAG_TRUE)]
        [#f
          (put-u8 port TAG_FALSE)]
        [()
          (put-u8 port TAG_NIL)]
        [(? vector? v)
          (put-u8 port TAG_VECTOR)
          (put-u16 port (vector-length v))
          (for-each
            (lambda (o)
              (write-sexp port o))
            (vector->list v))]
        [(? flonum? f)
          ;; TODO
          (write-sexp port 0)]
        [any
          (error (format "unknown sexp = ~a" any))]
      )]
    [(c)
      (let-values ([(p get) (open-bytevector-output-port)])
        (write-sexp p c)
        (get))]))

(define (write-op port tag . args)
  (put-u8 port tag)
  (for-each
    (lambda (arg)
      (write-sexp port arg))
    args))

(define (write-op->bv tag . args)
  (let-values ([(port get) (open-bytevector-output-port)])
    (apply write-op port tag args)
    (get)))

(test-equal #vu8(0 3 0 0 0 0 0 0 0) (write-sexp 3))
(test-equal #vu8(1) (write-sexp #t))
(test-equal #vu8(2) (write-sexp #f))
(test-equal #vu8(3) (write-sexp '()))
(test-equal #vu8(4 97 0 0 0) (write-sexp #\a))
(test-equal #vu8(5 5 0 104 0 0 0 101 0 0 0 108 0 0 0 108 0 0 0 111 0 0 0) (write-sexp 'hello))
(test-equal #vu8(6 3 0 97 0 0 0 98 0 0 0 99 0 0 0) (write-sexp "abc"))
(test-equal #vu8(7 5 1 0 97 0 0 0 3) (write-sexp '(a)))

(test-equal #vu8(26 7 5 1 0 97 0 0 0 3) (write-op->bv CONSTANT '(a)))
(test-equal #vu8(24 0 34 0 0 0 0 0 0 0 0 2 0 0 0 0 0 0 0 2 0 10 0 0 0 0 0 0 0) (write-op->bv CLOSURE 34 2 #f 10))
(test-equal #vu8(59 0 1 0 0 0 0 0 0 0) (write-op->bv REFER_LOCAL 1))

(test-results)

;; Enable debug log.
(define debug? #f)
(define (log str . args)
  (when debug?
    (apply format (current-error-port) str args)))

(define (insn->string insn)
  (string-delete (lambda (c) (equal? c #\_)) (string-titlecase  (symbol->string insn))))

;; Instruction with 1 symbol argument.
(define (sym1-insn? insn)
  (memq insn (list ASSIGN_GLOBAL DEFINE_GLOBAL REFER_GLOBAL REFER_GLOBAL_PUSH)))

;; Constant instruction with 1 argument.
(define (const1-insn? insn)
  (memq insn (list CONSTANT CONSTANT_PUSH PUSH_CONSTANT)))

;; Constant instruction with 2 arguments.
(define (const2-insn? insn)
  (memq insn (list REFER_LOCAL_PUSH_CONSTANT)))

(define (for-each-with-index proc lst)
  (do ((i 1 (+ i 1)) ; start with 1
       (lst lst (cdr lst)))
      ((null? lst))
    (proc i (car lst))))  

(define rewrite-insn*
  (case-lambda
   [(all-insn* insn*)
    (let-values ([(port get) (open-bytevector-output-port)])
      (rewrite-insn* all-insn* insn* 0 port)
      (let* ([u8* (get)]
             [u8* (bytevector->u8-list u8*)])
        u8*))]
   [(all-insn* insn* idx port)
     ;(log "insn*=~a idx=~a~n" (if (null? insn*) 'done (car insn*)) (if (null? insn*) 'done (list-ref all-insn* idx)))
     (let1 indent "            "
       (match insn*
          ;; Closure
          [(('*insn* 24) size arg-len optional? num-free-vars _stack-size _src . more*)
            (write-op port CLOSURE (adjust-offset all-insn* idx) arg-len optional? num-free-vars)
            (rewrite-insn* all-insn* more* (+ idx 7) port)]
          ;; 0 arg instructions.
          [(('*insn* (? arg0-insn? tag)) . more*)
            (write-op port tag)
            (rewrite-insn* all-insn* more*  (+ idx 1) port)]
          ;; 1 arg jump instruction.
          [(('*insn* (? jump1-insn? tag)) offset . more*)
            (write-op port tag (adjust-offset all-insn* idx))
            (rewrite-insn* all-insn* more* (+ idx 2) port)]
          ;; CONSTANT family with 1 arg.
          [(('*insn* (? const1-insn? tag)) v . more*)
            (write-op port tag v)
            (rewrite-insn* all-insn* more* (+ idx 2) port)]
          ;; GLOBAL family with 1 symbol argument.
          [(('*insn* (? sym1-insn? tag)) (? symbol? n) . more*)
            (write-op port tag n)
            (rewrite-insn* all-insn* more* (+ idx 2) port)]
          ;; Other 1 arg instructions.
          [(('*insn* (? arg1-insn? tag)) n . more*)
            (write-op port tag n)
            (rewrite-insn* all-insn* more* (+ idx 2) port)]
          ;; 2 args jump instructions.
          [(('*insn* (? jump2-insn? tag)) m offset . more*)
            (write-op port tag m (adjust-offset all-insn* idx))
            (rewrite-insn* all-insn* more* (+ idx 3) port)]
          ;; CONSTANT family with 2 args.
          [(('*insn* (? const2-insn? tag)) m v . more*)
            (write-op port tag m v)
            (rewrite-insn* all-insn* more* (+ idx 3) port)]
          [(('*insn* 88) (? symbol? s) n . more*)
            (write-op port REFER_GLOBAL_CALL s n)
            (rewrite-insn* all-insn* more* (+ idx 3) port)]
          ;; Other 2 args insturctions.
          [(('*insn* (? arg2-insn? tag)) m n . more*)
            (write-op port tag m n)
            (rewrite-insn* all-insn* more* (+ idx 3) port)]
          ;; REFER_LOCAL_PUSH_CONSTANT_BRANCH_NOT_LE
          [(('*insn* 92) m v offset . more*)
            (write-op port REFER_LOCAL_PUSH_CONSTANT_BRANCH_NOT_LE m v (adjust-offset all-insn* idx))          
            (rewrite-insn* all-insn* more* (+ idx 4) port)]
          ;; 3 arg jump instructions.
          ;;   Note that jump3-insn? should be evaluate first before arg3-insn.
          ;;   Because arg3-insn? include jump3-insn?
          [(('*insn* (? jump3-insn? tag)) l m offset . more*)
            (write-op port tag l m (adjust-offset all-insn* idx))
            (rewrite-insn* all-insn* more* (+ idx 4) port)]
          ;; Other 3 arg instructions.
          [(('*insn* (? arg3-insn? tag)) l m n . more*)
            (write-op port tag l m n)
            (rewrite-insn* all-insn* more* (+ idx 4) port)]
          [() #f]
          [else (error "unknown insn" (car insn*) (cadr insn*))]))]))

(define (file->sexp* file)
  (call-with-input-file file
    (lambda (p)
      (let loop ([sexp (read p)]
                 [sexp* '()])
        (cond
         [(eof-object? sexp) (reverse sexp*)]
         [else
          (loop (read p) (cons sexp sexp*))])))))

(define (main args)
  (let-values ([(port get) (open-string-output-port)])
    (let* ([op-file (cadr args)]
           [sexp* (file->sexp* op-file)]
           [insn* (vector->list (car sexp*))]
           [u8* (rewrite-insn* insn* insn*)]
           [decl-str (and (gen-code port) (get))])
      (display "pub static BIN_COMPILER: &[u8] = &[\n")
      (for-each-with-index
        (lambda (i u8)
          (format #t "~a," u8)
          (if (and (not (zero? i)) (zero? (modulo i 50)))
            (newline)))
        u8*)
      (display "];\n"))))

(main (command-line))
