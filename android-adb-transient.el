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
    ("l" "List devices" android-adb-list-devices)]
   ["Server"
    ("S" "Start server" android-adb-start-server)
    ("K" "Kill server" android-adb-kill-server)
    ("r" "Reconnect" android-adb-reconnect)]
   ["Command"
    ("x" "Run shell command" android-adb-shell)]])

(provide 'android-adb-transient)
;;; android-adb-transient.el ends here
