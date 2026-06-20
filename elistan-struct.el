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
           (let ((sn (elistan-struct--slot-name slot)))
             (when (and sn (symbolp sn))
               (push (cons (intern (concat conc (symbol-name sn)))
                           (list 'function (list name) 'mixed))
                     acc)))))
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
         ;; Slots may declare an :accessor.
         (dolist (slot slots)
           (when (consp slot)
             (let ((acc-name (plist-get (cdr slot) :accessor)))
               (when (and acc-name (symbolp acc-name))
                 (push (cons acc-name (list 'function (list name) 'mixed)) acc)))))
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
