;;; android-adb.el --- Android device communication -*- lexical-binding: t; -*-

;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1") (transient "0.3.0"))
;; URL: https://github.com/cat-emacs/android-adb
;; Keywords: tools processes

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;;; Commentary:

;; Locate adb, discover devices, and execute argument-vector commands without
;; requiring an Android project or enabling a minor mode.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'transient)

(defgroup android-adb nil
  "Android device communication."
  :group 'tools)

(defcustom android-adb-program nil
  "Explicit adb executable, or nil for automatic discovery."
  :type '(choice (const nil) string)
  :group 'android-adb)

(defcustom android-adb-sdk-directory nil
  "Optional SDK directory used after the variable `exec-path' when locating adb."
  :type '(choice (const nil) directory)
  :group 'android-adb)

(defcustom android-adb-query-timeout 5
  "Maximum seconds to wait for a short adb query."
  :type 'number
  :group 'android-adb)

(defcustom android-adb-default-device-serial nil
  "Default device serial used by adb commands and the `android-adb' menu."
  :type '(choice (const nil) string)
  :group 'android-adb)

(defun android-adb-executable ()
  "Return an executable adb path, or signal a user error.
An explicit `android-adb-program' takes precedence.  Otherwise search
the variable `exec-path', then configured SDK and SDK environment locations."
  (or (if android-adb-program
          (if (file-name-absolute-p android-adb-program)
              (and (file-executable-p android-adb-program) android-adb-program)
            (executable-find android-adb-program))
        (or (executable-find "adb")
            (cl-loop for sdk in (list android-adb-sdk-directory
                                     (getenv "ANDROID_HOME")
                                     (getenv "ANDROID_SDK_ROOT"))
                     when (and sdk (not (string-empty-p sdk)))
                     thereis
                     (cl-loop for name in '("adb" "adb.exe")
                              for path = (expand-file-name
                                          (concat "platform-tools/" name) sdk)
                              when (file-executable-p path) return path))))
      (user-error "Cannot find adb; set android-adb-program or add adb to exec-path")))

(defun android-adb-command (serial &rest arguments)
  "Return an adb argument vector for SERIAL and ARGUMENTS.
Nil SERIAL leaves device selection to adb.  Arguments are never shell parsed."
  (append (list (android-adb-executable))
          (when serial (list "-s" serial)) arguments))

(cl-defun android-adb-start (serial arguments &key name buffer filter sentinel)
  "Start adb for SERIAL with ARGUMENTS and return its process.
NAME, BUFFER, FILTER, and SENTINEL are `make-process' options.  The caller owns
process output and cleanup.  This function never waits for adb."
  (make-process :name (or name "android-adb")
                :buffer buffer :command (apply #'android-adb-command serial arguments)
                :filter filter :sentinel sentinel
                :connection-type 'pipe :noquery t))

(defun android-adb-query (serial &rest arguments)
  "Return output from a short adb query for SERIAL and ARGUMENTS.
Signal on failure or after `android-adb-query-timeout' seconds.  Long-running
operations should use `android-adb-start' instead."
  (let ((buffer (generate-new-buffer " *android-adb-query*")) process)
    (unwind-protect
        (progn
          (setq process (android-adb-start serial arguments :buffer buffer
                                          :sentinel #'ignore))
          (let ((deadline (+ (float-time) android-adb-query-timeout)))
            (while (and (process-live-p process) (< (float-time) deadline))
              (accept-process-output process 0.05))
            (when (process-live-p process)
              (user-error "Adb query timed out after %s seconds"
                          android-adb-query-timeout)))
          (let ((output (with-current-buffer buffer (buffer-string))))
            (unless (and (eq (process-status process) 'exit)
                         (zerop (process-exit-status process)))
              (user-error "Adb failed: %s" (string-trim output)))
            output))
      (when (and process (process-live-p process)) (delete-process process))
      (kill-buffer buffer))))

(defun android-adb-parse-devices (output)
  "Parse `adb devices -l' OUTPUT into device plists.
Each device has :serial and :state; optional keys include :model, :product,
:device, and :transport-id.  Offline and unauthorized devices are preserved."
  (let (devices)
    (dolist (line (split-string output "\n" t))
      (when (string-match
             "^\\([^[:space:]]+\\)[ \t]+\\(device\\|offline\\|unauthorized\\|recovery\\|sideload\\|bootloader\\|no permissions\\)\\(?:[ \t]+\\(.*\\)\\)?\r?$"
             line)
        (let ((device (list :serial (match-string 1 line)
                            :state (intern (string-replace " " "-" (match-string 2 line)))))
              (properties (or (match-string 3 line) "")))
          (dolist (property (split-string properties "[[:space:]]+" t))
            (when (string-match "^\\([^:]+\\):\\(.+\\)$" property)
              (setq device
                    (plist-put device
                               (intern (concat ":" (string-replace
                                                    "_" "-" (match-string 1 property))))
                               (match-string 2 property)))))
          (push device devices))))
    (nreverse devices)))

(defun android-adb-devices (&optional available-only)
  "Return connected device plists.
With AVAILABLE-ONLY non-nil, include only devices in the `device' state."
  (let ((devices (android-adb-parse-devices
                  (android-adb-query nil "devices" "-l"))))
    (if available-only
        (seq-filter (lambda (device) (eq (plist-get device :state) 'device)) devices)
      devices)))

(defun android-adb-device-label (device)
  "Return an unambiguous completion label for DEVICE."
  (format "%s (%s)" (or (plist-get device :model) (plist-get device :serial))
          (plist-get device :serial)))

(defun android-adb-read-device (&optional prompt)
  "Return a usable device serial, prompting with PROMPT when necessary.
A configured `android-adb-default-device-serial' is used when it is online.
A sole usable device is selected automatically.  If none is usable, report
connected device states rather than treating unauthorized devices as absent."
  (let* ((all (android-adb-devices))
         (devices (seq-filter (lambda (device)
                                (eq (plist-get device :state) 'device)) all))
         (default (and android-adb-default-device-serial
                       (seq-find
                        (lambda (device)
                          (equal android-adb-default-device-serial
                                 (plist-get device :serial)))
                        devices))))
    (cond
     (default (plist-get default :serial))
     ((null devices)
      (user-error "No usable Android device%s"
                  (if all
                      (concat ": " (mapconcat
                                     (lambda (device)
                                       (format "%s: %s" (plist-get device :serial)
                                               (plist-get device :state))) all ", "))
                    " connected")))
     ((= (length devices) 1)
      (setq android-adb-default-device-serial
            (plist-get (car devices) :serial)))
     (t (let* ((choices (mapcar (lambda (device)
                                 (cons (android-adb-device-label device)
                                       (plist-get device :serial))) devices))
               (choice (completing-read (or prompt "Android device: ") choices nil t
                                        nil nil
                                        (and android-adb-default-device-serial
                                             (android-adb-device-label
                                              (list :serial android-adb-default-device-serial))))))
          (setq android-adb-default-device-serial (cdr (assoc choice choices))))))))

(defun android-adb--buffer-output (name status output)
  "Display STATUS and OUTPUT in a special buffer named NAME."
  (with-current-buffer (get-buffer-create name)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert output)
      (unless (string-suffix-p "\n" output) (insert "\n"))
      (insert (format "\nExited with status %s\n" status)))
    (special-mode)
    (pop-to-buffer (current-buffer))))

(defun android-adb-list-devices ()
  "Display all devices reported by adb."
  (interactive)
  (let ((output (android-adb-query nil "devices" "-l")))
    (android-adb--buffer-output "*android-adb-devices*" 0 output)))

(defun android-adb-select-device (&optional serial)
  "Set the default device to SERIAL, or prompt for one."
  (interactive)
  (setq android-adb-default-device-serial
        (or serial (android-adb-read-device "Default Android device: ")))
  (message "android-adb: default device is %s" android-adb-default-device-serial))

(defun android-adb--server-command (command)
  "Run adb server COMMAND and display its output."
  (let ((output (android-adb-query nil command)))
    (android-adb--buffer-output "*android-adb-server*" 0 output)))

(defun android-adb-start-server ()
  "Start the adb server and display its output."
  (interactive)
  (android-adb--server-command "start-server"))

(defun android-adb-kill-server ()
  "Stop the adb server and display its output."
  (interactive)
  (android-adb--server-command "kill-server"))

(defun android-adb-reconnect ()
  "Reconnect the default device, or all devices when none is selected."
  (interactive)
  (let ((output (android-adb-query android-adb-default-device-serial "reconnect")))
    (android-adb--buffer-output "*android-adb-reconnect*" 0 output)))

(defun android-adb-shell (command)
  "Run COMMAND through adb shell on the default device.
COMMAND is split into arguments using `split-string-and-unquote', not passed
through a host shell."
  (interactive "sAdb shell command: ")
  (let* ((serial (android-adb-read-device))
         (arguments (append '("shell") (split-string-and-unquote command)))
         (buffer (get-buffer-create "*android-adb-shell*"))
         (process (android-adb-start
                   serial arguments
                   :name "android-adb-shell"
                   :buffer buffer
                   :sentinel
                   (lambda (process _event)
                     (when (memq (process-status process) '(exit signal))
                       (message "android-adb: shell exited with status %s"
                                (process-exit-status process)))))))
    (display-buffer buffer)
    process))

;;;###autoload (autoload 'android-adb "android-adb" nil t)
(transient-define-prefix android-adb ()
  "Discover and control Android devices through adb."
  [["Device"
    ("s" "Select default device" android-adb-select-device)
    ("l" "List devices" android-adb-list-devices)]
   ["Server"
    ("S" "Start server" android-adb-start-server)
    ("K" "Kill server" android-adb-kill-server)
    ("r" "Reconnect" android-adb-reconnect)]
   ["Command"
    ("x" "Run shell command" android-adb-shell)]])

(provide 'android-adb)
;;; android-adb.el ends here
