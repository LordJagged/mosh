;; http://home.earthlink.net/~krautj/sassy/sassy-Z-H-7.html#node_sec_5.1.1

;       movq    80(%rsp), %rbx

;;     Object ac_;  // accumulator     register
;;     Object dc_;  // display closure register, used for refer-free
;;     Object cl_;  // current closure register, used for profiler.
;;     Object* fp_; // frame pointer   register
;;     Object* sp_; // stack pointer   register
;;     Object* pc_; // program counter register

(define vm-register* '(ac dc cl fp sp pc))

;; VM register offset depends on your architecture.
(include/resolve ("mosh" "jit") "offset.ss")

(define (vm-register reg)
  `(& rdi ,(* (+ (receive (_ index) (find-with-index (cut eq? <> reg) vm-register*)
                   index) 1) vm-register-offset)))

(define register64* '(rax rcx rdx rbx rsp rbp rsi rdi r8  r9  r10 r11 r12 r13 r14 r15))
(define register32* '(eax ecx edx ebx esp ebp esi edi))

(define (register64? obj) (memq obj register64*))
(define (register32? obj) (memq obj register32*))

(define (register64->number reg)
  (receive (_ index) (find-with-index (cut eq? <> reg) register64*)
    index))
(define (register32->number reg)
  (receive (_ index) (find-with-index (cut eq? <> reg) register32*)
    index))

(define (number->register32 n)
  (list-ref register32* n))
(define (number->register64 n)
  (list-ref register64* n))


(define (register32->64 reg)
  (number->register64 (register32->number reg)))

(define (register64->32 reg)
  (number->register32 (register64->number reg)))

(define (find-with-index pred lst)
  (let loop ([i 0]
             [lst lst])
    (cond
     [(null? lst)
      (values #f #f)]
     [(pred (car lst))
      (values (car lst) i)]
     [else
      (loop (+ i 1) (cdr lst))])))


;; See Table 2-1. 16-Bit Addressing Forms with the ModR/M Byte
(define mod.disp0    #b00)
(define mod.disp8    #b01)
(define mod.disp32   #b10)
(define mod.register #b11)

(define sib.scale1 #b00)
(define sib.scale8 #b11)

(define (mod-r-m mod r/m reg)
  (assert (for-all register64? (list r/m reg)))
  (let ([reg-n (register64->number reg)]
        [r/m-n (register64->number r/m)])
    (+ (bitwise-arithmetic-shift-left mod 6)
       (bitwise-arithmetic-shift-left reg-n 3)
       r/m-n)))

(define-syntax opcode
  (lambda (x)
    (syntax-case x ()
      [(_ v) #'v])))

(define (effective-addr+disp8 r/m-reg other-reg)
  (assert (for-all register64? (list r/m-reg other-reg)))
  (values
   (mod-r-m mod.disp8 r/m-reg other-reg)
   (if (eq? r/m-reg 'rsp)
       (list (sib sib.scale1 'rsp 'rsp))
       '())))

(define (effective-addr+disp32 r/m-reg other-reg)
  (assert (for-all register64? (list r/m-reg other-reg)))
  (values
   (mod-r-m mod.disp32 r/m-reg other-reg)
   (if (eq? r/m-reg 'rsp)
       (list (sib sib.scale1 'rsp 'rsp))
       '())))


(define (effective-addr+scale8 r/m-reg other-reg base-reg src-reg)
  (assert (for-all register64? (list r/m-reg other-reg)))
  (values
   (mod-r-m mod.disp0 r/m-reg other-reg)
   (if (eq? r/m-reg 'rsp)
       (list (sib sib.scale8 base-reg src-reg))
       '())))


(define (effective-addr base-reg other-reg)
  (assert (for-all register64? (list base-reg other-reg)))
  (values
   (mod-r-m mod.disp0 base-reg other-reg)
   (if (eq? base-reg 'rsp)
       (list (sib #b00 base-reg))
       '())))

;; (define (sib scaled-index reg)
;;   (+ (bitwise-arithmetic-shift-left scaled-index 6)
;;      (bitwise-arithmetic-shift-left (register64->number reg) 3)
;;      (register64->number reg)))

(define (sib scaled-index base-reg src-reg)
  (+ (bitwise-arithmetic-shift-left scaled-index 6)
     (bitwise-arithmetic-shift-left (register64->number src-reg) 3)
     (register64->number base-reg)))


;; asm* : list of asm
;; asm  : (assembled-byte* addr-of-net-instruction label-to-fixup)
(define (assemble code*)
  (let loop ([code* code*]
             [addr 0]
             [asm* '()]
             [label* '()])
    (cond
     [(null? code*)
      (append-map (match-lambda
                      [(byte* addr #f) byte*]
                      [(byte* addr label-to-fixup)
                       (cond
                        [(assoc label-to-fixup label*) =>
                         (lambda (x)
                           (assert (imm8? (cdr x)))
                           (append (drop-right byte* 1) (list (imm8->u8 (- (cdr x) addr)))))]
                        [else
                         (error 'assemble (format "BUG: label:~a not found on ~a" label-to-fixup label*))])])
                  (reverse asm*))]
     [else
      (match (car code*)
        [('label label)
         (loop (cdr code*)
               addr
               asm*
               (cons (cons label addr) label*))]
        [x
         (let-values (([asm label-to-fixup] (assemble1 x)))
           (loop (cdr code*)
                 (+ (length asm) addr)
                 (cons (list asm (+ (length asm) addr) label-to-fixup) asm*)
                 label*))])])))

(define (imm16? n)
  (and (integer? n) (<= (- (expt 2 15)) n (- (expt 2 15) 1))))

(define (imm32? n)
  (and (integer? n) (<= (- (expt 2 31)) n (- (expt 2 31) 1))))

(define (imm64? n)
  (and (integer? n) (<= (- (expt 2 63)) n (- (expt 2 63) 1))))


(define (imm8? n)
  (and (integer? n) (<= -128 n 127)))

(define (imm8->u8 n)
  (assert (imm8? n))
  (bitwise-and n #xff))


(define (imm32->u8-list n)
  (list (bitwise-and n #xff)
        (bitwise-and (bitwise-arithmetic-shift-right n 8) #xff)
        (bitwise-and (bitwise-arithmetic-shift-right n 16) #xff)
        (bitwise-and (bitwise-arithmetic-shift-right n 24) #xff)))

(define (imm64->u8-list n)
  (list (bitwise-and n #xff)
        (bitwise-and (bitwise-arithmetic-shift-right n 8) #xff)
        (bitwise-and (bitwise-arithmetic-shift-right n 16) #xff)
        (bitwise-and (bitwise-arithmetic-shift-right n 24) #xff)
        (bitwise-and (bitwise-arithmetic-shift-right n 32) #xff)
        (bitwise-and (bitwise-arithmetic-shift-right n 40) #xff)
        (bitwise-and (bitwise-arithmetic-shift-right n 48) #xff)
        (bitwise-and (bitwise-arithmetic-shift-right n 56) #xff)))

;; (oprand dest src)
;; returns (values byte* label-to-fixup)
(define (assemble1 code)
  (define rex.w #x48)
  (match code
    [('je (? symbol? label))
     (values `(,(opcode #x74) #x00) label)]
    ;; CMP r64, r/m64
    ;;   REX.W + 3B /r
    [('cmpq (? register64? dest) (? register64? src))
     (values `(,rex.w ,(opcode #x39) ,(mod-r-m mod.register dest src)) #f)]
    ;; CALL r/m64
    ;;   FF /2
    [('callq (? register64? dest))
     (values `(,(opcode #xff) ,(mod-r-m mod.register dest (number->register64 2))) #f)]
    ;; INT 3
    [('int 3) (values '(#xcc) #f)]
    ;; MOV r/m64, imm32 Valid : Move imm32 sign extended to 64-bits to r/m64.
    ;;   REX.W + C7 /0 
    [('movq (? register64? dest) (? imm32? imm32))
     (values `(,rex.w ,(opcode #xc7) ,(mod-r-m mod.register dest (number->register64 0)) ,@(imm32->u8-list imm32)) #f)]
;;     ;; MOV r/m64, imm64 Valid
;;     ;;   REX.W + B8+ rd
;;     [('movq (? register64? dest) (? imm64? imm64))
;;      (values `(,rex.w ,(opcode #xb8) ,(mod-r-m mod.register dest (number->register64 0)) ,@(imm64->u8-list imm64)) #f)]
    ;; MOV r/m64,r64
    ;;   REX.W + 89 /r
    [('movq (? register64? dest) (? register64? src))
     (values `(,rex.w ,(opcode #x89) ,(mod-r-m mod.register dest src)) #f)]
    ;; MOV r64,r/m64
    ;;   REX.W + 8B /r
    [('movq dest-reg ('& src-reg displacement))
     (cond
      [(zero? displacement)
       (receive (modrm sib) (effective-addr src-reg dest-reg)
         (values `(,rex.w ,(opcode #x8b) ,modrm ,@sib) #f))]
      ;; disp8
      [(< displacement #xff)
       (receive (modrm sib) (effective-addr+disp8 src-reg dest-reg)
         (values `(,rex.w ,(opcode #x8b) ,modrm ,@sib ,displacement) #f))]
      [else
         (error 'assemble "not implemented")])]
    ;; MOV r64,r/m64
    ;;   REX.W + 8B /r
    [('movq dest-reg ('& (? register64? base-reg) (? register64? src-reg) (? number? scaled-index)))
     (cond
      [(= scaled-index 8)
       (receive (modrm sib) (effective-addr+scale8 (number->register64 4) dest-reg base-reg src-reg)
         (values `(,rex.w ,(opcode #x8b) ,modrm ,@sib) #f))]
      [else
         (error 'assemble "not implemented")])]
    [('movq dest-reg ('& src-reg))
     (assemble1 `(movq ,dest-reg (& ,src-reg 0)))]
    ;; MOV r/m64,r64
    ;;   REX.W + 89 /r
    [('movq ('& (? register64? dest-reg) displacement) (? register64? src-reg))
     (cond
      [(zero? displacement)
       (receive (modrm sib) (effective-addr dest-reg src-reg)
         (values `(,rex.w ,(opcode #x89) ,modrm) #f))]
      [else
       (receive (modrm sib) (effective-addr+disp8 dest-reg src-reg)
         (values `(,rex.w ,(opcode #x89) ,modrm ,displacement) #f))])]
    [('movq ('& (? register64? dest-reg)) (? register64? src-reg))
     (assemble1 `(movq (& ,dest-reg 0) ,src-reg))]
    ;; MOV r/m64, imm32
    ;;   REX.W + C7 /0
    [('movq ('& (? register64? dest-reg) (? imm8? displacement)) (? imm32? imm32))
       (receive (modrm sib) (effective-addr+disp8 dest-reg (number->register64 0))
         (values `(,rex.w ,(opcode #xc7) ,modrm ,displacement ,@(imm32->u8-list imm32)) #f))]
    [('movq ('& (? register64? dest-reg) (? imm32? displacement)) (? imm32? imm32))
       (receive (modrm sib) (effective-addr+disp32 dest-reg (number->register64 0))
         (values `(,rex.w ,(opcode #xc7) ,modrm ,displacement ,@(imm32->u8-list imm32)) #f))]
    ;; ADD r/m64, imm8 : REX.W + 83 /0 ib Valid N.E.
    [('addq (? register64? dest-reg) (? imm8? imm8))
     (values `(,rex.w ,(opcode #x83) ,(mod-r-m mod.register dest-reg (number->register64 0)) ,imm8) #f)]
    [('subq (? register64? dest-reg) (? imm8? imm8))
     (values `(,rex.w ,(opcode #x83) ,(mod-r-m mod.register dest-reg (number->register64 5)) ,imm8) #f)]
    ;; RET : C3
    [('retq)
     (values '(#xc3) #f)]
    ;; SAR r/m64, imm8 : REX.W + C1 /7 ib
    [('sarq (? register64? dest-reg) (? imm8? imm8))
     (values `(,rex.w ,(opcode #xc1) ,(mod-r-m mod.register dest-reg (number->register64 7)) ,imm8) #f)]
    ; MOVSXD r64, r/m32 : REX.W** + 63 /r
    [('movslq (? register64? dest-reg) (? register32? src-reg))
     (values `(,rex.w ,(opcode #x63) ,(mod-r-m mod.register dest-reg (register32->64 src-reg))) #f)
     ]
    [('leaq dest-reg ('& (? register64? src-reg)))
     (assemble1 `(leaq ,dest-reg (& ,src-reg 0)))]
    [('leaq dest-reg ('& src-reg displacement))
     (if (< displacement #xff);; disp8
        (cond
         [(zero? displacement)
          (receive (modrm sib) (effective-addr src-reg dest-reg)
            (values `(,rex.w ,(opcode #x8d) ,modrm ,@sib) #f))]
         [else
          (receive (modrm sib) (effective-addr+disp8 src-reg dest-reg)
            (values `(,rex.w ,(opcode #x8d) ,modrm ,@sib ,displacement) #f))])
         (error 'assemble "not implemented"))]
    [x
     (error 'assemble "assemble error: invalid syntax" x)]))

(define (vm-make-fixnum n)
  (+ (bitwise-arithmetic-shift-left n 2) 1))

(define (macro-to-fixnum reg)
  `((sarq ,reg 2)                        ; reg = reg >> 2
   (movslq ,reg ,(register64->32 reg)))) ; reg = reg32 (with sign)

(define (macro-refer-local dest-reg fp-reg index-reg)
  `((movq ,dest-reg (& ,fp-reg ,index-reg 8))))

(define (macro-push sp-reg value-reg)
  `((movq (& ,sp-reg) ,value-reg)
    (addq ,sp-reg 8)))

(define (REFER_LOCAL_PUSH_CONSTANT index constant)
  `((movq rcx ,(vm-register 'sp))
    (movq rdx ,(vm-make-fixnum index))
    (movq rax ,(vm-register 'fp))
    ,@(macro-to-fixnum 'rdx)
    ,@(macro-refer-local 'rax 'rax 'rdx)
    ,@(macro-push 'rcx 'rax)
    (movq ,(vm-register 'sp) rcx)
    (movq rcx ,constant)
    (movq ,(vm-register 'ac) rcx)))

(define (CONSTANT val)
  `((movq ,(vm-register 'ac) ,val)
    (movq rax ,(vm-register 'ac))))


;; (define (REFER_LOCAL_PUSH_CONSTANT index constant)
;; `(
;; ;  (movq rax ,(vm-register 'pc))
;;   (movq rcx ,(vm-register 'sp))
;;   (movq rdx ,(make-fixnum index))
;; ;  (movq ,(vm-register 'pc) rax)
;;   (movq rax ,(vm-register 'fp))
;;   (sarq rdx 2)                    ;; rdx = rdx >> 2 (= toFixnum())
;;   (movslq rdx edx)       ;; rdx = edx (with sign)
;;   (movq rax (& rax rdx 8))       ;; rax = *(fp + n)
;;   (movq (& rcx) rax)    ;; *sp = rax
;; ;  (movq rdx ,(vm-register 'pc))
;;   (addq rcx 8)
;;   (movq ,(vm-register 'sp) rcx)
;;   (movq rcx ,constant)
;;   (movq ,(vm-register 'ac) rcx)
;; ))

;; This is not VM instruction, but useful for test.
(define (POP)
  `((movq rcx ,(vm-register 'sp))
    (subq rcx 8)
    (movq rax (& rcx))
    (movq ,(vm-register 'ac) rax)
    (movq ,(vm-register 'sp) rcx)))

(define (FOREVER)
  '(#xeb #xfe))

(define (DEBUGGER)
  '(int 3))

;;    0:   48 8b 5c 24 38          mov    0x38(%rsp),%rbx
;;    5:   48 8b 43 30             mov    0x30(%rbx),%rax
;;    9:   48 8b 4b 28             mov    0x28(%rbx),%rcx
;;    d:   48 8b 10                mov    (%rax),%rdx
;;   10:   48 83 c0 08             add    $0x8,%rax
;;   14:   48 89 43 30             mov    %rax,0x30(%rbx)
;;   18:   48 8b 43 20             mov    0x20(%rbx),%rax
;;   1c:   48 c1 fa 02             sar    $0x2,%rdx
;;   20:   48 63 d2                movslq %edx,%rdx
;;   23:   48 8b 04 d0             mov    (%rax,%rdx,8),%rax
;;   27:   48 89 01                mov    %rax,(%rcx)
;;   2a:   48 8b 53 30             mov    0x30(%rbx),%rdx
;;   2e:   48 83 c1 08             add    $0x8,%rcx
;;   32:   48 89 4b 28             mov    %rcx,0x28(%rbx)
;;   36:   48 8b 0a                mov    (%rdx),%rcx
;;   39:   48 8d 42 08             lea    0x8(%rdx),%rax
;;   3d:   48 89 43 30             mov    %rax,0x30(%rbx)
;;   41:   48 89 4b 08             mov    %rcx,0x8(%rbx)

(define (gas->sassy gas)
  (cond
   ;; mov %rsp,%rbx
   [(#/([^\s]+)\s+%([^\s]+),%([^\s]+)/ gas) =>
    (lambda (m)
      `(,(string->symbol (string-append (m 1) "q")) ,(string->symbol (m 3)) ,(string->symbol (m 2))))]
   ;; mov 0x30(%rbx),%rdx
   [(#/([^\s]+)\s+0x(\d+)\(%([^\s]+)\),%([^\s]+)/ gas) =>
    (lambda (m)
      `(,(string->symbol (string-append (m 1) "q")) ,(string->symbol (m 4))
        (& ,(string->symbol (m 3)) , (string->number (m 2) 16))))]
   ;; mov (%rbx),%rdx
   [(#/([^\s]+)\s+\(%([^\s]+)\),%([^\s]+)/ gas) =>
    (lambda (m)
      `(,(string->symbol (string-append (m 1) "q")) ,(string->symbol (m 3))
        (& ,(string->symbol (m 2)))))]
   ;; mov    %rcx,0x28(%rbx)
   [(#/([^\s]+)\s+%([^\s]+),0x(\d+)\(%([^\s]+)\)/ gas) =>
    (lambda (m)
      `(,(string->symbol (string-append (m 1) "q"))
        (& ,(string->symbol (m 4)) ,(string->number (m 3) 16))
        ,(string->symbol (m 2))
        ))]
   ;; add    $0x8,%rcx
   [(#/([^\s]+)\s+\$0x(\d+),%([^\s]+)/ gas) =>
    (lambda (m)
      `(,(string->symbol (string-append (m 1) "q")) ,(string->symbol (m 3))
        ,(string->number (m 2) 16)))]
   ))

(define (u8-list->c-procedure+retq lst)
  (u8-list->c-procedure (append lst (assemble '((retq))))))

;; '(movq rbx (& rsp #x38))

;; )
;; (let ([p (open-string-input-port (car (string-split "mov   0x38(%rsp),%rbx" #\,)))])
;;   (display (read p))
;;   (display (read p)))
;; (gas->sassy "mov   0x38(%rsp),%rbx")

;; ToDo
;; (0) make constant op directory
;; (1) make constant op through assemble
;; (1) vm->reg offset support