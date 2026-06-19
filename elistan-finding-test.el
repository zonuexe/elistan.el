;;; elistan-finding-test.el --- Tests for elistan-finding  -*- lexical-binding: t; -*-

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

;; Tests for the finding record and its formatter.

;;; Code:

(require 'ert)
(require 'elistan-finding)

(ert-deftest elistan-finding-accessors ()
  "Struct construction and accessors; default severity is :warning."
  (let ((f (elistan-finding-create
            :category 'call-type-mismatch :pos 42
            :data '(:function foo :arg-index 0 :expected string :actual integer))))
    (should (eq (elistan-finding-category f) 'call-type-mismatch))
    (should (= (elistan-finding-pos f) 42))
    (should (eq (elistan-finding-severity f) :warning))
    (should (eq (plist-get (elistan-finding-data f) :function) 'foo))))

(ert-deftest elistan-finding-rendering ()
  "Each category renders structured data to text."
  (should (string-match-p
           "argument 1 has type integer, expected string"
           (elistan-finding-message
            (elistan-finding-create
             :category 'call-type-mismatch
             :data '(:function foo :arg-index 0 :expected string :actual integer)))))
  (should (string-match-p
           "always nil"
           (elistan-finding-message
            (elistan-finding-create
             :category 'dead-branch
             :data '(:test (integerp x) :verdict always-false :dead-branch then)))))
  (should (string-match-p
           "incompatible with declared string"
           (elistan-finding-message
            (elistan-finding-create
             :category 'return-type-mismatch
             :data '(:declared string :actual integer))))))

(provide 'elistan-finding-test)
;;; elistan-finding-test.el ends here
