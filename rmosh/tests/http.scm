(import (rnrs)
        (mosh socket)
        (only (srfi :13) string-contains)
        (http)
        (json)
        (match)
        (mosh test))

(when (ssl-supported?)
  (test-equal "19292868552" (cdr (vector-ref (json-read (open-string-input-port (http-get->utf8 "https://graph.facebook.com/19292868552"))) 0))))

(test-true (string-contains (http-get->utf8 "http://www.hatena.ne.jp") "</html>"))
(test-true (string-contains (http-get->utf8 "http://www.hatena.ne.jp:80") "</html>"))
(test-true (string-contains (http-get->utf8 "http://www.hatena.ne.jp:80/") "</html>"))

(test-true (string-contains (http-get->utf8 "http://ow.ly/3BKpg") "mona"))

(test-true (bytevector? (http-get "http://a1.twimg.com/profile_images/69441183/20060806012051_bigger.png")))
(let-values (([body status header*] (http-get "http://www.monaos.org/notexist")))
  (test-equal #vu8() body)
  (test-equal 404 status)
  (test-true (list? header*))
  (test-true (assoc "Content-Type" header*)))

(let-values (([body status header*] (http-post->utf8 "http://wiki.monaos.org/test.php" '(("hige" . "pon") ("mona" . "os") ("ひげ" . "ぽん")))))
  (test-equal 200 status)
  (test-equal "hige=pon&mona=os&ひげ=ぽん&" body))

(test-results)
