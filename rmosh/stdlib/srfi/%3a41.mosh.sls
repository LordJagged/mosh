;; this file is an alias-library.
;;  alias of:
;;   lib/srfi/%3a41/streams.mosh.sls
(library (srfi :41)
         (export
             define-stream
             list->stream
             port->stream
             stream
             stream->list
             stream-append
             stream-concat
             stream-constant
             stream-drop
             stream-drop-while
             stream-filter
             stream-fold
             stream-for-each
             stream-from
             stream-iterate
             stream-length
             stream-let
             stream-map
             stream-match
             stream-of
             stream-range
             stream-ref
             stream-reverse
             stream-scan
             stream-take
             stream-take-while
             stream-unfold
             stream-unfolds
             stream-zip
             stream-null
             stream-cons
             stream?
             stream-null?
             stream-pair?
             stream-car
             stream-cdr
             stream-lambda
         )
         (import
             (srfi :41 streams)
         )
) ;; library (srfi :41)
