;; Convert VM instruction offset for Rust.
;;   Instructions used in C++ VM are flat such as #(TEST 5 CONSTANT 3 PUSH).
;;   But in Rust VM they are grouped #(Test(5), Constant(3), Push).
;;   For that reason we have to adjust offset.
;;   Note that offsets can be negative for some instructions.

(import (scheme base))
(import (scheme write))
(import (scheme case-lambda))
(import (match))
(import (only (mosh) format))
(import (only (mosh control) let1))
(import (mosh test))
(import (only (srfi :1) take drop))
(import (only (srfi :13) string-join))

;; Instruction with no argument.
(define (arg0-insn? insn)
  (memq insn '(CAR CDR_PUSH)))

;; Instruction with 1 argument.
(define (arg1-insn? insn)
  (or (jump1-insn? insn)
      (memq insn '(CONSTANT REFER_LOCAL RETURN))))

;; Jump instuction with 1 argument.
(define (jump1-insn? insn)
  (memq insn '(BRANCH_NOT_NULL BRANCH_NOT_NUMBER_EQUAL LOCAL_JMP TEST)))

;; Instruction with 2 arguments.
(define (arg2-insn? insn)
  (or (jump2-insn? insn)
      (memq insn '())))      

;; Jump instuction with 2 arguments.
(define (jump2-insn? insn)
  (memq insn '(REFER_LOCAL_BRANCH_NOT_NULL)))

;; Instruction with 3 arguments.
(define (arg3-insn? insn)
  (memq insn '(SHIFTJ)))  

(define adjust-offset
  (case-lambda
    [(insn*)
      (adjust-offset insn* 0)]
    [(insn* start)
      (match (drop insn* start)
        ;; Jump forward.
        [((? jump1-insn? _) (? positive? offset) . more)
          (let1 new-insn* (take more (- offset 1))
            (+ (count-insn* new-insn*) 1))]
        ;; Jump backward.
        [((? jump1-insn? _) (? negative? offset) . more)
          ;; new-insn*
          ;; [...] [destination] ... [jump] [...] => [destination] ...
          (let1 new-insn* (take (drop insn* (+ start offset 1)) (- (abs offset) -1))
            (- (count-insn* new-insn*) 1))]
        [any
          (error (format "adjust-offset: no matching pattern ~a" (and (pair? any) (car any))))])]))

;; Count # of instructions in the sequence.
(define (count-insn* insn*)
  (match insn*
    [() 0]
    [((? arg0-insn? _) . more)
      (+ 1 (count-insn* more))]      
    [((? arg1-insn? _) _arg1 . more)
      (+ 1 (count-insn* more))]
    [((? arg2-insn? _) _arg1 _arg2 . more)
      (+ 1 (count-insn* more))]       
    [((? arg3-insn? _) _arg1 _arg2 _arg3 . more)
      (+ 1 (count-insn* more))]           
    [any
      (error (format "count-insn*: no matching pattern ~a" (and (pair? any) (car any))))]))          

(define (rust-offset insn*)
  ;; Count # of instructions in between jump source and destination.
  ;; Then +1 to get destination offset.
  (+ 1 (count-insn* insn*)))

;; Jump destination is HALT.
(test-equal 2 (adjust-offset '(LOCAL_JMP 3 CONSTANT #t HALT NOP)))

;; Jump destination is HALT.
(test-equal 2 (adjust-offset '(CONSTANT 3 LOCAL_JMP 3 CONSTANT #t HALT NOP) 2))

;; Jump destination is CONSTANT #t
(test-equal 3 (adjust-offset '(TEST 5 CONSTANT #f LOCAL_JMP 3 CONSTANT #t HALT NOP)))

;; Jump destination is REFER_LOCAL 0.
(test-equal 3 (adjust-offset '(BRANCH_NOT_NUMBER_EQUAL 5 REFER_LOCAL 0 RETURN 1 REFER_LOCAL 0 PUSH CONSTANT 1)))

;; Jump source is (LOCAL_JMP -20) and the destination is (REFER_LOCAL_BRANCH_NOT_NULL 0 5).
(test-equal 9 (adjust-offset
                '(ENTER 1 REFER_LOCAL_BRANCH_NOT_NULL 0 5 CONSTANT #t LOCAL_JMP 15 REFER_LOCAL 0 CAR BRANCH_NOT_NULL 10 REFER_LOCAL 0 CDR_PUSH SHIFTJ 1 1 0 LOCAL_JMP -20 LEAVE 1 RETURN 1)
                21))

(test-results)