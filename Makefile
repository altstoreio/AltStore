SHELL := /bin/bash
.PHONY: help ios update tvos

RUBY := $(shell command -v ruby 2>/dev/null)
RUST := $(shell command -v rust 2>/dev/null)
RUSTUP := $(shell command -v rustup 2>/dev/null)
HOMEBREW := $(shell command -v brew 2>/dev/null)
BUNDLER := $(shell command -v bundle 2>/dev/null)

default: help

# Add the following 'help' target to your Makefile
# And add help text after each target name starting with '\#\#'
# A category can be added with @category

# COLORS
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
WHITE  := $(shell tput -Txterm setaf 7)
RESET  := $(shell tput -Txterm sgr0)

## ----- Helper functions ------

# Helper target for declaring an external executable as a recipe dependency.
# For example,
#   `my_target: | _program_awk`
# will fail before running the target named `my_target` if the command `awk` is
# not found on the system path.
_program_%: FORCE
	@_=$(or $(shell which $* 2> /dev/null),$(error `$*` command not found. Please install `$*` and try again))

# Helper target for declaring required environment variables.
#
# For example,
#   `my_target`: | _var_PARAMETER`
#
# will fail before running `my_target` if the variable `PARAMETER` is not declared.
_var_%: FORCE
	@_=$(or $($*),$(error `$*` is a required parameter))

_tag: | _var_VERSION
	make --no-print-directory -B README.md
	git commit -am "Tagging release $(VERSION)"
	git tag -a $(VERSION) $(if $(NOTES),-m '$(NOTES)',-m $(VERSION))
.PHONY: _tag

_push: | _var_VERSION
	git push origin $(VERSION)
	git push origin master
.PHONY: _push

## ------ Commmands -----------

TARGET_MAX_CHAR_NUM=20
## Show help
help:
	@echo ''
	@echo 'Usage:'
	@echo '  ${YELLOW}make${RESET} ${GREEN}<target>${RESET}'
	@echo ''
	@echo 'Targets:'
	@awk '/^[a-zA-Z\-\_0-9]+:/ { \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = substr($$1, 0, index($$1, ":")-1); \
			helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
			printf "  ${YELLOW}%-$(TARGET_MAX_CHAR_NUM)s${RESET} ${GREEN}%s${RESET}\n", helpCommand, helpMessage; \
		} \
	} \
	{ lastLine = $$0 }' \
	$(MAKEFILE_LIST)

## Install dependencies.
setup: \
	pre_setup \
	install_rust \
	install_rustup \
	install_rust_toolchain \
	build_rust_dependencies

# check_for_homebrew \
# update_homebrew \

pull_request: \
	test \
	codecov_upload \
	danger

pre_setup:
	$(info Project setup…)

check_for_rust:
	$(info Checking for Rust…)

ifeq ($(RUST),)
	$(error Rust is not installed.)
endif

check_for_rustup:
	$(info Checking for Rustup…)

ifeq ($(RUSTUP),)
	$(error Rust is not installed.)
endif

check_for_ruby:
	$(info Checking for Ruby…)

ifeq ($(RUBY),)
	$(error Ruby is not installed.)
endif

check_for_homebrew:
	$(info Checking for Homebrew…)

ifeq ($(HOMEBREW),)
	$(error Homebrew is not installed)
endif

update_homebrew:
	$(info Updating Homebrew…)

	brew update

install_swift_lint:
	$(info Install swiftlint…)

	brew unlink swiftlint || true
	brew install swiftlint
	brew link --overwrite swiftlint

install_bundler_gem:
	$(info Checking and installing bundler…)

ifeq ($(BUNDLER),)
	gem install bundler -v '~> 1.17'
else
	gem update bundler '~> 1.17'
endif

install_ruby_gems:
	$(info Installing Ruby gems…)

	bundle install

pull:
	$(info Pulling new commits…)

	git stash push || true
	git pull
	git stash pop || true

## -- Source Code Tasks --

## Pull upstream and update 3rd party frameworks
# update: pull submodules build_rust_dependencies
update: submodules build_rust_dependencies

submodules:
	$(info Updating submodules…)

	git submodule update --init --recursive

build_rust_dependencies:
	$(info Building Rust dependencies…)

	pushd Dependencies/em_proxy
	cargo build --release --target aarch64-apple-ios
	popd
	pushd Dependencies/minimuxer
	cargo build --release --target aarch64-apple-ios
	popd

install_rustup:
	$(info Installing Rustup…)

	curl https://sh.rustup.rs -sSf | sh
	source "$(HOME)/.cargo/env"
	rustup target add aarch64-apple-ios

# TODO: Add x86, armv7? toolchains
# https://doc.rust-lang.org/nightly/rustc/platform-support.html

install_cbindgen:
	$(info Installing cbindgen…)

	cargo install cbindgen

install_rust_toolchain:
	$(info Installing Rust toolchain…)

	rustup target add aarch64-apple-ios

install_rust_toolchain_ios_sim:
	$(info Installing Rust iOS Sim toolchain…)

	rustup target add aarch64-apple-ios-sim

install_rust_toolchain_tvos:
	$(info Installing Rust tvOS toolchain…)

	rustup target add aarch64-apple-tvos

install_rust_toolchain_tvos_sim:
	$(info Installing Rust tvOS Sim toolchain…)

	rustup target add aarch64-apple-tvos-sim

install_rust_toolchain_watchos_sim:
	$(info Installing Rust watchOS Sim toolchain…)

	rustup target add aarch64-apple-watchos-sim

install_rust_toolchain_watchos:
	$(info Installing Rust watchOS toolchain…)

	rustup target add aarch64-apple-watchos

install_rust_toolchain_catalyst:
	$(info Installing Rust macOS Catalyst toolchain…)

	rustup target add aarch64-apple-ios-macabi

install_rust:
	$(info Installing Rust…)

	curl https://sh.rustup.rs -sSf | sh
	source "$(HOME)/.cargo/env"

## -- QA Task Runners --

codecov_upload:
	curl -s https://codecov.io/bash | bash

danger:
	bundle exec danger

## -- Testing --

## Run test on all targets
test:
	bundle exec fastlane test

## -- Building --

developer_ios:
	$(info Building iOS for Developer profile…)

	 xcodebuild -project AltStore.xcodeproj -scheme AltStore -sdk iphoneos archive -archivePath ./archive CODE_SIGNING_REQUIRED=NO AD_HOC_CODE_SIGNING_ALLOWED=YES CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM=XYZ0123456 ORG_IDENTIFIER=com.SideStore | xcpretty

developer_tvos:
	$(info Building tvOS for Developer profile…)

	 xcodebuild -project AltStore.xcodeproj -scheme AltStore -sdk tvos archive -archivePath ./archive CODE_SIGNING_REQUIRED=NO AD_HOC_CODE_SIGNING_ALLOWED=YES CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM=XYZ0123456 ORG_IDENTIFIER=com.SideStore | xcpretty

## Update & build for iOS
ios: | update developer_ios

## Update & build for tvOS
tvos: | update developer_tvos

## Open the workspace
open:
	open AltStore.xcodeproj

## tag and release to github
release: | _var_VERSION
	@if ! git diff --quiet HEAD; then \
		( $(call _error,refusing to release with uncommitted changes) ; exit 1 ); \
	fi
	test
	package
	make --no-print-directory _tag VERSION=$(VERSION)
	make --no-print-directory _push VERSION=$(VERSION)
