;; rmosh doesn't implement some compiler related procedures in Rust.
;; For example make-code-builder is written in Scheme. So we have special free-vars-decl for rmosh.
(define *free-vars-decl* (quote (
number?
cons
cons*
car
cdr
null?
set-car!
set-cdr!
sys-display
rxmatch
regexp?
regexp->string
rxmatch-start
rxmatch-end
rxmatch-after
rxmatch-before
rxmatch-substring
make-string
string-set!
string-length
string->symbol
string->number
string-append
string-split
string
number->string
reverse
eof-object?
read-char
peek-char
char=?
string?
get-environment-variable
get-environment-variables
equal?
open-string-input-port
open-output-string
sys-port-seek
close-output-port
digit->integer
get-remaining-input-string
directory-list
file-exists?
delete-file
get-output-string
string->regexp
char->integer
integer->char
format
current-input-port
current-output-port
set-current-input-port!
set-current-output-port!
char?
write
gensym
string=?
caaaar
caaadr
caaar
caadar
caaddr
caadr
caar
cadaar
cadadr
cadar
caddar
cadddr
caddr
cadr
cdaaar
cdaadr
cdaar
cdadar
cdaddr
cdadr
cdar
cddaar
cddadr
cddar
cdddar
cddddr
cdddr
cddr
symbol=?
boolean=?
vector?
list?
list
memq
eq?
eqv?
member
boolean?
symbol->string
string-ref
get-timeofday
make-eq-hashtable
make-eqv-hashtable
hashtable-set!
hashtable-ref
hashtable-keys
string-hash
eqv-hash
string-ci-hash
symbol-hash
equal-hash
eq-hashtable-copy
current-error-port
values
vm/apply
pair?
make-custom-binary-input-port
make-custom-binary-output-port
make-custom-textual-input-port
make-custom-textual-output-port
get-u8
put-u8
put-string
flush-output-port
output-port-buffer-mode
bytevector-u8-set!
port-has-port-position?
port-has-set-port-position!?
port-position
set-port-position!
get-bytevector-n!
get-bytevector-some
get-bytevector-all
transcoded-port
latin-1-codec
utf-8-codec
utf-16-codec
make-transcoder
eof-object
sys-open-bytevector-output-port
sys-get-bytevector
bytevector-length
standard-input-port
standard-output-port
standard-error-port
get-bytevector-n
open-file-output-port
open-file-input-port
close-input-port
vector
regexp-replace
regexp-replace-all
source-info
eval
eval-compiled
apply
assq
assoc
assv
exit
macroexpand-1
memv
procedure?
load
symbol?
char<=?
char<?
char>=?
char>?
read
vector->list
set-source-info!
%call-process
%confstr
%dup
%start-process
%get-closure-name
append
append2
append!
not_implemented ;pass3/find-free
not_implemented ;pass3/find-sets
not_implemented ;pass4/fixup-labels
not_implemented ;make-code-builder
not_implemented ;code-builder-put-extra1!
not_implemented ;code-builder-put-extra2!
not_implemented ;code-builder-put-extra3!
not_implemented ;code-builder-put-extra4!
not_implemented ;code-builder-put-extra5!
not_implemented ;code-builder-append!
not_implemented ;code-builder-emit
not_implemented ;code-builder-put-insn-arg0!
not_implemented ;code-builder-put-insn-arg1!
not_implemented ;code-builder-put-insn-arg2!
length
list->vector
not_implemented ;pass3/compile-refer
not_implemented ;pass1/find-symbol-in-lvars
not_implemented ;$label
not_implemented ;$local-ref
list-transpose+
symbol-value
set-symbol-value!
make-hashtable
hashtable?
hashtable-size
hashtable-delete!
hashtable-contains?
hashtable-copy
hashtable-mutable?
hashtable-clear!
hashtable-keys
hashtable-equivalence-function
hashtable-hash-function
throw
<
<=
>
>=
=
+
-
*
/
max
min
get-char
lookahead-char
get-string-n
get-string-n!
get-string-all
get-line
get-datum
bytevector?
current-directory
standard-library-path
native-endianness
make-bytevector
make-bytevector
bytevector-length
bytevector=?
bytevector-fill!
bytevector-copy!
bytevector-copy
bytevector-u8-ref
bytevector-u8-set!
bytevector-s8-ref
bytevector-s8-set!
bytevector->u8-list
u8-list->bytevector
bytevector-u16-ref
bytevector-s16-ref
bytevector-u16-native-ref
bytevector-s16-native-ref
bytevector-u16-set!
bytevector-s16-set!
bytevector-u16-native-set!
bytevector-s16-native-set!
bytevector-u32-ref
bytevector-s32-ref
bytevector-u32-native-ref
bytevector-s32-native-ref
bytevector-u32-set!
bytevector-s32-set!
bytevector-u32-native-set!
bytevector-s32-native-set!
bytevector-u64-ref
bytevector-s64-ref
bytevector-u64-native-ref
bytevector-s64-native-ref
bytevector-u64-set!
bytevector-s64-set!
bytevector-u64-native-set!
bytevector-s64-native-set!
bytevector->string
string->bytevector
string->utf8
utf8->string
null-terminated-bytevector->string
null-terminated-utf8->string
string->utf16
string->utf32
utf16->string
utf32->string
close-port
make-instruction
make-compiler-instruction
fasl-write
fasl-read
get-string-n
rational?
flonum?
fixnum?
bignum?
fixnum-width
least-fixnum
greatest-fixnum
make-rectangular
real-part
imag-part
exact?
inexact?
exact
inexact
nan?
infinite?
finite?
real->flonum
fl=?
fl<?
fl>?
fl>=?
fl<=?
flinteger?
flzero?
flpositive?
flnegative?
flodd?
fleven?
flfinite?
flinfinite?
flnan?
flmax
flmin
fl+
fl*
fl-
fl/
flabs
fldiv
flmod
fldiv0
flmod0
flnumerator
fldenominator
flfloor
flceiling
fltruncate
flround
flexp
fllog
flsin
flcos
fltan
flasin
flacos
flatan
flsqrt
flexpt
fixnum->flonum
bitwise-not
bitwise-and
bitwise-ior
bitwise-xor
bitwise-bit-count
bitwise-length
bitwise-first-bit-set
bitwise-arithmetic-shift-left
bitwise-arithmetic-shift-right
bitwise-arithmetic-shift
complex?
real?
rational?
integer?
real-valued?
rational-valued?
integer-valued?
fx=?
fx>?
fx<?
fx>=?
fx<=?
fxzero?
fxpositive?
fxnegative?
fxodd?
fxeven?
fxmax
fxmin
fx+
fx*
fx-
fxdiv
fxmod
fxdiv0
fxmod0
fxnot
fxand
fxior
fxxor
fxif
fxbit-count
fxlength
fxfirst-bit-set
fxbit-set?
fxcopy-bit
fxbit-field
fxcopy-bit-field
fxarithmetic-shift
fxarithmetic-shift-left
fxarithmetic-shift-right
fxrotate-bit-field
fxreverse-bit-field
bytevector-ieee-single-native-ref
bytevector-ieee-single-ref
bytevector-ieee-double-native-ref
bytevector-ieee-double-ref
bytevector-ieee-single-native-set!
bytevector-ieee-single-set!
bytevector-ieee-double-native-set!
bytevector-ieee-double-set!
even?
odd?
abs
div
div0
numerator
denominator
floor
ceiling
truncate
round
exp
log
sin
cos
tan
asin
acos
sqrt
magnitude
angle
atan
expt
make-polar
string-copy
vector-fill!
ungensym
disasm
print-stack
fast-equal?
native-eol-style
buffer-mode?
microseconds
local-tz-offset
%fork
%exec
%waitpid
%pipe
%getpid
current-directory
set-current-directory!
binary-port?
input-port?
port-eof?
lookahead-u8
open-bytevector-input-port
%ffi-open
%ffi-lookup
%ffi-call
%ffi-supported?
%ffi-malloc
%ffi-free
%ffi-make-c-callback-trampoline
%ffi-free-c-callback-trampoline
%ffi-close
%ffi-error
host-os
output-port?
textual-port?
port?
port-transcoder
native-transcoder
put-bytevector
put-char
write-char
transcoder-codec
transcoder-eol-style
transcoder-error-handling-mode
quotient
remainder
modulo
open-file-input/output-port
make-custom-binary-input/output-port
make-custom-textual-input/output-port
put-datum
list-ref
list-tail
time-usage
mosh-executable-path
socket?
socket-accept
make-client-socket
make-server-socket
os-constant
socket-recv
socket-recv!
socket-send
socket-close
socket-shutdown
socket-port
make-vm
vm-start!
vm?
vm-set-value!
vm-join!
main-vm?
vm-self
register
whereis
make-condition-variable
condition-variable-wait!
condition-variable-notify!
condition-variable-notify-all!
mutex?
make-mutex
mutex-lock!
mutex-try-lock!
mutex-unlock!
make-vector
vector-length
vector-ref
vector-set!
create-directory
delete-directory
rename-file
create-symbolic-link
file-directory?
file-symbolic-link?
file-regular?
file-readable?
file-executable?
file-writable?
file-size-in-bytes
file-stat-mtime
file-stat-atime
file-stat-ctime
pointer?
pointer->integer
integer->pointer
pointer-ref-c-uint8
pointer-ref-c-uint16
pointer-ref-c-uint32
pointer-ref-c-uint64
pointer-ref-c-int8
pointer-ref-c-int16
pointer-ref-c-int32
pointer-ref-c-int64
pointer-ref-c-signed-char
pointer-ref-c-unsigned-char
pointer-ref-c-signed-short
pointer-ref-c-unsigned-short
pointer-ref-c-signed-int
pointer-ref-c-unsigned-int
pointer-ref-c-signed-long
pointer-ref-c-unsigned-long
pointer-ref-c-signed-long-long
pointer-ref-c-unsigned-long-long
pointer-ref-c-float
pointer-ref-c-double
pointer-ref-c-pointer
pointer-set-c-int8!
pointer-set-c-int16!
pointer-set-c-int32!
pointer-set-c-int64!
pointer-set-c-uint8!
pointer-set-c-uint16!
pointer-set-c-uint32!
pointer-set-c-uint64!
pointer-set-c-char!
pointer-set-c-short!
pointer-set-c-int!
pointer-set-c-long!
pointer-set-c-long-long!
pointer-set-c-float!
pointer-set-c-double!
pointer-set-c-pointer!
pointer-copy!
bytevector-pointer
shared-errno
simple-struct?
make-simple-struct
simple-struct-ref
simple-struct-set!
simple-struct-name
lookup-nongenerative-rtd
nongenerative-rtd-set!
same-marks*?
same-marks?
id->real-label
join-wraps
gensym-prefix-set!
current-dynamic-winders
sexp-map
sexp-map/debug
write/ss
%monapi-message-send
%monapi-name-whereis
%monapi-message-receive
%monapi-name-add!
%monapi-message-send-receive
%monapi-message-reply
%monapi-make-stream
%monapi-stream-handle
%monapi-stream-write
%monapi-stream-read
process-list
process-terminate!
socket-sslize!
ssl-socket?
ssl-supported?
file->string
annotated-cons
annotated-pair?
get-annotation
set-annotation!
pointer->object
object->pointer
set-current-error-port!
port-open?
make-f64array
f64array?
f64array-ref
f64array-set!
f64array-shape
f64array-dot-product
) ) )
