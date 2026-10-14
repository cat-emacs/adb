;;; android-adb.el --- Android device communication -*- lexical-binding: t; -*-

;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1"))
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
A sole usable device is selected automatically.  If none is usable, report
connected device states rather than treating unauthorized devices as absent."
  (let* ((all (android-adb-devices))
         (devices (seq-filter (lambda (device)
                                (eq (plist-get device :state) 'device)) all)))
    (cond
     ((null devices)
      (user-error "No usable Android device%s"
                  (if all
                      (concat ": " (mapconcat
                                     (lambda (device)
                                       (format "%s: %s" (plist-get device :serial)
                                               (plist-get device :state))) all ", "))
                    " connected")))
     ((= (length devices) 1) (plist-get (car devices) :serial))
     (t (let* ((choices (mapcar (lambda (device)
                                 (cons (android-adb-device-label device)
                                       (plist-get device :serial))) devices))
               (choice (completing-read (or prompt "Android device: ") choices nil t)))
          (cdr (assoc choice choices)))))))

(provide 'android-adb)
;;; android-adb.el ends here
