SHELL := /bin/sh
PREFIX ?= $(HOME)/.local
SCRIPTS := bin/nisemono lib/*.sh scripts/*.sh .github/scripts/*.sh test/*.sh test/*.bash test/*.bats test/shim/sudo test/bin/gum screens/*.sh

.PHONY: help fmt lint test test-all test-linux coverage check screens install

help:
	@echo "targets:"
	@echo "  fmt         format every script with shfmt -i 2"
	@echo "  lint        shfmt, shellcheck -o all and mandoc at zero findings"
	@echo "  test        bats suites under the system sh"
	@echo "  test-all    bats suites under every installed shell"
	@echo "  test-linux  the same suites in a privileged Ubuntu container"
	@echo "  coverage    bashcov line coverage on this Mac and in the Ubuntu container, gate 100%"
	@echo "  check       lint and test"
	@echo "  screens     record the README screens from the real tool with VHS, on macOS"
	@echo "  install     install the tool, man page and completions under PREFIX (default ~/.local)"

fmt:
	shfmt -i 2 -w $(SCRIPTS)

lint:
	shfmt -i 2 -d $(SCRIPTS)
	shellcheck -x -s sh -o all bin/nisemono lib/*.sh scripts/*.sh .github/scripts/*.sh test/bin/gum screens/*.sh
	sh scripts/check-names.sh
	shellcheck -x -o all test/*.sh test/*.bash test/*.bats test/shim/sudo
	shellcheck -s bash -o all completions/nisemono.bash
	mandoc -T lint man/nisemono.1
	yamllint -s -c .yamllint.yml .github .yamllint.yml
	actionlint

test:
	NISEMONO_TEST_SHELLS=sh sh test/run-matrix.sh test

test-all:
	sh test/run-matrix.sh test

test-linux:
	sh test/linux-container.sh sh test/run-matrix.sh test

coverage:
	sh scripts/coverage.sh 0 && cp -f coverage/.resultset.json coverage-macos.json
	sh test/linux-container.sh sh scripts/linux-coverage.sh
	python3 scripts/coverage-gate.py '/(bin/nisemono|lib/[a-z]+\.sh)\Z' 100 coverage-macos.json coverage-linux.json

screens:
	sh screens/record.sh

check: lint test

install:
	mkdir -p "$(PREFIX)/share/nisemono" "$(PREFIX)/bin" "$(PREFIX)/share/man/man1" "$(PREFIX)/share/bash-completion/completions" "$(PREFIX)/share/zsh/site-functions" "$(PREFIX)/share/fish/vendor_completions.d"
	cp -R bin lib "$(PREFIX)/share/nisemono/"
	cp -f man/nisemono.1 "$(PREFIX)/share/man/man1/nisemono.1"
	cp -f completions/nisemono.bash "$(PREFIX)/share/bash-completion/completions/nisemono"
	cp -f completions/_nisemono "$(PREFIX)/share/zsh/site-functions/_nisemono"
	cp -f completions/nisemono.fish "$(PREFIX)/share/fish/vendor_completions.d/nisemono.fish"
	printf '#!/bin/sh\nexec "%s/share/nisemono/bin/nisemono" "$$@"\n' "$(PREFIX)" > "$(PREFIX)/bin/nisemono"
	chmod 755 "$(PREFIX)/bin/nisemono"
