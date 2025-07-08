# Evil Keypad
[![MELPA](https://melpa.org/packages/evil-keypad-badge.svg)](https://melpa.org/#/evil-keypad)
[![MELPA Stable](https://stable.melpa.org/packages/evil-keypad-badge.svg)](https://stable.melpa.org/#/evil-keypad)

## What Is Evil Keypad?

**Evil Keypad** is a transient key dispatch system for Emacs Evil users. Inspired by [Meow's Keypad](https://github.com/meow-edit/meow) and [God Mode](https://github.com/emacsorphanage/god-mode), it provides a fast and ergonomic way to enter Emacs commands like `C-x C-f`, `C-c C-x C-c`, or `C-u 4 C-x ^` without holding modifier keys.

After pressing a trigger key (e.g., `,` or `SPC` in Evil normal state), you enter a short sequence of unmodified keys. Evil Keypad interprets this sequence into a standard Emacs keybinding and executes the resulting command, then automatically exits. Think modal input for native Emacs keybindings with no chording and fewer custom leader keymaps.

## Why Evil Keypad?

Standard Emacs bindings, while powerful, can feel cumbersome when integrated with a modal editing paradigm like Evil. Holding `Ctrl` or `Meta` for multi-step command chains can break the ergonomic flow. While leader key setups (e.g., via `general.el`) mitigate this, they often require extensive manual configuration, as many commands might need explicit rebinding.

Meow's Keypad introduced an elegant solution by translating sequences of simple keys into standard Emacs bindings on the fly. However, adopting Meow typically means forgoing Evil's rich editing model. Evil Keypad aims to avoid this tradeoff: it brings the keypad translation concept to Evil users (and others) without requiring them to discard existing muscle memory or text editing workflows.

**Evil Keypad is designed to:**

* Make Emacs commands ergonomic by replacing modifier key chords with simple sequential keypresses
* Guide you through command sequences with live suggestions and completions via `which-key`
* Work naturally with Evil's modal editing while remaining useful for non-Evil users
* Preserve all native Emacs keybindings without any manual rebinding needed

## Installation

Evil Keypad is available on MELPA. You can install it using `package.el`:

### Using `package-install`

1. Ensure MELPA is added to your `package-archives`:
   ```elisp
   (require 'package)
   (add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
   (package-initialize)
   ```

2. Install `evil-keypad`:
   ```elisp
   M-x package-install RET evil-keypad RET
   ```

3. Enable the mode:
   ```elisp
   (require 'evil-keypad)
   (evil-keypad-global-mode 1)
   ```

### Using `use-package`

```elisp
(use-package evil-keypad
  :ensure t
  :after evil
  :config
  (evil-keypad-global-mode 1))
```

### Manual Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/achyudh/evil-keypad.git /path/to/your/emacs/site-lisp/evil-keypad
    ```
2.  **Add to `load-path` in your Emacs configuration (`init.el` or `~/.emacs.d/init.el`):**
    ```elisp
    (add-to-list 'load-path "/path/to/your/emacs/site-lisp/evil-keypad")
    (require 'evil-keypad)
    (evil-keypad-global-mode 1)
    ```

## Usage

### Activating Evil Keypad

You have two options for activating the keypad:

1. **Global Activation Mode (Recommended)**:
   Enable `evil-keypad-global-mode` to automatically bind the trigger key in specified Evil states:
   ```elisp
   (evil-keypad-global-mode 1)
   ```
   You can customize:
   - `evil-keypad-activation-trigger` (default: `SPC`) - The key that activates the keypad
   - `evil-keypad-activation-states` (default: `'(normal visual emacs)`) - Evil states where the trigger is active

2. **Manual Key Binding**:
   Bind `evil-keypad-start` to your preferred key:
   ```elisp
   ;; For Evil Normal state:
   (define-key evil-normal-state-map (kbd "SPC") #'evil-keypad-start)
   ;; For global binding:
   (global-set-key (kbd "C-;") #'evil-keypad-start)
   ```

### Using Evil Keypad

1.  Press your chosen trigger key. The echo area will clear, indicating Evil Keypad is active.
2.  Type a sequence of keys according to the translation logic detailed in the next section.
    * If you type a sequence that translates to an Emacs prefix (e.g., keypad `x` for `C-x`), the echo area will show the prefix with a dash (e.g., `C-x-`).
    * If you type a modifier trigger (`m`, `g`, `SPC`), the echo area indicates the pending modifier (e.g., `C-x M-`).
    * If `which-key-mode` is active, a `which-key` popup will appear showing available commands.
3.  To pass numeric arguments to commands (like `C-u 4` or `M-5`):
    * Press `u` for universal argument (`C-u`)
    * Press `-` for negative argument (`M--`)
    * Press digits `0-9` for numeric arguments
    * These can be combined: `u u` = `C-u C-u`, `- 5` = `M-- 5`, etc.
4.  Once a complete command is recognized, it executes, and the keypad automatically exits.
5.  If the sequence is unbound, an `<sequence> is undefined` message appears, and the keypad exits.
6.  Press `C-g` anytime to cancel and exit the keypad.
7.  Press `C-h` (or `help-char`) to get help for the current prefix. If `evil-keypad-prefix-help-command` is set, it will be called with the current keymap; otherwise, Emacs will ding.
8.  Press `Backspace` or `DEL` to undo the last keypress, pending modifier, or prefix argument.

### Key Translation Logic

Evil Keypad uses a systematic approach to translate simple key sequences into Emacs commands with modifiers. The translation system distinguishes between the first key you type (which often determines what kind of command sequence you're starting) and subsequent keys. When you start typing, special keys like `x`, `c`, and `h` trigger common Emacs command prefixes (`C-x`, `C-c`, `C-h`), while `m` and `g` set up Meta and Control-Meta modifiers. Any other key is treated as a shortcut for a `C-c` command sequence. These trigger keys can be customized—see the Customization section below.

A key feature of the translation system is the concept of **Ctrl-persistent prefixes**. These are command prefixes (like `C-c` or `C-x`) that, when explicitly triggered, cause subsequent keys to default to being `Ctrl`-modified unless a modifier trigger is used. This behavior mimics how many Emacs users naturally think about command sequences - for instance, `C-x C-f` is often thought of as "Control-x, then Control-f" rather than two separate chord keypresses.

* **First Key Typed:**
    * `x`: Translates to `C-x`. This is a Ctrl-persistent prefix and subsequent keys will be `Ctrl`-modified unless a modifier trigger is used.
    * `c`: Translates to `C-c`. This is a Ctrl-persistent prefix and subsequent keys will be `Ctrl`-modified unless a modifier trigger is used.
    * `h`: Translates to `C-h`. This is not a Ctrl-persistent prefix and subsequent keys default to literal.
    * `m`: Sets a pending `M-` (Meta) modifier for the next key. `M-` initiated prefixes are Ctrl-persistent and subsequent keys will be `Ctrl`-modified unless a modifier trigger is used.
    * `g`: Sets a pending `C-M-` (Control-Meta) modifier for the next key. `C-M-` initiated prefixes are Ctrl-persistent and subsequent keys will be `Ctrl`-modified unless a modifier trigger is used.
    * Any other key `k` (e.g., `a`, `f`, `SPC`): Interpreted as `C-c k`. This implicitly-started `C-c` is not a Ctrl-persistent prefix and subsequent keys default to literal.

* **Subsequent Keys:**
    * `m`: Sets a pending `M-` modifier for the *next* key. Makes the sequence Ctrl-persistent so subsequent keys will be `Ctrl`-modified unless a modifier trigger is used.
    * `g`: Sets a pending `C-M-` modifier for the *next* key. Makes the sequence Ctrl-persistent so subsequent keys will be `Ctrl`-modified unless a modifier trigger is used.
    * `SPC` (if not the first key): Sets a pending `literal` modifier for the *next* key only. The key will be inserted without any modifiers.
    * **If a modifier was pending (`M-`, `C-M-`, `literal`):** It's applied to the current typed key.
    * **If no modifier was pending:**
        * If the sequence is Ctrl-persistent (after `x`, `c`, or any use of `m`/`g`): The current key `k` is modified with `Control` (becomes `C-k`).
        * Otherwise (after `h` trigger or after implicit `C-c k`): The current key `k` is treated literally.

* **Case:** Uppercase letters interact as expected with `Control` and `Meta` modifiers (e.g., `x F` translates to `C-x C-S-f` and `m F` translates to `M-F`).

* **Modifier Handling in Keymaps:** When using `m` or `g` after a prefix, Evil Keypad first checks if the current keymap supports Meta or Control-Meta modified keys directly. For example:
    * In `C-x` keymap: `x m f` becomes `C-x M-f` because `C-x` has bindings that start with `M-`
    * In other keymaps: If no Meta bindings exist, the modifier key itself is treated as a regular key with Control modifier, so `x m f` would become `C-x C-m C-f`
    * This behavior ensures maximum compatibility with Emacs keymaps while preserving the ability to enter Meta-modified commands when available.

* **Fallback Logic:** If a sequence ending in an implicitly `Control`-modified key (e.g., `x f` -\> `C-x C-f`) is undefined, the keypad automatically attempts the sequence with a literal final key (`C-x f`). This fallback can result in a command or a new prefix state (with `which-key` updating). Fallback does *not* occur if the original modifier was an explicit `M-` or `C-M-` from an `m` or `g` trigger.

**Examples:**

| Keypad Input  | Translated Emacs Sequence | Notes                                                                         |
|:------------- |:------------------------- |:----------------------------------------------------------------------------- |
| `a`           | `C-c a`                   | Implicit `C-c` does not start a Ctrl-persistent sequence                      |
| `a s`         | `C-c a s`                 | Keys are not `Ctrl`-modified as this is not a Ctrl-persistent sequence        |
| `c`           | `C-c`                     | `c` starts a Ctrl-persistent sequence                                         |
| `c a`         | `C-c C-a`                 | In a Ctrl-persistent sequence, keys will be `Ctrl`-modified                   |
| `x f`         | `C-x C-f`                 | `x` also starts a Ctrl-persistent sequence                                    |
| `x SPC t`     | `C-x t`                   | `SPC` makes next key literal in a Ctrl-persistent sequence                    |
| `x SPC t a`   | `C-x t C-a`               | After literal `t`, sequence is still Ctrl-persistent                          |
| `m s`         | `M-s`                     | `m` applies Meta to next key and makes sequence Ctrl-persistent               |
| `m x f`       | `M-x C-f`                 | After `M-x`, `f` will be `Ctrl`-modified as `m` makes the sequence Ctrl-persistent |
| `h v`         | `C-h v`                   | `h` does not start a Ctrl-persistent sequence                                 |
| `x m f`       | `C-x M-f`                 | `m` handling depends on keymap, here `C-x` has bindings starting with `M-`    |
| `u f`         | `C-u C-f`                 | Universal argument followed by command                                        |
| `u u f`       | `C-u C-u C-f`             | Multiple universal arguments stack                                            |
| `- f`         | `M-- C-f`                 | Negative argument                                                             |
| `5 f`         | `M-5 C-f`                 | Numeric argument                                                              |
| `- 5 f`       | `M--5 C-f`                | Negative numeric argument                                                     |

### Custom Leader Key Patterns

Evil Keypad also provides an elegant way to create leader-key-style bindings without explicit configuration. Any key that isn't a special trigger (`x`, `c`, `h`) automatically starts a `C-c` sequence. This means you can organize your custom bindings under `C-c` prefixes, and they become naturally available through Evil Keypad with intuitive sequences. For example, here's how you might set up some Consult commands:

```elisp
(use-package consult
  :bind (("C-c SPC" . 'consult-buffer)     ; → SPC SPC
         ("C-c f" . 'consult-flymake)      ; → SPC f
         ("C-c i" . 'consult-imenu)        ; → SPC i
         ("C-c I" . 'consult-imenu-multi)  ; → SPC I
         ("C-c o a" . 'consult-org-agenda) ; → SPC o a
         ("C-c s f" . 'consult-fd)         ; → SPC s f
         ("C-c s r" . 'consult-ripgrep)    ; → SPC s r
         ("C-c s s" . 'consult-line)))     ; → SPC s s
```

This gives you the ergonomics of a leader key setup while maintaining the simplicity and discoverability of standard key bindings. You can organize your bindings in a hierarchical way that feels natural (like `s s` for consult-line, `s r` for consult-ripgrep) without additional configuration.

## Which-Key Integration

Evil Keypad integrates deeply with `which-key` to provide interactive command discovery:

* When the keypad starts, which-key shows available first-key options (x, c, h, m, g, etc.).
* After entering a prefix, which-key shows the standard Emacs keymap for that prefix.
* The display updates automatically as you type modifiers or keys.
* *Note:* `which-key` is bundled with Emacs starting from version 30. For Emacs 29 and earlier, ensure the `which-key` package is installed (e.g., from ELPA/NonGNU ELPA) and `which-key-mode` is enabled.

## Customizing Help Behavior

The `evil-keypad-prefix-help-command` variable allows you to customize the behavior when `help-char` (typically `C-h`) is pressed after a prefix in Evil Keypad. If this variable is set to a function, that function will be called with one argument: the keymap for the current prefix. If the variable is `nil` (the default), Emacs will simply ding.

Here are some examples of functions you can assign to `evil-keypad-prefix-help-command`:

**1. Using `describe-keymap`:**

This will make `C-h` within Evil Keypad show a `*Help*` buffer describing the keymap of the current prefix.

```elisp
(setq evil-keypad-prefix-help-command #'describe-keymap)
```

**2. Using `embark-bindings-in-keymap`:**

If you have `embark` installed, this will allow you to interactively explore the bindings in the current prefix's keymap using `embark`'s powerful `completing-read` interface.

```elisp
(setq evil-keypad-prefix-help-command #'embark-bindings-in-keymap)
```

## Customization

You can customize Evil Keypad via `M-x customize-group RET evil-keypad RET`. Here are the key variables:

| Variable                                 | Default | Purpose                                                             |
| :--------------------------------------- | :------ | :------------------------------------------------------------------ |
| `evil-keypad-activation-trigger`         | `SPC`   | Key that activates the keypad in `evil-keypad-global-mode`          |
| `evil-keypad-activation-states`          | `'(normal visual emacs)` | Evil states where the activation trigger is active |
| `evil-keypad-M-trigger`                  | `m`     | Key to trigger `M-` for the next input                              |
| `evil-keypad-C-M-trigger`                | `g`     | Key to trigger `C-M-` for the next input                            |
| `evil-keypad-literal-trigger`            | `SPC`   | Key to trigger literal next input                                   |
| `evil-keypad-C-x-trigger`                | `x`     | First key to represent the `C-x` prefix                             |
| `evil-keypad-C-c-trigger`                | `c`     | First key to represent the `C-c` prefix                             |
| `evil-keypad-C-h-trigger`                | `h`     | First key to represent the `C-h` prefix                             |
| `evil-keypad-universal-argument-trigger` | `u`     | Key to emulate universal argument (`C-u`)                           |
| `evil-keypad-negative-argument-trigger`  | `-`     | Key to emulate negative argument (`M--`)                            |
| `evil-keypad-prefix-help-command`        | `nil`   | Command to run when `help-char` is pressed after a prefix           |
| `evil-keypad-quit-key`                   | `C-g`   | Key to quit the keypad input state                                  |

## License

This package is licensed under the GNU General Public License v3.0.
