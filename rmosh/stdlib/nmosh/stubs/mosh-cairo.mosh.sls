;; generated from src/ext/cairo/Library.scm DO NOT EDIT!!
(library (nmosh stubs mosh-cairo)
(export
  mc_win32_create_font
  mc_win32_create_alpha
  mc_win32_create
  mc_mem_png_save
  mc_mem_png_load
  mc_mem_create_alpha
  mc_mem_create
  mc_kick
  mc_pattern_surface
  mc_pattern_solid
  mc_pattern_disable_aa
  mc_pattern_destroy
  mc_surface_destroy
  mc_context_destroy
  mc_context_disable_aa
  mc_context_create)
(import
  (mosh ffi)
  (rnrs)
  (nmosh ffi pffi-plugin)
  (nmosh ffi stublib))


(define %library (make-pffi-ref/plugin 'mosh_cairo))


(define
  mc_context_create
  (pffi-c-function
    %library
    void*
    mc_context_create
    void*))
(define
  mc_context_disable_aa
  (pffi-c-function
    %library
    void
    mc_context_disable_aa
    void*))
(define
  mc_context_destroy
  (pffi-c-function
    %library
    void
    mc_context_destroy
    void*))
(define
  mc_surface_destroy
  (pffi-c-function
    %library
    void
    mc_surface_destroy
    void*))
(define
  mc_pattern_destroy
  (pffi-c-function
    %library
    void
    mc_pattern_destroy
    void*))
(define
  mc_pattern_disable_aa
  (pffi-c-function
    %library
    void
    mc_pattern_disable_aa
    void*))
(define
  mc_pattern_solid
  (pffi-c-function
    %library
    void*
    mc_pattern_solid
    double
    double
    double
    double))
(define
  mc_pattern_surface
  (pffi-c-function
    %library
    void*
    mc_pattern_surface
    void*))
(define
  mc_kick
  (pffi-c-function
    %library
    void
    mc_kick
    void*
    void*
    int
    void*
    int
    void*
    int
    void*
    int))
(define
  mc_mem_create
  (pffi-c-function
    %library
    void*
    mc_mem_create
    int
    int))
(define
  mc_mem_create_alpha
  (pffi-c-function
    %library
    void*
    mc_mem_create_alpha
    int
    int))
(define
  mc_mem_png_load
  (pffi-c-function
    %library
    void*
    mc_mem_png_load
    char*))
(define
  mc_mem_png_save
  (pffi-c-function
    %library
    int
    mc_mem_png_save
    void*
    char*))
(define
  mc_win32_create
  (pffi-c-function
    %library
    void*
    mc_win32_create
    void*))
(define
  mc_win32_create_alpha
  (pffi-c-function
    %library
    void*
    mc_win32_create_alpha
    void*
    int
    int))
(define
  mc_win32_create_font
  (pffi-c-function
    %library
    void*
    mc_win32_create_font
    void*))
)