# Makefile for elistan

EMACS ?= emacs
# Path to the typespec foundation (provides `typespec-eval' etc.).
TYPESPEC ?= ../emacs-typespec
LOAD_PATH ?= -L . -L $(TYPESPEC)

EL_SOURCES = elistan.el

.PHONY: test check compile clean

# clean -> test (source) -> compile -> test (.elc)
test check: clean
	$(MAKE) test-source
	$(MAKE) compile
	$(MAKE) test-source

test-source:
	$(EMACS) -Q --batch $(LOAD_PATH) \
		-l ert -l elistan-test \
		-f ert-run-tests-batch-and-exit

compile:
	$(EMACS) -Q --batch $(LOAD_PATH) -f batch-byte-compile $(EL_SOURCES)

clean:
	rm -f *.elc
