;;; recall.el --- Recall measurement harness for elistan  -*- lexical-binding: t; -*-

;; Measures elistan's RECALL: of a labelled set of type bugs, how many does it
;; catch?  Precision is already established (zero FP on the 743-file elpa sweep);
;; this quantifies the other axis and maps the design boundary.
;;
;; Each case is a self-contained snippet run through the full batch pipeline
;; (`elistan-batch-check-file': annotations + structs + declare + class + check).
;; A case is labelled:
;;   :expect CATEGORY  -- the finding category the checker SHOULD report, or nil
;;   :scope in|out     -- `in' = within the design (a true bug it claims to find);
;;                        `out' = deliberately out of scope (ADR-0014 etc.)
;;
;; Run: emacs -Q --batch -L . -L ../emacs-typespec -l .scratch/recall/recall.el

(require 'elistan-batch)

(defvar recall-cases
  '(;; ---- call-type-mismatch (against an author-written contract) ----
    (:name "call/elsa-literal" :scope in :expect call-type-mismatch
     :code "\
;; (need-str :: (function (string) integer))
(defun need-str (s) 0)
(defun caller () (need-str 5))")
    (:name "call/elsa-computed" :scope in :expect call-type-mismatch
     :code "\
;; (need-str :: (function (string) integer))
(defun need-str (s) 0)
(defun caller (n) (need-str (+ n 1)))")
    (:name "call/typespec-macro" :scope in :expect call-type-mismatch
     :code "\
(typespec #'need-int (function (integer) integer))
(defun need-int (n) n)
(defun caller () (need-int \"x\"))")
    (:name "call/declare-ftype" :scope in :expect call-type-mismatch
     :code "\
(defun need-sym (s) (declare (typespec-ftype (function (symbol) t))) s)
(defun caller () (need-sym \"x\"))")
    (:name "call/inside-lambda" :scope in :expect call-type-mismatch
     :code "\
;; (need-str :: (function (string) integer))
(defun need-str (s) 0)
(defun caller (xs) (mapcar (lambda (x) (need-str (length x))) xs))")

    ;; ---- dead-branch (provable from narrowing / result types) ----
    (:name "dead/param-guard" :scope in :expect dead-branch
     :code "\
;; (g :: (function (string) integer))
(defun g (x) (if (integerp x) 1 2))")
    (:name "dead/let-typed" :scope in :expect dead-branch
     :code "(defun g (s) (let ((n (length s))) (if (stringp n) 1 2)))")
    (:name "dead/eq-const" :scope in :expect dead-branch
     :code "\
;; (h :: (function (string) integer))
(defun h (x) (if (eq x 5) 1 2))")
    (:name "dead/and-narrow" :scope in :expect dead-branch
     :code "\
;; (k :: (function (string) integer))
(defun k (x) (and (integerp x) x))")
    ;; False-branch direction: a value provably WITHIN the guard type makes the
    ;; guard always true, so the ELSE branch is dead.  Unlocked by typespec's
    ;; strict (sound) subtype relation driving `(diff …)' to `never'.
    (:name "dead/else-subtype" :scope in :expect dead-branch
     :code "\
;; (es :: (function (string) integer))
(defun es (x) (if (arrayp x) 1 2))")

    ;; ---- return-type-mismatch ----
    (:name "return/elsa" :scope in :expect return-type-mismatch
     :code "\
;; (r :: (function (string) integer))
(defun r (s) s)")
    (:name "return/typespec-macro" :scope in :expect return-type-mismatch
     :code "\
(typespec #'r2 (function (integer) string))
(defun r2 (n) n)")

    ;; ---- slot-type-mismatch ----
    (:name "slot/oset" :scope in :expect slot-type-mismatch
     :code "\
(defclass w () ((width :type integer :initarg :width)))
;; (f :: (function ((:class w)) integer))
(defun f (obj) (oset obj width \"wide\") 0)")
    ;; The idiomatic `(setf (oref …) …)' slot write (expands to `eieio-oset'
    ;; once eieio is loaded during analysis).
    (:name "slot/setf-oref" :scope in :expect slot-type-mismatch
     :code "\
(defclass w () ((width :type integer :initarg :width)))
;; (f :: (function ((:class w)) integer))
(defun f (obj) (setf (oref obj width) \"wide\") 0)")

    ;; ==== OUT OF SCOPE (expected misses — quantify the design ceiling) ====
    (:name "miss/builtin-arg" :scope out :expect nil
     :code "(defun bad () (+ \"a\" 1))")            ; builtins lenient (ADR-0014)
    (:name "miss/builtin-message" :scope out :expect nil
     :code "(defun bad () (length 5))")             ; length builtin, not authoritative
    (:name "miss/interprocedural" :scope out :expect nil
     :code "\
(defun producer () \"a string\")
(defun consumer () (1+ (producer)))")              ; producer untyped -> unknown
    (:name "miss/free-var-flow" :scope out :expect nil
     :code "\
;; (need-str :: (function (string) integer))
(defun need-str (s) 0)
(defvar gv)
(defun caller () (setq gv 5) (need-str gv))")      ; special var not tracked
    (:name "miss/nil-deref" :scope out :expect nil
     :code "(defun bad (x) (car (if x nil 1)))")    ; nil-safety / car arg not authoritative
    (:name "miss/list-element" :scope out :expect nil
     :code "\
;; (need-str :: (function (string) integer))
(defun need-str (s) 0)
(defun caller (xs) (need-str (car xs)))")          ; car returns unknown element

    ;; ==== correct code (precision sanity — must NOT fire) ====
    (:name "ok/correct-call" :scope in :expect nil
     :code "\
;; (need-str :: (function (string) integer))
(defun need-str (s) 0)
(defun caller () (need-str \"hi\"))")
    (:name "ok/live-branch" :scope in :expect nil
     :code "\
;; (g :: (function (mixed) integer))
(defun g (x) (if (integerp x) 1 2))")
    (:name "ok/subclass-arg" :scope in :expect nil
     :code "\
(defclass animal () ())
(defclass dog (animal) ())
;; (feed :: (function ((:class animal)) integer))
(defun feed (a) 0)
(defun caller (d) (when (dog-p d) (feed d)))"))
  "Labelled recall cases.")

(defun recall--catches-p (file category)
  "Return non-nil if checking FILE yields a finding of CATEGORY."
  (let ((reports (elistan-batch-check-file file)))
    ;; The batch driver renders findings to strings keyed by message; match the
    ;; category via its message signature.
    (seq-some
     (lambda (r)
       (pcase category
         ('call-type-mismatch (string-match-p "expected" r))
         ('dead-branch (string-match-p "unreachable" r))
         ('return-type-mismatch (string-match-p "return type" r))
         ('slot-type-mismatch (string-match-p "slot `" r))
         (_ nil)))
     reports)))

(defun recall--any-finding-p (file)
  "Return non-nil if checking FILE yields ANY finding."
  (consp (elistan-batch-check-file file)))

(let ((in-total 0) (in-caught 0) (out-total 0) (out-leak 0)
      (fp 0) (rows nil))
  (dolist (c recall-cases)
    (let* ((name (plist-get c :name))
           (scope (plist-get c :scope))
           (expect (plist-get c :expect))
           (file (make-temp-file "recall" nil ".el" (plist-get c :code)))
           (caught (and expect (recall--catches-p file expect)))
           (anyfind (recall--any-finding-p file))
           status)
      (cond
       ;; A correct-code case (in-scope, expect nil): must not fire at all.
       ((and (eq scope 'in) (null expect))
        (if anyfind (setq fp (1+ fp) status "FALSE-POSITIVE")
          (setq status "ok (silent)")))
       ;; An in-scope bug: should be caught.
       ((eq scope 'in)
        (setq in-total (1+ in-total))
        (if caught (progn (setq in-caught (1+ in-caught)) (setq status "CAUGHT"))
          (setq status "MISSED")))
       ;; An out-of-scope bug: expected miss; note if it leaks a finding.
       ((eq scope 'out)
        (setq out-total (1+ out-total))
        (if anyfind (setq out-leak (1+ out-leak) status "LEAK(finding)")
          (setq status "miss (by design)"))))
      (push (format "  %-22s %-7s %-18s %s"
                    name scope (or expect "-") status)
            rows)
      (delete-file file)))
  (princ "=== elistan recall measurement ===\n")
  (princ (mapconcat #'identity (nreverse rows) "\n"))
  (princ "\n\n")
  (princ (format "In-scope recall : %d/%d caught (%.0f%%)\n"
                 in-caught in-total (/ (* 100.0 in-caught) (max 1 in-total))))
  (princ (format "Precision (correct cases): %d false positives\n" fp))
  (princ (format "Out-of-scope leaks       : %d/%d emitted a finding\n"
                 out-leak out-total)))
