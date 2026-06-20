;;; elistan-walk-test.el --- Tests for elistan-walk  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  USAMI Kenta

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; End-to-end tests for the analysis walker over whole defuns.

;;; Code:

(require 'ert)
(require 'elistan-walk)

(defun elistan-walk-test--declare (sym spec)
  "Give SYM the declared typespec SPEC for the duration of a test."
  (function-put sym 'typespec (list :spec spec)))

(defun elistan-walk-test--of (findings category)
  "Return the first finding in FINDINGS with CATEGORY, or nil."
  (seq-find (lambda (f) (eq (elistan-finding-category f) category)) findings))

(ert-deftest elistan-walk-call-mismatch ()
  "A provably incompatible argument is reported (category 1)."
  (elistan-walk-test--declare 'et-need-string '(function (string) integer))
  (elistan-walk-test--declare 'et-caller '(function (integer) integer))
  (let* ((fs (elistan-walk-defun '(defun et-caller (n) (et-need-string n))))
         (f (elistan-walk-test--of fs 'call-type-mismatch)))
    (should f)
    (should (equal (plist-get (elistan-finding-data f) :expected) 'string))
    (should (equal (plist-get (elistan-finding-data f) :actual) 'integer))
    (should (= (plist-get (elistan-finding-data f) :arg-index) 0))
    ;; no spurious return-type finding (caller returns integer as declared).
    (should-not (elistan-walk-test--of fs 'return-type-mismatch))))

(ert-deftest elistan-walk-dead-branch ()
  "Narrowing that makes a branch impossible is reported (category 2)."
  (elistan-walk-test--declare 'et-g '(function (string) integer))
  (let* ((fs (elistan-walk-defun '(defun et-g (x) (if (integerp x) 1 2))))
         (f (elistan-walk-test--of fs 'dead-branch)))
    (should f)
    (should (eq (plist-get (elistan-finding-data f) :verdict) 'always-false))
    (should (eq (plist-get (elistan-finding-data f) :dead-branch) 'then))))

(ert-deftest elistan-walk-setq-reassign-invalidates-narrowing ()
  "Reassigning a non-lexical variable clears a prior narrowing (no false branch).
`et-special' is narrowed to nil by the `unless', then `setq' reassigns it; the
later test must not be read as provably nil."
  (let ((fs (elistan-walk-defun
             '(defun et-spec ()
                (unless et-special
                  (setq et-special (compute))
                  (if et-special 'a 'b))))))
    (should-not (elistan-walk-test--of fs 'dead-branch))))

(ert-deftest elistan-walk-lambda-body-dead-branch ()
  "A provably dead branch inside a lambda body is reported."
  (let* ((fs (elistan-walk-defun
              '(defun et-lam (xs)
                 (mapcar (lambda (x)
                           (let ((n (length x)))   ; n : integer
                             (if (stringp n) 1 2))) ; then is dead
                         xs))))
         (f (elistan-walk-test--of fs 'dead-branch)))
    (should f)
    (should (eq (plist-get (elistan-finding-data f) :dead-branch) 'then))))

(ert-deftest elistan-walk-lambda-captured-var-not-flagged ()
  "A captured variable is `unknown' inside a lambda (no false dead branch)."
  (let* ((fs (elistan-walk-defun
              '(defun et-cap ()
                 (let ((s "hi"))               ; string in the enclosing scope
                   (lambda () (if (integerp s) 1 2))))))  ; captured -> unknown
         (f (elistan-walk-test--of fs 'dead-branch)))
    (should-not f)))

(ert-deftest elistan-walk-lambda-call-mismatch ()
  "A provably incompatible call inside a lambda body is reported."
  (elistan-walk-test--declare 'et-need-str2 '(function (string) integer))
  (let* ((fs (elistan-walk-defun
              '(defun et-uses (xs)
                 (mapcar (lambda (x)
                           (let ((n (length x))) ; integer
                             (et-need-str2 n)))   ; expects string -> mismatch
                         xs))))
         (f (elistan-walk-test--of fs 'call-type-mismatch)))
    (should f)
    (should (equal (plist-get (elistan-finding-data f) :expected) 'string))
    (should (equal (plist-get (elistan-finding-data f) :actual) 'integer))))

(ert-deftest elistan-walk-oref-slot-type ()
  "`(slot-value obj 'slot)' / `(oref obj slot)' reads are typed as the slot type.
A slot typed integer makes `(stringp …)' on it a provably dead branch."
  (elistan-walk-test--declare 'et-w1 '(function ((:class widget)) integer))
  (elistan-walk-test--declare 'et-w2 '(function ((:class button)) integer))
  (let ((elistan-walk-class-slots '((widget (width . integer))))
        (typespec-eval-types-class-parents '((button widget))))
    ;; slot-value on the object's own slot -> integer -> `then' dead.
    (should (elistan-walk-test--of
             (elistan-walk-defun
              '(defun et-w1 (obj)
                 (let ((n (slot-value obj 'width))) (if (stringp n) 1 2))))
             'dead-branch))
    ;; oref on a slot INHERITED via the hierarchy (button <- widget) -> integer.
    (should (elistan-walk-test--of
             (elistan-walk-defun
              '(defun et-w2 (obj)
                 (let ((n (oref obj width))) (if (stringp n) 1 2))))
             'dead-branch))
    ;; An unknown slot stays `unknown' -> no finding (no false positive).
    (should-not (elistan-walk-test--of
                 (elistan-walk-defun
                  '(defun et-w1 (obj)
                     (let ((n (slot-value obj 'missing))) (if (stringp n) 1 2))))
                 'dead-branch))))

(ert-deftest elistan-walk-return-mismatch ()
  "A body type incompatible with the declared return is reported (category 3)."
  (elistan-walk-test--declare 'et-h '(function (string) integer))
  (let* ((fs (elistan-walk-defun '(defun et-h (x) x)))
         (f (elistan-walk-test--of fs 'return-type-mismatch)))
    (should f)
    (should (equal (plist-get (elistan-finding-data f) :declared) 'integer))
    (should (equal (plist-get (elistan-finding-data f) :actual) 'string))))

(ert-deftest elistan-walk-clean ()
  "A well-typed function with full branch coverage produces no findings."
  (elistan-walk-test--declare 'et-ok '(function ((or string integer)) string))
  (should-not
   (elistan-walk-defun
    '(defun et-ok (x) (if (stringp x) x (number-to-string x))))))

(ert-deftest elistan-walk-guard-clause-narrowing ()
  "An early-exit guard narrows the fall-through path (divergence-aware join)."
  ;; After `(when (stringp x) (error ...))', x is integer; a later `(stringp x)'
  ;; is then provably false -> a dead-branch finding.  Without the guard there is
  ;; no such finding (stringp could go either way).  This isolates the narrowing.
  (elistan-walk-test--declare 'et-guard '(function ((or string integer)) integer))
  (should (elistan-walk-test--of
           (elistan-walk-defun
            '(defun et-guard (x)
               (when (stringp x) (error "no strings"))
               (if (stringp x) 1 2)))
           'dead-branch))
  (elistan-walk-test--declare 'et-noguard '(function ((or string integer)) integer))
  (should-not (elistan-walk-test--of
               (elistan-walk-defun '(defun et-noguard (x) (if (stringp x) 1 2)))
               'dead-branch)))

(ert-deftest elistan-walk-loop-no-false-positive ()
  "A mutating loop widens assigned variables and emits no spurious findings."
  (elistan-walk-test--declare 'et-loop '(function (integer) integer))
  (should-not
   (elistan-walk-defun
    '(defun et-loop (n)
       (let ((acc 0))
         (while (> n 0)
           (setq acc (+ acc n))
           (setq n (1- n)))
         acc)))))

(ert-deftest elistan-walk-no-false-dead-branch-from-and ()
  "An `and' test must not leak narrowing into a later `cond' clause."
  ;; Regression: clause 1's `(not ca)' narrowed `ca'; if that leaked into the
  ;; clause-2 environment, `(and ca ...)' would look unreachable (false dead).
  (should-not
   (elistan-walk-test--of
    (elistan-walk-defun
     '(defun et-andleak (a b)
        (let ((ca a) (cb b))
          (cond ((and cb (not ca)) 1)
                ((and ca (not cb)) 2)
                (t 3)))))
    'dead-branch)))

(ert-deftest elistan-walk-closure-mutation-no-false-positive ()
  "A variable `setq'-mutated inside a closure must not be assumed constant."
  ;; `found' is bound to nil, then mutated inside a lambda passed to `mapc'
  ;; (whose body the walker does not descend into).  It must NOT be treated as
  ;; always-nil, or `(if found ...)' would be a false dead-branch.
  (should-not
   (elistan-walk-test--of
    (elistan-walk-defun
     '(defun et-closure (items)
        (let ((found nil))
          (mapc (lambda (x) (when x (setq found x))) items)
          (if found 1 2))))
    'dead-branch)))

(ert-deftest elistan-walk-destructive-op-clears-narrowing ()
  "An in-place destructive op clears its variable's narrowing."
  ;; Mirrors `(while (consp x) ... (!cdr x) ... (if (consp x) ...))' from real
  ;; code: after the mutation, `(consp x)' is no longer known to hold, so the
  ;; second test must NOT be flagged as a dead branch.
  (should-not
   (elistan-walk-test--of
    (elistan-walk-defun
     '(defun et-destr (x)
        (while (consp x)
          (!cdr x)
          (if (consp x) 1 2))))
    'dead-branch)))

(ert-deftest elistan-walk-improper-list-robustness ()
  "Improper (dotted) sub-forms must not crash the walker."
  (should (listp (elistan-walk-defun
                  '(defun et-dotted (x) (foo (x . y) '(a . b))))))
  (should (listp (elistan-walk-defun
                  '(defun et-dotted2 (f) (-lambda ((head . tail)) (cons head tail)))))))

(ert-deftest elistan-walk-and-setq-mutation ()
  "A `setq' inside `and' (as `when-let' expands to) propagates out of the and."
  ;; Without carrying the mutation, `found' would stay null and `(if found ...)'
  ;; would be a false dead-branch.
  (should-not
   (elistan-walk-test--of
    (elistan-walk-defun
     '(defun et-andsetq (x)
        (let ((found nil))
          (when (and x (setq found x)) (ignore found))
          (if found 1 2))))
    'dead-branch)))

(ert-deftest elistan-walk-builtin-args-not-flagged ()
  "Calls to non-authoritative (builtin/fallback) functions are not arg-checked."
  ;; `number-to-string' (fallback) wants a number; passing the string `s' is NOT
  ;; flagged, because builtin databases are coverage heuristics, not contracts.
  (elistan-walk-test--declare 'et-bi '(function (string) string))
  (should-not (elistan-walk-test--of
               (elistan-walk-defun '(defun et-bi (s) (number-to-string s) s))
               'call-type-mismatch)))

(ert-deftest elistan-walk-condition-case-handler-mutation ()
  "A `setq' in a condition-case handler is carried out (no false dead-branch)."
  (should-not
   (elistan-walk-test--of
    (elistan-walk-defun
     '(defun et-cc (x)
        (let ((skip nil))
          (condition-case e (setq x (frob x)) (error (setq skip t)))
          (if skip 1 2))))
    'dead-branch)))

(ert-deftest elistan-walk-free-variable-not-tracked ()
  "A free/special variable is not assumed constant after `(setq it nil)'."
  (should-not
   (elistan-walk-test--of
    (elistan-walk-defun
     '(defun et-free (x)
        (setq et-some-global nil)
        (frob x)
        (if et-some-global 1 2)))
    'dead-branch)))

(ert-deftest elistan-walk-nil-binding-not-constant ()
  "A variable bound to the literal nil is treated as unknown, not null."
  (should-not
   (elistan-walk-test--of
    (elistan-walk-defun
     '(defun et-nilb (x)
        (let ((acc nil))
          (external-filler)
          (if acc 1 2))))
    'dead-branch)))

(ert-deftest elistan-walk-macroexpand-failure-no-crash ()
  "A defun whose macro expansion could fail does not crash the walker."
  (should (listp (elistan-walk-defun
                  '(defun et-nl (n)
                     (named-let loop ((i 0)) (when (< i n) (loop (1+ i)))))))))

(ert-deftest elistan-walk-huge-form-terminates ()
  "A very large body terminates (work budget + type-size cap), not hangs."
  ;; 5000 accumulating setqs would blow up the type of `acc' without the cap.
  (let ((body (cons 'progn (make-list 5000 '(setq acc (cons 1 acc))))))
    (should (listp (elistan-walk-defun (list 'defun 'et-huge '(acc) body))))))

(ert-deftest elistan-walk-non-defun ()
  "Non-function-defining top-level forms are out of scope."
  (should-not (elistan-walk-form '(defvar foo nil)))
  (should-not (elistan-walk-form '(message "hi"))))

(provide 'elistan-walk-test)
;;; elistan-walk-test.el ends here
