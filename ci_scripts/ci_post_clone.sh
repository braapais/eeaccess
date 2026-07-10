#!/bin/sh

# ci_post_clone.sh — Xcode Cloud runs this immediately after cloning the repo,
# before resolving dependencies or building.
#
# EEAccess.xcodeproj is generated from project.yml by XcodeGen and is NOT
# committed, so we install XcodeGen and generate it here. All Swift packages
# (TeslaKeyKit, Vendor/swift-protobuf) are vendored locally in the repo, so no
# network access to package registries is required.

set -e
set -x

echo "▸ Installing XcodeGen via Homebrew…"
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_ENV_HINTS=1

# Xcode Cloud's Homebrew snapshot can be stale enough that `xcodegen` isn't in
# its local formula index yet (fails fast, not a network issue). Retry once
# with `brew update` before giving up — keeps the common case fast while
# covering the stale-tap case that broke a prior build.
brew install xcodegen || {
  echo "⚠️ brew install xcodegen failed — retrying after brew update…"
  unset HOMEBREW_NO_AUTO_UPDATE
  brew update
  brew install xcodegen
}
export PATH="$(brew --prefix)/bin:$PATH"
which xcodegen
xcodegen version

echo "▸ Generating EEAccess.xcodeproj from project.yml…"
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

echo "▸ Done — project generated for Xcode Cloud."
