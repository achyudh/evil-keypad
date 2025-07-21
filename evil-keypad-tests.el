;;; evil-keypad-tests.el --- ERT tests for evil-keypad.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'evil)
(require 'evil-keypad)

;;----------------------------------------
;; Test Helpers
;;----------------------------------------

;; State variables for test mocking
(defvar evil-keypad-test--executed-cmd nil "Last executed command.")
(defvar evil-keypad-test--executed-prefix-arg nil "Prefix arg used with last command.")
(defvar evil-keypad-test--which-key-called nil "Flag to track if which-key display was called.")
(defvar evil-keypad-test--which-key-hidden nil "Flag to track if which-key display was hidden.")
(defvar evil-keypad-test--which-key-keymap-arg nil "Store keymap argument passed to which-key display function.")

;; Execution tracking and mocking
(defun evil-keypad-test--track-execution (orig-fn command)
  "Advice for evil-keypad--execute to track execution."
  (setq evil-keypad-test--executed-cmd command
        evil-keypad-test--executed-prefix-arg evil-keypad--session-active-prefix-arg)
  t)

(defun evil-keypad-test--null-try-execute (orig-fn &rest _args)
  "Advise `evil-keypad--try-execute` to do nothing and return nil.
Used to test only the state-update logic of `evil-keypad--handle-input`."
  nil)

;; Which-key mocking
(defun evil-keypad-test--mock-which-key-show (&optional prefix-keys from-keymap filter prefix-title)
  "Mock for which-key--create-buffer-and-show."
  (setq evil-keypad-test--which-key-called t
        evil-keypad-test--which-key-keymap-arg from-keymap))

(defun evil-keypad-test--mock-which-key-hide ()
  "Mock for which-key--hide-popup."
  (setq evil-keypad-test--which-key-hidden t))

(defun evil-keypad-test--reset-which-key-mocks ()
  "Reset which-key mock state."
  (setq evil-keypad-test--which-key-called nil
        evil-keypad-test--which-key-hidden nil
        evil-keypad-test--which-key-keymap-arg nil))

(defun evil-keypad-test--force-timer ()
  "Force immediate execution of display timer."
  (when evil-keypad--display-timer
    (cancel-timer evil-keypad--display-timer)
    (funcall evil-keypad--display-bindings-function)))

;; State management and verification
(defun evil-keypad-test--get-state ()
  "Return a snapshot of the current evil-keypad state."
  (list :keys evil-keypad--keys
        :pending-modifier evil-keypad--pending-modifier
        :control-inducing evil-keypad--control-inducing-sequence-p
        :prefix-arg evil-keypad--session-active-prefix-arg
        :initial-prefix-arg evil-keypad--session-initial-prefix-arg))

(defun evil-keypad-test--verify-clean-state ()
  "Verify that all state variables are properly reset."
  (should (null evil-keypad--keys))
  (should (null evil-keypad--pending-modifier))
  (should (null evil-keypad--control-inducing-sequence-p))
  (should (null evil-keypad--session-active-prefix-arg))
  (should (null evil-keypad--session-initial-prefix-arg)))

;; Testing macros and setup functions
(defmacro evil-keypad-test-translations-only (&rest body)
  "Execute BODY with `evil-keypad--try-execute` advised to do nothing and return nil."
  (declare (indent 0))
  `(let ((evil-keypad--keys nil)
         (evil-keypad--pending-modifier nil)
         (evil-keypad--control-inducing-sequence-p nil)
         (evil-keypad--session-active-prefix-arg nil))
     (advice-add 'evil-keypad--try-execute :around #'evil-keypad-test--null-try-execute)
     (unwind-protect
         (progn ,@body)
       (evil-keypad--quit)
       (advice-remove 'evil-keypad--try-execute #'evil-keypad-test--null-try-execute))))

;; Prefix argument testing helpers
(defun evil-keypad-test--simulate-prefix-arg (key-events-list)
  "Simulate typing KEY-EVENTS-LIST into evil-keypad for prefix arg testing.
Returns the current prefix arg value after simulation.
Resets evil-keypad internal state before and after each call."
  (let ((evil-keypad--keys nil)
        (evil-keypad--pending-modifier nil)
        (evil-keypad--control-inducing-sequence-p nil)
        (evil-keypad--session-active-prefix-arg nil))

    (dolist (event key-events-list)
      (evil-keypad--handle-input event))

    (prog1 evil-keypad--session-active-prefix-arg
      (evil-keypad--quit))))

(defun evil-keypad-test--get-prefix-arg-display (key-events-list)
  "Simulate typing KEY-EVENTS-LIST and return the formatted prefix arg display.
Resets evil-keypad internal state before and after each call."
  (let ((evil-keypad--keys nil)
        (evil-keypad--pending-modifier nil)
        (evil-keypad--control-inducing-sequence-p nil)
        (evil-keypad--session-active-prefix-arg nil))

    (dolist (event key-events-list)
      (evil-keypad--handle-input event))

    (prog1 (evil-keypad--format-prefix-arg evil-keypad--session-active-prefix-arg)
      (evil-keypad--quit))))

(defun evil-keypad-test--simulate-translation (key-events-list)
  "Simulate typing KEY-EVENTS-LIST into evil-keypad for translation testing.
Returns (FORMATTED-SEQ . CONTROL-INDUCING-P)."
  (let ((evil-keypad--keys nil)
        (evil-keypad--pending-modifier nil)
        (evil-keypad--control-inducing-sequence-p nil))

    (dolist (event key-events-list)
      (evil-keypad--handle-input event))

    (cons (evil-keypad--format-sequence evil-keypad--keys)
          evil-keypad--control-inducing-sequence-p)))

;;----------------------------------------
;; ERT Test Cases - Key Sequence Translations
;;----------------------------------------

(ert-deftest evil-keypad-test-sequence-translations ()
  "Test core key sequence translations (state update and formatting)."
  (evil-keypad-test-translations-only
   ;; --- Basic C-x, M-x, C-c k ---
   (let ((result (evil-keypad-test--simulate-translation '(?x ?f))))
     (should (string= (car result) "C-x C-f"))
     (should (cdr result))) ; control-inducing should be t

   (let ((result (evil-keypad-test--simulate-translation '(?m ?x))))
     (should (string= (car result) "M-x"))
     (should (cdr result)))

   (let ((result (evil-keypad-test--simulate-translation '(?a))))
     (should (string= (car result) "C-c a"))
     (should-not (cdr result)))

   ;; --- Control-Inducing Logic & Literal SPC ---
   (let ((result (evil-keypad-test--simulate-translation '(?c ?a))))
     (should (string= (car result) "C-c C-a"))
     (should (cdr result)))

   (let ((result (evil-keypad-test--simulate-translation '(?x ?\s ?f))))
     (should (string= (car result) "C-x f"))
     (should (cdr result)))

   (let ((result (evil-keypad-test--simulate-translation '(?h ?v))))
     (should (string= (car result) "C-h v"))
     (should-not (cdr result)))

   (let ((result (evil-keypad-test--simulate-translation '(?x ?\s ?t ?a))))
     (should (string= (car result) "C-x t C-a"))
     (should (cdr result)))

   (let ((result (evil-keypad-test--simulate-translation '(?m ?s ?a))))
     (should (string= (car result) "M-s C-a"))
     (should (cdr result)))

   (let ((result (evil-keypad-test--simulate-translation '(?g ?s ?a))))
     (should (string= (car result) "C-M-s C-a"))
     (should (cdr result)))

   (let ((result (evil-keypad-test--simulate-translation '(?a ?s ?d))))
     (should (string= (car result) "C-c a s d"))
     (should-not (cdr result)))

   ;; --- Uppercase Handling ---
   (let ((result (evil-keypad-test--simulate-translation '(?x ?F))))
     (should (string= (car result) "C-x C-S-f"))
     (should (cdr result)))

   (let ((result (evil-keypad-test--simulate-translation '(?m ?F))))
     (should (string= (car result) "M-F"))
     (should (cdr result)))

   (let ((result (evil-keypad-test--simulate-translation '(?g ?F))))
     (should (string= (car result) "C-M-S-f"))
     (should (cdr result)))

   (let ((result (evil-keypad-test--simulate-translation '(?h ?\s ?F))))
     (should (string= (car result) "C-h F"))
     (should-not (cdr result)))

   (let ((result (evil-keypad-test--simulate-translation '(?a ?F))))
     (should (string= (car result) "C-c a F"))
     (should-not (cdr result)))

   ;; --- Control-Inducing Prefixes ---
   (let ((result (evil-keypad-test--simulate-translation '(?c ?t ?t))))
     (should (string= (car result) "C-c C-t C-t"))
     (should (cdr result)))

   ;; --- Trigger key interactions ---
   (let ((result (evil-keypad-test--simulate-translation '(?m ?m))))
     (should (string= (car result) "M-m"))
     (should (cdr result)))

   (let ((result (evil-keypad-test--simulate-translation '(?g ?g))))
     (should (string= (car result) "C-M-g"))
     (should (cdr result)))

   (let ((result (evil-keypad-test--simulate-translation '(?m ?g))))
     (should (string= (car result) "M-g"))
     (should (cdr result)))

   (let ((result (evil-keypad-test--simulate-translation '(?g ?m))))
     (should (string= (car result) "C-M-m"))
     (should (cdr result)))

   (let ((result (evil-keypad-test--simulate-translation '(?x ?\s ?\s))))
     (should (string= (car result) "C-x SPC"))
     (should (cdr result)))

   ;; --- Special keys and SPC as first key ---
   (let ((result (evil-keypad-test--simulate-translation (list (string-to-char " ")))))
     (should (string= (car result) "C-c SPC"))
     (should-not (cdr result)))

   (let ((result (evil-keypad-test--simulate-translation (list (string-to-char "\t")))))
     (should (string= (car result) "C-c TAB"))
     (should-not (cdr result)))

   (let ((result (evil-keypad-test--simulate-translation (list evil-keypad-C-x-trigger (string-to-char "\r")))))
     (should (string= (car result) "C-x C-RET"))
     (should (cdr result)))))

;;----------------------------------------
;; ERT Test Cases - State Management
;;----------------------------------------

(ert-deftest evil-keypad-test-clean-state ()
  "Test that state is properly initialized and cleaned."
  (evil-keypad-test-translations-only
   ;; Test initial state
   (evil-keypad-test--verify-clean-state)

   ;; Modify state
   (evil-keypad--handle-input ?x)
   (should evil-keypad--keys)
   (should evil-keypad--control-inducing-sequence-p)

   ;; Test cleanup
   (evil-keypad--quit)
   (evil-keypad-test--verify-clean-state)))

(ert-deftest evil-keypad-test-control-inducing-transitions ()
  "Test control-inducing flag transitions for different sequences."
  (evil-keypad-test-translations-only
   ;; Test C-x (should be control-inducing)
   (evil-keypad--handle-input ?x)
   (should evil-keypad--control-inducing-sequence-p)
   (evil-keypad--quit)

   ;; Test C-c (should be control-inducing)
   (evil-keypad--handle-input ?c)
   (should evil-keypad--control-inducing-sequence-p)
   (evil-keypad--quit)

   ;; Test C-h (should not be control-inducing)
   (evil-keypad--handle-input ?h)
   (should-not evil-keypad--control-inducing-sequence-p)
   (evil-keypad--quit)

   ;; Test regular key (should not be control-inducing)
   (evil-keypad--handle-input ?a)
   (should-not evil-keypad--control-inducing-sequence-p)
   (evil-keypad--quit)

   ;; Test Meta modifier (should be control-inducing)
   (evil-keypad--handle-input ?m)
   (should evil-keypad--control-inducing-sequence-p)
   (should (eq evil-keypad--pending-modifier 'meta))
   (evil-keypad--quit)

   ;; Test Control-Meta modifier (should be control-inducing)
   (evil-keypad--handle-input ?g)
   (should evil-keypad--control-inducing-sequence-p)
   (should (eq evil-keypad--pending-modifier 'control-meta))))

(ert-deftest evil-keypad-test-modifier-state-transitions ()
  "Test state transitions involving modifiers."
  (evil-keypad-test-translations-only
   ;; Test Meta modifier pending state
   (should (null evil-keypad--pending-modifier))
   (evil-keypad--handle-input ?m)
   (should (eq evil-keypad--pending-modifier 'meta))
   (should evil-keypad--control-inducing-sequence-p)

   ;; Test Meta modifier application
   (evil-keypad--handle-input ?x)
   (should (null evil-keypad--pending-modifier))
   (should (equal (car evil-keypad--keys) '(meta . "x")))

   ;; Test Control-Meta modifier pending state
   (evil-keypad--quit)
   (evil-keypad--handle-input ?g)
   (should (eq evil-keypad--pending-modifier 'control-meta))
   (should evil-keypad--control-inducing-sequence-p)

   ;; Test Control-Meta modifier application
   (evil-keypad--handle-input ?x)
   (should (null evil-keypad--pending-modifier))
   (should (equal (car evil-keypad--keys) '(control-meta . "x")))))

(ert-deftest evil-keypad-test-literal-modifier-state ()
  "Test literal modifier state in different contexts."
  (evil-keypad-test-translations-only
   ;; Test literal modifier in control-inducing sequence
   (evil-keypad--handle-input ?x)
   (should (equal evil-keypad--keys '((control . "x"))))
   (should evil-keypad--control-inducing-sequence-p)

   (evil-keypad--handle-input ?\s)
   (should (eq evil-keypad--pending-modifier 'literal))

   (evil-keypad--handle-input ?f)
   (should (equal evil-keypad--keys
                  '((literal . "f") (control . "x"))))
   (should evil-keypad--control-inducing-sequence-p)

   ;; Test that subsequent keys maintain control-inducing
   (evil-keypad--handle-input ?a)
   (should (equal evil-keypad--keys
                  '((control . "a") (literal . "f") (control . "x"))))
   (should evil-keypad--control-inducing-sequence-p)))

;;----------------------------------------
;; ERT Test Cases - Undo Logic
;;----------------------------------------

(ert-deftest evil-keypad-test-undo-logic ()
  "Test undo functionality and its effect on sequence state and flags."
  (evil-keypad-test-translations-only
   ;; 1. Type 'x', then 'm' (pending), then undo 'm'
   (evil-keypad--handle-input ?x)
   (should (string= (evil-keypad--format-sequence evil-keypad--keys) "C-x"))
   (should evil-keypad--control-inducing-sequence-p)

   (evil-keypad--handle-input ?m)
   (should (eq evil-keypad--pending-modifier 'meta))
   (should (string= (evil-keypad--format-sequence evil-keypad--keys) "C-x"))

   (evil-keypad-undo)
   (should (null evil-keypad--pending-modifier))
   (should (string= (evil-keypad--format-sequence evil-keypad--keys) "C-x"))
   (should evil-keypad--control-inducing-sequence-p)

   ;; 2. Type 'f' (becomes C-f), then undo 'f'
   (evil-keypad--handle-input ?f)
   (should (string= (evil-keypad--format-sequence evil-keypad--keys) "C-x C-f"))
   (evil-keypad-undo)
   (should (string= (evil-keypad--format-sequence evil-keypad--keys) "C-x"))
   (should evil-keypad--control-inducing-sequence-p)

   ;; 3. Undo 'x'
   (evil-keypad-undo)
   (should (null evil-keypad--keys))
   (should (not evil-keypad--control-inducing-sequence-p))

   ;; 4. Undo on empty state
   (evil-keypad-undo)
   (should (null evil-keypad--keys))
   (should (not evil-keypad--control-inducing-sequence-p))))

;;----------------------------------------
;; ERT Test Cases - Prefix Arguments
;;----------------------------------------

(ert-deftest evil-keypad-test-numeric-prefix-args ()
  "Test basic numeric prefix argument handling."
  (evil-keypad-test-translations-only
   ;; Single digits
   (should (equal (evil-keypad-test--simulate-prefix-arg '(?5)) 5))

   ;; Multiple digits
   (should (equal (evil-keypad-test--simulate-prefix-arg '(?4 ?2)) 42))
   (should (equal (evil-keypad-test--simulate-prefix-arg '(?1 ?2 ?3)) 123))

   ;; Leading zero
   (should (equal (evil-keypad-test--simulate-prefix-arg '(?0)) 0))
   (should (equal (evil-keypad-test--simulate-prefix-arg '(?0 ?5)) 5))

   ;; Negative numbers
   (should (equal (evil-keypad-test--simulate-prefix-arg '(?-)) '-))
   (should (equal (evil-keypad-test--simulate-prefix-arg '(?- ?5)) -5))
   (should (equal (evil-keypad-test--simulate-prefix-arg '(?- ?1 ?2)) -12))

   ;; Toggles with multiple minuses
   (should (equal (evil-keypad-test--simulate-prefix-arg '(?- ?-)) nil))
   (should (equal (evil-keypad-test--simulate-prefix-arg '(?- ?- ?-)) '-))))

(ert-deftest evil-keypad-test-universal-prefix-args ()
  "Test universal argument (C-u) handling."
  (evil-keypad-test-translations-only
   ;; Basic universal argument
   (should (equal (evil-keypad-test--simulate-prefix-arg '(?u)) '(4)))

   ;; Multiple universal arguments
   (should (equal (evil-keypad-test--simulate-prefix-arg '(?u ?u)) '(16)))
   (should (equal (evil-keypad-test--simulate-prefix-arg '(?u ?u ?u)) '(64)))

   ;; Universal with numbers
   (should (equal (evil-keypad-test--simulate-prefix-arg '(?u ?5)) 5))
   (should (equal (evil-keypad-test--simulate-prefix-arg '(?u ?4 ?2)) 42))

   ;; Universal with negative
   (should (equal (evil-keypad-test--simulate-prefix-arg '(?u ?-)) '(-4)))
   (should (equal (evil-keypad-test--simulate-prefix-arg '(?- ?u)) '(-4)))

   ;; Numbers before universal
   (should (equal (evil-keypad-test--simulate-prefix-arg '(?5 ?u)) '(4)))
   (should (equal (evil-keypad-test--simulate-prefix-arg '(?4 ?2 ?u)) '(4)))))

(ert-deftest evil-keypad-test-prefix-arg-display ()
  "Test prefix argument display formatting."
  (evil-keypad-test-translations-only
   ;; Basic numeric display
   (should (string= (evil-keypad-test--get-prefix-arg-display '(?5)) "C-u 5"))
   (should (string= (evil-keypad-test--get-prefix-arg-display '(?4 ?2)) "C-u 42"))

   ;; Universal argument display
   (should (string= (evil-keypad-test--get-prefix-arg-display '(?u)) "C-u"))
   (should (string= (evil-keypad-test--get-prefix-arg-display '(?u ?u)) "C-u (16)"))

   ;; Negative number display
   (should (string= (evil-keypad-test--get-prefix-arg-display '(?-)) "C-u -"))
   (should (string= (evil-keypad-test--get-prefix-arg-display '(?- ?5)) "C-u -5"))

   ;; Complex combinations
   (should (string= (evil-keypad-test--get-prefix-arg-display '(?u ?-)) "C-u -"))
   (should (string= (evil-keypad-test--get-prefix-arg-display '(?5 ?u)) "C-u"))

   ;; Empty/nil display
   (should (string= (evil-keypad-test--get-prefix-arg-display '()) ""))))

;;----------------------------------------
;; ERT Test Cases - Which-Key Integration
;;----------------------------------------

(ert-deftest evil-keypad-test-which-key-integration ()
  "Test which-key integration behavior."
  (when (featurep 'which-key)
    (evil-keypad-test-translations-only
     (advice-add 'which-key--create-buffer-and-show :override #'evil-keypad-test--mock-which-key-show)
     (advice-add 'which-key--hide-popup :override #'evil-keypad-test--mock-which-key-hide)
     (unwind-protect
         (let ((evil-keypad--display-bindings-function #'evil-keypad--trigger-which-key-display)
               (evil-keypad--clear-display-function #'which-key--hide-popup)
               (which-key-mode t))

           ;; Test initial display
           (evil-keypad-test--reset-which-key-mocks)
           (evil-keypad--trigger-which-key-display)
           (should evil-keypad-test--which-key-called)
           (should (keymapp evil-keypad-test--which-key-keymap-arg))

           ;; Test display with keymap
           (evil-keypad-test--reset-which-key-mocks)
           (let ((test-map (make-sparse-keymap)))
             (evil-keypad--trigger-which-key-display test-map)
             (should evil-keypad-test--which-key-called)
             (should (eq evil-keypad-test--which-key-keymap-arg test-map)))

           ;; Test display cancellation and clearing
           (evil-keypad-test--reset-which-key-mocks)
           (evil-keypad--cancel-display-timer-and-clear)
           (should evil-keypad-test--which-key-hidden)

           ;; Test scheduled display - using direct call instead of timer
           (evil-keypad-test--reset-which-key-mocks)
           (let ((which-key-idle-delay 0.01))
             (evil-keypad--schedule-display)
             (should evil-keypad--display-timer)
             (evil-keypad-test--force-timer)  ; Force execution instead of waiting
             (should evil-keypad-test--which-key-called)))
       (advice-remove 'which-key--create-buffer-and-show #'evil-keypad-test--mock-which-key-show)
       (advice-remove 'which-key--hide-popup #'evil-keypad-test--mock-which-key-hide)))))

;;----------------------------------------
;; ERT Test Cases - Command Execution
;;----------------------------------------

(ert-deftest evil-keypad-test-command-execution ()
  "Test command execution with proper prefix args."
  (advice-add 'evil-keypad--execute :around #'evil-keypad-test--track-execution)
  (unwind-protect
      (progn
        ;; Test simple command execution
        (setq evil-keypad--executed-cmd nil
              evil-keypad--executed-prefix-arg nil
              evil-keypad--session-active-prefix-arg nil)
        (evil-keypad--handle-command-binding 'find-file "C-x C-f")
        (should (eq evil-keypad-test--executed-cmd 'find-file))
        (should (null evil-keypad-test--executed-prefix-arg))

        ;; Test command with universal arg
        (setq evil-keypad--executed-cmd nil
              evil-keypad--executed-prefix-arg nil
              evil-keypad--session-active-prefix-arg '(4))
        (evil-keypad--handle-command-binding 'forward-char "C-f")
        (should (eq evil-keypad-test--executed-cmd 'forward-char))
        (should (equal evil-keypad-test--executed-prefix-arg '(4)))

        ;; Test command with numeric arg
        (setq evil-keypad--executed-cmd nil
              evil-keypad--executed-prefix-arg nil
              evil-keypad--session-active-prefix-arg 5)
        (evil-keypad--handle-command-binding 'previous-line "C-p")
        (should (eq evil-keypad-test--executed-cmd 'previous-line))
        (should (= evil-keypad-test--executed-prefix-arg 5)))
    (advice-remove 'evil-keypad--execute #'evil-keypad-test--track-execution)))

(defun evil-keypad-test--simulate-input (key-events-list)
  "Simulate typing KEY-EVENTS-LIST into evil-keypad."
  (evil-keypad--cancel-display-timer-and-clear)
  (setq evil-keypad--keys nil
        evil-keypad--pending-modifier nil
        evil-keypad--session-initial-prefix-arg current-prefix-arg
        evil-keypad--session-active-prefix-arg evil-keypad--session-initial-prefix-arg
        evil-keypad--control-inducing-sequence-p nil)

  (dolist (event key-events-list)
    (evil-keypad--handle-input event)))

(ert-deftest evil-keypad-test-prefix-help-command ()
  "Test the prefix-help-command functionality."
  (let ((help-command-called-with-keymap nil))
    (fset 'my-test-help-command
          (lambda (keymap)
            (setq help-command-called-with-keymap keymap)))
    (setq evil-keypad-prefix-help-command 'my-test-help-command)

    (unwind-protect
        (progn
          ;; Test that help is called for an unbound prefix
          (evil-keypad-test--simulate-input (list ?x help-char))
          (should (keymapp help-command-called-with-keymap))
          (should (eq (lookup-key help-command-called-with-keymap (kbd "C-f")) 'find-file))

          ;; Test that help is NOT called for a bound prefix
          (setq help-command-called-with-keymap nil)
          (define-key ctl-x-map (vector help-char) 'test-command)
          (evil-keypad-test--simulate-input (list ?x help-char))
          (should (null help-command-called-with-keymap)))
      (fmakunbound 'my-test-help-command)
      (define-key ctl-x-map (vector help-char) nil))))

(ert-deftest evil-keypad-test-prefix-help-command-nil ()
  "Test that `help-char` dings when `evil-keypad-prefix-help-command` is nil."
  (let ((help-command-called-with-keymap nil))
    (fset 'my-test-help-command
          (lambda (keymap)
            (setq help-command-called-with-keymap keymap)))
    (setq evil-keypad-prefix-help-command nil)

    (unwind-protect
        (progn
          ;; Simulate input that would trigger help
          (evil-keypad-test--simulate-input (list ?x help-char))

          ;; Verify that the help command was NOT called
          (should (null help-command-called-with-keymap)))
      (fmakunbound 'my-test-help-command))))

(provide 'evil-keypad-tests)

;;; evil-keypad-tests.el ends here
