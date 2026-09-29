# Marc — build, run, install.
# Parallel agents can use private build output: make test DERIVED=.build/dd-lint
DERIVED ?= .build/DerivedData
PREFIX  ?= $(HOME)/.local
# A tagged commit is its tag (v1.0.0), otherwise the branch (main), a detached
# HEAD its short hash, and a tree without git "dev". Override: make VERSION=x.
VERSION ?= $(shell git describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null \
	|| git symbolic-ref --short -q HEAD 2>/dev/null \
	|| git rev-parse --short HEAD 2>/dev/null \
	|| echo dev)

ARCH := $(shell uname -m)
XCODEBUILD_BASE = xcodebuild -project Marc.xcodeproj -scheme Marc -derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=$(ARCH)'
XCODEBUILD = $(XCODEBUILD_BASE) -quiet MARKETING_VERSION=$(VERSION)
DEBUG_APP   = $(DERIVED)/Build/Products/Debug/Marc.app
RELEASE_APP = $(DERIVED)/Build/Products/Release/Marc.app

SHELL := /bin/bash
.PHONY: build run install test clean quit

build:
	$(XCODEBUILD) -configuration Debug build

quit:
	@osascript -e 'if application "Marc" is running then tell application "Marc" to quit' >/dev/null 2>&1 || true
	@for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Marc >/dev/null || exit 0; sleep 0.5; done; pkill -x Marc || true

run: quit build
	open $(DEBUG_APP)

install: quit
	$(XCODEBUILD) -configuration Release build
	rm -rf /Applications/Marc.app
	cp -R $(RELEASE_APP) /Applications/Marc.app
	mkdir -p $(PREFIX)/bin
	ln -sf /Applications/Marc.app/Contents/Resources/marc $(PREFIX)/bin/marc
	@echo "Installed /Applications/Marc.app and $(PREFIX)/bin/marc"

# Full xcodebuild output is huge; keep results, failures and errors.
test:
	@set -o pipefail; $(XCODEBUILD_BASE) -configuration Debug test 2>&1 \
		| grep -E '^(\s*)(✔ Test run|✘|Test Case .*failed|\*\* TEST)|(^|: )error:|warning: .*marc/(App|Tests)/'

clean:
	$(XCODEBUILD) clean || true
	rm -rf $(DERIVED)
