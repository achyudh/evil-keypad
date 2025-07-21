;;; evil-keypad.el --- Modal command dispatch for evil-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Achyudh Ram <mail@achyudh.me>
;; Author: Achyudh Ram <mail@achyudh.me>
;; Maintainer: Achyudh Ram <mail@achyudh.me>
;; Created: 2025-05-03
;; Package-Requires: ((emacs "30.1") (evil "1.0.0"))
;; Version: 0.1.6
;; Keywords: convenience, emulation
;; URL: https://github.com/achyudh/evil-keypad

;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 3
;; of the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:
;; Provides `evil-keypad-start', a command to activate a transient
;; keypad mode inspired by Meow Keypad.  Allows entering complex Emacs
;; key sequences using a series of single key presses without holding
;; down modifier keys.
;;
;; After triggering the keypad, type a sequence representing modifiers
;; and keys (e.g., 'x f' for C-x C-f, 'm x' for M-x, 'a s' for C-c a
;; s).  The keypad translates and executes the corresponding Emacs
;; command, then exits.  Numeric prefix arguments (e.g. C-u 4, M-5)
;; can be initiated using dedicated keypad keys before command keys.
;;
;; Which-key integration is provided if `which-key-mode` is active,
;; showing the target Emacs keymap contents after a prefix is entered.

;;; Code:

(require 'cl-lib)
(require 'evil)
(require 'which-key nil t) ; Optionally load which-key

;;----------------------------------------
;; Internal State Variables
;;----------------------------------------

(defvar evil-keypad--keys nil
  "Internal list representing the keys sequence during keypad invocation.
Stores (MODIFIER . KEY-STRING) cons cells, ordered most recent first.
MODIFIER is a symbol like \\='literal, \\='control, \\='meta, \\='control-meta.
KEY-STRING is the result of `single-key-description'.")

(defvar evil-keypad--pending-modifier nil
  "Stores the pending modifier symbol to be applied to the next key.")

(defvar evil-keypad--session-initial-prefix-arg nil
  "Prefix argument active in Emacs before this keypad session started.")

(defvar evil-keypad--session-active-prefix-arg nil
  "Prefix argument built or active during the current keypad session.
Can be nil, an integer, a list like \\='(4) for C-u, or \\='- for M-- (raw minus).")

(defvar evil-keypad--control-inducing-sequence-p nil
  "Non-nil if the current keypad sequence context implies keys default to Control.
Set based on the first command key of the sequence (e.g. x, c, m, g).")

(defvar evil-keypad--display-timer nil
  "Holds the idle timer object for the which-key popup.")

(defvar evil-keypad--display-bindings-function #'ignore
  "Function called by the idle timer to display available bindings via which-key.")

(defvar evil-keypad--clear-display-function #'ignore
  "Function called to hide the which-key bindings display.")

(defvar evil-keypad--original-which-key-show-prefix nil
  "Stores the original value of `which-key-show-prefix` during keypad activation.")

;;----------------------------------------
;; Customization Variables (Triggers)
;;----------------------------------------

;;;###autoload
(defcustom evil-keypad-activation-trigger (kbd "SPC")
  "Key to activate `evil-keypad-start` globally.
Works when `evil-keypad-global-mode` is non-nil and Evil state is one of
`evil-keypad-activation-states`."
  :type 'string :group 'evil-keypad)

;;;###autoload
(defcustom evil-keypad-activation-states '(normal visual motion emacs)
  "Evil states where the `evil-keypad-activation-trigger` should be active."
  :type '(repeat symbol) :group 'evil-keypad)

;;;###autoload
(defcustom evil-keypad-M-trigger ?m
  "Character to trigger Meta modifier for the next key in keypad."
  :type 'character :group 'evil-keypad)

;;;###autoload
(defcustom evil-keypad-C-M-trigger ?g
  "Character to trigger Control-Meta modifier for the next key in keypad."
  :type 'character :group 'evil-keypad)

;;;###autoload
(defcustom evil-keypad-literal-trigger ?\s ; Space character
  "Character to trigger literal interpretation for the next key in keypad.
Used after first key is entered."
  :type 'character :group 'evil-keypad)

;;;###autoload
(defcustom evil-keypad-C-x-trigger ?x
  "Character used as first key in keypad to represent the C-x prefix."
  :type 'character :group 'evil-keypad)

;;;###autoload
(defcustom evil-keypad-C-c-trigger ?c
  "Character used as first key in keypad to represent the C-c prefix."
  :type 'character :group 'evil-keypad)

;;;###autoload
(defcustom evil-keypad-C-h-trigger ?h
  "Character used as first key in keypad to represent the C-h prefix."
  :type 'character :group 'evil-keypad)

;;;###autoload
(defcustom evil-keypad-universal-argument-trigger ?u
  "Keypad key to emulate `universal-argument` (C-u)."
  :type 'character :group 'evil-keypad)

;;;###autoload
(defcustom evil-keypad-negative-argument-trigger ?-
  "Keypad key to emulate `negative-argument` (M-- or C-u -)."
  :type 'character :group 'evil-keypad)

;;;###autoload
(defcustom evil-keypad-quit-key (kbd "C-g")
  "Key to quit the keypad input state."
  :type 'string :group 'evil-keypad)

;;;###autoload
(defcustom evil-keypad-prefix-help-command nil
  "Command to run when `help-char` is pressed after a prefix.
This command is used only when there is no actual binding for `help-char`
after that prefix. The function is called with one argument: the keymap for
the current prefix."
  :type '(function :tag "Help function")
  :group 'evil-keypad)

;;----------------------------------------
;; Global Trigger Activation
;;----------------------------------------

(defvar evil-keypad-global-activation-map (make-sparse-keymap)
  "Keymap for `evil-keypad-global-mode`.")

(defun evil-keypad-global-mode--maybe-setup-evil-integration ()
  "Setup evil integration if evil is available."
  (when (featurep 'evil)
    (evil-keypad--setup-global-activation-bindings)))

(defun evil-keypad--setup-global-activation-bindings ()
  "Set up bindings in `evil-keypad-global-activation-map` for target states.
Assumes `evil.el` is loaded."
  (when (and (fboundp 'evil-make-intercept-map) (fboundp 'evil-define-key))
    (dolist (state evil-keypad-activation-states)
      (evil-make-intercept-map
       (evil-get-auxiliary-keymap evil-keypad-global-activation-map state t t)
       state)
      (evil-define-key state evil-keypad-global-activation-map
        evil-keypad-activation-trigger #'evil-keypad-start))))

(defun evil-keypad--clear-global-activation-bindings ()
  "Clear bindings from `evil-keypad-global-activation-map` for target states."
  (when (fboundp 'evil-define-key)
    (dolist (state evil-keypad-activation-states)
      (evil-define-key state evil-keypad-global-activation-map
        evil-keypad-activation-trigger nil))))

;;;###autoload
(define-minor-mode evil-keypad-global-mode
  "Enable a global high-precedence trigger for `evil-keypad-start`.
Activates `evil-keypad-start` via `evil-keypad-activation-trigger`
in Evil states defined by `evil-keypad-activation-states`."
  :global t
  :lighter nil ; Example: " EKAct"
  :keymap evil-keypad-global-activation-map
  :group 'evil-keypad
  (if evil-keypad-global-mode
      (if (featurep 'evil)
          (evil-keypad--setup-global-activation-bindings)
        (add-hook 'evil-mode-hook #'evil-keypad-global-mode--maybe-setup-evil-integration))
    (remove-hook 'evil-mode-hook #'evil-keypad-global-mode--maybe-setup-evil-integration)
    (when (featurep 'evil)
      (evil-keypad--clear-global-activation-bindings))))

;;----------------------------------------
;; Formatting Functions
;;----------------------------------------

(defun evil-keypad--format-key-pair (pair)
  "Format a single (MODIFIER . KEY-STRING) PAIR into a readable string."
  (let ((modifier (car pair)) (key-string (cdr pair)))
    (cond
     ((eq modifier 'meta) (format "M-%s" key-string))
     ((or (eq modifier 'control) (eq modifier 'control-meta))
      (let* ((char (and (> (length key-string) 0) (aref key-string 0)))
             (is-uppercase (and char (= (length key-string) 1) (<= ?A char) (<= char ?Z))))
        (if is-uppercase
            (format "%sS-%s" (if (eq modifier 'control) "C-" "C-M-") (downcase key-string))
          (format "%s%s" (if (eq modifier 'control) "C-" "C-M-") key-string))))
     (t key-string))))

(defun evil-keypad--format-sequence (keys-list)
  "Format the given KEYS-LIST into a readable key sequence string."
  (if keys-list (mapconcat #'evil-keypad--format-key-pair (reverse keys-list) " ") ""))

(defun evil-keypad--format-prefix-arg (prefix-arg-value)
  "Format PREFIX-ARG-VALUE for display in the echo area."
  (cond
   ((null prefix-arg-value) "")
   ((eq prefix-arg-value '-) "C-u -")
   ((integerp prefix-arg-value) (format "C-u %d" prefix-arg-value))
   ((listp prefix-arg-value)
    (let ((val (car prefix-arg-value)))
      (cond
       ((eq val 4) "C-u")
       ((eq val -4) "C-u -")
       (t (format "C-u (%d)" val)))))))

;;----------------------------------------
;; Which-Key Integration Logic
;;----------------------------------------

(declare-function which-key--create-buffer-and-show "which-key" (&optional prefix-keys from-keymap filter prefix-title))
(declare-function which-key--hide-popup "which-key" ())

(defun evil-keypad--cancel-display-timer ()
  "Cancel the which-key display timer if it exists."
  (when evil-keypad--display-timer
    (cancel-timer evil-keypad--display-timer)
    (setq evil-keypad--display-timer nil)))

(defun evil-keypad--cancel-display-timer-and-clear ()
  "Cancel the display timer and clear the which-key popup."
  (evil-keypad--cancel-display-timer)
  (funcall evil-keypad--clear-display-function))

(defun evil-keypad--display-idle-delay ()
  "Return which-key idle delay or default of 0.4 seconds."
  (or (and (bound-and-true-p which-key-idle-delay) which-key-idle-delay) 0.4))

(defun evil-keypad--schedule-display (&optional binding)
  "Schedule the display of available bindings cancelling any existing timer.
If BINDING is non‑nil, pass it to that function; otherwise call with no args."
  (evil-keypad--cancel-display-timer)
  (setq evil-keypad--display-timer
        (run-with-idle-timer (evil-keypad--display-idle-delay)
                             nil
                             evil-keypad--display-bindings-function
                             binding)))

(defun evil-keypad--make-initial-display-map ()
  "Create and return a keymap for initial which-key display."
  (let ((map (copy-keymap mode-specific-map)))
    (define-key map (vector evil-keypad-C-x-trigger) "keypad/C-x-prefix")
    (define-key map (vector evil-keypad-C-c-trigger) "keypad/C-c-prefix")
    (define-key map (vector evil-keypad-C-h-trigger) "keypad/C-h-prefix")
    (define-key map (vector evil-keypad-M-trigger)   "keypad/M-trigger")
    (define-key map (vector evil-keypad-C-M-trigger) "keypad/C-M-trigger")
    (define-key map (vector evil-keypad-universal-argument-trigger) "keypad/universal-arg")
    (define-key map (vector evil-keypad-negative-argument-trigger) "keypad/negative-arg")
    (define-key map evil-keypad-quit-key #'evil-keypad-quit)
    map))

(defun evil-keypad--trigger-which-key-display (&optional target-keymap)
  "Show relevant bindings using which-key.
If TARGET-KEYMAP is non-nil, display that Emacs keymap.  Otherwise, show
the initial evil-keypad trigger keys."
  (evil-keypad--cancel-display-timer)
  (condition-case err
      (if (and target-keymap (keymapp target-keymap))
          (which-key--create-buffer-and-show nil target-keymap nil nil)
        (if (null evil-keypad--keys)
            (if evil-keypad--session-active-prefix-arg
                (funcall evil-keypad--clear-display-function)
              (which-key--create-buffer-and-show nil (evil-keypad--make-initial-display-map) nil "C-c"))
          (funcall evil-keypad--clear-display-function)))
    (error (message "Error showing which-key: %S" err))))

(defun evil-keypad--which-key-integration-setup ()
  "Set display/clear functions and manage `which-key-show-prefix'."
  (if (and (boundp 'which-key-mode) which-key-mode
           (fboundp 'which-key--create-buffer-and-show)
           (fboundp 'which-key--hide-popup))
      (progn
        (setq evil-keypad--display-bindings-function
              (lambda (&optional keymap) (evil-keypad--trigger-which-key-display keymap)))
        (setq evil-keypad--clear-display-function #'which-key--hide-popup)
        (when (boundp 'which-key-show-prefix)
          (setq evil-keypad--original-which-key-show-prefix (symbol-value 'which-key-show-prefix))
          (setq which-key-show-prefix nil)))
    (setq evil-keypad--display-bindings-function #'ignore evil-keypad--clear-display-function #'ignore)
    (when (and (boundp 'which-key-show-prefix) evil-keypad--original-which-key-show-prefix)
      (setq which-key-show-prefix evil-keypad--original-which-key-show-prefix)
      (setq evil-keypad--original-which-key-show-prefix nil))))

;; Add which-key hook if which-key is available
(defun evil-keypad--maybe-setup-which-key-integration ()
  "Set up which-key integration if which-key is loaded."
  (when (featurep 'which-key)
    (add-hook 'which-key-mode-hook #'evil-keypad--which-key-integration-setup)
    (evil-keypad--which-key-integration-setup)))

;; Initialize which-key integration if already loaded
(evil-keypad--maybe-setup-which-key-integration)

;;----------------------------------------
;; Core Logic
;;----------------------------------------

(defun evil-keypad--keymap-has-ctrl-meta-bindings-p (keymap)
  "Return t if KEYMAP contains any C-M- modified single key bindings."
  (when (keymapp keymap)
    (catch 'found
      (map-keymap
       (lambda (key _binding)
         (unless (vectorp key) ; Process single events
           (let ((mods (event-modifiers key)))
             (when (and (memq 'control mods) (memq 'meta mods))
               (throw 'found t)))))
       keymap)
      nil)))

(defun evil-keypad--context-allows-modifier-type-p (modifier-type)
  "Check if the current keypad context allows for PENDING-MODIFIER-TYPE.
MODIFIER-TYPE is \\='meta or \\='control-meta."
  (if (null evil-keypad--keys) ; If at the very start of keypad input
      t ; Always allow m/g to trigger initially
    (let* ((seq-str (evil-keypad--format-sequence evil-keypad--keys))
           (current-map (if (string-empty-p seq-str)
                            (current-global-map)
                          (key-binding (kbd seq-str) t))))
      (if (keymapp current-map)
          (cl-case modifier-type
            (meta (lookup-key current-map (kbd "ESC") t))
            (control-meta (evil-keypad--keymap-has-ctrl-meta-bindings-p current-map)))
        nil))))

(defun evil-keypad--execute (command)
  "Execute COMMAND, applying the active prefix argument."
  (condition-case err
      (let ((current-prefix-arg evil-keypad--session-active-prefix-arg))
        (call-interactively command))
    (error (message "Error executing %s: %s" command err))))

(defun evil-keypad--try-execute ()
  "Check current sequence, execute/fallback, or update echo/which-key.
Returns t to exit."
  (if evil-keypad--pending-modifier
      (progn (evil-keypad--display-pending-state) nil)
    (if (null evil-keypad--keys)
        (progn (evil-keypad--display-pending-state)
               (evil-keypad--schedule-display)
               nil)
      (let ((seq-str (evil-keypad--format-sequence evil-keypad--keys)))
        (if (string-empty-p seq-str)
            (progn (evil-keypad--display-pending-state) nil)
          (let* ((seq-vec (kbd seq-str)) (binding (key-binding seq-vec t)))
            (cond
             ((keymapp binding) (evil-keypad--handle-prefix-binding binding seq-str))
             ((commandp binding) (evil-keypad--handle-command-binding binding seq-str))
             (t (evil-keypad--handle-unbound-sequence seq-str)))))))))

(defun evil-keypad--quit ()
  "Internal cleanup for keypad."
  (evil-keypad--cancel-display-timer-and-clear)
  (when (and (boundp 'which-key-show-prefix) evil-keypad--original-which-key-show-prefix)
    (setq which-key-show-prefix evil-keypad--original-which-key-show-prefix
          evil-keypad--original-which-key-show-prefix nil))
  (setq evil-keypad--keys nil
        evil-keypad--pending-modifier nil
        evil-keypad--session-initial-prefix-arg nil
        evil-keypad--session-active-prefix-arg nil
        evil-keypad--control-inducing-sequence-p nil))

;;;###autoload
(defun evil-keypad-quit ()
  "Interactive command to quit keypad."
  (interactive)
  (evil-keypad--quit) t)

;;;###autoload
(defun evil-keypad-undo ()
  "Interactive command to undo last keypad input."
  (interactive)
  (evil-keypad--cancel-display-timer-and-clear)
  (cond
   (evil-keypad--pending-modifier
    (setq evil-keypad--pending-modifier nil))
   (evil-keypad--keys
    (pop evil-keypad--keys))
   ((not (equal evil-keypad--session-active-prefix-arg evil-keypad--session-initial-prefix-arg))
    (setq evil-keypad--session-active-prefix-arg evil-keypad--session-initial-prefix-arg))
   (t (ding)))

  (if (and (null evil-keypad--keys)
           (null evil-keypad--pending-modifier))
      (setq evil-keypad--control-inducing-sequence-p nil))

  (evil-keypad--try-execute)
  nil)

(defun evil-keypad--make-state-keymap ()
  "Create and return the keypad state keymap."
  (let ((map (make-sparse-keymap)))
    (define-key map evil-keypad-quit-key #'evil-keypad-quit)

    (define-key map (kbd "<backspace>") #'evil-keypad-undo)
    (define-key map (kbd "DEL") #'evil-keypad-undo)
    map))

(defvar evil-keypad-state-keymap (evil-keypad--make-state-keymap)
  "Keymap for keypad internal commands.")

(defun evil-keypad--echo (format-string &rest args)
  "Display a message in the echo area with a \"Keypad:\" prefix.
FORMAT-STRING is the format string passed to `format`.
ARGS are the arguments for the format string."
  (message "Keypad: %s" (apply #'format format-string args)))

(defun evil-keypad--get-current-keymap ()
  "Get the keymap for the current key sequence."
  (let* ((seq-str (evil-keypad--format-sequence evil-keypad--keys))
         (seq-vec (if (string-empty-p seq-str) nil (kbd seq-str))))
    (if seq-vec (key-binding seq-vec t) (current-global-map))))

(defun evil-keypad--display-pending-state ()
  "Display the current prefix arg, sequence, and pending modifier.  Returns nil."
  (let ((prefix-str (evil-keypad--format-prefix-arg evil-keypad--session-active-prefix-arg))
        (seq-str (if evil-keypad--keys (evil-keypad--format-sequence evil-keypad--keys) ""))
        (pending-mod-str (cl-case evil-keypad--pending-modifier
                           (meta "M-") (control-meta "C-M-") (literal "_") (t ""))))
    (if (and (string-empty-p seq-str)
             (string-empty-p pending-mod-str)
             (not (string-empty-p prefix-str)))
        (evil-keypad--echo "%s-" prefix-str)
      (evil-keypad--echo "%s" (string-join
                               (seq-filter (lambda (s) (not (string-empty-p s)))
                                           (list prefix-str seq-str pending-mod-str))
                               " "))))
  nil)

(defun evil-keypad--handle-prefix-binding (binding seq-str)
  "Handle a key sequence that maps to a prefix (keymap).
Displays prefix in echo area and schedules which-key display.  Returns nil.
BINDING is the keymap the key sequence maps to.
SEQ-STR is the formatted key sequence string."
  (let ((prefix-str (evil-keypad--format-prefix-arg evil-keypad--session-active-prefix-arg)))
    (if (string-empty-p prefix-str)
        (evil-keypad--echo "%s-" seq-str)
      (evil-keypad--echo "%s %s-" prefix-str seq-str)))
  (evil-keypad--schedule-display binding)
  nil)

(defun evil-keypad--handle-command-binding (binding _seq-str)
  "Handle a key sequence that maps to a command.  Executes and returns t.
BINDING is the command to execute with the current prefix argument."
  (evil-keypad--cancel-display-timer-and-clear)
  (evil-keypad--execute binding)
  t)

(defun evil-keypad--handle-help-request (keymap)
  "Handle a help request for the given KEYMAP."
  (if (and evil-keypad-prefix-help-command
           (fboundp evil-keypad-prefix-help-command))
      (progn
        (evil-keypad--cancel-display-timer-and-clear)
        (funcall evil-keypad-prefix-help-command keymap)
        (evil-keypad--quit)
        t)
    (ding)
    nil))

(defun evil-keypad--handle-unbound-sequence (original-seq-str)
  "Handle an unbound ORIGINAL-SEQ-STR, attempting fallback.
Returns t to exit, nil to continue (if fallback leads to new prefix)."
  (let* ((last-pair (car evil-keypad--keys))
         (last-modifier (car last-pair))
         ;; Fallback is possible only if last modifier was 'control'
         (fallback-possible (and evil-keypad--keys (eq last-modifier 'control)))
         (fallback-binding nil)
         (fallback-keys nil)
         (fallback-seq-str nil))

    (when fallback-possible
      (setq fallback-keys (cons (cons 'literal (cdr last-pair))
                                (cdr evil-keypad--keys)))
      (setq fallback-seq-str (evil-keypad--format-sequence fallback-keys))
      (when (not (string-empty-p fallback-seq-str))
        (setq fallback-binding (key-binding (kbd fallback-seq-str) t))))

    (cond
     ((commandp fallback-binding)
      (evil-keypad--handle-command-binding fallback-binding fallback-seq-str)) ; Returns t
     ((keymapp fallback-binding)
      (setq evil-keypad--keys fallback-keys)
      ;; Let handle-prefix-binding display new prefix and schedule which-key
      (evil-keypad--handle-prefix-binding fallback-binding fallback-seq-str)) ; Returns nil
     (t
      (evil-keypad--cancel-display-timer-and-clear)
      (message "%s is undefined" original-seq-str)
      (evil-keypad--quit)
      t))))

(defun evil-keypad--set-new-pending-modifier (event)
  "Handle EVENT when it's a new modifier trigger (m, g, SPC).  Returns nil."
  (cond
   ((eq event evil-keypad-M-trigger)
    (setq evil-keypad--pending-modifier 'meta
          evil-keypad--control-inducing-sequence-p t))
   ((eq event evil-keypad-C-M-trigger)
    (setq evil-keypad--pending-modifier 'control-meta
          evil-keypad--control-inducing-sequence-p t))
   ((eq event evil-keypad-literal-trigger)
    (setq evil-keypad--pending-modifier 'literal)))
  (evil-keypad--try-execute)
  nil)

(defun evil-keypad--process-resolved-key (event mod-from-pending)
  "Process EVENT as a key that resolves MOD-FROM-PENDING or is a regular key.
Returns result of `evil-keypad--try-execute` (t to exit, nil to continue)."
  (let* ((key-string (single-key-description event))
         (is-first-command-key (null evil-keypad--keys))
         (add-implicit-C-c-prefix-p nil)
         (modifier-for-current-key
          (cond
           (mod-from-pending mod-from-pending)
           (is-first-command-key
            (cond
             ((or (eq event evil-keypad-C-x-trigger) (eq event evil-keypad-C-c-trigger))
              (setq evil-keypad--control-inducing-sequence-p t) 'control)
             ((eq event evil-keypad-C-h-trigger)
              (setq evil-keypad--control-inducing-sequence-p nil) 'control)
             (t
              (setq add-implicit-C-c-prefix-p t)
              (setq evil-keypad--control-inducing-sequence-p nil) 'literal)))
           (evil-keypad--control-inducing-sequence-p 'control)
           ((and (characterp event) (< event 32)) ; Check for control character
            'literal)
           (t 'literal))))
    (setq evil-keypad--keys
          (if add-implicit-C-c-prefix-p
              (list (cons modifier-for-current-key key-string)
                    (cons 'control "c"))
            (cons (cons modifier-for-current-key key-string)
                  evil-keypad--keys))))
  (evil-keypad--try-execute))

(defun evil-keypad--handle-universal-argument-trigger ()
  "Handle the universal argument trigger \\='u\\='.  Returns nil."
  (setq evil-keypad--session-active-prefix-arg
        (let ((arg evil-keypad--session-active-prefix-arg))
          (cond
           ((null arg) '(4))
           ((eq arg '-) '(-4))
           ((integerp arg) '(4))
           ((listp arg) (list (* (car arg) 4)))
           (t '(4)))))
  nil)

(defun evil-keypad--handle-negative-argument-trigger ()
  "Handle the negative argument trigger '-'.  Returns nil."
  (setq evil-keypad--session-active-prefix-arg
        (let ((arg evil-keypad--session-active-prefix-arg))
          (cond
           ((null arg) '-)
           ((eq arg '-) nil)
           ((integerp arg) (* arg -1))
           ((listp arg) (list (* (car arg) -1)))
           (t '-))))
  nil)

(defun evil-keypad--handle-digit-argument-trigger (digit-char)
  "Handle a digit character for building a numeric prefix argument.  Returns nil.
DIGIT-CHAR is the digit character (0-9) that was pressed."
  (let ((digit-val (string-to-number (string digit-char))))
    (setq evil-keypad--session-active-prefix-arg
          (let ((arg evil-keypad--session-active-prefix-arg))
            (cond
             ((null arg) digit-val)
             ((eq arg '-) (* digit-val -1))
             ((integerp arg)
              (if (< arg 0)
                  (- (* arg 10) digit-val)
                (+ (* arg 10) digit-val)))
             ((listp arg) digit-val)
             (t digit-val)))))
  nil)

(defun evil-keypad--maybe-set-pending-modifier (event mod-from-pending)
  "Set pending modifier based on EVENT and MOD-FROM-PENDING.
EVENT is the key event pressed.  MOD-FROM-PENDING is the pending modifier."
  (let ((key-is-m-trigger (eq event evil-keypad-M-trigger))
        (key-is-cm-trigger (eq event evil-keypad-C-M-trigger))
        (key-is-literal-trigger (eq event evil-keypad-literal-trigger)))
    (cond
     ((and (not mod-from-pending) key-is-m-trigger (evil-keypad--context-allows-modifier-type-p 'meta))
      (evil-keypad--set-new-pending-modifier event))
     ((and (not mod-from-pending) key-is-cm-trigger (evil-keypad--context-allows-modifier-type-p 'control-meta))
      (evil-keypad--set-new-pending-modifier event))
     ((and (not mod-from-pending) key-is-literal-trigger evil-keypad--keys)
      (evil-keypad--set-new-pending-modifier event))
     (t
      (evil-keypad--process-resolved-key event mod-from-pending)))))

(defun evil-keypad--handle-input (event)
  "Handle a single EVENT.  Returns t if loop should exit, nil otherwise."
  (evil-keypad--cancel-display-timer)
  (let ((cmd (lookup-key evil-keypad-state-keymap (vector event))))
    (if cmd
        (call-interactively cmd)
      (let ((is-initial-phase (and (null evil-keypad--keys) (null evil-keypad--pending-modifier))))
        (cond
         ((and (eq event help-char)
               (not (lookup-key (evil-keypad--get-current-keymap) (vector event) t)))
          (if (keymapp (evil-keypad--get-current-keymap))
              (evil-keypad--handle-help-request (evil-keypad--get-current-keymap))
            (progn (ding) nil)))
         ((and is-initial-phase
               (eq event evil-keypad-universal-argument-trigger))
          (evil-keypad--handle-universal-argument-trigger)
          (evil-keypad--try-execute))
         ((and is-initial-phase
               (eq event evil-keypad-negative-argument-trigger))
          (evil-keypad--handle-negative-argument-trigger)
          (evil-keypad--try-execute))
         ((and is-initial-phase
               (characterp event) (>= event ?0) (<= event ?9))
          (evil-keypad--handle-digit-argument-trigger event)
          (evil-keypad--try-execute))
         (t
          (let ((mod-from-pending evil-keypad--pending-modifier))
            (setq evil-keypad--pending-modifier nil)
            (evil-keypad--maybe-set-pending-modifier event mod-from-pending))))))))

;;;###autoload
(defun evil-keypad-start ()
  "Start the Evil Keypad transient mode."
  (interactive)
  (evil-keypad--cancel-display-timer-and-clear)
  (setq evil-keypad--keys nil
        evil-keypad--pending-modifier nil
        evil-keypad--session-initial-prefix-arg current-prefix-arg
        evil-keypad--session-active-prefix-arg evil-keypad--session-initial-prefix-arg
        evil-keypad--control-inducing-sequence-p nil)

  (when (and (boundp 'which-key-mode) which-key-mode)
    (evil-keypad--which-key-integration-setup))

  (evil-keypad--try-execute)

  (unwind-protect
      (while (not (evil-keypad--handle-input (read-key))))
    (evil-keypad--quit)))


(provide 'evil-keypad)

;;; evil-keypad.el ends here
