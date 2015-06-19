;;; guix-pcomplete.el --- Functions for completing guix commands  -*- lexical-binding: t -*-

;; Copyright © 2015 Alex Kost <alezost@gmail.com>

;; This file is part of GNU Guix.

;; GNU Guix is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Guix is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This file provides completions for "guix" command that may be used in
;; `shell', `eshell' and wherever `pcomplete' works.

;;; Code:

(require 'pcomplete)
(require 'pcmpl-unix)
(require 'cl-lib)
(require 'guix-utils)


;;; Regexps for parsing various "guix ..." outputs

(defvar guix-pcomplete-parse-package-regexp
  (rx bol (group (one-or-more (not blank))))
  "Regexp used to find names of the packages.")

(defvar guix-pcomplete-parse-command-regexp
  (rx bol "   "
      (group wordchar (one-or-more (or wordchar "-"))))
  "Regexp used to find guix commands.
'Command' means any option not prefixed with '-'.  For example,
guix subcommand, system action, importer, etc.")

(defvar guix-pcomplete-parse-long-option-regexp
  (rx (or "  " ", ")
      (group "--" (one-or-more (or wordchar "-"))
             (zero-or-one "=")))
  "Regexp used to find long options.")

(defvar guix-pcomplete-parse-short-option-regexp
  (rx bol (one-or-more blank)
      "-" (group (not (any "- "))))
  "Regexp used to find short options.")

(defvar guix-pcomplete-parse-linter-regexp
  (rx bol "- " (group (one-or-more (or wordchar "-"))))
  "Regexp used to find 'lint' checkers.")

(defvar guix-pcomplete-parse-regexp-group 1
  "Parenthesized expression of regexps used to find commands and
options.")


;;; Non-receivable completions

(defvar guix-pcomplete-systems
  '("x86_64-linux" "i686-linux" "armhf-linux" "mips64el-linux")
  "List of supported systems.")

(defvar guix-pcomplete-hash-formats
  '("nix-base32" "base32" "base16" "hex" "hexadecimal")
  "List of supported hash formats.")

(defvar guix-pcomplete-refresh-subsets
  '("core" "non-core")
  "List of supported 'refresh' subsets.")

(defvar guix-pcomplete-key-policies
  '("interactive" "always" "never")
  "List of supported key download policies.")


;;; Interacting with guix

(defcustom guix-pcomplete-guix-program (executable-find "guix")
  "Name of the 'guix' program.
It is used to find guix commands, options, packages, etc."
  :type 'file
  :group 'pcomplete
  :group 'guix)

(defun guix-pcomplete-run-guix (&rest args)
  "Run `guix-pcomplete-guix-program' with ARGS.
Insert the output to the current buffer."
  (apply #'call-process
         guix-pcomplete-guix-program nil t nil args))

(defun guix-pcomplete-run-guix-and-search (regexp &optional group
                                                  &rest args)
  "Run `guix-pcomplete-guix-program' with ARGS and search for matches.
Return a list of strings matching REGEXP.
GROUP specifies a parenthesized expression used in REGEXP."
  (with-temp-buffer
    (apply #'guix-pcomplete-run-guix args)
    (goto-char (point-min))
    (let (result)
      (while (re-search-forward regexp nil t)
        (push (match-string-no-properties group) result))
      (nreverse result))))

(defmacro guix-pcomplete-define-options-finder (name docstring regexp
                                                     &optional filter)
  "Define function NAME to receive guix options and commands.

The defined function takes an optional COMMAND argument.  This
function will run 'guix COMMAND --help' (or 'guix --help' if
COMMAND is nil) using `guix-pcomplete-run-guix-and-search' and
return its result.

If FILTER is specified, it should be a function.  The result is
passed to this FILTER as argument and the result value of this
function call is returned."
  (declare (doc-string 2) (indent 1))
  `(guix-memoized-defun ,name (&optional command)
     ,docstring
     (let* ((args '("--help"))
            (args (if command (cons command args) args))
            (res (apply #'guix-pcomplete-run-guix-and-search
                        ,regexp guix-pcomplete-parse-regexp-group args)))
       ,(if filter
            `(funcall ,filter res)
          'res))))

(guix-pcomplete-define-options-finder guix-pcomplete-commands
  "If COMMAND is nil, return a list of available guix commands.
If COMMAND is non-nil (it should be a string), return available
subcommands, actions, etc. for this guix COMMAND."
  guix-pcomplete-parse-command-regexp)

(guix-pcomplete-define-options-finder guix-pcomplete-long-options
  "Return a list of available long options for guix COMMAND."
  guix-pcomplete-parse-long-option-regexp)

(guix-pcomplete-define-options-finder guix-pcomplete-short-options
  "Return a string with available short options for guix COMMAND."
  guix-pcomplete-parse-short-option-regexp
  (lambda (list)
    (mapconcat #'identity list "")))

(guix-memoized-defun guix-pcomplete-all-packages ()
  "Return a list of all available Guix packages."
  (guix-pcomplete-run-guix-and-search
   guix-pcomplete-parse-package-regexp
   guix-pcomplete-parse-regexp-group
   "package" "--list-available"))

(guix-memoized-defun guix-pcomplete-installed-packages (&optional profile)
  "Return a list of Guix packages installed in PROFILE."
  (let* ((args (and profile
                    (list (concat "--profile=" profile))))
         (args (append '("package" "--list-installed") args)))
    (apply #'guix-pcomplete-run-guix-and-search
           guix-pcomplete-parse-package-regexp
           guix-pcomplete-parse-regexp-group
           args)))

(guix-memoized-defun guix-pcomplete-lint-checkers ()
  "Return a list of all available lint checkers."
  (guix-pcomplete-run-guix-and-search
   guix-pcomplete-parse-linter-regexp
   guix-pcomplete-parse-regexp-group
   "lint" "--list-checkers"))


;;; Completing

(defvar guix-pcomplete-option-regexp (rx string-start "-")
  "Regexp to match an option.")

(defvar guix-pcomplete-long-option-regexp (rx string-start "--")
  "Regexp to match a long option.")

(defvar guix-pcomplete-long-option-with-arg-regexp
  (rx string-start
      (group "--" (one-or-more any)) "="
      (group (zero-or-more any)))
  "Regexp to match a long option with its argument.
The first parenthesized group defines the option and the second
group - the argument.")

(defvar guix-pcomplete-short-option-with-arg-regexp
  (rx string-start
      (group "-" (not (any "-")))
      (group (zero-or-more any)))
  "Regexp to match a short option with its argument.
The first parenthesized group defines the option and the second
group - the argument.")

(defun guix-pcomplete-match-option ()
  "Return non-nil, if the current argument is an option."
  (pcomplete-match guix-pcomplete-option-regexp 0))

(defun guix-pcomplete-match-long-option ()
  "Return non-nil, if the current argument is a long option."
  (pcomplete-match guix-pcomplete-long-option-regexp 0))

(defun guix-pcomplete-match-long-option-with-arg ()
  "Return non-nil, if the current argument is a long option with value."
  (pcomplete-match guix-pcomplete-long-option-with-arg-regexp 0))

(defun guix-pcomplete-match-short-option-with-arg ()
  "Return non-nil, if the current argument is a short option with value."
  (pcomplete-match guix-pcomplete-short-option-with-arg-regexp 0))

(defun guix-pcomplete-long-option-arg (option args)
  "Return a long OPTION's argument from a list of arguments ARGS."
  (let* ((re (concat "\\`" option "=\\(.*\\)"))
         (args (cl-member-if (lambda (arg)
                               (string-match re arg))
                             args))
         (cur (car args)))
    (when cur
      (match-string-no-properties 1 cur))))

(defun guix-pcomplete-short-option-arg (option args)
  "Return a short OPTION's argument from a list of arguments ARGS."
  (let* ((re (concat "\\`" option "\\(.*\\)"))
         (args (cl-member-if (lambda (arg)
                               (string-match re arg))
                             args))
         (cur (car args)))
    (when cur
      (let ((arg (match-string-no-properties 1 cur)))
        (if (string= "" arg)
            (cadr args)                 ; take the next arg
          arg)))))

(defun guix-pcomplete-complete-comma-args (entries)
  "Complete comma separated arguments using ENTRIES."
  (let ((index pcomplete-index))
    (while (= index pcomplete-index)
      (let* ((args (if (or (guix-pcomplete-match-long-option-with-arg)
                           (guix-pcomplete-match-short-option-with-arg))
                       (pcomplete-match-string 2 0)
                     (pcomplete-arg 0)))
             (input (if (string-match ".*,\\(.*\\)" args)
                        (match-string-no-properties 1 args)
                      args)))
        (pcomplete-here* entries input)))))

(defun guix-pcomplete-complete-command-arg (command)
  "Complete argument for guix COMMAND."
  (cond
   ((member command
            '("archive" "build" "environment" "lint" "refresh"))
    (while t
      (pcomplete-here (guix-pcomplete-all-packages))))
   (t (pcomplete-here* (pcomplete-entries)))))

(defun guix-pcomplete-complete-option-arg (command option &optional input)
  "Complete argument for COMMAND's OPTION.
INPUT is the current partially completed string."
  (cl-flet ((option? (short long)
              (or (string= option short)
                  (string= option long)))
            (command? (&rest commands)
              (member command commands))
            (complete (entries)
              (pcomplete-here entries input nil t))
            (complete* (entries)
              (pcomplete-here* entries input t)))
    (cond
     ((option? "-L" "--load-path")
      (complete* (pcomplete-dirs)))
     ((string= "--key-download" option)
      (complete* guix-pcomplete-key-policies))

     ((command? "package")
      (cond
       ;; For '--install[=]' and '--remove[=]', try to complete a package
       ;; name (INPUT) after the "=" sign, and then the rest packages
       ;; separated with spaces.
       ((option? "-i" "--install")
        (complete (guix-pcomplete-all-packages))
        (while (not (guix-pcomplete-match-option))
          (pcomplete-here (guix-pcomplete-all-packages))))
       ((option? "-r" "--remove")
        (let* ((profile (or (guix-pcomplete-short-option-arg
                             "-p" pcomplete-args)
                            (guix-pcomplete-long-option-arg
                             "--profile" pcomplete-args)))
               (profile (and profile (expand-file-name profile))))
          (complete (guix-pcomplete-installed-packages profile))
          (while (not (guix-pcomplete-match-option))
            (pcomplete-here (guix-pcomplete-installed-packages profile)))))
       ((string= "--show" option)
        (complete (guix-pcomplete-all-packages)))
       ((option? "-p" "--profile")
        (complete* (pcomplete-dirs)))
       ((option? "-m" "--manifest")
        (complete* (pcomplete-entries)))))

     ((and (command? "archive" "build")
           (option? "-s" "--system"))
      (complete* guix-pcomplete-systems))

     ((and (command? "build")
           (option? "-r" "--root"))
      (complete* (pcomplete-entries)))

     ((and (command? "environment")
           (option? "-l" "--load"))
      (complete* (pcomplete-entries)))

     ((and (command? "hash" "download")
           (option? "-f" "--format"))
      (complete* guix-pcomplete-hash-formats))

     ((and (command? "lint")
           (option? "-c" "--checkers"))
      (guix-pcomplete-complete-comma-args
       (guix-pcomplete-lint-checkers)))

     ((and (command? "publish")
           (option? "-u" "--user"))
      (complete* (pcmpl-unix-user-names)))

     ((and (command? "refresh")
           (option? "-s" "--select"))
      (complete* guix-pcomplete-refresh-subsets)))))

(defun guix-pcomplete-complete-options (command)
  "Complete options (with their arguments) for guix COMMAND."
  (while (guix-pcomplete-match-option)
    (let ((index pcomplete-index))
      (if (guix-pcomplete-match-long-option)

          ;; Long options.
          (if (guix-pcomplete-match-long-option-with-arg)
              (let ((option (pcomplete-match-string 1 0))
                    (arg    (pcomplete-match-string 2 0)))
                (guix-pcomplete-complete-option-arg
                 command option arg))

            (pcomplete-here* (guix-pcomplete-long-options command))
            ;; We support '--opt arg' style (along with '--opt=arg'),
            ;; because 'guix package --install/--remove' may be used this
            ;; way.  So try to complete an argument after the option has
            ;; been completed.
            (unless (guix-pcomplete-match-option)
              (guix-pcomplete-complete-option-arg
               command (pcomplete-arg 0 -1))))

        ;; Short options.
        (let ((arg (pcomplete-arg 0)))
          (if (> (length arg) 2)
              ;; Support specifying an argument after a short option without
              ;; spaces (for example, '-L/tmp/foo').
              (guix-pcomplete-complete-option-arg
               command
               (substring-no-properties arg 0 2)
               (substring-no-properties arg 2))
            (pcomplete-opt (guix-pcomplete-short-options command))
            (guix-pcomplete-complete-option-arg
             command (pcomplete-arg 0 -1)))))

      ;; If there were no completions, move to the next argument and get
      ;; out if the last argument is achieved.
      (when (= index pcomplete-index)
        (if (= pcomplete-index pcomplete-last)
            (throw 'pcompleted nil)
          (pcomplete-next-arg))))))

;;;###autoload
(defun pcomplete/guix ()
  "Completion for `guix'."
  (let ((commands (guix-pcomplete-commands)))
    (pcomplete-here* (cons "--help" commands))
    (let ((command (pcomplete-arg 'first 1)))
      (when (member command commands)
        (guix-pcomplete-complete-options command)
        (let ((subcommands (guix-pcomplete-commands command)))
          (when subcommands
            (pcomplete-here* subcommands)))
        (guix-pcomplete-complete-options command)
        (guix-pcomplete-complete-command-arg command)))))

(provide 'guix-pcomplete)

;;; guix-pcomplete.el ends here