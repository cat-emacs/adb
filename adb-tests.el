;;; adb-tests.el --- Device communication tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'adb)

(ert-deftest adb-install-apk-builds-command ()
  (let ((apk (make-temp-file "adb-test" nil ".apk")) command)
    (unwind-protect
        (cl-letf (((symbol-function 'adb-start)
                   (lambda (serial arguments &rest options)
                     (setq command (list serial arguments options))
                     'fake-process)))
          (should (eq (adb-install-apk "SER1" apk) 'fake-process))
          (should (equal (car command) "SER1"))
          (should (equal (cadr command) (list "install" "-r" apk))))
      (delete-file apk))))

(ert-deftest adb-install-apk-rejects-missing-file ()
  (should-error (adb-install-apk "SER1" "/missing/test.apk")
                :type 'user-error))

(ert-deftest adb-app-and-file-operations-build-commands ()
  (let ((apk (make-temp-file "adb-test" nil ".apk")) commands)
    (unwind-protect
        (cl-letf (((symbol-function 'adb-start)
                   (lambda (serial arguments &rest _options)
                     (push (list serial arguments) commands)
                     'fake-process)))
          (adb-launch-package "SER1" "com.example.app")
          (adb-force-stop "SER1" "com.example.app")
          (adb-uninstall "SER1" "com.example.app")
          (adb-clear-package-data "SER1" "com.example.app")
          (adb-push "SER1" apk "/data/local/tmp/app.apk")
          (adb-pull "SER1" "/data/local/tmp/app.apk" "/tmp/app.apk")
          (should (= (length commands) 6))
          (should (member '("SER1" ("uninstall" "com.example.app")) commands)))
      (delete-file apk))))

(ert-deftest adb-interactive-command-builders ()
  (let ((apk (make-temp-file "adb-test" nil ".apk")) commands)
    (unwind-protect
        (cl-letf (((symbol-function 'adb-start)
                   (lambda (serial arguments &rest _options)
                     (push (list serial arguments) commands)
                     'fake-process)))
          (adb-reboot "SER1" "recovery")
          (adb-tcpip "SER1" "5555")
          (adb-usb "SER1")
          (adb-install-multiple "SER1" (list apk))
          (adb-bugreport "SER1" "/tmp/report.zip")
          (should (member '("SER1" ("reboot" "recovery")) commands))
          (should (member '("SER1" ("tcpip" "5555")) commands))
          (should (member '("SER1" ("usb")) commands))
          (should (member (list "SER1" (list "install-multiple" "-r" apk))
                         commands)))
      (delete-file apk))))

(ert-deftest adb-packages-parses-and-sorts-package-list ()
  (cl-letf (((symbol-function 'adb-query)
             (lambda (_serial &rest _arguments)
               "package:zeta
package:alpha
package:alpha
")))
    (should (equal (adb-packages "SER1") '("alpha" "zeta")))))

(ert-deftest adb-parser-keeps-device-states ()
  (should
   (equal (adb-parse-devices
           "* daemon started successfully\nList of devices attached\nA device product:p model:Pixel_9 device:x transport_id:1\nB offline\nC unauthorized\nD no permissions (missing udev rules)\n")
          '((:serial "A" :state device :product "p" :model "Pixel_9"
             :device "x" :transport-id "1")
            (:serial "B" :state offline)
            (:serial "C" :state unauthorized)
            (:serial "D" :state no-permissions)))))

(ert-deftest adb-command-preserves-argument-boundaries ()
  (cl-letf (((symbol-function 'adb-executable)
             (lambda () "/SDK with spaces/adb")))
    (should (equal (adb-command "SER1" "install" "/an apk.apk")
                   '("/SDK with spaces/adb" "-s" "SER1" "install" "/an apk.apk")))))

(ert-deftest adb-explicit-program-does-not-silently-fallback ()
  (let ((adb-program "/missing/adb"))
    (cl-letf (((symbol-function 'file-executable-p) (lambda (_) nil))
              ((symbol-function 'executable-find) (lambda (_) "/another/adb")))
      (should-error (adb-executable) :type 'user-error))))

(ert-deftest adb-executable-falls-back-to-sdk ()
  (let ((adb-program nil)
        (adb-sdk-directory "/sdk"))
    (cl-letf (((symbol-function 'executable-find) (lambda (_) nil))
              ((symbol-function 'file-executable-p)
               (lambda (file) (equal file "/sdk/platform-tools/adb"))))
      (should (equal (adb-executable) "/sdk/platform-tools/adb")))))

(ert-deftest adb-read-device-uses-only-ready-devices ()
  (cl-letf (((symbol-function 'adb-devices)
             (lambda (&optional _)
               '((:serial "OFF" :state offline)
                 (:serial "OK" :state device :model "Pixel")))))
    (let ((adb-default-device-serial nil))
      (should (equal (adb-read-device) "OK")))))

(ert-deftest adb-read-device-prefers-default-device ()
  (let ((adb-default-device-serial "OK"))
    (cl-letf (((symbol-function 'adb-devices)
               (lambda (&optional _)
                 '((:serial "OK" :state device)
                   (:serial "OTHER" :state device)))))
      (should (equal (adb-read-device) "OK")))))

(ert-deftest adb-read-device-reports-authorization ()
  (cl-letf (((symbol-function 'adb-devices)
             (lambda (&optional _) '((:serial "SER1" :state unauthorized)))))
    (let ((error (should-error (adb-read-device) :type 'user-error)))
      (should (string-match-p "unauthorized" (error-message-string error))))))

(ert-deftest adb-query-cleans-up-on-success-and-failure ()
  (cl-letf (((symbol-function 'adb-command)
             (lambda (_serial &rest arguments)
               (list shell-file-name "-c" (car arguments)))))
    (should (equal (adb-query nil "printf 'hello'") "hello"))
    (should-error (adb-query nil "printf 'failed'; exit 1") :type 'user-error)
    (should-not (get-buffer " *adb-query*"))))

(ert-deftest adb-query-timeout-kills-process ()
  (let ((adb-query-timeout 0.05) process)
    (cl-letf (((symbol-function 'adb-command)
               (lambda (&rest _) (list shell-file-name "-c" "exec sleep 10")))
              ((symbol-function 'adb-start)
               (lambda (_serial _arguments &rest options)
                 (setq process (make-process :name "adb-timeout-test"
                                             :command (list shell-file-name "-c" "exec sleep 10")
                                             :buffer (plist-get options :buffer)
                                             :sentinel #'ignore :noquery t)))))
      (should-error (adb-query nil "devices") :type 'user-error)
      (should-not (process-live-p process))
      (should-not (get-buffer " *adb-query*")))))

(ert-deftest adb-query-start-failure-preserves-buffer-process ()
  (let ((buffer (generate-new-buffer " *adb-existing-process*")) process)
    (unwind-protect
        (with-current-buffer buffer
          (setq process (make-process :name "adb-existing-process"
                                      :buffer buffer :command '("sleep" "10")
                                      :sentinel #'ignore :noquery t))
          (cl-letf (((symbol-function 'adb-start)
                     (lambda (&rest _) (user-error "Cannot find adb"))))
            (should-error (adb-query nil "devices") :type 'user-error)
            (should (process-live-p process))))
      (when (and process (process-live-p process)) (delete-process process))
      (kill-buffer buffer))))

(provide 'adb-tests)
;;; adb-tests.el ends here
