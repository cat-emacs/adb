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

(defun adb--read-package ()
  "Read an installed Android package from the default device."
  (let* ((serial (adb-read-device))
         (packages (adb-packages serial)))
    (completing-read "Package: " packages nil nil)))

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

;;;###autoload (autoload 'adb "adb-transient" nil t)
(transient-define-prefix adb ()
  "Discover and control Android devices through adb."
  [["Device"
    ("s" "Select default device" adb-select-device)
    ("l" "List devices" adb-list-devices)
    ("S" "Start server" adb-start-server)
    ("K" "Kill server" adb-kill-server)
    ("r" "Reconnect" adb-reconnect)
    ("c" "Connect" adb-connect-host)
    ("d" "Disconnect" adb-disconnect-host)
    ("p" "Pair" adb-pair-host)
    ("w" "Wait for device" adb-wait-device)]
   ["App"
    ("i" "Install APK" adb-install-apk-file)
    ("m" "Install multiple APKs" adb-install-multiple-files)
    ("l" "Launch package" adb-launch-package-command)
    ("k" "Force-stop package" adb-force-stop-command)
    ("u" "Uninstall package" adb-uninstall-package)
    ("c" "Clear package data" adb-clear-package)]
   ["Files"
    ("p" "Push file" adb-push-file)
    ("P" "Pull file" adb-pull-file)]
   ["System"
    ("R" "Reboot" adb-reboot-device)
    ("t" "TCP/IP" adb-switch-tcpip)
    ("U" "USB" adb-switch-usb)
    ("f" "Forward port" adb-forward-port)
    ("r" "Reverse port" adb-reverse-port)
    ("B" "Bugreport" adb-create-bugreport)]
   ["Info"
    ("I" "Device info" adb-show-device-info)
    ("b" "Battery" adb-show-battery)
    ("x" "Run shell command" adb-shell)]])

(provide 'adb-transient)
;;; adb-transient.el ends here
