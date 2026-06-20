;;; elistan-struct.el --- defstruct / defclass as a type source  -*- lexical-binding: t; -*-

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

;; Reads `cl-defstruct' and `defclass' (EIEIO) definitions from the analysed
;; file as a type source.  For each definition it registers the function types
;; of the generated functions — the predicate (a guard, so `(NAME-p x)' narrows
;; x), the constructor (returns the class type), the copier, and the slot
;; accessors.  The class/struct NAME is used as an *opaque* atomic type: two
;; distinct opaque types are not provably disjoint, so this never produces a
;; false positive, while predicate narrowing and constructor result typing add
;; real precision.
;;
;; A slot's declared `:type' (when present) becomes the accessor's return type,
;; so `(NAME-slot x)' is typed precisely instead of `mixed'.  A slot `:type' is
;; treated as an author-written contract (same trust level as an Elsa
;; annotation): EIEIO enforces it at runtime, and `cl-defstruct' does not but
;; the declaration is still the author's stated intent.  Translation is
;; deliberately conservative (docs/adr/0004): anything not confidently modelled
;; collapses to `mixed', so a slot type can never introduce a false positive.
;;
;; Full EIEIO support (the inheritance hierarchy, slot-type-checked `oref'/`oset')
;; needs class subtyping in typespec and is future work (docs/adr/0013).

;;; Code:

(defun elistan-struct--slot-name (slot)
  "Return the symbol name of a defstruct/defclass SLOT spec."
  (cond ((symbolp slot) slot)
        ((consp slot) (car slot))
        (t nil)))

(defun elistan-struct--option (options key)
  "Return the value of OPTION KEY among defstruct OPTIONS (a list), or nil.
Handles both `(:key value)' and bare `:key' forms."
  (seq-some (lambda (o)
              (cond ((and (consp o) (eq (car o) key)) (or (cadr o) t))
                    ((eq o key) t)))
            options))

(defun elistan-struct--bounds-ok-p (bounds)
  "Return non-nil if BOUNDS is a well-formed typespec numeric range tail.
Each bound must be a number or `*', and an explicit numeric LO..HI must be
ordered.  Rejects CL exclusive bounds like `(0)' and inverted ranges, which
would otherwise collapse the type to `never' and so flag every use of the slot."
  (let ((n (proper-list-p bounds)))
    (and n (<= n 2)
         (seq-every-p (lambda (b) (or (numberp b) (eq b '*))) bounds)
         (pcase bounds
           (`(,(and lo (pred numberp)) ,(and hi (pred numberp))) (<= lo hi))
           (_ t)))))

(defun elistan-struct--translate-type (ty)
  "Translate a `cl-defstruct'/`defclass' slot :type TY to a typespec type.
Conservative by design (docs/adr/0004): anything not confidently modelled — and
a missing :type (nil) — becomes `mixed', so a slot type never introduces a
false positive."
  (pcase ty
    ;; A missing :type, CL `t' (top) and CL `nil' (the empty type) all stay
    ;; maximally permissive.  Mapping nil -> `never' would make every accessor
    ;; result look like dead code.
    ((or 'nil 't) 'mixed)
    ('null 'null)
    ;; typespec mis-intersects opaque `boolean' with nil (`boolean' n
    ;; `(const nil)' = never); spell it as the explicit t/nil union, as
    ;; `elistan-elsa--translate-type' does.
    ('boolean '(or (const t) null))
    ;; Any other atomic type symbol: either a primitive typespec handles
    ;; directly (integer, string, …) or an opaque class/alias name, which is
    ;; never provably disjoint from anything — both are false-positive-free.
    ((pred symbolp) ty)
    ;; Unions: translate each member.  Require a non-empty body; an empty
    ;; `(or)' would be `never'.
    (`(or ,_ . ,_) (cons 'or (mapcar #'elistan-struct--translate-type (cdr ty))))
    ;; CL/EIEIO enumerations map onto typespec `member'/`const' directly.
    (`(member ,_ . ,_) ty)
    (`(eql ,v) (list 'const v))
    (`(const ,_) ty)
    ;; Bounded numeric ranges, only when the bounds are well-formed.
    (`(,(or 'integer 'float 'number) . ,bounds)
     (if (elistan-struct--bounds-ok-p bounds) ty 'mixed))
    ;; Parameterised containers: keep the container type, drop element/size
    ;; precision.  A `(list-of T)' value is still a list, a `(vector T N)' still
    ;; a vector, etc. — a sound widening that typespec models as the bare type.
    (`(list-of . ,_) 'list)
    (`(,(or 'vector 'simple-vector) . ,_) 'vector)
    (`(array . ,_) 'array)
    (`(string . ,_) 'string)
    (`(cons . ,_) 'cons)
    ;; Everything else (satisfies, and, function, …) is not reliably modelled:
    ;; fall back to the dynamic top.
    (_ 'mixed)))

(defun elistan-struct--nilable (ty)
  "Return TY widened so a TY-typed value may also be nil.
Used when a slot's initial value can be nil but its declared `:type' does not
admit nil — a `cl-defstruct' slot does not enforce `:type', so an (implicit or
explicit) nil default leaves the slot nil-valued.  Widening keeps the accessor
result from being treated as provably non-nil (which would wrongly flag
`(if (NAME-slot x) ...)' branches), while staying disjoint from any type that
excludes both TY and nil, so genuine mismatches still surface."
  (if (memq ty '(mixed null)) ty (list 'or ty 'null)))

(defun elistan-struct--defstruct (form)
  "Return an alist of generated NAME -> funspec for a `cl-defstruct' FORM."
  (pcase form
    (`(,(or 'cl-defstruct 'defstruct) ,head . ,slots)
     (let* ((options (and (consp head) (cdr head)))
            (name (if (consp head) (car head) head))
            (pred (let ((p (elistan-struct--option options :predicate)))
                    (if (and p (not (eq p t))) p
                      (intern (format "%s-p" name)))))
            (conc (let ((c (elistan-struct--option options :conc-name)))
                    (cond ((and c (not (eq c t))) (format "%s" c))
                          (c "")
                          (t (format "%s-" name)))))
            (ctor (let ((c (elistan-struct--option options :constructor)))
                    (if (and c (not (eq c t))) c
                      (intern (format "make-%s" name)))))
            (acc nil))
       (when (and name (symbolp name))
         (when (and pred (symbolp pred))
           (push (cons pred (list 'function '(t) (list :guard! name))) acc))
         (when (and ctor (symbolp ctor))
           (push (cons ctor (list 'function '(&rest mixed) name)) acc))
         (push (cons (intern (format "copy-%s" name))
                     (list 'function (list name) name))
               acc)
         (dolist (slot slots)
           ;; `slots' may lead with a docstring (a string), which `--slot-name'
           ;; maps to nil; the guard skips it (and anything non-symbol-named).
           (let ((sn (elistan-struct--slot-name slot)))
             (when (and sn (symbolp sn))
               (let* (;; CL slot: `(name [default [keyword value]...])'; :type
                      ;; lives in the keyword plist after the default value.
                      (ty (elistan-struct--translate-type
                           (and (consp slot) (plist-get (cddr slot) :type))))
                      ;; The slot's initial value is its default; a bare name, a
                      ;; `(name)' with no default, or an explicit nil default all
                      ;; leave it nil — which a non-nil `:type' would contradict.
                      (nil-default (or (symbolp slot)
                                       (null (cdr slot))
                                       (null (cadr slot)))))
                 (when nil-default
                   (setq ty (elistan-struct--nilable ty)))
                 (push (cons (intern (concat conc (symbol-name sn)))
                             (list 'function (list name) ty))
                       acc))))))
       (nreverse acc)))
    (_ nil)))

(defun elistan-struct--defclass (form)
  "Return an alist of generated NAME -> funspec for a `defclass' FORM."
  (pcase form
    (`(defclass ,name ,_parents ,slots . ,_)
     (when (and name (symbolp name))
       (let ((acc (list
                   (cons (intern (format "%s-p" name))
                         (list 'function '(t) (list :guard! name)))
                   ;; EIEIO allows `(NAME ...)' as a constructor.
                   (cons name (list 'function '(&rest mixed) name)))))
         ;; Slots may declare an :accessor and a :type.
         (dolist (slot slots)
           (when (consp slot)
             (let* ((plist (cdr slot))
                    (acc-name (plist-get plist :accessor))
                    (ty (elistan-struct--translate-type (plist-get plist :type)))
                    ;; An explicit `:initform nil' leaves the slot nil-valued; an
                    ;; absent :initform leaves it *unbound* (access errors rather
                    ;; than returning nil), so only the explicit case widens.
                    (init (plist-member plist :initform)))
               (when (and init (null (cadr init)))
                 (setq ty (elistan-struct--nilable ty)))
               (when (and acc-name (symbolp acc-name))
                 (push (cons acc-name (list 'function (list name) ty)) acc)))))
         (nreverse acc))))
    (_ nil)))

(defun elistan-struct-parse-buffer ()
  "Scan the current buffer for `cl-defstruct'/`defclass' definitions.
Return an alist of generated NAME -> typespec funspec."
  (let ((result nil))
    (save-excursion
      (goto-char (point-min))
      (condition-case nil
          (while t
            (let ((form (read (current-buffer))))
              (setq result (append result
                                   (elistan-struct--defstruct form)
                                   (elistan-struct--defclass form)))))
        ((end-of-file invalid-read-syntax) nil)))
    result))

(provide 'elistan-struct)
;;; elistan-struct.el ends here
