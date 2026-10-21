;;; adb-transient-tests.el --- Tests for adb Transient UI -*- lexical-binding: t; -*-

(require 'ert)
(require 'adb-transient)

(ert-deftest adb-package-reader-offers-installed-packages ()
  (let (prompt candidates)
    (cl-letf (((symbol-function 'adb-read-device)
               (lambda (&optional _) "SER1"))
              ((symbol-function 'adb-packages)
               (lambda (serial)
                 (should (equal serial "SER1"))
                 '("com.example.alpha" "com.example.beta")))
              ((symbol-function 'completing-read)
               (lambda (read-prompt collection &rest _)
                 (setq prompt read-prompt candidates collection)
                 "com.example.beta")))
      (should (equal (adb--read-package) "com.example.beta"))
      (should (equal prompt "Package: "))
      (should (equal candidates '("com.example.alpha" "com.example.beta"))))))

(ert-deftest adb-disconnect-reader-offers-tcp-devices ()
  (let (prompt choices)
    (cl-letf (((symbol-function 'adb-devices)
               (lambda (&optional _)
                 '((:serial "emulator-5554" :state device)
                   (:serial "192.168.1.20:5555" :state device)
                   (:serial "10.0.0.2:5555" :state offline))))
              ((symbol-function 'completing-read)
               (lambda (read-prompt collection &rest _)
                 (setq prompt read-prompt choices collection)
                 "192.168.1.20:5555")))
      (should (equal (adb--read-disconnect-host)
                     "192.168.1.20:5555"))
      (should (equal prompt "Disconnect host (empty for all): "))
      (should (equal choices '("192.168.1.20:5555" "10.0.0.2:5555"))))))

(defun adb-test--suffix-command (prefix key)
  (let ((suffix (transient-get-suffix prefix key)))
    (plist-get (if (keywordp (cadr suffix)) (cdr suffix) (nth 2 suffix))
               :command)))

(ert-deftest adb-permission-names-ignores-group-headers ()
  (should (equal (adb--permission-names
                  "Dangerous Permissions:\ngroup:android.permission-group.CAMERA\n  permission:android.permission.CAMERA\npermission:android.permission.RECORD_AUDIO\n")
                 '("android.permission.CAMERA"
                   "android.permission.RECORD_AUDIO"))))

(ert-deftest adb-am-start-uses-common-options ()
  (should (equal (adb--am-start-arguments
                  '("--component=com.example/.Main"
                    "--user=current"
                    "--debug"
                    "--wait-for-launch"
                    "--stop-first"
                    "--es=message=hello=world"
                    "--ez=debug=true"
                    "--activity-clear-task"
                    "--grant-read-uri-permission"))
                 '("am" "start" "-D" "-W" "-S" "--user" "current"
                   "-n" "com.example/.Main"
                   "--es" "message" "hello=world" "--ez" "debug" "true"
                   "--activity-clear-task" "--grant-read-uri-permission"))))

(ert-deftest adb-am-start-launches-package-when-no-component ()
  (should (equal (adb--am-start-arguments '("--package=com.example"))
                 '("am" "start"
                   "-a" "android.intent.action.MAIN"
                   "-c" "android.intent.category.LAUNCHER"
                   "-p" "com.example"))))

(ert-deftest adb-am-start-rejects-bare-component ()
  (should-error (adb--am-start-arguments '("--component=com.example"))
                :type 'user-error))

(ert-deftest adb-pm-list-packages-maps-common-filters ()
  (should (equal (adb--pm-list-packages-arguments
                  '("--third-party" "--show-apk" "--show-versioncode"
                    "--user=0" "--filter=example"))
                 '("pm" "list" "packages" "-3" "-f" "--show-versioncode"
                   "--user" "0" "example"))))

(ert-deftest adb-pm-uninstall-can-keep-data ()
  (should (equal (adb--pm-package-arguments
                  "uninstall"
                  '("--package=com.example" "--user=all" "--keep-data")
                  "-k")
                 '("pm" "uninstall" "-k" "--user" "all" "com.example"))))

(ert-deftest adb-pm-grant-accepts-one-permission-or-all ()
  (should (equal (adb--pm-permission-arguments
                  "grant"
                  '("--package=com.example"
                    "--permission=android.permission.CAMERA"))
                 '("pm" "grant" "com.example" "android.permission.CAMERA")))
  (should (equal (adb--pm-permission-arguments
                  "revoke" '("--all-permissions"))
                 '("pm" "revoke" "--all-permissions"))))

(ert-deftest adb-transient-is-available ()
  (should (commandp #'adb))
  (should (commandp #'adb-am))
  (should (commandp #'adb-pm))
  (should (eq (adb-test--suffix-command 'adb "a") 'adb-am))
  (should (eq (adb-test--suffix-command 'adb "p") 'adb-pm))
  (dolist (key '("s" "l" "w" "r" "S" "K" "c" "d" "y" "t" "U" "F" "V"
                 "i" "m" "u" "P" "G" "b" "B" "I" "E" "x"))
    (should (transient-get-suffix 'adb key)))
  (dolist (key '("-n" "-p" "-u" "-a" "-d" "-e" "-z" "-C" "-D" "-W" "-S"))
    (should (transient-get-suffix 'adb-am key)))
  (dolist (key '("s" "k" "b" "i" "l"))
    (should (transient-get-suffix 'adb-am key)))
  (dolist (key '("-p" "-u" "-P" "-3" "-s" "-k" "-C" "-A"))
    (should (transient-get-suffix 'adb-pm key)))
  (dolist (key '("l" "c" "n" "g" "r" "u"))
    (should (transient-get-suffix 'adb-pm key))))

(provide 'adb-transient-tests)
;;; adb-transient-tests.el ends here
