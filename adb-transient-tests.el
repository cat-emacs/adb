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

(ert-deftest adb-remote-path-completion-navigates-and-caches-directories ()
  (let (queries)
    (cl-letf (((symbol-function 'adb-directory-files)
               (lambda (serial directory)
                 (should (equal serial "SER1"))
                 (push directory queries)
                 (pcase directory
                   ("/sdcard/" '("Download/" "hello world.txt" ".hidden"))
                   ("/sdcard/Download/" '("app.apk"))
                   (_ (error "Unexpected directory")))))
              ((symbol-function 'completing-read)
               (lambda (_prompt table _predicate mustmatch initial &rest _)
                 (should mustmatch)
                 (should (equal initial "/sdcard/"))
                 (should (equal (completion-boundaries
                                 "/sdcard/Do" table nil "wnload/file")
                                '(8 . 6)))
                 (should (equal (try-completion "/sdcard/Do" table)
                                "/sdcard/Download/"))
                 (should (member "hello world.txt"
                                 (all-completions "/sdcard/" table)))
                 (should (test-completion "/sdcard/" table))
                 (should (test-completion "/sdcard/.hidden" table))
                 (should (equal (all-completions "/sdcard/Download/a" table)
                                '("app.apk")))
                 (should (test-completion "/sdcard/Download/app.apk" table))
                 "/sdcard/Download/app.apk")))
      (should (equal (adb--read-remote-path "SER1" t)
                     "/sdcard/Download/app.apk"))
      (should (equal (nreverse queries)
                     '("/sdcard/" "/sdcard/Download/"))))))

(ert-deftest adb-push-completion-allows-new-destination-and-pins-device ()
  (let (command)
    (cl-letf (((symbol-function 'adb-read-device) (lambda () "SER1"))
              ((symbol-function 'read-file-name)
               (lambda (_prompt _directory _default mustmatch &rest _)
                 (should mustmatch)
                 "/tmp/local file"))
              ((symbol-function 'completing-read)
               (lambda (_prompt _table _pred mustmatch &rest _)
                 (should-not mustmatch)
                 "/sdcard/new file"))
              ((symbol-function 'adb-push)
               (lambda (serial local remote &optional _callback)
                 (setq command (list serial local remote)))))
      (call-interactively #'adb-push-file)
      (should (equal command '("SER1" "/tmp/local file" "/sdcard/new file"))))))

(ert-deftest adb-pull-completion-requires-source-and-pins-device ()
  (let (command)
    (cl-letf (((symbol-function 'adb-read-device) (lambda () "SER1"))
              ((symbol-function 'completing-read)
               (lambda (_prompt _table _pred mustmatch &rest _)
                 (should mustmatch)
                 "/sdcard/source file"))
              ((symbol-function 'read-file-name)
               (lambda (_prompt &rest _) "/tmp/destination"))
              ((symbol-function 'adb-pull)
               (lambda (serial remote local &optional _callback)
                 (setq command (list serial remote local)))))
      (call-interactively #'adb-pull-file)
      (should (equal command
                     '("SER1" "/sdcard/source file" "/tmp/destination"))))))

(ert-deftest adb-remote-path-completion-reports-query-failure ()
  (cl-letf (((symbol-function 'adb-directory-files)
             (lambda (&rest _) (user-error "Permission denied")))
            ((symbol-function 'completing-read)
             (lambda (_prompt table &rest _)
               (all-completions "/data/private/" table))))
    (should-error (adb--read-remote-path "SER1" t) :type 'user-error)))

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

(ert-deftest adb-normalize-apk-files-keeps-readable-apks ()
  (let* ((dir (make-temp-file "adb-apks-" t))
         (apk (expand-file-name "app.apk" dir))
         (other (expand-file-name "notes.txt" dir))
         (nested (expand-file-name "nested/" dir)))
    (unwind-protect
        (progn
          (write-region "" nil apk)
          (write-region "" nil other)
          (make-directory nested)
          (should (equal (adb--normalize-apk-files
                          (list apk other nested "missing.apk" apk))
                         (list (file-truename apk))))
          (should-error (adb--normalize-apk-files (list other))
                        :type 'user-error))
      (delete-directory dir t))))

(ert-deftest adb-normalize-apk-files-collapses-the-same-file ()
  (let* ((dir (make-temp-file "adb-apks-" t))
         (apk (expand-file-name "app.apk" dir))
         (link (expand-file-name "link.apk" dir)))
    (unwind-protect
        (progn
          (write-region "" nil apk)
          (make-symbolic-link apk link)
          (should (equal (adb--normalize-apk-files (list link apk))
                         (list (file-truename apk)))))
      (delete-directory dir t))))

(ert-deftest adb-install-apk-files-installs-each-apk ()
  (let (commands)
    (cl-letf (((symbol-function 'adb-install-apk)
               (lambda (serial apk callback &key replace)
                 (should replace)
                 (push (list serial apk) commands)
                 (funcall callback 0 "Success\n"))))
      (adb--install-apk-files "SER1" '("/tmp/a.apk" "/tmp/b.apk") t)
      (should (equal (nreverse commands)
                     '(("SER1" "/tmp/a.apk") ("SER1" "/tmp/b.apk")))))))

(ert-deftest adb-install-apk-files-stops-after-failure ()
  (let (commands)
    (cl-letf (((symbol-function 'adb-install-apk)
               (lambda (_serial apk callback &key replace)
                 (should-not replace)
                 (push apk commands)
                 (funcall callback 1 "Failure [INSTALL_FAILED_INVALID_APK]")))
              ((symbol-function 'adb--report-operation) #'ignore))
      (adb--install-apk-files "SER1" '("/tmp/a.apk" "/tmp/b.apk") nil)
      (should (equal commands '("/tmp/a.apk"))))))

(ert-deftest adb-read-apk-files-uses-multiple-file-completion ()
  (let* ((dir (make-temp-file "adb-apks-" t))
         (apk (expand-file-name "app.apk" dir))
         args)
    (unwind-protect
        (progn
          (write-region "" nil apk)
          (cl-letf (((symbol-function 'completing-read-multiple)
                     (lambda (&rest arguments)
                       (setq args arguments)
                       (list apk))))
            (should (equal (adb--read-apk-files) (list (file-truename apk))))
            (should (eq (nth 1 args) #'read-file-name-internal))
            (should (eq (nth 2 args) #'adb--apk-file-completion-p))
            (should (eq (nth 3 args) t))
            (should (equal (nth 4 args)
                           (minibuffer-maybe-quote-filename
                            (adb--file-name-directory))))
            (should (eq (nth 5 args) 'file-name-history))))
      (delete-directory dir t))))

(ert-deftest adb-transient-is-available ()
  (should (commandp #'adb))
  (should (commandp #'adb-am))
  (should (commandp #'adb-pm))
  (should (eq (adb-test--suffix-command 'adb "a") 'adb-am))
  (should (eq (adb-test--suffix-command 'adb "p") 'adb-pm))
  (should (equal (transient-args 'adb) '("-r")))
  (dolist (key '("s" "l" "w" "r" "S" "K" "c" "d" "y" "t" "U" "F" "V"
                 "-r" "i" "m" "u" "P" "G" "b" "B" "I" "E" "x"))
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
