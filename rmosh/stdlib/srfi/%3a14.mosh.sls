;; this file is an alias-library.
;;  alias of:
;;   lib/srfi/%3a14/char-sets.sls
(library (srfi :14)
         (export
             char-set:full
             char-set:empty
             char-set:ascii
             char-set:blank
             char-set:hex-digit
             char-set:symbol
             char-set:punctuation
             char-set:iso-control
             char-set:whitespace
             char-set:printing
             char-set:graphic
             char-set:letter+digit
             char-set:digit
             char-set:letter
             char-set:title-case
             char-set:upper-case
             char-set:lower-case
             char-set-diff+intersection!
             char-set-xor!
             char-set-difference!
             char-set-diff+intersection
             char-set-xor
             char-set-difference
             char-set-intersection!
             char-set-union!
             char-set-complement!
             char-set-intersection
             char-set-union
             char-set-complement
             char-set-delete!
             char-set-adjoin!
             char-set-delete
             char-set-adjoin
             char-set-any
             char-set-every
             char-set-contains?
             char-set-count
             char-set-size
             char-set->string
             char-set->list
             ->char-set
             ucs-range->char-set!
             char-set-filter!
             ucs-range->char-set
             char-set-filter
             string->char-set!
             list->char-set!
             string->char-set
             list->char-set
             char-set
             char-set-copy
             char-set-map
             char-set-for-each
             char-set-unfold!
             char-set-unfold
             char-set-fold
             end-of-char-set?
             char-set-cursor-next
             char-set-ref
             char-set-cursor
             char-set-hash
             char-set<=
             char-set=
             char-set?
         )
         (import
             (srfi :14 char-sets)
         )
) ;; library (srfi :14)
