# Marcdown — build, run, install.
# Parallel agents can use private build output: make test DERIVED=.build/dd-lint
DERIVED ?= .build/DerivedData
PREFIX  ?= $(HOME)/.local
APPDIR  ?= $(HOME)/Applications
# A tagged commit is its tag (v1.0.0), otherwise the branch (main), a detached
# HEAD its short hash, and a tree without git "dev". Override: make VERSION=x.
VERSION ?= $(shell git describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null \
	|| git symbolic-ref --short -q HEAD 2>/dev/null \
	|| git rev-parse --short HEAD 2>/dev/null \
	|| echo dev)

ARCH := $(shell uname -m)
XCODEBUILD_BASE = xcodebuild -project Marcdown.xcodeproj -scheme Marcdown -derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=$(ARCH)'
XCODEBUILD = $(XCODEBUILD_BASE) -quiet MARKETING_VERSION=$(VERSION)
DEBUG_APP   = $(DERIVED)/Build/Products/Debug/Marcdown.app
RELEASE_APP = $(DERIVED)/Build/Products/Release/Marcdown.app

SHELL := /bin/bash
.PHONY: build bundle _bundle run install test clean quit

build:
	$(XCODEBUILD) -configuration Debug build

# Release bundle for one arch: make bundle ARCH=arm64|x86_64 VERSION=1.0.0
bundle:
	$(MAKE) DERIVED=.build/dd-$(ARCH) ARCH=$(ARCH) VERSION=$(VERSION) _bundle

_bundle:
	$(XCODEBUILD) -configuration Release build
	rm -rf build/$(ARCH)
	mkdir -p build/$(ARCH)
	cp -R $(RELEASE_APP) build/$(ARCH)/Marcdown.app

quit:
	@osascript -e 'if application "Marcdown" is running then tell application "Marcdown" to quit' >/dev/null 2>&1 || true
	@for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Marcdown >/dev/null || exit 0; sleep 0.5; done; pkill -x Marcdown || true

run: quit build
	open $(DEBUG_APP)

install: quit
	$(XCODEBUILD) -configuration Release build
	rm -rf $(APPDIR)/Marcdown.app
	mkdir -p $(APPDIR) $(PREFIX)/bin
	cp -R $(RELEASE_APP) $(APPDIR)/Marcdown.app
	ln -sf $(APPDIR)/Marcdown.app/Contents/Resources/marcdown $(PREFIX)/bin/marcdown
	@echo "Installed $(APPDIR)/Marcdown.app and $(PREFIX)/bin/marcdown"

# Full xcodebuild output is huge; keep results, failures and errors.
test:
	@set -o pipefail; $(XCODEBUILD_BASE) -configuration Debug test 2>&1 \
		| grep -E '^(\s*)(✔ Test run|✘|Test Case .*failed|\*\* TEST)|(^|: )error:|warning: .*marc/(App|Tests)/'

clean:
	$(XCODEBUILD) clean || true
	rm -rf $(DERIVED)
