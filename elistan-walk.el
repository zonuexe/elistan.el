;;; elistan-walk.el --- The elistan analysis walker  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  USAMI Kenta

;; Author: USAMI Kenta <tadsan@zonu.me>
;; Keywords: lisp, extensions, tools
;; License: GPL-3.0-or-later

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

;; The analysis core: walks an already-macroexpanded function body, threading a
;; type environment, and emits findings.  See docs/adr/0010 (env-threading and
;; divergence-aware confluence), 0011 (mutation and loops), 0012 (return-type
;; check).
;;
;; `elistan-walk-type' returns `(TYPE . ENV)' for a form: its value type and the
;; environment after it (carrying `setq' mutations).  Condition effects are kept
;; separate, in `elistan-recognise' (ADR-0009).  Findings are collected in the
;; dynamic variable `elistan-walk--findings' for the duration of a defun walk.

;;; Code:

(require 'cl-lib)
(require 'elistan)
(require 'elistan-type)
(require 'elistan-source)
(require 'elistan-recognise)
(require 'elistan-finding)
(require 'typespec-eval)

(defvar elistan-walk--findings nil
  "Accumulator (dynamically bound per defun walk) of `elistan-finding' values.")

(defconst elistan-walk--destructive-ops
  '(setf setq-default push pop cl-incf cl-decf incf decf cl-pushnew pushnew
    !cdr !cons)
  "Operators that mutate a bare-variable argument in place.
After such a call the argument's narrowing is cleared (set to `unknown'),
covering destructive forms that stay unexpanded when a library is not loaded.
Forms that macroexpand to `setq' (the loaded `push'/`setf'/… in most cases) are
handled by the `setq' path instead.")

(defvar elistan-walk--lexical-vars nil
  "Bare variables that are lexical in the current scope (params + `let' bindings).
Only these are tracked through `setq': a free/special variable can be mutated
unobservably by any function it is dynamically bound around, so its type is left
`unknown' rather than assumed constant.")

(defun elistan-walk--arglist-vars (arglist)
  "Return the bare parameter symbols in ARGLIST (dropping &-markers)."
  (delq nil (mapcar (lambda (p)
                      (and (symbolp p)
                           (let ((b (elistan-walk--bare p)))
                             (and (not (memq b '(&optional &rest &key
                                                 &allow-other-keys)))
                                  b))))
                    arglist)))

(defvar elistan-walk--closure-vars nil
  "Bare variables `setq'-assigned inside a lambda within the current defun.
Such variables are captured by a closure we do not analyse, so their value at
any read is uncertain; they are kept at `unknown' to avoid false positives.")

(defun elistan-walk--bind (env var type)
  "Bind VAR to TYPE in ENV, or to `unknown' if VAR is closure-mutated."
  (elistan-env-set env var
                   (if (memq (elistan-walk--bare var) elistan-walk--closure-vars)
                       'unknown type)))

(defun elistan-walk--closure-assigned-vars (form)
  "Return the bare variables `setq'-assigned inside a lambda within FORM."
  (let (vars)
    (cl-labels ((scan (f in-lambda)
                  (when (and (consp f) (not (eq (car-safe f) 'quote)))
                    (let ((in (or in-lambda
                                  (memq (car-safe f) '(lambda closure)))))
                      (when (and in (eq (car-safe f) 'setq))
                        (let ((p (cdr f)))
                          (while (and (consp p) (consp (cdr p)))
                            (when (symbolp (car p))
                              (push (elistan-walk--bare (car p)) vars))
                            (setq p (cddr p)))))
                      (let ((x f))
                        (while (consp x)
                          (elistan-walk--tick)
                          (scan (car x) in) (setq x (cdr x))))))))
      (scan form nil))
    (delete-dups vars)))

(defun elistan-walk--emit (category pos data &optional severity)
  "Record a finding of CATEGORY at POS with DATA (and optional SEVERITY)."
  (push (elistan-finding-create :category category :pos pos
                                :severity (or severity :warning) :data data)
        elistan-walk--findings))

(defvar elistan-walk--budget nil
  "Remaining work budget for the current defun walk, or nil for unlimited.
Bounds worst-case time so a pathological form — a huge macro-generated body, or
a circular list from `#N=' read syntax — can never hang the checker.")

(defmacro elistan-walk--tick ()
  "Spend one unit of the analysis budget; abort the walk when it is exhausted."
  '(when (and elistan-walk--budget
              (< (setq elistan-walk--budget (1- elistan-walk--budget)) 0))
     (throw 'elistan-walk--over nil)))

(defun elistan-walk--pos (form)
  "Best-effort source position of FORM (via symbol-with-pos), or nil."
  (cond ((symbol-with-pos-p form) (symbol-with-pos-pos form))
        ((consp form) (elistan-walk--pos (car form)))
        (t nil)))

;;; Confluence

(defun elistan-walk--confluence (branches fallback-env)
  "Join surviving BRANCHES (each a `(TYPE . ENV)').
With none surviving the result is `(never . FALLBACK-ENV)'."
  (pcase branches
    ('() (cons 'never fallback-env))
    (`(,only) only)
    (_ (cons (apply #'elistan-type-union (mapcar #'car branches))
             (cl-reduce #'elistan-env-join (mapcar #'cdr branches))))))

;;; Core dispatch

(defun elistan-walk-type (form env)
  "Return `(TYPE . ENV)' for FORM under ENV, emitting findings as a side effect."
  (elistan-walk--tick)
  (cond
   ((null form) (cons 'null env))
   ((eq form t) (cons '(const t) env))
   ((keywordp form) (cons (list 'const form) env))
   ((symbolp form) (cons (elistan-env-get env form) env))
   ((numberp form) (cons (list 'const form) env))
   ((stringp form) (cons 'string env))
   ((vectorp form) (cons 'vector env))
   ((consp form) (elistan-walk--list form env))
   (t (cons 'unknown env))))

(defun elistan-walk--list (form env)
  "Dispatch a cons FORM under ENV."
  (pcase form
    (`(quote ,v) (cons (if (null v) 'null (list 'const v)) env))
    (`(function ,_) (cons 'function env))
    (`(lambda . ,_) (cons 'function env))
    (`(if ,test ,then . ,else) (elistan-walk--if test then else env))
    (`(cond . ,clauses) (elistan-walk--cond clauses env))
    (`(and . ,args) (elistan-walk--and args env))
    (`(or . ,args) (elistan-walk--or args env))
    (`(progn . ,body) (elistan-walk--progn body env))
    (`(prog1 ,first . ,rest) (elistan-walk--prog1 first rest env))
    (`(,(or 'save-excursion 'save-restriction 'save-current-buffer) . ,body)
     (elistan-walk--progn body env))
    (`(let ,bindings . ,body) (elistan-walk--let bindings body env nil))
    (`(let* ,bindings . ,body) (elistan-walk--let bindings body env t))
    (`(setq . ,pairs) (elistan-walk--setq pairs env))
    (`(while ,test . ,body) (elistan-walk--while test body env))
    (`(unwind-protect ,body . ,cleanup) (elistan-walk--unwind body cleanup env))
    (`(condition-case ,_ ,bodyform . ,handlers)
     (elistan-walk--condition-case bodyform handlers env))
    (`(catch ,_ . ,body)
     (cons 'unknown (cdr (elistan-walk--progn body env))))
    (`(,(pred symbolp) . ,_) (elistan-walk--call form env))
    (_ (cons 'unknown env))))

;;; Control forms

(defun elistan-walk--if (test then else env)
  "Walk `(if TEST THEN ELSE...)' under ENV."
  (let* ((tres (elistan-walk-type test env))
         (tt (car tres)) (te (cdr tres))
         (refn (elistan-recognise test te))
         (true-env (elistan-refine-true te refn))
         (false-env (elistan-refine-false te refn))
         (pos (elistan-walk--pos test))
         ;; A branch is dead when narrowing makes a tested variable `never'
         ;; (e.g. testing `(integerp x)' where x : string).
         (true-never (cl-some (lambda (c) (elistan-type-never-p (cadr c))) refn))
         (false-never (cl-some (lambda (c) (elistan-type-never-p (cddr c))) refn))
         (verdict (cond
                   ((or (elistan-type-never-nil-p tt) false-never) 'always-true)
                   ((or (elistan-type-always-nil-p tt)
                        (elistan-type-never-p tt) true-never) 'always-false)
                   (t nil))))
    (pcase verdict
      ('always-true
       (elistan-walk--emit 'dead-branch pos
                           (list :test test :verdict 'always-true :dead-branch 'else))
       (elistan-walk-type then true-env))
      ('always-false
       (elistan-walk--emit 'dead-branch pos
                           (list :test test :verdict 'always-false :dead-branch 'then))
       (if else (elistan-walk--progn else false-env) (cons 'null false-env)))
      (_
       (let* ((thn (elistan-walk-type then true-env))
              (els (if else (elistan-walk--progn else false-env)
                     (cons 'null false-env)))
              (survivors (cl-remove-if
                          (lambda (b) (elistan-type-never-p (car b)))
                          (list thn els))))
         (elistan-walk--confluence survivors te))))))

(defun elistan-walk--cond (clauses env)
  "Walk `(cond CLAUSES...)' under ENV."
  (let ((e env) (branches nil) (exhaustive nil))
    (catch 'done
      (dolist (clause clauses)
        (let* ((test (car clause)) (body (cdr clause))
               (tr (elistan-walk-type test e)) (tt (car tr)) (te (cdr tr))
               (refn (elistan-recognise test te))
               (true-env (elistan-refine-true te refn))
               (true-never (cl-some (lambda (c) (elistan-type-never-p (cadr c)))
                                    refn)))
          (if true-never
              (elistan-walk--emit 'dead-branch (elistan-walk--pos test)
                                  (list :test test :verdict 'always-false
                                        :dead-branch 'then))
            (push (if body (elistan-walk--progn body true-env) (cons tt true-env))
                  branches))
          (setq e (elistan-refine-false te refn))
          (when (elistan-type-never-nil-p tt)
            (setq exhaustive t) (throw 'done nil)))))
    (unless exhaustive (push (cons 'null e) branches))
    (let ((survivors (cl-remove-if (lambda (b) (elistan-type-never-p (car b)))
                                   (nreverse branches))))
      (elistan-walk--confluence survivors env))))

;; NOTE: `and'/`or' use progressive narrowing *internally* (to type each operand
;; under the assumption that earlier ones held), but that narrowing must NOT leak
;; into the returned out-env — the out-env carries only mutation (ADR-0010), and
;; the whole form's condition effect is computed separately by
;; `elistan-recognise'.  Leaking it would double-apply narrowing at the
;; enclosing `if'/`cond' and manufacture false dead-branch findings.

(defun elistan-walk--carry-mutations (env threaded forms)
  "Return ENV with each variable `setq'-assigned in FORMS widened from THREADED.
A `setq' inside `and'/`or' is *conditional* (it runs only if the earlier
operands were truthy / nil), so the variable's out-type is the union of its
original type and the assigned one — never just the assigned one, which would
wrongly narrow it.  Narrowing on non-assigned variables is left behind."
  (let ((out env))
    (dolist (v (elistan-walk--assigned-vars (cons 'progn forms)) out)
      (setq out (elistan-env-set
                 out v (elistan-type-union (elistan-env-get env v)
                                           (elistan-env-get threaded v)))))))

(defun elistan-walk--and (args env)
  "Walk `(and ARGS...)' under ENV with internal progressive narrowing.
The out-env keeps `setq' mutations from the operands but not the speculative
narrowing (which is the separate recogniser's job)."
  (if (null args)
      (cons '(const t) env)
    (let ((e env) (last 'null) (diverged nil))
      (dolist (a args)
        (unless diverged
          (let* ((r (elistan-walk-type a e)) (at (car r)) (ae (cdr r)))
            (setq last at)
            (if (elistan-type-never-p at)
                (setq e ae diverged t)
              (setq e (elistan-refine-true ae (elistan-recognise a ae)))))))
      (cons (if diverged 'never (elistan-type-union 'null last))
            (elistan-walk--carry-mutations env e args)))))

(defun elistan-walk--or (args env)
  "Walk `(or ARGS...)' under ENV with internal progressive narrowing.
The out-env keeps `setq' mutations but not the speculative narrowing."
  (if (null args)
      (cons 'null env)
    (let ((e env) (types nil))
      (catch 'diverge
        (dolist (a args)
          (let* ((r (elistan-walk-type a e)) (at (car r)) (ae (cdr r)))
            (push at types)
            (when (elistan-type-never-p at) (setq e ae) (throw 'diverge nil))
            (setq e (elistan-refine-false ae (elistan-recognise a ae))))))
      (cons (apply #'elistan-type-union (nreverse types))
            (elistan-walk--carry-mutations env e args)))))

(defun elistan-walk--progn (body env)
  "Walk an implicit-progn BODY under ENV; divergence stops the sequence."
  (let ((e env) (ty 'null))
    (catch 'diverge
      (dolist (f body)
        (let ((r (elistan-walk-type f e)))
          (setq ty (car r) e (cdr r))
          (when (elistan-type-never-p ty) (throw 'diverge nil)))))
    (cons ty e)))

(defun elistan-walk--prog1 (first rest env)
  "Walk `(prog1 FIRST REST...)' under ENV."
  (let* ((fr (elistan-walk-type first env)) (ft (car fr)))
    (if (elistan-type-never-p ft)
        fr
      (cons ft (cdr (elistan-walk--progn rest (cdr fr)))))))

(defun elistan-walk--let (bindings body env sequential)
  "Walk `(let/let* BINDINGS BODY...)'; SEQUENTIAL non-nil for `let*'."
  (let ((work-env env) (vars nil))
    (dolist (b bindings)
      (let* ((var (if (consp b) (car b) b))
             (init (if (consp b) (cadr b) nil))
             ;; A binding to the literal `nil' is almost always an accumulator
             ;; or flag that gets mutated later — sometimes by a path we cannot
             ;; see (a dynamic special variable an external function fills in).
             ;; Seed it as `unknown', not `null', so we never wrongly conclude
             ;; "always nil".  Concrete-typed bindings keep their precise type.
             (itype (if (null init)
                        'unknown
                      (let ((ir (elistan-walk-type init (if sequential work-env env))))
                        (when sequential (setq work-env (cdr ir)))
                        (car ir)))))
        (push var vars)
        (setq work-env (elistan-walk--bind work-env var itype))))
    (let* ((elistan-walk--lexical-vars
            (append (mapcar #'elistan-walk--bare vars) elistan-walk--lexical-vars))
           (br (elistan-walk--progn body work-env))
           (be (cdr br)))
      ;; Local bindings do not leak: restore the outer type of each bound var.
      (dolist (v vars)
        (setq be (elistan-env-set be v (elistan-env-get env v))))
      (cons (car br) be))))

(defun elistan-walk--setq (pairs env)
  "Walk `(setq PAIRS...)' under ENV, rebinding each assigned variable."
  (let ((e env) (ty 'null) (p pairs))
    (while (and (consp p) (consp (cdr p)))
      (let ((r (elistan-walk-type (cadr p) e)))
        (setq ty (car r)
              ;; Only track assignment to a lexical variable; a free/special
              ;; variable may be changed by code we cannot see.
              e (if (memq (elistan-walk--bare (car p)) elistan-walk--lexical-vars)
                    (elistan-walk--bind (cdr r) (car p) ty)
                  (cdr r))
              p (cddr p))))
    (cons ty e)))

(defun elistan-walk--assigned-vars (form)
  "Return the list of variables assigned by `setq' anywhere within FORM.
Tolerates improper (dotted) lists and does not descend into quoted data."
  (let (vars)
    (cl-labels ((scan (f)
                  (when (and (consp f) (not (eq (car-safe f) 'quote)))
                    (when (eq (car-safe f) 'setq)
                      (let ((p (cdr f)))
                        (while (and (consp p) (consp (cdr p)))
                          (when (symbolp (car p)) (push (car p) vars))
                          (setq p (cddr p)))))
                    ;; Walk elements, tolerating an improper tail.
                    (let ((x f))
                      (while (consp x)
                        (elistan-walk--tick)
                        (scan (car x)) (setq x (cdr x)))))))
      (scan form))
    (delete-dups vars)))

(defun elistan-walk--while (test body env)
  "Walk `(while TEST BODY...)'; body-assigned variables are widened (ADR-0011)."
  (let ((we env))
    (dolist (v (elistan-walk--assigned-vars (cons test body)))
      (setq we (elistan-env-set we v 'unknown)))
    (let* ((tr (elistan-walk-type test we)) (te (cdr tr))
           (refn (elistan-recognise test te)))
      (elistan-walk--progn body (elistan-refine-true te refn))
      (cons 'null (elistan-refine-false te refn)))))

(defun elistan-walk--unwind (body cleanup env)
  "Walk `(unwind-protect BODY CLEANUP...)' under ENV."
  (let ((br (elistan-walk-type body env)))
    (elistan-walk--progn cleanup (cdr br))
    br))

(defun elistan-walk--condition-case (bodyform handlers env)
  "Walk `(condition-case VAR BODYFORM HANDLERS...)' under ENV (approximated).
The value is the union of the body and handler values; mutations from the body
and handlers are carried out conditionally (the body may error partway, or a
handler may run), so an assigned variable is widened to the union of its types."
  (let* ((br (elistan-walk-type bodyform env))
         (types (list (car br)))
         (envs (list (cdr br)))
         (forms (list bodyform)))
    (dolist (h handlers)
      (when (consp h)
        (let ((hr (elistan-walk--progn (cdr h) env)))
          (push (car hr) types)
          (push (cdr hr) envs)
          (setq forms (append forms (cdr h))))))
    (cons (apply #'elistan-type-union types)
          (elistan-walk--carry-mutations
           env (cl-reduce #'elistan-env-join envs) forms))))

;;; Calls

(defun elistan-walk--call-result (funspec arg-types)
  "Return the result type of calling FUNSPEC with ARG-TYPES.
Dynamic arguments are sanitised to `mixed' so typespec does not flag them; a
guard return types as `boolean'; anything typespec cannot type is `unknown'."
  (let ((ret (elistan-source-return funspec)))
    (cond
     ((memq (car-safe ret) '(:guard :guard!)) 'boolean)
     ((eq (car-safe ret) :assert) (cadr ret))
     (t (let* ((sani (mapcar (lambda (ty) (if (elistan-type-dynamic-p ty) 'mixed ty))
                             arg-types))
               (r (typespec-eval-call funspec sani)))
          (if (eq (car-safe r) :cause-error) 'unknown r))))))

(defun elistan-walk--check-args (fn funspec arg-types arg-forms)
  "Emit a finding for each ARG-TYPE provably incompatible with FUNSPEC's params."
  (let* ((split (elistan-source-arglist funspec))
         (params (append (plist-get split :required) (plist-get split :optional)))
         (rest (plist-get split :rest))
         (n (length params))
         (idx 0))
    (cl-mapc
     (lambda (at af)
       (let ((expected (cond ((< idx n) (nth idx params))
                             (rest rest)
                             (t nil))))
         (when (and expected (not (elistan-type-consistent-p at expected)))
           (elistan-walk--emit 'call-type-mismatch (elistan-walk--pos af)
                               (list :function (elistan-walk--bare fn)
                                     :arg-index idx :expected expected :actual at))))
       (setq idx (1+ idx)))
     arg-types arg-forms)))

(defun elistan-walk--bare (sym)
  "Return the bare symbol of SYM if it carries a position, else SYM."
  (if (symbol-with-pos-p sym) (bare-symbol sym) sym))

(defun elistan-walk--call (form env)
  "Walk a function call FORM under ENV: type args, check them, type the result.
Tolerates an improper (dotted) FORM by iterating only its proper prefix."
  (let ((env2 env) (arg-types nil) (arg-forms nil) (tail (cdr form)))
    (while (consp tail)
      (let ((r (elistan-walk-type (car tail) env2)))
        (push (car r) arg-types)
        (push (car tail) arg-forms)
        (setq env2 (cdr r)))
      (setq tail (cdr tail)))
    (setq arg-types (nreverse arg-types)
          arg-forms (nreverse arg-forms))
    (let ((fn (elistan-walk--bare (car form))))
      ;; A destructive op invalidates the narrowing of its variable arguments.
      (when (memq fn elistan-walk--destructive-ops)
        (dolist (af arg-forms)
          (when (symbolp af)
            (setq env2 (elistan-env-set env2 (elistan-walk--bare af) 'unknown)))))
      (let ((funspec (elistan-source-function-spec fn)))
        (if (not funspec)
            (cons 'unknown env2)
          (progn
            ;; Only check arguments against an author-written contract; builtin
            ;; databases are coverage heuristics (may be too strict).
            (when (elistan-source-authoritative-p fn)
              (elistan-walk--check-args (car form) funspec arg-types arg-forms))
            (cons (elistan-walk--call-result funspec arg-types) env2)))))))

;;; Entry points

(defun elistan-walk--seed-env (arglist funspec)
  "Build the entry environment from ARGLIST and the declared FUNSPEC (ADR-0007)."
  (let* ((split (and funspec (elistan-source-arglist funspec)))
         (req (plist-get split :required))
         (opt (plist-get split :optional))
         (rest (plist-get split :rest))
         (state 'required) (ri 0) (oi 0)
         (env (elistan-env-make)))
    (dolist (p arglist)
      (cond
       ((eq p '&optional) (setq state 'optional))
       ((eq p '&rest) (setq state 'rest))
       ((memq p '(&key &allow-other-keys)) (setq state 'ignore))
       (t (pcase state
            ('required (setq env (elistan-walk--bind env p (or (nth ri req) 'unknown)))
                       (setq ri (1+ ri)))
            ('optional (setq env (elistan-walk--bind env p (or (nth oi opt) 'unknown)))
                       (setq oi (1+ oi)))
            ('rest (setq env (elistan-walk--bind
                              env p (if rest (list 'list rest) 'list))))))))
    env))

(defun elistan-walk-defun (form)
  "Analyse a function-defining FORM and return a list of `elistan-finding'."
  ;; Bind the flag around the whole match so positioned symbols (from a
  ;; position-aware reader) compare as their bare symbols throughout.
  (let ((symbols-with-pos-enabled t))
    (pcase form
      (`(,(or 'defun 'defsubst 'cl-defun) ,name ,arglist . ,body)
       (let* ((elistan-walk--findings nil)
              ;; Bound work budget: a pathological body (huge macro-generated
              ;; form, circular literal) aborts with partial findings instead of
              ;; hanging.  Normal defuns use a tiny fraction of this.
              (elistan-walk--budget 600000)
              (funspec (elistan-source-function-spec (elistan-walk--bare name)))
              ;; Macro expansion can fail (e.g. `named-let' demands
              ;; lexical-binding, or a macro is not loaded); degrade to the
              ;; unexpanded body rather than crash (ADR-0005).
              (expanded (condition-case nil
                            (let ((lexical-binding t))
                              (macroexpand-all (cons 'progn body)))
                          (error (cons 'progn body)))))
         (catch 'elistan-walk--over
           (let* ((elistan-walk--closure-vars
                   (elistan-walk--closure-assigned-vars expanded))
                  (elistan-walk--lexical-vars (elistan-walk--arglist-vars arglist))
                  (env (elistan-walk--seed-env arglist funspec))
                  (body-type (car (elistan-walk-type expanded env))))
             (when funspec
               (let ((declared (elistan-source-return funspec)))
                 (when (and declared
                            (not (memq (car-safe declared) '(:guard :guard! :assert)))
                            (not (eq declared 'unknown))
                            (not (elistan-type-never-p body-type))
                            (not (elistan-type-dynamic-p body-type))
                            (not (elistan-type-consistent-p body-type declared)))
                   (elistan-walk--emit 'return-type-mismatch (elistan-walk--pos name)
                                       (list :declared declared :actual body-type)))))))
         (nreverse elistan-walk--findings)))
      (_ nil))))

(defun elistan-walk-form (form)
  "Analyse a single top-level FORM; non-function-defining forms yield nil."
  (and (consp form)
       (memq (elistan-walk--bare (car form)) '(defun defsubst cl-defun))
       (elistan-walk-defun form)))

(defun elistan-check-forms (forms)
  "Analyse each top-level form in FORMS and return all findings."
  (apply #'append (mapcar #'elistan-walk-form forms)))

(provide 'elistan-walk)
;;; elistan-walk.el ends here
