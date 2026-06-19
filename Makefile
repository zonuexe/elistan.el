# Makefile for elistan

EMACS ?= emacs
# Path to the typespec foundation (provides `typespec-eval' etc.).
TYPESPEC ?= ../emacs-typespec
LOAD_PATH ?= -L . -L $(TYPESPEC)

# All elistan sources except test files, and all test files.
EL_SOURCES = $(filter-out %-test.el,$(wildcard elistan*.el))
EL_TESTS = $(wildcard *-test.el)

.PHONY: test check compile clean test-source

# clean -> test (source) -> compile -> test (.elc)
test check: clean
	$(MAKE) test-source
	$(MAKE) compile
	$(MAKE) test-source

test-source:
	$(EMACS) -Q --batch $(LOAD_PATH) \
		-l ert $(addprefix -l ,$(EL_TESTS)) \
		-f ert-run-tests-batch-and-exit

compile:
	$(EMACS) -Q --batch $(LOAD_PATH) -f batch-byte-compile $(EL_SOURCES)

clean:
	rm -f *.elc
