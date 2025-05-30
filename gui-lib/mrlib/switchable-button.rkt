#lang racket/base
(require racket/gui/base
         racket/contract
         racket/class
         "private/panel-wob.rkt")

(provide switchable-button%)
(define gap 4) ;; space between the text and the icon
(define margin 2)
(define w-circle-space 6)
(define h-circle-space 6)

;; extra space outside the bitmap,
;; but inside the mouse highlighting (on the right)
(define rhs-pad 2)

(define half-gray (make-object color% 127 127 127))
(define one-fifth-gray (make-object color% 200 200 200))

(define yellow-message%
  (class canvas%
    (init-field label)

    (define/override (on-paint)
      (define dc (get-dc))
      (define pen (send dc get-pen))
      (define brush (send dc get-brush))
      (define font (send dc get-font))
      (define yellow (make-object color% 255 255 200))

      (send dc set-pen yellow 1 'transparent)
      (send dc set-brush yellow 'solid)
      (define-values (cw ch) (get-client-size))
      (send dc draw-rectangle 0 0 cw ch)

      (send dc set-font small-control-font)

      (define-values (tw th _1 _2) (send dc get-text-extent label))
      (send dc draw-text
            label
            (- (/ cw 2) (/ tw 2))
            (- (/ ch 2) (/ th 2)))

      (send dc set-pen pen)
      (send dc set-brush brush)
      (send dc set-font font))

    (define/override (on-event evt)
      (send (get-top-level-window) show #f))

    (inherit stretchable-width stretchable-height
             min-width min-height
             get-client-size get-dc
             get-top-level-window)
    (super-new)
    (let-values ([(tw th _1 _2) (send (get-dc) get-text-extent label small-control-font)])
      (min-width (floor (inexact->exact (+ tw 4))))
      (min-height (floor (inexact->exact (+ th 4)))))))

(define switchable-button%
  (class canvas%
    (init-field label
                bitmap
                callback
                [alternate-bitmap bitmap]
                [vertical-tight? #f]
                [min-width-includes-label? #f]
                [right-click-menu #f])

    (define/public (get-button-label) label)
    (define/override (set-label l)
      (set! label l)
      (update-sizes)
      (refresh))

    (when (and (is-a? label bitmap%)
               (not (send label ok?)))
      (error 'switchable-button% "label bitmap is not ok?"))

    (let ([rcb-pred (or/c #f (list/c string? (procedure-arity-includes/c 0)))])
      (unless (rcb-pred right-click-menu)
        (error 'switchable-button% "contract violation\n  expected: ~s\n  got: ~e"
               (contract-name rcb-pred)
               right-click-menu)))

    (define/override (get-label) label)

    (define disable-bitmap (make-dull-mask bitmap))

    (define alternate-disable-bitmap
      (if (eq? bitmap alternate-bitmap)
          disable-bitmap
          (make-dull-mask alternate-bitmap)))

    (inherit get-dc min-width min-height get-client-size refresh
	     client->screen get-top-level-window popup-menu)

    (define down? #f)
    (define in? #f)
    (define disabled? #f)
    (define has-label? (string? label))

    (define/override (enable e?)
      (unless (equal? disabled? (not e?))
        (set! disabled? (not e?))
        (set! down? #f)
        (update-float (and has-label? in? (not disabled?)))
        (refresh))
      (super enable e?))
    (define/override (is-enabled?) (not disabled?))

    (define/override (on-superwindow-show show?)
      (unless show?
        (set! in? #f)
        (set! down? #f)
        (update-float #f)
        (refresh))
      (super on-superwindow-show show?))

    (define/override (on-superwindow-activate active?)
      (unless active?
        (set! in? #f)
        (set! down? #f)
        (update-float #f)
        (refresh))
      (super on-superwindow-show active?))

    (define/override (on-event evt)
      (cond
        [(send evt button-down? 'left)
         (set! down? #t)
         (refresh)
         (update-float #t)]
        [(send evt button-up? 'left)
         (set! down? #f)
         (refresh)
         (when (and in?
                    (not disabled?))
           (update-float #f)
           (callback this))]
        [(send evt button-up?)
         (set! down? #f)
         (refresh)]
        [(send evt button-down? 'right)
         (when right-click-menu
           (define m (new popup-menu%))
           (new menu-item%
                [label (list-ref right-click-menu 0)]
                [parent m]
                [callback (λ (_1 _2) ((list-ref right-click-menu 1)))])
           (define-values (cw ch) (get-client-size))
           (popup-menu m 0 ch))]
        [(send evt entering?)
         (set! in? #t)
         (update-float #t)
         (unless disabled?
           (refresh))]
        [(send evt leaving?)
         (set! in? #f)
         (update-float #f)
         (unless disabled?
           (refresh))]))

    (define/public (command)
      (callback this)
      (void))

    (define float-window #f)
    (inherit get-width get-height)
    (define timer (new timer%
                       [just-once? #t]
                       [notify-callback
                        (λ ()
                          (unless has-label?
                            (define float-should-be-shown? (and (not disabled?) in?))
                            (unless (equal? (send float-window is-shown?)
                                            float-should-be-shown?)
                              (send float-window show float-should-be-shown?)))
                          (set! timer-running? #f))]))
    (define timer-running? #f)

    (define/private (update-float new-value?)
      (when label
        (cond
          [has-label?
           (when float-window
             (send float-window show #f))]
          [else
           (unless (and float-window
                        (equal? new-value? (send float-window is-shown?)))
             (cond
               [new-value?
                (unless float-window
                  (set! float-window (new frame%
                                          [label ""]
                                          [parent (get-top-level-window)]
                                          [style '(no-caption no-resize-border float)]
                                          [stretchable-width #f]
                                          [stretchable-height #f]))
                  (new yellow-message% [parent float-window] [label (or label "")]))

                (send float-window reflow-container)

                ;; position the floating window
                (define-values (dw dh) (get-display-size))
                (define-values (x y) (client->screen (floor (get-width))
                                                     (floor
                                                      (- (/ (get-height) 2)
                                                         (/ (send float-window get-height) 2)))))
                (define-values (dx dy) (get-display-left-top-inset))
                (define rhs-x (- x dx))
                (define rhs-y (- y dy))
                (cond
                  [(< (+ rhs-x (send float-window get-width)) dw)
                   (send float-window move rhs-x rhs-y)]
                  [else
                   (send float-window move
                         (- rhs-x (send float-window get-width) (get-width))
                         rhs-y)])
                (unless timer-running?
                  (set! timer-running? #t)
                  (send timer start 500 #t))]
               [else
                (when float-window
                  (send float-window show #f))]))])))

    (define/override (on-paint)
      (define dc (get-dc))
      (define-values (cw ch) (get-client-size))
      (define alpha (send dc get-alpha))
      (define pen (send dc get-pen))
      (define text-foreground (send dc get-text-foreground))
      (define brush (send dc get-brush))

      ;; Draw background. Use alpha blending if it can work,
      ;;  otherwise fall back to a suitable color.
      (define down-same-as-black-on-white?
        (equal? down?
                (not (white-on-black-panel-scheme?))))
      (define color
        (cond
          [disabled? #f]
          [in? (if (equal? (send dc get-smoothing) 'aligned)
                   (if down-same-as-black-on-white? 0.5 0.2)
                   (if down-same-as-black-on-white?
                       half-gray
                       one-fifth-gray))]
          [else #f]))
      (when color
        (send dc set-pen "black" 1 'transparent)
        (send dc set-brush (if (number? color)
                               (get-label-foreground-color)
                               color) 'solid)
        (when (number? color)
          (send dc set-alpha color))
        (send dc draw-rounded-rectangle
              margin
              margin
              (max 0 (- cw margin margin))
              (max 0 (- ch margin margin)))
        (when (number? color)
          (send dc set-alpha alpha)))

      (send dc set-font normal-control-font)

      (when disabled?
        (send dc set-alpha .5))

      (cond
        [has-label?
         (cond
           [(<= cw (get-small-width))
            (draw-the-bitmap (- (/ cw 2) (/ (send bitmap get-width) 2))
                             (- (/ ch 2) (/ (send bitmap get-height) 2)))]
           [else
            (define-values (tw th _1 _2) (send dc get-text-extent label))
            (define text-start (+ (/ cw 2)
                                  (- (/ tw 2))
                                  (- (/ (send bitmap get-width) 2))
                                  (- rhs-pad)))
            (send dc set-text-foreground (get-label-foreground-color))
            (send dc draw-text label text-start (- (/ ch 2) (/ th 2)))
            (draw-the-bitmap (+ text-start tw gap)
                             (- (/ ch 2) (/ (send bitmap get-height) 2)))])]
        [else
         (draw-the-bitmap
          (- (/ cw 2)
             (/ (send (if has-label? bitmap alternate-bitmap) get-width)
                2))
          (- (/ ch 2)
             (/ (send (if has-label? bitmap alternate-bitmap) get-height)
                2)))])

      (send dc set-pen pen)
      (send dc set-alpha alpha)
      (send dc set-brush brush)
      (send dc set-text-foreground text-foreground))

    (define/private (draw-the-bitmap x y)
      (define bm (if has-label? bitmap alternate-bitmap))
      (send (get-dc)
            draw-bitmap
            bm
            x y
            'solid
            (send the-color-database find-color "black")
            (if disabled?
                (if has-label? disable-bitmap alternate-disable-bitmap)
                (send bm get-loaded-mask))))

    (define/public (set-label-visible in-h?)
      (define h? (and in-h? #t))
      (unless (equal? has-label? h?)
        (set! has-label? h?)
        (update-sizes)
        (update-float (and has-label? in? (not disabled?)))
        (refresh)))
    (define/public (get-label-visible) has-label?)

    (define/private (update-sizes)
      (define dc (get-dc))
      (define-values (tw th _1 _2) (send dc get-text-extent label normal-control-font))
      (define h
        (inexact->exact
         (floor
          (+ (max th
                  (send alternate-bitmap get-height)
                  (send bitmap get-height))
             h-circle-space margin margin
             (if vertical-tight? -6 0)))))
      (cond
        [has-label?
         (cond
           [min-width-includes-label?
            (min-width (get-large-width))]
           [else
            (min-width (get-small-width))])
         (min-height h)]
        [else
         (min-width (get-without-label-small-width))
         (min-height h)]))

    (define/public (get-large-width)
      (define dc (get-dc))
      (define-values (tw th _1 _2) (send dc get-text-extent label normal-control-font))
      (inexact->exact
       (floor
        (+ (+ tw gap (send bitmap get-width) rhs-pad)
           w-circle-space
           margin
           margin))))

    (define/public (get-without-label-small-width)
      (inexact->exact
       (floor
        (+ (send alternate-bitmap get-width)
           w-circle-space
           margin
           margin))))

    (define/public (get-small-width)
      (inexact->exact
       (floor
        (+ (send bitmap get-width)
           w-circle-space
           margin
           margin))))

    (super-new [style '(transparent no-focus)])
    (send (get-dc) set-smoothing 'aligned)

    (inherit stretchable-width stretchable-height)
    (stretchable-width #f)
    (stretchable-height #f)
    (inherit get-graphical-min-size)
    (update-sizes)))

(define (make-dull-mask bitmap)
  (define alpha-bm (send bitmap get-loaded-mask))
  (cond
    [alpha-bm
     (define w (send alpha-bm get-width))
     (define h (send alpha-bm get-height))
     (define disable-bm (make-object bitmap% w h))
     (define pixels (make-bytes (* 4 w h)))
     (define bdc (make-object bitmap-dc% alpha-bm))
     (send bdc get-argb-pixels 0 0 w h pixels)
     (let loop ([i 0])
       (when (< i (* 4 w h))
         (bytes-set! pixels i (- 255 (quotient (- 255 (bytes-ref pixels i)) 2)))
         (loop (+ i 1))))
     (send bdc set-bitmap disable-bm)
     (send bdc set-argb-pixels 0 0 w h pixels)
     (send bdc set-bitmap #f)
     disable-bm]
    [else #f]))

(module+ examples
  (define f (new frame% [label ""]))
  (define vp (new vertical-pane% [parent f]))
  (define p (new horizontal-panel% [parent vp] [alignment '(right top)]))

  (define label "Run")
  (define bitmap (read-bitmap (collection-file-path "run.png" "icons")))
  (define foot (read-bitmap (collection-file-path "foot.png" "icons")))
  (define foot-up (read-bitmap (collection-file-path "foot-up.png" "icons")))
  (define small-planet (read-bitmap (collection-file-path "small-planet.png" "icons")))

  (define b1 (new switchable-button% [parent p] [label label] [bitmap bitmap] [callback void]))
  (define b2 (new switchable-button% [parent p] [label label] [bitmap bitmap] [callback void]))
  (define b3 (new switchable-button% [parent p] [label "Step"] [bitmap foot]
                  [alternate-bitmap foot-up]
                  [callback void]))

  ;; button with a callback that enables and disables like the debugger's step button
  (define b4
    (new switchable-button%
         [label "Step"]
         [bitmap small-planet]
         [parent p]
         [callback (λ (_) (send b4 enable #f) (send b4 enable #t))]
         [min-width-includes-label? #t]))

  (define sb (new button% [parent p] [stretchable-width #t] [label "b"]))
  (define state #t)
  (define swap-button
    (new button%
         [parent f]
         [label "swap"]
         [callback
          (λ (a b)
            (set! state (not state))
            (send b1 set-label-visible state)
            (send b2 set-label-visible state)
            (send b3 set-label-visible state))]))
  (define disable-button
    (new button%
         [parent f]
         [label "disable"]
         [callback
          (λ (a b)
            (send sb enable (not (send sb is-enabled?)))
            (send b1 enable (not (send b1 is-enabled?))))]))
  (send f show #t))
