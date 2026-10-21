;;; adb-transient.el --- Transient UI for adb -*- lexical-binding: t; -*-

;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1") (transient "0.3.0"))
;; URL: https://github.com/cat-emacs/adb
;; Keywords: tools processes android

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; Optional Transient commands for discovering and controlling Android devices.
;; The core adb library has no Transient dependency.

;;; Code:

(require 'adb)
(require 'transient)

(defun adb--buffer-output (name status output)
  "Display STATUS and OUTPUT in a special buffer named NAME."
  (with-current-buffer (get-buffer-create name)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert output)
      (unless (string-suffix-p "\n" output) (insert "\n"))
      (insert (format "\nExited with status %s\n" status)))
    (special-mode)
    (pop-to-buffer (current-buffer))))

(defun adb-list-devices ()
  "Display all devices reported by adb."
  (interactive)
  (let ((output (adb-query nil "devices" "-l")))
    (adb--buffer-output "*adb-devices*" 0 output)))

(defun adb-select-device (&optional serial)
  "Set the default device to SERIAL, or prompt for one."
  (interactive)
  (setq adb-default-device-serial
        (or serial (adb-read-device "Default Android device: ")))
  (message "adb: default device is %s" adb-default-device-serial))

(defun adb--server-command (command)
  "Run adb server COMMAND and display its output."
  (let ((output (adb-query nil command)))
    (adb--buffer-output "*adb-server*" 0 output)))

(defun adb-start-server ()
  "Start the adb server and display its output."
  (interactive)
  (adb--server-command "start-server"))

(defun adb-kill-server ()
  "Stop the adb server and display its output."
  (interactive)
  (adb--server-command "kill-server"))

(defun adb-reconnect ()
  "Reconnect the default device, or all devices when none is selected."
  (interactive)
  (let ((output (adb-query adb-default-device-serial "reconnect")))
    (adb--buffer-output "*adb-reconnect*" 0 output)))

(defun adb--read-package (&optional prompt initial)
  "Read an installed package, using PROMPT and INITIAL when supplied."
  (let* ((serial (adb-read-device))
         (packages (adb-packages serial)))
    (completing-read (or prompt "Package: ") packages nil nil initial)))

(defun adb--read-package-argument (prompt initial-input _history)
  "Read a package for a Transient option.
PROMPT and INITIAL-INPUT come from Transient.  A failed package query falls
back to free text."
  (condition-case err
      (adb--read-package prompt initial-input)
    (error
     (message "adb: %s" (error-message-string err))
     (read-string prompt initial-input))))

(defun adb--read-component-argument (prompt initial-input _history)
  "Read a package/activity component for a Transient option.
PROMPT and INITIAL-INPUT come from Transient.  Package names are offered as
the initial candidates."
  (condition-case err
      (adb--read-package (or prompt "Component (package/activity): ")
                         initial-input)
    (error
     (message "adb: %s" (error-message-string err))
     (read-string prompt initial-input))))

(defun adb--read-user-argument (prompt initial-input _history)
  "Read an Android user id, using PROMPT and INITIAL-INPUT.
`current', `all', and `0' are offered, and another id can be typed."
  (completing-read prompt '("current" "all" "0") nil nil initial-input))

(defun adb--permission-names (output)
  "Return permission names parsed from `pm list permissions' OUTPUT."
  (sort
   (delete-dups
    (delq nil
          (mapcar
           (lambda (line)
             (when (string-match "^[[:space:]]*permission:\\(.+\\)$" line)
               (match-string 1 line)))
           (split-string (or output "") "\n" t))))
   #'string<))

(defun adb--read-permission-argument (prompt initial-input _history)
  "Read a runtime permission, using PROMPT and INITIAL-INPUT.
Candidates are the device's dangerous permissions.  A failed query falls back
to free text."
  (let ((permissions
         (condition-case err
             (adb--permission-names
              (adb-query (adb-read-device)
                         "shell" "pm" "list" "permissions" "-d" "-g"))
           (error
            (message "adb: %s" (error-message-string err))
            nil))))
    (completing-read prompt permissions nil nil initial-input)))

(defun adb--read-remote-path ()
  "Read an Android device path."
  (read-string "Remote path: "))

(defun adb--report-operation (label status output)
  "Report LABEL operation result from STATUS and OUTPUT."
  (if (zerop status)
      (message "adb: %s completed" label)
    (adb--buffer-output (format "*adb-%s*" label)
                                status output)
    (message "adb: %s failed with status %s" label status)))

(defun adb-install-apk-file (apk)
  "Install APK selected by the user on the default Android device."
  (interactive (list (read-file-name "APK: " nil nil t nil
                                      (lambda (file)
                                        (or (file-directory-p file)
                                            (string-match-p "\\.apk\\'" file))))))
  (let ((serial (adb-read-device)))
    (adb-install-apk
     serial apk
     (lambda (status output)
       (if (and (zerop status) (string-match-p "Success" output))
           (message "adb: installed %s on %s"
                    (file-name-nondirectory apk) serial)
         (adb--report-operation
          (format "install-%s" (file-name-nondirectory apk)) status output))))))

(defun adb-launch-package-command (package &optional activity)
  "Launch PACKAGE, optionally using ACTIVITY, on the default device."
  (interactive (list (adb--read-package)
                     (read-string "Activity (empty for launcher): ")))
  (let ((serial (adb-read-device)))
    (adb-launch-package
     serial package (unless (string-empty-p activity) activity)
     (lambda (status output)
       (adb--report-operation "launch" status output)))))

(defun adb-force-stop-command (package)
  "Force-stop PACKAGE on the default device."
  (interactive (list (adb--read-package)))
  (adb-force-stop
   (adb-read-device) package
   (lambda (status output) (adb--report-operation "force-stop" status output))))

(defun adb-uninstall-package (package)
  "Uninstall PACKAGE from the default device."
  (interactive (list (adb--read-package)))
  (adb-uninstall
   (adb-read-device) package
   (lambda (status output) (adb--report-operation "uninstall" status output))))

(defun adb-clear-package (package)
  "Clear data for PACKAGE on the default device."
  (interactive (list (adb--read-package)))
  (adb-clear-package-data
   (adb-read-device) package
   (lambda (status output) (adb--report-operation "clear-package" status output))))

(defun adb-push-file (local remote)
  "Push LOCAL to REMOTE on the default device."
  (interactive (list (read-file-name "Local file: ")
                     (adb--read-remote-path)))
  (adb-push
   (adb-read-device) local remote
   (lambda (status output) (adb--report-operation "push" status output))))

(defun adb-pull-file (remote local)
  "Pull REMOTE to LOCAL."
  (interactive (list (adb--read-remote-path)
                     (read-file-name "Local destination: ")))
  (adb-pull
   (adb-read-device) remote local
   (lambda (status output) (adb--report-operation "pull" status output))))

(defun adb-forward-port (local remote)
  "Forward LOCAL to REMOTE on the default device."
  (interactive "sLocal address (e.g. tcp:8080): \nsRemote address (e.g. tcp:8080): ")
  (message "adb: %s" (adb-forward (adb-read-device) local remote)))

(defun adb-reverse-port (remote local)
  "Reverse REMOTE to LOCAL on the default device."
  (interactive "sRemote address (e.g. tcp:8080): \nsLocal address (e.g. tcp:8080): ")
  (message "adb: %s" (adb-reverse (adb-read-device) remote local)))

(defun adb-show-device-info ()
  "Display common properties for the default device."
  (interactive)
  (let* ((serial (adb-read-device))
         (info (adb-device-info serial)))
    (adb--buffer-output "*adb-device-info*" 0
                                (format "%S" info))))

(defun adb-show-battery ()
  "Display battery information for the default device."
  (interactive)
  (let ((serial (adb-read-device)))
    (adb--buffer-output "*adb-battery*" 0
                                (format "%S" (adb-battery serial)))))

(defun adb--read-host ()
  "Read a host and optional port."
  (read-string "Host[:port]: "))

(defun adb-connect-host (host)
  "Connect to HOST."
  (interactive (list (adb--read-host)))
  (message "adb: %s" (adb-connect host)))

(defun adb--read-disconnect-host ()
  "Read a connected TCP/IP host, or empty to disconnect all.
Candidates come from the current adb device list."
  (let* ((serials
          (delete-dups
           (delq nil
                 (mapcar
                  (lambda (device)
                    (let ((serial (plist-get device :serial)))
                      (and (string-match-p ":[0-9]+\\'" serial) serial)))
                  (adb-devices)))))
         (default (and (member adb-default-device-serial serials)
                       adb-default-device-serial)))
    (completing-read "Disconnect host (empty for all): " serials nil nil
                     default)))

(defun adb-disconnect-host (host)
  "Disconnect HOST, or all hosts when empty."
  (interactive (list (adb--read-disconnect-host)))
  (message "adb: %s"
           (adb-disconnect
            (unless (string-empty-p host) host))))

(defun adb-pair-host (host code)
  "Pair with HOST using CODE."
  (interactive (list (adb--read-host) (read-string "Pairing code: ")))
  (message "adb: %s" (adb-pair host code)))

(defun adb-show-state ()
  "Display the state of the default device."
  (interactive)
  (let ((serial (adb-read-device)))
    (message "adb: %s" (adb-get-state serial))))

(defun adb-wait-device ()
  "Wait for the default device to become ready."
  (interactive)
  (let ((serial adb-default-device-serial))
    (adb-wait-for-device
     serial nil
     (lambda (status output)
       (adb--report-operation "wait-for-device" status output)))))

(defun adb-reboot-device (mode)
  "Reboot the default device into MODE."
  (interactive (list (let ((value (completing-read "Reboot mode: "
                                                    '("system" "bootloader" "recovery" "sideload" "sideload-auto")
                                                    nil t nil nil "system")))
                       (unless (string= value "system") value))))
  (adb-reboot
   (adb-read-device) mode
   (lambda (status output) (adb--report-operation "reboot" status output))))

(defun adb-switch-tcpip (port)
  "Switch the default device to TCP/IP PORT."
  (interactive "sTCP/IP port: ")
  (adb-tcpip
   (adb-read-device) port
   (lambda (status output) (adb--report-operation "tcpip" status output))))

(defun adb-switch-usb ()
  "Switch the default device back to USB."
  (interactive)
  (adb-usb
   (adb-read-device)
   (lambda (status output) (adb--report-operation "usb" status output))))

(defun adb-install-multiple-files (apks)
  "Install selected APKS on the default device."
  (interactive (list (let ((file (read-file-name "APK: " nil nil t)))
                       (let ((files (list file)))
                         (while (y-or-n-p "Add another APK? ")
                           (push (read-file-name "APK: " nil nil t) files))
                         (nreverse files)))))
  (adb-install-multiple
   (adb-read-device) apks
   (lambda (status output) (adb--report-operation "install-multiple" status output))))

(defun adb-create-bugreport (destination)
  "Write a bug report to DESTINATION."
  (interactive (list (read-file-name "Bug report destination: ")))
  (adb-bugreport
   (adb-read-device) destination
   (lambda (status output) (adb--report-operation "bugreport" status output))))

(defun adb-shell (command)
  "Run COMMAND through adb shell on the default device.
COMMAND is split into arguments using `split-string-and-unquote', not passed
through a host shell."
  (interactive "sAdb shell command: ")
  (let* ((serial (adb-read-device))
         (arguments (append '("shell") (split-string-and-unquote command)))
         (buffer (get-buffer-create "*adb-shell*"))
         (process (adb-start
                   serial arguments
                   :name "adb-shell"
                   :buffer buffer
                   :sentinel
                   (lambda (process _event)
                     (when (memq (process-status process) '(exit signal))
                       (message "adb: shell exited with status %s"
                                (process-exit-status process)))))))
    (display-buffer buffer)
    process))

(defun adb--run-shell (label arguments &optional always-show)
  "Run adb shell ARGUMENTS on the selected device.
LABEL names the output buffer.  Show it when ALWAYS-SHOW is non-nil, the
command fails, or it writes output.  A silent success only prints a message."
  (let* ((serial (adb-read-device))
         (buffer (get-buffer-create (format "*adb-%s*" label))))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (fundamental-mode)))
    (adb-start
     serial (append '("shell") arguments)
     :name (format "adb-%s" label)
     :buffer buffer
     :sentinel
     (lambda (process _event)
       (when (memq (process-status process) '(exit signal))
         (let* ((status (process-exit-status process))
                (output (with-current-buffer (process-buffer process)
                          (buffer-string))))
           (if (or always-show (not (zerop status))
                   (not (string-empty-p (string-trim output))))
               (progn
                 (with-current-buffer (process-buffer process)
                   (let ((inhibit-read-only t))
                     (goto-char (point-max))
                     (unless (string-suffix-p "\n" output) (insert "\n"))
                     (insert (format "\nExited with status %s\n" status))
                     (special-mode)))
                 (pop-to-buffer (process-buffer process)))
             (message "adb: %s completed" label))))))
    buffer))

(defun adb--option-value (prefix arguments)
  "Return the value of PREFIX in ARGUMENTS, or nil.
PREFIX includes its trailing \"=\"."
  (let ((match (seq-find (lambda (argument)
                           (and (stringp argument)
                                (string-prefix-p prefix argument)))
                         arguments)))
    (and match (substring match (length prefix)))))

(defun adb--user-arguments (arguments)
  "Return a --user argument list from transient ARGUMENTS."
  (when-let* ((user (adb--option-value "--user=" arguments)))
    (unless (string-empty-p user)
      (list "--user" user))))

(defun adb--extra-pair (value label)
  "Split VALUE at the first equals sign.
LABEL names the option in the error when VALUE is not key=value."
  (unless (and (stringp value)
               (string-match "\\`\\([^=]+\\)=\\(.*\\)\\'" value)
               (not (string-empty-p (match-string 1 value))))
    (user-error "%s must be key=value" label))
  (list (match-string 1 value) (match-string 2 value)))

(defun adb--boolean-extra (value)
  "Return a key and true/false pair parsed from boolean extra VALUE."
  (let ((pair (adb--extra-pair value "Boolean extra")))
    (unless (member (cadr pair) '("true" "false"))
      (user-error "Boolean extra must be key=true or key=false"))
    pair))

(defconst adb--intent-flags
  '("--activity-clear-task"
    "--activity-clear-top"
    "--activity-single-top"
    "--activity-exclude-from-recents"
    "--grant-read-uri-permission"
    "--grant-write-uri-permission")
  "Intent flags accepted by the am menu.")

(defun adb--intent-target-p (arguments)
  "Return non-nil when ARGUMENTS identify an am intent target."
  (or (adb--option-value "--component=" arguments)
      (adb--option-value "--package=" arguments)
      (adb--option-value "--action=" arguments)
      (adb--option-value "--data=" arguments)))

(defun adb--am-intent-arguments (arguments &optional launch-package)
  "Return am intent arguments from transient ARGUMENTS.
With LAUNCH-PACKAGE, a package and no other intent target starts its launcher
activity."
  (let ((component (adb--option-value "--component=" arguments))
        (package (adb--option-value "--package=" arguments))
        (action (adb--option-value "--action=" arguments))
        (data (adb--option-value "--data=" arguments))
        (mime (adb--option-value "--mime=" arguments))
        (category (adb--option-value "--category=" arguments))
        (extra (adb--option-value "--es=" arguments))
        (bool (adb--option-value "--ez=" arguments))
        result)
    (when (and launch-package package (not component) (not action)
               (not data) (not category))
      (setq action "android.intent.action.MAIN"
            category "android.intent.category.LAUNCHER"))
    (when action (setq result (append result (list "-a" action))))
    (when data (setq result (append result (list "-d" data))))
    (when mime (setq result (append result (list "-t" mime))))
    (when category (setq result (append result (list "-c" category))))
    (when component
      (unless (string-match-p "/" component)
        (user-error "Component must be package/activity"))
      (setq result (append result (list "-n" component))))
    (when package (setq result (append result (list "-p" package))))
    (when extra
      (let ((pair (adb--extra-pair extra "String extra")))
        (setq result (append result (list "--es" (car pair) (cadr pair))))))
    (when bool
      (let ((pair (adb--boolean-extra bool)))
        (setq result (append result (list "--ez" (car pair) (cadr pair))))))
    (dolist (flag adb--intent-flags)
      (when (member flag arguments)
        (setq result (append result (list flag)))))
    result))

(defun adb--am-start-arguments (arguments)
  "Return shell arguments for am start from transient ARGUMENTS."
  (unless (adb--intent-target-p arguments)
    (user-error "Set a component, package, action, or data URI"))
  (append '("am" "start")
          (and (member "--debug" arguments) '("-D"))
          (and (member "--wait-for-launch" arguments) '("-W"))
          (and (member "--stop-first" arguments) '("-S"))
          (adb--user-arguments arguments)
          (adb--am-intent-arguments arguments t)))

(defun adb--am-service-arguments (command arguments)
  "Return shell arguments for am COMMAND from transient ARGUMENTS."
  (unless (adb--intent-target-p arguments)
    (user-error "Set a component, package, action, or data URI"))
  (append (list "am" command)
          (adb--user-arguments arguments)
          (adb--am-intent-arguments arguments)))

(defun adb--am-package-arguments (command arguments)
  "Return shell arguments for am COMMAND on the package in ARGUMENTS."
  (let ((package (adb--option-value "--package=" arguments)))
    (unless (and package (not (string-empty-p package)))
      (user-error "Set a package"))
    (append (list "am" command)
            (adb--user-arguments arguments)
            (list package))))

(defun adb--ensure-package (arguments)
  "Return ARGUMENTS, prompting for a package when none is set."
  (if (adb--option-value "--package=" arguments)
      arguments
    (cons (concat "--package=" (adb--read-package)) arguments)))

(defun adb--ensure-component (arguments)
  "Return ARGUMENTS, prompting for a component when none is set."
  (if (adb--option-value "--component=" arguments)
      arguments
    (cons (concat "--component="
                  (adb--read-component-argument
                   "Component (package/activity): " nil nil))
          arguments)))

(defun adb--ensure-permission (arguments)
  "Return ARGUMENTS, prompting for a permission when none is set.
`--all-permissions' satisfies the requirement without a prompt."
  (if (or (member "--all-permissions" arguments)
          (let ((permission (adb--option-value "--permission=" arguments)))
            (and permission (not (string-empty-p permission)))))
      arguments
    (cons (concat "--permission="
                  (adb--read-permission-argument "Permission: " nil nil))
          arguments)))

(defun adb--am-instrument-arguments (arguments)
  "Return shell arguments for am instrument from transient ARGUMENTS."
  (let ((component (adb--option-value "--component=" arguments))
        (arg (adb--option-value "--instrument-arg=" arguments)))
    (unless (and component (string-match-p "/" component))
      (user-error "Set an instrumentation component as package/runner"))
    (append '("am" "instrument")
            (and (member "--instrument-wait" arguments) '("-w"))
            (and (member "--instrument-raw" arguments) '("-r"))
            (adb--user-arguments arguments)
            (when arg
              (let ((pair (adb--extra-pair arg "Instrumentation argument")))
                (list "-e" (car pair) (cadr pair))))
            (list component))))

(defun adb--am-debug-app-arguments (arguments)
  "Return shell arguments for am set-debug-app from transient ARGUMENTS."
  (let ((package (adb--option-value "--package=" arguments)))
    (unless (and package (not (string-empty-p package)))
      (user-error "Set a package"))
    (append '("am" "set-debug-app")
            (and (member "--wait-debugger" arguments) '("-w"))
            (and (member "--persistent" arguments) '("--persistent"))
            (list package))))

(defun adb-am-start ()
  "Start an activity with the current am options."
  (interactive)
  (adb--run-shell "am-start"
                  (adb--am-start-arguments (transient-args 'adb-am)) t))

(defun adb-am-start-service ()
  "Start a service with the current am options."
  (interactive)
  (adb--run-shell "am-start-service"
                  (adb--am-service-arguments
                   "start-service" (transient-args 'adb-am))
                  t))

(defun adb-am-start-foreground-service ()
  "Start a foreground service with the current am options."
  (interactive)
  (adb--run-shell "am-start-foreground-service"
                  (adb--am-service-arguments
                   "start-foreground-service" (transient-args 'adb-am))
                  t))

(defun adb-am-stop-service ()
  "Stop a service with the current am options."
  (interactive)
  (adb--run-shell "am-stop-service"
                  (adb--am-service-arguments
                   "stop-service" (transient-args 'adb-am))
                  t))

(defun adb-am-broadcast ()
  "Send a broadcast with the current am options."
  (interactive)
  (adb--run-shell "am-broadcast"
                  (adb--am-service-arguments
                   "broadcast" (transient-args 'adb-am))
                  t))

(defun adb-am-force-stop ()
  "Force-stop the selected package."
  (interactive)
  (adb--run-shell "am-force-stop"
                  (adb--am-package-arguments
                   "force-stop" (adb--ensure-package (transient-args 'adb-am)))))

(defun adb-am-kill ()
  "Kill background processes for the selected package."
  (interactive)
  (adb--run-shell "am-kill"
                  (adb--am-package-arguments
                   "kill" (adb--ensure-package (transient-args 'adb-am)))))

(defun adb-am-crash ()
  "Crash the selected package."
  (interactive)
  (adb--run-shell "am-crash"
                  (adb--am-package-arguments
                   "crash" (adb--ensure-package (transient-args 'adb-am)))
                  t))

(defun adb-am-instrument ()
  "Run instrumentation with the current am options."
  (interactive)
  (adb--run-shell "am-instrument"
                  (adb--am-instrument-arguments
                   (adb--ensure-component (transient-args 'adb-am)))
                  t))

(defun adb-am-set-debug-app ()
  "Mark the selected package as the debug application."
  (interactive)
  (adb--run-shell "am-set-debug-app"
                  (adb--am-debug-app-arguments
                   (adb--ensure-package (transient-args 'adb-am)))))

(defun adb-am-clear-debug-app ()
  "Clear the previously set debug application."
  (interactive)
  (adb--run-shell "am-clear-debug-app" '("am" "clear-debug-app")))

(defun adb-am-stack-list ()
  "List activity stacks on the selected device."
  (interactive)
  (adb--run-shell "am-stack-list" '("am" "stack" "list") t))

(defun adb--pm-list-packages-arguments (arguments)
  "Return shell arguments for pm list packages from transient ARGUMENTS."
  (let ((filter (adb--option-value "--filter=" arguments)))
    (append '("pm" "list" "packages")
            (and (member "--third-party" arguments) '("-3"))
            (and (member "--system" arguments) '("-s"))
            (and (member "--disabled" arguments) '("-d"))
            (and (member "--enabled" arguments) '("-e"))
            (and (member "--show-apk" arguments) '("-f"))
            (and (member "--show-installer" arguments) '("-i"))
            (and (member "--show-uid" arguments) '("-U"))
            (and (member "--include-uninstalled" arguments) '("-u"))
            (and (member "--show-versioncode" arguments)
                 '("--show-versioncode"))
            (adb--user-arguments arguments)
            (and (not (string-empty-p (or filter ""))) (list filter)))))

(defun adb--pm-list-permissions-arguments (arguments)
  "Return shell arguments for pm list permissions from transient ARGUMENTS."
  (append '("pm" "list" "permissions")
          (and (member "--group-permissions" arguments) '("-g"))
          (and (member "--dangerous" arguments) '("-d"))))

(defun adb--pm-list-instrumentation-arguments (arguments)
  "Return shell arguments for pm list instrumentation from ARGUMENTS."
  (let ((package (adb--option-value "--package=" arguments)))
    (append '("pm" "list" "instrumentation")
            (and (member "--show-apk" arguments) '("-f"))
            (and package (list package)))))

(defun adb--pm-package-arguments (command arguments &rest extras)
  "Return shell arguments for pm COMMAND from transient ARGUMENTS.
EXTRAS are flags inserted before the package."
  (let ((package (adb--option-value "--package=" arguments)))
    (unless (and package (not (string-empty-p package)))
      (user-error "Set a package"))
    (append (list "pm" command)
            (delq nil extras)
            (adb--user-arguments arguments)
            (list package))))

(defun adb--pm-permission-arguments (command arguments)
  "Return shell arguments for pm COMMAND grant or revoke from ARGUMENTS."
  (let ((package (adb--option-value "--package=" arguments))
        (permission (adb--option-value "--permission=" arguments))
        (all (member "--all-permissions" arguments)))
    (unless (or all permission)
      (user-error "Set a permission or all runtime permissions"))
    (unless (or package all)
      (user-error "Set a package"))
    (append (list "pm" command)
            (and all '("--all-permissions"))
            (adb--user-arguments arguments)
            (and package (list package))
            (and (not all) (list permission)))))

(defun adb-pm-list-packages ()
  "List packages using the current pm filters."
  (interactive)
  (adb--run-shell "pm-list-packages"
                  (adb--pm-list-packages-arguments (transient-args 'adb-pm))
                  t))

(defun adb-pm-path ()
  "Show the APK path of the selected package."
  (interactive)
  (adb--run-shell "pm-path"
                  (adb--pm-package-arguments
                   "path" (adb--ensure-package (transient-args 'adb-pm)))
                  t))

(defun adb-pm-dump ()
  "Dump package manager state for the selected package."
  (interactive)
  (adb--run-shell "pm-dump"
                  (let ((arguments (adb--ensure-package (transient-args 'adb-pm))))
                    (list "pm" "dump" (adb--option-value "--package=" arguments)))
                  t))

(defun adb-pm-clear ()
  "Clear data for the selected package."
  (interactive)
  (let ((arguments (adb--ensure-package (transient-args 'adb-pm))))
    (adb--run-shell "pm-clear"
                    (adb--pm-package-arguments
                     "clear" arguments
                     (and (member "--cache-only" arguments) "--cache-only")))))

(defun adb-pm-uninstall ()
  "Uninstall the selected package with pm."
  (interactive)
  (let ((arguments (adb--ensure-package (transient-args 'adb-pm))))
    (adb--run-shell "pm-uninstall"
                    (adb--pm-package-arguments
                     "uninstall" arguments
                     (and (member "--keep-data" arguments) "-k")))))

(defun adb-pm-enable ()
  "Enable the selected package or component."
  (interactive)
  (adb--run-shell "pm-enable"
                  (adb--pm-package-arguments
                   "enable" (adb--ensure-package (transient-args 'adb-pm)))))

(defun adb-pm-disable ()
  "Disable the selected package or component."
  (interactive)
  (adb--run-shell "pm-disable"
                  (adb--pm-package-arguments
                   "disable" (adb--ensure-package (transient-args 'adb-pm)))))

(defun adb-pm-disable-user ()
  "Disable the selected package or component for one user."
  (interactive)
  (adb--run-shell "pm-disable-user"
                  (adb--pm-package-arguments
                   "disable-user"
                   (adb--ensure-package (transient-args 'adb-pm)))))

(defun adb--pm-change-permission (label command)
  "Run pm COMMAND and report it as LABEL."
  (let ((arguments (adb--ensure-permission (transient-args 'adb-pm))))
    (unless (member "--all-permissions" arguments)
      (setq arguments (adb--ensure-package arguments)))
    (adb--run-shell label (adb--pm-permission-arguments command arguments))))

(defun adb-pm-grant ()
  "Grant a runtime permission to the selected package."
  (interactive)
  (adb--pm-change-permission "pm-grant" "grant"))

(defun adb-pm-revoke ()
  "Revoke a runtime permission from the selected package."
  (interactive)
  (adb--pm-change-permission "pm-revoke" "revoke"))

(defun adb-pm-list-permissions ()
  "List permissions using the current pm options."
  (interactive)
  (adb--run-shell "pm-list-permissions"
                  (adb--pm-list-permissions-arguments (transient-args 'adb-pm))
                  t))

(defun adb-pm-list-users ()
  "List users on the selected device."
  (interactive)
  (adb--run-shell "pm-list-users" '("pm" "list" "users") t))

(defun adb-pm-list-features ()
  "List system features on the selected device."
  (interactive)
  (adb--run-shell "pm-list-features" '("pm" "list" "features") t))

(defun adb-pm-list-instrumentation ()
  "List instrumentation packages on the selected device."
  (interactive)
  (adb--run-shell "pm-list-instrumentation"
                  (adb--pm-list-instrumentation-arguments
                   (transient-args 'adb-pm))
                  t))

;;;###autoload (autoload 'adb-am "adb-transient" nil t)
(transient-define-prefix adb-am ()
  "Run activity manager commands on the selected device."
  [["Target"
    ("-n" "Component" "--component="
     :reader adb--read-component-argument)
    ("-p" "Package" "--package="
     :reader adb--read-package-argument)
    ("-u" "User" "--user="
     :reader adb--read-user-argument)]
   ["Intent"
    ("-a" "Action" "--action=")
    ("-d" "Data URI" "--data=")
    ("-t" "MIME type" "--mime=")
    ("-c" "Category" "--category=")
    ("-e" "String extra" "--es=")
    ("-z" "Boolean extra" "--ez=")]
   ["Flags"
    ("-C" "Clear task" "--activity-clear-task")
    ("-T" "Clear top" "--activity-clear-top")
    ("-O" "Single top" "--activity-single-top")
    ("-H" "Hide from recents" "--activity-exclude-from-recents")
    ("-R" "Grant read URI" "--grant-read-uri-permission")
    ("-G" "Grant write URI" "--grant-write-uri-permission")]]
  [["Start"
    ("-D" "Debug" "--debug")
    ("-W" "Wait for launch" "--wait-for-launch")
    ("-S" "Force-stop first" "--stop-first")]
   ["Test"
    ("-w" "Wait for instrumentation" "--instrument-wait")
    ("-r" "Raw instrumentation" "--instrument-raw")
    ("-E" "Instrumentation argument" "--instrument-arg=")
    ("-y" "Wait for debugger" "--wait-debugger")
    ("-Y" "Persistent debug app" "--persistent")]
   ["Actions"
    ("s" "Start activity" adb-am-start)
    ("v" "Start service" adb-am-start-service)
    ("F" "Start foreground service" adb-am-start-foreground-service)
    ("q" "Stop service" adb-am-stop-service)
    ("b" "Broadcast" adb-am-broadcast)
    ("k" "Force-stop" adb-am-force-stop)
    ("K" "Kill background" adb-am-kill)
    ("c" "Crash" adb-am-crash)
    ("i" "Instrument" adb-am-instrument)
    ("d" "Set debug app" adb-am-set-debug-app)
    ("x" "Clear debug app" adb-am-clear-debug-app)
    ("l" "Activity stacks" adb-am-stack-list)]])

;;;###autoload (autoload 'adb-pm "adb-transient" nil t)
(transient-define-prefix adb-pm ()
  "Run package manager commands on the selected device."
  [["Target"
    ("-p" "Package" "--package="
     :reader adb--read-package-argument)
    ("-u" "User" "--user="
     :reader adb--read-user-argument)
    ("-P" "Permission" "--permission="
     :reader adb--read-permission-argument)
    ("-F" "Name filter" "--filter=")]
   ["List packages"
    ("-3" "Third-party" "--third-party")
    ("-s" "System" "--system")
    ("-d" "Disabled" "--disabled")
    ("-e" "Enabled" "--enabled")
    ("-f" "Show APK path" "--show-apk")
    ("-i" "Show installer" "--show-installer")
    ("-U" "Show UID" "--show-uid")
    ("-x" "Include uninstalled" "--include-uninstalled")
    ("-v" "Show version code" "--show-versioncode")]
   ["Changes"
    ("-k" "Keep data on uninstall" "--keep-data")
    ("-C" "Clear cache only" "--cache-only")
    ("-A" "All runtime permissions" "--all-permissions")
    ("-g" "Group permissions" "--group-permissions")
    ("-D" "Dangerous permissions" "--dangerous")]]
  [["Packages"
    ("l" "List packages" adb-pm-list-packages)
    ("a" "APK path" adb-pm-path)
    ("d" "Dump package" adb-pm-dump)
    ("c" "Clear data" adb-pm-clear)
    ("n" "Uninstall" adb-pm-uninstall)
    ("e" "Enable" adb-pm-enable)
    ("b" "Disable" adb-pm-disable)
    ("B" "Disable for user" adb-pm-disable-user)]
   ["Permissions"
    ("g" "Grant" adb-pm-grant)
    ("r" "Revoke" adb-pm-revoke)
    ("P" "List permissions" adb-pm-list-permissions)]
   ["Info"
    ("u" "List users" adb-pm-list-users)
    ("f" "List features" adb-pm-list-features)
    ("t" "List instrumentation" adb-pm-list-instrumentation)]])

;;;###autoload (autoload 'adb "adb-transient" nil t)
(transient-define-prefix adb ()
  "Discover and control Android devices through adb."
  [["Device"
    ("s" "Select device" adb-select-device)
    ("l" "List devices" adb-list-devices)
    ("w" "Wait for device" adb-wait-device)
    ("r" "Reconnect" adb-reconnect)
    ("S" "Start server" adb-start-server)
    ("K" "Kill server" adb-kill-server)]
   ["Network"
    ("c" "Connect" adb-connect-host)
    ("d" "Disconnect" adb-disconnect-host)
    ("y" "Pair" adb-pair-host)
    ("t" "TCP/IP" adb-switch-tcpip)
    ("U" "USB" adb-switch-usb)
    ("F" "Forward port" adb-forward-port)
    ("V" "Reverse port" adb-reverse-port)]
   ["App"
    ("a" "Activity manager" adb-am)
    ("p" "Package manager" adb-pm)
    ("i" "Install APK" adb-install-apk-file)
    ("m" "Install multiple APKs" adb-install-multiple-files)
    ("u" "Uninstall APK" adb-uninstall-package)]
   ["Files"
    ("P" "Push file" adb-push-file)
    ("G" "Pull file" adb-pull-file)]
   ["System"
    ("b" "Reboot" adb-reboot-device)
    ("B" "Bugreport" adb-create-bugreport)
    ("I" "Device info" adb-show-device-info)
    ("E" "Battery" adb-show-battery)
    ("x" "Shell" adb-shell)]])

(provide 'adb-transient)
;;; adb-transient.el ends here
