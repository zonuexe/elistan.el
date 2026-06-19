;;; elistan-finding.el --- The elistan finding record and formatter  -*- lexical-binding: t; -*-

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

;; A finding is the analysis core's only output and the stable interchange to
;; the drivers and the tests (docs/adr/0006).  It is a structured record, not a
;; pre-baked message: the core emits `category', `pos', `severity' and a
;; category-specific `data' plist, and a separate formatter renders human text.

;;; Code:

(require 'cl-lib)

(cl-defstruct (elistan-finding (:constructor elistan-finding-create)
                               (:copier nil))
  "A single issue reported by the analysis core.
CATEGORY is a stable symbol: `call-type-mismatch', `dead-branch', or
`return-type-mismatch'.  POS is a source position (character offset) or nil.
SEVERITY is `:error', `:warning' (default) or `:note'.  DATA is a
category-specific plist."
  category
  pos
  (severity :warning)
  data)

(defun elistan-finding--type (type)
  "Render TYPE for display in a message."
  (format "%S" type))

(defun elistan-finding-message (finding)
  "Render FINDING to human-readable text."
  (let ((data (elistan-finding-data finding)))
    (pcase (elistan-finding-category finding)
      ('call-type-mismatch
       (format "in call to `%s': argument %d has type %s, expected %s"
               (plist-get data :function)
               (1+ (plist-get data :arg-index))
               (elistan-finding--type (plist-get data :actual))
               (elistan-finding--type (plist-get data :expected))))
      ('dead-branch
       (pcase (plist-get data :verdict)
         ('always-true
          (format "condition is always non-nil; the `%s' branch is unreachable"
                  (plist-get data :dead-branch)))
         ('always-false
          (format "condition is always nil; the `%s' branch is unreachable"
                  (plist-get data :dead-branch)))
         (_ "condition has a constant truth value")))
      ('return-type-mismatch
       (format "return type %s is incompatible with declared %s"
               (elistan-finding--type (plist-get data :actual))
               (elistan-finding--type (plist-get data :declared))))
      (other (format "%s" other)))))

(provide 'elistan-finding)
;;; elistan-finding.el ends here
