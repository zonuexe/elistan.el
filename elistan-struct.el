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

(defun elistan-struct--class-type (name)
  "Return the typespec class type `(:class NAME)' for class/struct NAME.
typespec gives `(:class …)' static subtyping from the hierarchy supplied via
`typespec-eval-types-class-parents' (see `elistan-struct-parse-hierarchy'), so
a subclass instance is accepted where a superclass is wanted while unrelated
classes stay non-disjoint (no false positive)."
  (list :class name))

(defun elistan-struct--conc-name (name options)
  "Return the accessor-name prefix string for `cl-defstruct' NAME with OPTIONS."
  (let ((c (elistan-struct--option options :conc-name)))
    (cond ((and c (not (eq c t))) (format "%s" c))
          (c "")
          (t (format "%s-" name)))))

(defun elistan-struct--slot-type (slot)
  "Return the typespec type for a `cl-defstruct' SLOT spec.
Translates the slot `:type' and applies the nil-default widening (a bare name,
a `(name)' with no default, or an explicit nil default leaves the slot nil)."
  (let ((ty (elistan-struct--translate-type
             (and (consp slot) (plist-get (cddr slot) :type))))
        (nil-default (or (symbolp slot) (null (cdr slot)) (null (cadr slot)))))
    (if nil-default (elistan-struct--nilable ty) ty)))

(defun elistan-struct--defstruct (form)
  "Return an alist of generated NAME -> funspec for a `cl-defstruct' FORM."
  (pcase form
    (`(,(or 'cl-defstruct 'defstruct) ,head . ,slots)
     (let* ((options (and (consp head) (cdr head)))
            (name (if (consp head) (car head) head))
            (pred (let ((p (elistan-struct--option options :predicate)))
                    (if (and p (not (eq p t))) p
                      (intern (format "%s-p" name)))))
            (conc (elistan-struct--conc-name name options))
            (ctor (let ((c (elistan-struct--option options :constructor)))
                    (if (and c (not (eq c t))) c
                      (intern (format "make-%s" name)))))
            (copier (let ((c (elistan-struct--option options :copier)))
                      (if (and c (not (eq c t))) c
                        (intern (format "copy-%s" name)))))
            (ctype (elistan-struct--class-type name))
            (acc nil))
       (when (and name (symbolp name))
         (when (and pred (symbolp pred))
           (push (cons pred (list 'function '(t) (list :guard! ctype))) acc))
         (when (and ctor (symbolp ctor))
           (push (cons ctor (list 'function '(&rest mixed) ctype)) acc))
         (when (and copier (symbolp copier))
           (push (cons copier (list 'function (list ctype) ctype)) acc))
         (dolist (slot slots)
           ;; `slots' may lead with a docstring (a string), which `--slot-name'
           ;; maps to nil; the guard skips it (and anything non-symbol-named).
           (let ((sn (elistan-struct--slot-name slot)))
             (when (and sn (symbolp sn))
               (push (cons (intern (concat conc (symbol-name sn)))
                           (list 'function (list ctype)
                                 (elistan-struct--slot-type slot)))
                     acc)))))
       (nreverse acc)))
    (_ nil)))

(defun elistan-struct--defclass-slot-type (slot)
  "Return the typespec type for a `defclass' SLOT spec.
Translates the slot `:type'; an explicit `:initform nil' widens it with nil (an
absent :initform leaves the slot *unbound* — access errors rather than returning
nil — so it does not widen)."
  (let ((ty (elistan-struct--translate-type (plist-get (cdr slot) :type)))
        (init (plist-member (cdr slot) :initform)))
    (if (and init (null (cadr init))) (elistan-struct--nilable ty) ty)))

(defun elistan-struct--defclass (form)
  "Return an alist of generated NAME -> funspec for a `defclass' FORM."
  (pcase form
    (`(defclass ,name ,_parents ,slots . ,_)
     (when (and name (symbolp name))
       (let* ((ctype (elistan-struct--class-type name))
              (acc (list
                    (cons (intern (format "%s-p" name))
                          (list 'function '(t) (list :guard! ctype)))
                    ;; EIEIO allows `(NAME ...)' as a constructor.
                    (cons name (list 'function '(&rest mixed) ctype)))))
         ;; Slots may declare a :type and one or more reader functions.
         (dolist (slot slots)
           (when (consp slot)
             (let ((ty (elistan-struct--defclass-slot-type slot)))
               ;; `:accessor' and `:reader' both generate a reader `(NAME obj)'
               ;; of the slot type (`:accessor' is additionally setf-able; the
               ;; read shape is identical).
               (dolist (key '(:accessor :reader))
                 (let ((fn (plist-get (cdr slot) key)))
                   (when (and fn (symbolp fn))
                     (push (cons fn (list 'function (list ctype) ty)) acc)))))))
         (nreverse acc))))
    (_ nil)))

(defun elistan-struct--parents (form)
  "Return `(CHILD PARENT...)' for a defstruct `:include' / defclass FORM, or nil.
Used to build the class hierarchy for `(:class …)' subtyping."
  (pcase form
    (`(,(or 'cl-defstruct 'defstruct) ,head . ,_)
     (let* ((name (if (consp head) (car head) head))
            (inc (and (consp head)
                      (elistan-struct--option (cdr head) :include))))
       ;; `:include' takes a single parent struct.
       (and name (symbolp name) inc (symbolp inc) (list name inc))))
    (`(defclass ,name ,parents . ,_)
     (and name (symbolp name) (proper-list-p parents)
          (let ((ps (seq-filter #'symbolp parents)))
            (and ps (cons name ps)))))
    (_ nil)))

(defun elistan-struct--struct-info (form)
  "Return a plist `(:name :conc :include :slots)' for a `cl-defstruct' FORM.
:slots holds the raw slot specs (a leading docstring and non-symbol entries
dropped).  Returns nil for any other form.  Used to resolve inherited slots."
  (pcase form
    (`(,(or 'cl-defstruct 'defstruct) ,head . ,slots)
     (let* ((options (and (consp head) (cdr head)))
            (name (if (consp head) (car head) head))
            (inc (elistan-struct--option options :include)))
       (when (and name (symbolp name))
         (list :name name
               :conc (elistan-struct--conc-name name options)
               :include (and inc (symbolp inc) inc)
               :slots (seq-filter
                       (lambda (s) (let ((sn (elistan-struct--slot-name s)))
                                     (and sn (symbolp sn))))
                       slots)))))
    (_ nil)))

(defun elistan-struct--inherited-accessors-from-infos (infos)
  "Return inherited-slot accessor funspecs for the struct INFOS.
A child reaches an inherited slot via its own conc-name (`CHILD-PARENTSLOT'),
so resolve each `:include' ancestor chain within INFOS and register a reader
`(function ((:class CHILD)) TYPE)' for every inherited slot not shadowed by a
nearer definition.  A parent absent from INFOS simply ends the chain."
  (let ((acc nil))
    (dolist (info infos)
      (let* ((name (plist-get info :name))
             (conc (plist-get info :conc))
             (ctype (elistan-struct--class-type name))
             ;; Slot names already provided by a nearer definition (own first).
             (seen (mapcar #'elistan-struct--slot-name (plist-get info :slots)))
             (p (plist-get info :include))
             (guard nil))
        (while (and p (symbolp p) (not (memq p guard)))
          (push p guard)
          (let ((pinfo (seq-find (lambda (i) (eq (plist-get i :name) p)) infos)))
            (if (not pinfo)
                (setq p nil)
              (dolist (slot (plist-get pinfo :slots))
                (let ((sn (elistan-struct--slot-name slot)))
                  (unless (memq sn seen)
                    (push sn seen)
                    (push (cons (intern (concat conc (symbol-name sn)))
                                (list 'function (list ctype)
                                      (elistan-struct--slot-type slot)))
                          acc))))
              (setq p (plist-get pinfo :include)))))))
    (nreverse acc)))

(defun elistan-struct-parse-struct-infos ()
  "Return the `cl-defstruct' infos of the current buffer (see `--struct-info').
Exposed so a project driver can resolve `:include' chains across files."
  (delq nil (mapcar #'elistan-struct--struct-info (elistan-struct--read-forms))))

(defun elistan-struct--read-forms ()
  "Read all top-level forms from the current buffer, tolerating read errors."
  (let ((forms nil))
    (save-excursion
      (goto-char (point-min))
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        ((end-of-file invalid-read-syntax) nil)))
    (nreverse forms)))

(defun elistan-struct-parse-buffer ()
  "Scan the current buffer for `cl-defstruct'/`defclass' definitions.
Return an alist of generated NAME -> typespec funspec, including inherited-slot
accessors for `cl-defstruct' `:include' chains defined in the same buffer."
  (let ((forms (elistan-struct--read-forms)))
    (append (apply #'append (mapcar #'elistan-struct--defstruct forms))
            (apply #'append (mapcar #'elistan-struct--defclass forms))
            (elistan-struct--inherited-accessors-from-infos
             (delq nil (mapcar #'elistan-struct--struct-info forms))))))

(defun elistan-struct-parse-hierarchy ()
  "Scan the current buffer for the class hierarchy.
Return an alist of CLASS -> (PARENT...) from `cl-defstruct' `:include' and
`defclass' parent lists, suitable for `typespec-eval-types-class-parents'."
  (let ((result nil))
    (save-excursion
      (goto-char (point-min))
      (condition-case nil
          (while t
            (let ((cell (elistan-struct--parents (read (current-buffer)))))
              (when cell (push (cons (car cell) (cdr cell)) result))))
        ((end-of-file invalid-read-syntax) nil)))
    (nreverse result)))

(defun elistan-struct-parse-class-slots ()
  "Scan the current buffer for class slot types (defstruct + defclass).
Return an alist CLASS -> ((SLOT . TYPE)...) keyed by the bare slot name, for
typing `(oref OBJ SLOT)' / `(slot-value OBJ \\='SLOT)' reads.  Inheritance is
resolved at lookup time via the class hierarchy, so only own slots are listed."
  (let ((result nil))
    (dolist (form (elistan-struct--read-forms) (nreverse result))
      (pcase form
        (`(defclass ,name ,_parents ,slots . ,_)
         (when (and name (symbolp name))
           (push (cons name
                       (delq nil
                             (mapcar
                              (lambda (s)
                                (and (consp s) (symbolp (car s))
                                     (cons (car s)
                                           (elistan-struct--defclass-slot-type s))))
                              slots)))
                 result)))
        ((or `(cl-defstruct . ,_) `(defstruct . ,_))
         (let ((info (elistan-struct--struct-info form)))
           (when info
             (push (cons (plist-get info :name)
                         (mapcar (lambda (s)
                                   (cons (elistan-struct--slot-name s)
                                         (elistan-struct--slot-type s)))
                                 (plist-get info :slots)))
                   result))))))))

(provide 'elistan-struct)
;;; elistan-struct.el ends here
