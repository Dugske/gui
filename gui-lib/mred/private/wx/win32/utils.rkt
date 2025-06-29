#lang racket/base
(require ffi/unsafe
	 ffi/unsafe/define
	 ffi/unsafe/alloc
         "../common/utils.rkt"
	 "../../lock.rkt"
         "types.rkt"
	 "const.rkt")

(provide
 define-mz
 (protect-out define-gdi32
              define-user32
              define-kernel32
              define-comctl32
              define-comdlg32
              define-shell32
              define-uxtheme
              define-winmm
              define-dwampi
              failed
	      is-win64?

              GetLastError

              GetWindowLongPtrW
              SetWindowLongPtrW
              SendMessageW SendMessageW/str SendMessageW/ptr
              GetSysColor GetRValue GetGValue GetBValue make-COLORREF COLORREF-alpha-blend
              GetSysColorBrush
              CreateBitmap
              CreateCompatibleBitmap
              DeleteObject
              CreateCompatibleDC
              DeleteDC
              MoveWindow
              ShowWindow
              EnableWindow
              SetWindowTextW
              SetCursor
              GetDC
              ReleaseDC
              InvalidateRect
              ValidateRect
              GetMenuState
              CheckMenuItem
              ModifyMenuW
              RemoveMenu
              SelectObject
              WideCharToMultiByte
              SetTextColor
              GetBkColor SetBkColor
              GetPixel
        GetDeviceCaps
	      strip-&
	      ->screen
	      ->screen*
	      ->normal))

(define gdi32-lib (ffi-lib "gdi32.dll"))
(define user32-lib (ffi-lib "user32.dll"))
(define kernel32-lib (ffi-lib "kernel32.dll"))
(define comctl32-lib (ffi-lib "comctl32.dll"))
(define comdlg32-lib (ffi-lib "comdlg32.dll"))
(define shell32-lib (ffi-lib "shell32.dll"))
(define uxtheme-lib (ffi-lib "uxtheme.dll"))
(define winmm-lib (ffi-lib "winmm.dll"))
(define dwampi-lib (ffi-lib "dwmapi.dll"))

(define-ffi-definer define-gdi32 gdi32-lib)
(define-ffi-definer define-user32 user32-lib)
(define-ffi-definer define-kernel32 kernel32-lib)
(define-ffi-definer define-comctl32 comctl32-lib)
(define-ffi-definer define-comdlg32 comdlg32-lib)
(define-ffi-definer define-shell32 shell32-lib)
(define-ffi-definer define-uxtheme uxtheme-lib)
(define-ffi-definer define-winmm winmm-lib)
(define-ffi-definer define-dwampi dwampi-lib)

(define-kernel32 GetLastError (_wfun -> _DWORD))

(define (failed who)
  ;; There's a race condition between this use of GetLastError()
  ;;  and other Racket threads that may have run since
  ;;  the call in this thread that we're reporting as failed.
  ;;  In the rare case that we lose a race, though, it just
  ;;  means a bad report for an error that shouldn't have happened
  ;;; anyway.
  (error who "call failed (~s)"
         (GetLastError)))

(define is-win64?
  (eqv? 64 (system-type 'word)))

(define GetWindowLongPtrW
  (get-ffi-obj (if is-win64? 'GetWindowLongPtrW 'GetWindowLongW) user32-lib
	       (_wfun _HWND _int -> _pointer)))
(define SetWindowLongPtrW
  (get-ffi-obj (if is-win64? 'SetWindowLongPtrW 'SetWindowLongW) user32-lib
	       (_wfun _HWND _int _pointer -> _pointer)))

(define-user32 SendMessageW (_wfun _HWND _UINT _WPARAM _LPARAM -> _LRESULT))
(define-user32 SendMessageW/str (_wfun _HWND _UINT _WPARAM _string/utf-16 -> _LRESULT)
  #:c-id SendMessageW)
(define-user32 SendMessageW/ptr (_wfun _HWND _UINT _WPARAM _pointer -> _LRESULT)
  #:c-id SendMessageW)

(define-user32 GetSysColor (_wfun _int -> _DWORD))
(define-user32 GetSysColorBrush (_wfun _int -> _HBRUSH))

(define (GetRValue v) (bitwise-and v #xFF))
(define (GetGValue v) (bitwise-and (arithmetic-shift v -8) #xFF))
(define (GetBValue v) (bitwise-and (arithmetic-shift v -16) #xFF))
(define (make-COLORREF r g b) (bitwise-ior
                               r
                               (arithmetic-shift g 8)
                               (arithmetic-shift b 16)))
(define (COLORREF-alpha-blend fg bg fg-alpha)
  (cond
    [(= fg-alpha 1.0) fg]
    [else
     (define bg-alpha (- 1.0 fg-alpha))
     (make-COLORREF
      (clamp-color-val (+ (* (GetRValue fg) fg-alpha)
                          (* (GetRValue bg) bg-alpha)))
      (clamp-color-val (+ (* (GetGValue fg) fg-alpha)
                          (* (GetGValue bg) bg-alpha)))
      (clamp-color-val (+ (* (GetBValue fg) fg-alpha)
                          (* (GetBValue bg) bg-alpha))))]))
(define (clamp-color-val v)
  (modulo (inexact->exact (truncate v)) 256))

(define-user32 MoveWindow(_wfun _HWND _int _int _int _int _BOOL -> (r : _BOOL)
                                -> (unless r (failed 'MoveWindow))))

(define-user32 ShowWindow (_wfun _HWND _int -> (previously-shown? : _BOOL) -> (void)))
(define-user32 EnableWindow (_wfun _HWND _BOOL -> _BOOL))

(define-user32 SetWindowTextW (_wfun _HWND _string/utf-16 -> (r : _BOOL)
                                     -> (unless r (failed 'SetWindowText))))

(define-user32 SetCursor (_wfun _HCURSOR -> _HCURSOR))

(define-user32 _GetDC (_wfun  _HWND -> _HDC)
  #:c-id GetDC)
(define (GetDC hwnd)
  (((allocator (lambda (hdc) (ReleaseDC hwnd hdc)))
    _GetDC)
   hwnd))

(define-user32 ReleaseDC (_wfun _HWND _HDC -> _int)
  #:wrap (deallocator cadr))

(define-gdi32 DeleteObject (_wfun _pointer -> (r : _BOOL)
                                  -> (unless r (failed 'DeleteObject)))
  #:wrap (deallocator))

(define-gdi32 CreateCompatibleBitmap (_wfun _HDC _int _int -> _HBITMAP)
  #:wrap (allocator DeleteObject))
(define-gdi32 CreateBitmap (_wfun _int _int _UINT _UINT _pointer -> _HBITMAP)
  #:wrap (allocator DeleteObject))

(define-gdi32 DeleteDC (_wfun _HDC -> (r : _BOOL)
                              -> (unless r (failed 'DeleteDC)))
  #:wrap (deallocator))
(define-gdi32 CreateCompatibleDC (_wfun _HDC -> _HDC)
  #:wrap (allocator DeleteDC))

(define-user32 InvalidateRect (_wfun _HWND (_or-null _RECT-pointer) _BOOL -> (r : _BOOL)
                                     -> (unless r (failed 'InvalidateRect))))
(define-user32 ValidateRect (_wfun _HWND (_or-null _RECT-pointer) -> (r : _BOOL)
                                   -> (unless r (failed 'ValidateRect))))

(define-user32 GetMenuState (_wfun _HMENU _UINT _UINT -> _UINT))
(define-user32 CheckMenuItem (_wfun _HMENU _UINT _UINT -> _DWORD))
(define-user32 ModifyMenuW (_wfun _HMENU _UINT _UINT _UINT_PTR _string/utf-16
                                  -> (r : _BOOL)
                                  -> (unless r (failed 'ModifyMenuW))))
(define-user32 RemoveMenu (_wfun _HMENU _UINT _UINT -> (r : _BOOL)
                                 -> (unless r (failed 'RemoveMenu))))

(define-gdi32 SelectObject (_wfun _HDC _pointer -> _pointer))

(define-kernel32 WideCharToMultiByte (_wfun _UINT _DWORD _pointer _int
                                            _pointer _int _pointer _pointer
                                            -> _int))
;; ----------------------------------------

(define (strip-& s)
  (if (string? s)
      (regexp-replace* #rx"&(.)" s "\\1")
      s))

;; ----------------------------------------

(define-gdi32 GetDeviceCaps (_wfun _HDC _int -> _int))

(define screen-dpi
  (atomically
   (let ([hdc (GetDC #f)])
     (begin0
      (GetDeviceCaps hdc LOGPIXELSX)
      (ReleaseDC #f hdc)))))

;; Convert a normalized (conceptually 96-dpi) measure into a screen measure
(define (->screen x)
  (and x
       (if (= screen-dpi 96)
	   x
	   (if (exact? x)
	       (ceiling (/ (* x screen-dpi) 96))
	       (/ (* x screen-dpi) 96)))))
(define (->screen* x)
  (if (and (not (= screen-dpi 96))
	   (exact? x))
      (floor (/ (* x screen-dpi) 96))
      (->screen x)))

;; Convert a screen measure to a normalize (conceptually 96-dpi) measure
(define (->normal x)
  (and x
       (if (= screen-dpi 96)
	   x
	   (if (exact? x)
	       (floor (/ (* x 96) screen-dpi))
	       (/ (* x 96) screen-dpi)))))

(define-gdi32 SetTextColor (_wfun _HDC _COLORREF -> _COLORREF))
(define-gdi32 GetBkColor (_wfun _HDC -> _COLORREF))
(define-gdi32 SetBkColor (_wfun _HDC _COLORREF -> _COLORREF))
(define-gdi32 GetPixel (_wfun _HDC _int _int -> _COLORREF))
