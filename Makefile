EMACS ?= emacs
BATCH = $(EMACS) -Q --batch
TEST_DEPS_DIR ?= .test-deps
PACKAGE_USER_DIR ?= $(abspath $(TEST_DEPS_DIR)/elpa)
LOAD_PATH = -L .
ARCHIVES = --eval "(setq package-user-dir \"$(PACKAGE_USER_DIR)\")" \
           --eval "(require 'package)" \
           --eval "(add-to-list 'package-archives '(\"gnu\" . \"https://elpa.gnu.org/packages/\") t)" \
           --eval "(package-initialize)"

.PHONY: install-deps lint build test clean
install-deps:
	mkdir -p "$(TEST_DEPS_DIR)"
	$(BATCH) $(ARCHIVES) \
	  --eval "(package-refresh-contents)" \
	  --eval "(package-install 'transient)"

lint:
	$(BATCH) $(ARCHIVES) $(LOAD_PATH) --eval '(checkdoc-file "android-adb.el")' \
	  --eval '(with-temp-buffer (insert-file-contents "android-adb.el") (emacs-lisp-mode) (check-parens))'

build:
	$(BATCH) $(ARCHIVES) $(LOAD_PATH) --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile android-adb.el

test:
	$(BATCH) $(ARCHIVES) $(LOAD_PATH) -l android-adb.el -l android-adb-tests.el -f ert-run-tests-batch-and-exit

clean:
	rm -f *.elc
