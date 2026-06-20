;;; elistan-flymake.el --- Flymake backend for elistan  -*- lexical-binding: t; -*-

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

;; The editor driver (docs/adr/0008): a Flymake backend that reads the buffer's
;; top-level forms (positioned), runs the analysis core, and reports findings as
;; Flymake diagnostics.  Enable it with `M-x elistan-flymake-setup' (or add it
;; to `emacs-lisp-mode-hook') and turn on `flymake-mode'.
;;
;; v1 analyses every top-level form in the buffer; a changed-only incremental
;; pass is a future refinement (ADR-0008).

;;; Code:

(require 'flymake)
(require 'elistan-walk)
(require 'elistan-batch)                ; reuse `elistan-batch--read-buffer'
(require 'elistan-elsa)
(require 'elistan-struct)
(require 'elistan-declare)

(defun elistan-flymake--type (severity)
  "Map a finding SEVERITY to a Flymake diagnostic type."
  (pcase severity
    (:error :error)
    (:note :note)
    (_ :warning)))

(defun elistan-flymake--diagnostic (buffer finding)
  "Convert FINDING into a Flymake diagnostic in BUFFER, or nil without a position."
  (let ((pos (elistan-finding-pos finding)))
    (when pos
      (let* ((beg (max (point-min) (min pos (point-max))))
             (end (save-excursion
                    (goto-char beg)
                    (condition-case nil
                        (progn (forward-sexp) (point))
                      (error (min (point-max) (1+ beg)))))))
        (flymake-make-diagnostic
         buffer beg end
         (elistan-flymake--type (elistan-finding-severity finding))
         (elistan-finding-message finding))))))

(defun elistan-flymake-backend (report-fn &rest _args)
  "A Flymake backend that reports elistan findings via REPORT-FN."
  (let* ((buffer (current-buffer))
         ;; Same in-file type sources as the batch driver (ADR-0002).
         (elistan-source-local (append (elistan-declare-parse-buffer)
                                       (elistan-elsa-parse-buffer)
                                       (elistan-struct-parse-buffer)
                                       elistan-source-local))
         (typespec-eval-types-class-parents
          (append (elistan-struct-parse-hierarchy)
                  typespec-eval-types-class-parents))
         (elistan-walk-class-slots
          (append (elistan-struct-parse-class-slots)
                  elistan-walk-class-slots))
         (forms (save-excursion
                  (goto-char (point-min))
                  (elistan-batch--read-buffer)))
         (findings (elistan-check-forms forms))
         (diagnostics (delq nil (mapcar (lambda (f)
                                          (elistan-flymake--diagnostic buffer f))
                                        findings))))
    (funcall report-fn diagnostics)))

;;;###autoload
(defun elistan-flymake-setup ()
  "Enable the elistan Flymake backend in the current buffer."
  (interactive)
  (add-hook 'flymake-diagnostic-functions #'elistan-flymake-backend nil t))

(provide 'elistan-flymake)
;;; elistan-flymake.el ends here
