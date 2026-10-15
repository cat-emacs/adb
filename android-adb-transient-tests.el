;;; android-adb-transient-tests.el --- Tests for adb Transient UI -*- lexical-binding: t; -*-

(require 'ert)
(require 'android-adb-transient)

(ert-deftest android-adb-transient-is-available ()
  (should (commandp #'android-adb))
  (should (transient-get-suffix 'android-adb "s"))
  (should (transient-get-suffix 'android-adb "x"))
  (should (transient-get-suffix 'android-adb "i"))
  (should (transient-get-suffix 'android-adb "l"))
  (should (transient-get-suffix 'android-adb "p"))
  (should (transient-get-suffix 'android-adb "f"))
  (should (transient-get-suffix 'android-adb "I"))
  (should (transient-get-suffix 'android-adb "c"))
  (should (transient-get-suffix 'android-adb "r")))

(provide 'android-adb-transient-tests)
;;; android-adb-transient-tests.el ends here
