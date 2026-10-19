;;; adb.el --- Android device communication -*- lexical-binding: t; -*-

;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1"))
;; URL: https://github.com/cat-emacs/adb
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

(defgroup adb nil
  "Android device communication."
  :group 'tools)

(defcustom adb-program nil
  "Explicit adb executable, or nil for automatic discovery."
  :type '(choice (const nil) string)
  :group 'adb)

(defcustom adb-sdk-directory nil
  "Optional SDK directory used after the variable `exec-path' when locating adb."
  :type '(choice (const nil) directory)
  :group 'adb)

(defcustom adb-query-timeout 5
  "Maximum seconds to wait for a short adb query."
  :type 'number
  :group 'adb)

(defcustom adb-default-device-serial nil
  "Default device serial used by adb commands and the `adb' menu."
  :type '(choice (const nil) string)
  :group 'adb)

(defun adb-executable ()
  "Return an executable adb path, or signal a user error.
An explicit `adb-program' takes precedence.  Otherwise search
the variable `exec-path', then configured SDK and SDK environment locations."
  (or (if adb-program
          (if (file-name-absolute-p adb-program)
              (and (file-executable-p adb-program) adb-program)
            (executable-find adb-program))
        (or (executable-find "adb")
            (cl-loop for sdk in (list adb-sdk-directory
                                     (getenv "ANDROID_HOME")
                                     (getenv "ANDROID_SDK_ROOT"))
                     when (and sdk (not (string-empty-p sdk)))
                     thereis
                     (cl-loop for name in '("adb" "adb.exe")
                              for path = (expand-file-name
                                          (concat "platform-tools/" name) sdk)
                              when (file-executable-p path) return path))))
      (user-error "Cannot find adb; set adb-program or add adb to exec-path")))

(defun adb-command (serial &rest arguments)
  "Return an adb argument vector for SERIAL and ARGUMENTS.
Nil SERIAL leaves device selection to adb.  Arguments are never shell parsed."
  (append (list (adb-executable))
          (when serial (list "-s" serial)) arguments))

(cl-defun adb-start (serial arguments &key name buffer filter sentinel)
  "Start adb for SERIAL with ARGUMENTS and return its process.
NAME, BUFFER, FILTER, and SENTINEL are `make-process' options.  The caller owns
process output and cleanup.  This function never waits for adb."
  (make-process :name (or name "adb")
                :buffer buffer :command (apply #'adb-command serial arguments)
                :filter filter :sentinel sentinel
                :connection-type 'pipe :noquery t))

(defun adb-query (serial &rest arguments)
  "Return output from a short adb query for SERIAL and ARGUMENTS.
Signal on failure or after `adb-query-timeout' seconds.  Long-running
operations should use `adb-start' instead."
  (let ((buffer (generate-new-buffer " *adb-query*")) process)
    (unwind-protect
        (progn
          (setq process (adb-start serial arguments :buffer buffer
                                          :sentinel #'ignore))
          (let ((deadline (+ (float-time) adb-query-timeout)))
            (while (and (process-live-p process) (< (float-time) deadline))
              (accept-process-output process 0.05))
            (when (process-live-p process)
              (user-error "Adb query timed out after %s seconds"
                          adb-query-timeout)))
          ;; Emacs may deliver the final stdout chunk after the exit event.
          (accept-process-output process 0)
          (let ((output (with-current-buffer buffer (buffer-string))))
            (unless (and (eq (process-status process) 'exit)
                         (zerop (process-exit-status process)))
              (user-error "Adb failed: %s" (string-trim output)))
            output))
      (when (and process (process-live-p process)) (delete-process process))
      (kill-buffer buffer))))

(defun adb--start-operation (serial arguments name &optional callback)
  "Start adb ARGUMENTS for SERIAL under NAME and return its process.
CALLBACK receives the exit status and complete output when the process exits.
The output buffer is named from NAME and remains available to the caller."
  (let ((buffer (get-buffer-create (format "*adb-%s*" name))))
    (with-current-buffer buffer (let ((inhibit-read-only t)) (erase-buffer)))
    (adb-start
     serial arguments
     :name (format "adb-%s" name)
     :buffer buffer
     :sentinel
     (lambda (process _event)
       (when (memq (process-status process) '(exit signal))
         (when callback
           (funcall callback
                    (process-exit-status process)
                    (with-current-buffer (process-buffer process)
                      (buffer-string)))))))))

(defun adb-install-apk (serial apk &optional callback)
  "Install APK on SERIAL asynchronously and return its process.
Use `-r' to replace an existing installation.  CALLBACK receives the process
exit status and complete output after adb exits."
  (unless (file-readable-p apk)
    (user-error "Cannot read APK: %s" apk))
  (adb--start-operation
   serial (list "install" "-r" (expand-file-name apk))
   (format "install %s" (file-name-nondirectory apk)) callback))

(defun adb-launch-package (serial package &optional activity callback)
  "Launch PACKAGE on SERIAL asynchronously and return its process.
When ACTIVITY is non-nil, launch the explicit component PACKAGE/ACTIVITY;
otherwise use the Android launcher category.  CALLBACK receives status/output."
  (let ((arguments
         (if activity
             (list "shell" "am" "start" "-n"
                   (concat package "/" activity))
           (list "shell" "monkey" "-p" package
                 "-c" "android.intent.category.LAUNCHER" "1"))))
    (adb--start-operation serial arguments "launch" callback)))

(defun adb-force-stop (serial package &optional callback)
  "Force-stop PACKAGE on SERIAL asynchronously and return its process."
  (adb--start-operation
   serial (list "shell" "am" "force-stop" package) "force-stop" callback))

(defun adb-uninstall (serial package &optional callback)
  "Uninstall PACKAGE from SERIAL asynchronously and return its process."
  (adb--start-operation
   serial (list "uninstall" package) "uninstall" callback))

(defun adb-clear-package-data (serial package &optional callback)
  "Clear PACKAGE data on SERIAL asynchronously and return its process."
  (adb--start-operation
   serial (list "shell" "pm" "clear" package) "clear-package" callback))

(defun adb-push (serial local remote &optional callback)
  "Push LOCAL to REMOTE on SERIAL asynchronously and return its process."
  (unless (file-readable-p local)
    (user-error "Cannot read local file: %s" local))
  (adb--start-operation
   serial (list "push" (expand-file-name local) remote) "push" callback))

(defun adb-pull (serial remote local &optional callback)
  "Pull REMOTE to LOCAL on SERIAL asynchronously and return its process."
  (adb--start-operation
   serial (list "pull" remote (expand-file-name local)) "pull" callback))

(defun adb-forward (serial local remote)
  "Forward LOCAL to REMOTE on SERIAL and return adb output."
  (adb-query serial "forward" local remote))

(defun adb-reverse (serial remote local)
  "Reverse REMOTE to LOCAL on SERIAL and return adb output."
  (adb-query serial "reverse" remote local))

(defun adb-list-forward (&optional serial)
  "Return adb forward rules for SERIAL, or all devices when SERIAL is nil."
  (adb-query serial "forward" "--list"))

(defun adb-list-reverse (&optional serial)
  "Return adb reverse rules for SERIAL, or all devices when SERIAL is nil."
  (adb-query serial "reverse" "--list"))

(defun adb-remove-forward (serial local)
  "Remove LOCAL forward rule from SERIAL."
  (adb-query serial "forward" "--remove" local))

(defun adb-remove-reverse (serial remote)
  "Remove REMOTE reverse rule from SERIAL."
  (adb-query serial "reverse" "--remove" remote))

(defun adb-packages (serial)
  "Return installed application package names for SERIAL.
The result is sorted and excludes the `package:' prefix from `pm list packages'."
  (sort
   (delete-dups
    (delq nil
          (mapcar
           (lambda (line)
             (when (string-match "^package:\\(.+\\)$" line)
               (match-string 1 line)))
           (split-string
            (adb-query serial "shell" "pm" "list" "packages")
            "
" t))))
   #'string<))

(defun adb-getprop (serial property)
  "Return PROPERTY from SERIAL's `getprop' output."
  (string-trim (adb-query serial "shell" "getprop" property)))

(defun adb-device-info (serial)
  "Return common build properties for SERIAL as a plist."
  (list :serial serial
        :model (adb-getprop serial "ro.product.model")
        :manufacturer (adb-getprop serial "ro.product.manufacturer")
        :android-version (adb-getprop serial "ro.build.version.release")
        :sdk (adb-getprop serial "ro.build.version.sdk")
        :abi (adb-getprop serial "ro.product.cpu.abi")))

(defun adb-battery (serial)
  "Return battery information for SERIAL as a plist."
  (let ((output (adb-query serial "shell" "dumpsys" "battery"))
        result)
    (dolist (line (split-string output "\\n" t))
      (when (string-match "^[[:space:]]*\\([^:]+\\):[[:space:]]*\\(.+?\\)[[:space:]]*$" line)
        (setq result (plist-put result
                                (intern (concat ":" (string-trim (match-string 1 line))))
                                (string-trim (match-string 2 line))))))
    result))

(defun adb-display-size (serial)
  "Return the physical display size reported by SERIAL, or nil."
  (let ((output (adb-query serial "shell" "wm" "size")))
    (when (string-match "Physical size:[[:space:]]*\\([0-9]+x[0-9]+\\)" output)
      (match-string 1 output))))

(defun adb-connect (host)
  "Connect to HOST, returning adb output."
  (adb-query nil "connect" host))

(defun adb-disconnect (&optional host)
  "Disconnect HOST, or all TCP/IP devices when HOST is nil."
  (if host
      (adb-query nil "disconnect" host)
    (adb-query nil "disconnect")))

(defun adb-pair (host pairing-code)
  "Pair with HOST using PAIRING-CODE, returning adb output."
  (adb-query nil "pair" host pairing-code))

(defun adb-get-state (serial)
  "Return the state of SERIAL."
  (string-trim (adb-query serial "get-state")))

(defun adb-get-serialno (serial)
  "Return the serial number reported by SERIAL."
  (string-trim (adb-query serial "get-serialno")))

(defun adb-wait-for-device (serial &optional state callback)
  "Wait asynchronously for SERIAL to reach STATE.
STATE defaults to `device'.  CALLBACK receives status and output."
  (adb--start-operation
   serial (list (format "wait-for-%s" (or state "device"))) "wait-for-device" callback))

(defun adb-reboot (serial &optional mode callback)
  "Reboot SERIAL, optionally into MODE, asynchronously.
CALLBACK receives status and output."
  (adb--start-operation
   serial (if mode (list "reboot" mode) '("reboot")) "reboot" callback))

(defun adb-tcpip (serial port &optional callback)
  "Restart adbd on SERIAL in TCP mode at PORT.
CALLBACK receives status and output."
  (adb--start-operation
   serial (list "tcpip" port) "tcpip" callback))

(defun adb-usb (serial &optional callback)
  "Restart adbd on SERIAL in USB mode.
CALLBACK receives status and output."
  (adb--start-operation serial '("usb") "usb" callback))

(defun adb-install-multiple (serial apks &optional callback)
  "Install APKS atomically on SERIAL and return its process.
APKS is a non-empty list of readable APK paths.  CALLBACK receives status
and output."
  (unless (and apks (seq-every-p #'file-readable-p apks))
    (user-error "Select one or more readable APK files"))
  (adb--start-operation
   serial (append '("install-multiple" "-r") (mapcar #'expand-file-name apks))
   "install-multiple" callback))

(defun adb-bugreport (serial destination &optional callback)
  "Write a bug report for SERIAL to DESTINATION asynchronously.
CALLBACK receives status and output."
  (adb--start-operation
   serial (list "bugreport" (expand-file-name destination)) "bugreport" callback))

(defun adb-parse-devices (output)
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

(defun adb-devices (&optional available-only)
  "Return connected device plists.
With AVAILABLE-ONLY non-nil, include only devices in the `device' state."
  (let ((devices (adb-parse-devices
                  (adb-query nil "devices" "-l"))))
    (if available-only
        (seq-filter (lambda (device) (eq (plist-get device :state) 'device)) devices)
      devices)))

(defun adb-device-label (device)
  "Return an unambiguous completion label for DEVICE."
  (format "%s (%s)" (or (plist-get device :model) (plist-get device :serial))
          (plist-get device :serial)))

(defun adb-read-device (&optional prompt)
  "Return a usable device serial, prompting with PROMPT when necessary.
A configured `adb-default-device-serial' is used when it is online.
A sole usable device is selected automatically.  If none is usable, report
connected device states rather than treating unauthorized devices as absent."
  (let* ((all (adb-devices))
         (devices (seq-filter (lambda (device)
                                (eq (plist-get device :state) 'device)) all))
         (default (and adb-default-device-serial
                       (seq-find
                        (lambda (device)
                          (equal adb-default-device-serial
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
      (setq adb-default-device-serial
            (plist-get (car devices) :serial)))
     (t (let* ((choices (mapcar (lambda (device)
                                 (cons (adb-device-label device)
                                       (plist-get device :serial))) devices))
               (choice (completing-read (or prompt "Android device: ") choices nil t
                                        nil nil
                                        (and adb-default-device-serial
                                             (adb-device-label
                                              (list :serial adb-default-device-serial))))))
          (setq adb-default-device-serial (cdr (assoc choice choices))))))))

(provide 'adb)
;;; adb.el ends here
