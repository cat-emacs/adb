;;; android-adb-transient.el --- Transient UI for adb -*- lexical-binding: t; -*-

;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1") (transient "0.3.0"))
;; URL: https://github.com/cat-emacs/android-adb
;; Keywords: tools processes android

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; Optional Transient commands for discovering and controlling Android devices.
;; The core android-adb library has no Transient dependency.

;;; Code:

(require 'android-adb)
(require 'transient)

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

(defun android-adb--read-package ()
  "Read an Android application package name."
  (read-string "Package: "))

(defun android-adb--read-remote-path ()
  "Read an Android device path."
  (read-string "Remote path: "))

(defun android-adb--report-operation (label status output)
  "Report LABEL operation result from STATUS and OUTPUT."
  (if (zerop status)
      (message "android-adb: %s completed" label)
    (android-adb--buffer-output (format "*android-adb-%s*" label)
                                status output)
    (message "android-adb: %s failed with status %s" label status)))

(defun android-adb-install-apk-file (apk)
  "Install APK selected by the user on the default Android device."
  (interactive (list (read-file-name "APK: " nil nil t nil
                                      (lambda (file)
                                        (or (file-directory-p file)
                                            (string-match-p "\\.apk\\'" file))))))
  (let ((serial (android-adb-read-device)))
    (android-adb-install-apk
     serial apk
     (lambda (status output)
       (if (and (zerop status) (string-match-p "Success" output))
           (message "android-adb: installed %s on %s"
                    (file-name-nondirectory apk) serial)
         (android-adb--report-operation
          (format "install-%s" (file-name-nondirectory apk)) status output))))))

(defun android-adb-launch-package-command (package &optional activity)
  "Launch PACKAGE, optionally using ACTIVITY, on the default device."
  (interactive (list (android-adb--read-package)
                     (read-string "Activity (empty for launcher): ")))
  (let ((serial (android-adb-read-device)))
    (android-adb-launch-package
     serial package (unless (string-empty-p activity) activity)
     (lambda (status output)
       (android-adb--report-operation "launch" status output)))))

(defun android-adb-force-stop-command (package)
  "Force-stop PACKAGE on the default device."
  (interactive (list (android-adb--read-package)))
  (android-adb-force-stop
   (android-adb-read-device) package
   (lambda (status output) (android-adb--report-operation "force-stop" status output))))

(defun android-adb-uninstall-package (package)
  "Uninstall PACKAGE from the default device."
  (interactive (list (android-adb--read-package)))
  (android-adb-uninstall
   (android-adb-read-device) package
   (lambda (status output) (android-adb--report-operation "uninstall" status output))))

(defun android-adb-clear-package (package)
  "Clear data for PACKAGE on the default device."
  (interactive (list (android-adb--read-package)))
  (android-adb-clear-package-data
   (android-adb-read-device) package
   (lambda (status output) (android-adb--report-operation "clear-package" status output))))

(defun android-adb-push-file (local remote)
  "Push LOCAL to REMOTE on the default device."
  (interactive (list (read-file-name "Local file: ")
                     (android-adb--read-remote-path)))
  (android-adb-push
   (android-adb-read-device) local remote
   (lambda (status output) (android-adb--report-operation "push" status output))))

(defun android-adb-pull-file (remote local)
  "Pull REMOTE to LOCAL."
  (interactive (list (android-adb--read-remote-path)
                     (read-file-name "Local destination: ")))
  (android-adb-pull
   (android-adb-read-device) remote local
   (lambda (status output) (android-adb--report-operation "pull" status output))))

(defun android-adb-forward-port (local remote)
  "Forward LOCAL to REMOTE on the default device."
  (interactive "sLocal address (e.g. tcp:8080): \nsRemote address (e.g. tcp:8080): ")
  (message "android-adb: %s" (android-adb-forward (android-adb-read-device) local remote)))

(defun android-adb-reverse-port (remote local)
  "Reverse REMOTE to LOCAL on the default device."
  (interactive "sRemote address (e.g. tcp:8080): \nsLocal address (e.g. tcp:8080): ")
  (message "android-adb: %s" (android-adb-reverse (android-adb-read-device) remote local)))

(defun android-adb-show-device-info ()
  "Display common properties for the default device."
  (interactive)
  (let* ((serial (android-adb-read-device))
         (info (android-adb-device-info serial)))
    (android-adb--buffer-output "*android-adb-device-info*" 0
                                (format "%S" info))))

(defun android-adb-show-battery ()
  "Display battery information for the default device."
  (interactive)
  (let ((serial (android-adb-read-device)))
    (android-adb--buffer-output "*android-adb-battery*" 0
                                (format "%S" (android-adb-battery serial)))))

(defun android-adb--read-host ()
  "Read a host and optional port."
  (read-string "Host[:port]: "))

(defun android-adb-connect-host (host)
  "Connect to HOST."
  (interactive (list (android-adb--read-host)))
  (message "android-adb: %s" (android-adb-connect host)))

(defun android-adb--read-disconnect-host ()
  "Read a connected TCP/IP host, or empty to disconnect all.
Candidates come from the current adb device list."
  (let* ((serials
          (delete-dups
           (delq nil
                 (mapcar
                  (lambda (device)
                    (let ((serial (plist-get device :serial)))
                      (and (string-match-p ":[0-9]+\\'" serial) serial)))
                  (android-adb-devices)))))
         (default (and (member android-adb-default-device-serial serials)
                       android-adb-default-device-serial)))
    (completing-read "Disconnect host (empty for all): " serials nil nil
                     default)))

(defun android-adb-disconnect-host (host)
  "Disconnect HOST, or all hosts when empty."
  (interactive (list (android-adb--read-disconnect-host)))
  (message "android-adb: %s"
           (android-adb-disconnect
            (unless (string-empty-p host) host))))

(defun android-adb-pair-host (host code)
  "Pair with HOST using CODE."
  (interactive (list (android-adb--read-host) (read-string "Pairing code: ")))
  (message "android-adb: %s" (android-adb-pair host code)))

(defun android-adb-show-state ()
  "Display the state of the default device."
  (interactive)
  (let ((serial (android-adb-read-device)))
    (message "android-adb: %s" (android-adb-get-state serial))))

(defun android-adb-wait-device ()
  "Wait for the default device to become ready."
  (interactive)
  (let ((serial android-adb-default-device-serial))
    (android-adb-wait-for-device
     serial nil
     (lambda (status output)
       (android-adb--report-operation "wait-for-device" status output)))))

(defun android-adb-reboot-device (mode)
  "Reboot the default device into MODE."
  (interactive (list (let ((value (completing-read "Reboot mode: "
                                                    '("system" "bootloader" "recovery" "sideload" "sideload-auto")
                                                    nil t nil nil "system")))
                       (unless (string= value "system") value))))
  (android-adb-reboot
   (android-adb-read-device) mode
   (lambda (status output) (android-adb--report-operation "reboot" status output))))

(defun android-adb-switch-tcpip (port)
  "Switch the default device to TCP/IP PORT."
  (interactive "sTCP/IP port: ")
  (android-adb-tcpip
   (android-adb-read-device) port
   (lambda (status output) (android-adb--report-operation "tcpip" status output))))

(defun android-adb-switch-usb ()
  "Switch the default device back to USB."
  (interactive)
  (android-adb-usb
   (android-adb-read-device)
   (lambda (status output) (android-adb--report-operation "usb" status output))))

(defun android-adb-install-multiple-files (apks)
  "Install selected APKS on the default device."
  (interactive (list (let ((file (read-file-name "APK: " nil nil t)))
                       (let ((files (list file)))
                         (while (y-or-n-p "Add another APK? ")
                           (push (read-file-name "APK: " nil nil t) files))
                         (nreverse files)))))
  (android-adb-install-multiple
   (android-adb-read-device) apks
   (lambda (status output) (android-adb--report-operation "install-multiple" status output))))

(defun android-adb-create-bugreport (destination)
  "Write a bug report to DESTINATION."
  (interactive (list (read-file-name "Bug report destination: ")))
  (android-adb-bugreport
   (android-adb-read-device) destination
   (lambda (status output) (android-adb--report-operation "bugreport" status output))))

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

;;;###autoload (autoload 'android-adb "android-adb-transient" nil t)
(transient-define-prefix android-adb ()
  "Discover and control Android devices through adb."
  [["Device"
    ("s" "Select default device" android-adb-select-device)
    ("l" "List devices" android-adb-list-devices)
    ("S" "Start server" android-adb-start-server)
    ("K" "Kill server" android-adb-kill-server)
    ("r" "Reconnect" android-adb-reconnect)
    ("c" "Connect" android-adb-connect-host)
    ("d" "Disconnect" android-adb-disconnect-host)
    ("p" "Pair" android-adb-pair-host)
    ("w" "Wait for device" android-adb-wait-device)]
   ["App"
    ("i" "Install APK" android-adb-install-apk-file)
    ("m" "Install multiple APKs" android-adb-install-multiple-files)
    ("l" "Launch package" android-adb-launch-package-command)
    ("k" "Force-stop package" android-adb-force-stop-command)
    ("u" "Uninstall package" android-adb-uninstall-package)
    ("c" "Clear package data" android-adb-clear-package)]
   ["Files"
    ("p" "Push file" android-adb-push-file)
    ("P" "Pull file" android-adb-pull-file)]
   ["System"
    ("R" "Reboot" android-adb-reboot-device)
    ("t" "TCP/IP" android-adb-switch-tcpip)
    ("U" "USB" android-adb-switch-usb)
    ("f" "Forward port" android-adb-forward-port)
    ("r" "Reverse port" android-adb-reverse-port)
    ("B" "Bugreport" android-adb-create-bugreport)]
   ["Info"
    ("I" "Device info" android-adb-show-device-info)
    ("b" "Battery" android-adb-show-battery)
    ("x" "Run shell command" android-adb-shell)]])

(provide 'android-adb-transient)
;;; android-adb-transient.el ends here
