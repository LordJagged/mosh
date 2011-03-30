(import (rnrs)
        (mosh test)
        (mosh control)
        (mosh ffi)
        (mecab))

(let1 m (mecab-new2 "")
  (test-false (pointer-null? m))
  (let* ([text (string->utf8 "僕はお腹がすいた")]
         [len (bytevector-length text)])
    (test-equal "僕\t名詞,代名詞,一般,*,*,*,僕,ボク,ボク\nは\t助詞,係助詞,*,*,*,*,は,ハ,ワ\nお腹\t名詞,一般,*,*,*,*,お腹,オナカ,オナカ\nが\t助詞,格助詞,一般,*,*,*,が,ガ,ガ\nすい\t動詞,自立,*,*,五段・カ行イ音便,連用タ接続,すく,スイ,スイ\nた\t助動詞,*,*,*,特殊・タ,基本形,た,タ,タ\nEOS\n" (mecab-sparse-tostr2 m text len)))
)

  ;;      [src (string->utf8 "ぼくひげぽん。")]
  ;;      [len (bytevector-length src)])
  ;; (write (pointer->string (mecab-sparse-tostr2 m src len)))
  ;; (let loop ([node (mecab-sparse-tonode2 m src len)])
  ;;   (cond
  ;;    [(pointer-null? node) '()]
  ;;    [else
  ;;     (write (mecab-node-length node))
  ;;     (write (mecab-node-surface node))
  ;;     (newline)
  ;;     (loop (mecab-node-next node))
  ;;     ])
  ;;   )
  ;; (mecab-destroy m))


(test-results)

