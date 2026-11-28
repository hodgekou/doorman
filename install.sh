#!/bin/bash
# Doorman installer
#
#   Install or update (latest release):
#     curl -fsSL https://raw.githubusercontent.com/hodgekou/doorman/main/install.sh | bash
#
#   Install a specific version:
#     curl -fsSL https://raw.githubusercontent.com/hodgekou/doorman/main/install.sh | bash -s -- --version v0.1.0
#
#   Uninstall (add --purge to also remove settings and history):
#     curl -fsSL https://raw.githubusercontent.com/hodgekou/doorman/main/install.sh | bash -s -- --uninstall
#
# What it does: downloads Doorman.dmg from GitHub Releases, verifies its SHA-256
# checksum, code signature and bundle identifier, then copies Doorman.app to
# /Applications and opens it. It only ever replaces an app with Doorman's bundle ID.

set -euo pipefail

REPO="hodgekou/doorman"
BUNDLE_ID="dev.doorman.Doorman"
DEST="/Applications/Doorman.app"
MIN_MACOS_MAJOR=13

VERSION=""
UNINSTALL=0
PURGE=0
OPEN_APP=1
TMP=""
MOUNT=""
STAGE=""
LOCK="/Applications/.Doorman.install.lock"
LOCK_HELD=0

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mWarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: install.sh [--version vX.Y.Z] [--no-open]
       install.sh --uninstall [--purge]

  --version vX.Y.Z   Install a specific release instead of the latest
  --no-open          Don't open Doorman after installing
  --uninstall        Remove /Applications/Doorman.app
  --purge            With --uninstall, also remove settings and lock history
EOF
}

cleanup() {
  if [ -n "$STAGE" ]; then
    # Keep the previous bundle recoverable if the replacement was interrupted.
    if run_privileged test -d "$STAGE/previous.app"; then
      if [ ! -e "$DEST" ]; then
        run_privileged mv "$STAGE/previous.app" "$DEST" || warn "Previous app saved in $STAGE/previous.app"
      fi
    fi
    if ! run_privileged test -d "$STAGE/previous.app"; then
      run_privileged rm -rf "$STAGE"
    fi
  fi
  if [ "$LOCK_HELD" -eq 1 ]; then
    run_privileged unlink "$LOCK"
  fi
  if [ -n "$MOUNT" ] && [ -d "$MOUNT" ]; then
    hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || hdiutil detach "$MOUNT" -force -quiet >/dev/null 2>&1 || true
  fi
  if [ -n "$TMP" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --version)
        [ $# -ge 2 ] || die "--version needs a value, e.g. --version v0.1.0"
        VERSION="$2"; shift 2 ;;
      --uninstall) UNINSTALL=1; shift ;;
      --purge) PURGE=1; shift ;;
      --no-open) OPEN_APP=0; shift ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; die "Unknown option: $1" ;;
    esac
  done
  if [ -n "$VERSION" ]; then
    [[ "$VERSION" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid version: $VERSION (expected v1.2.3)"
    case "$VERSION" in v*) ;; *) VERSION="v$VERSION" ;; esac
  fi
}

check_system() {
  [ "$(uname -s)" = "Darwin" ] || die "Doorman only runs on macOS."
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  [ "$major" -ge "$MIN_MACOS_MAJOR" ] 2>/dev/null || die "Doorman needs macOS $MIN_MACOS_MAJOR or later (this Mac: $(sw_vers -productVersion))."
}

bundle_id_of() {
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$1/Contents/Info.plist" 2>/dev/null || true
}

# Use sudo only when /Applications isn't writable by the current user.
run_privileged() {
  if [ -w "/Applications" ]; then
    "$@"
  else
    sudo "$@"
  fi
}

quit_running_app() {
  if pgrep -x Doorman >/dev/null 2>&1; then
    say "Quitting the running Doorman…"
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    local i=0
    while pgrep -x Doorman >/dev/null 2>&1 && [ $i -lt 10 ]; do
      sleep 0.5; i=$((i + 1))
    done
    pkill -x Doorman >/dev/null 2>&1 || true
  fi
}

ensure_replaceable() {
  if [ -e "$DEST" ]; then
    local existing
    existing="$(bundle_id_of "$DEST")"
    [ "$existing" = "$BUNDLE_ID" ] || die "$DEST exists but isn't Doorman (bundle ID: ${existing:-unknown}). Not touching it."
  fi
}

lock_destination() {
  run_privileged /usr/bin/shlock -p "$$" -f "$LOCK" || die "Another Doorman install or uninstall is in progress, or /Applications is not writable."
  LOCK_HELD=1
}

uninstall() {
  if [ -e "$DEST" ]; then
    lock_destination
  fi
  ensure_replaceable
  quit_running_app
  local removed=0
  if [ -e "$DEST" ]; then
    say "Removing $DEST"
    run_privileged rm -rf "$DEST"
    removed=1
  else
    warn "$DEST wasn't found, so there was no app to remove."
  fi
  if [ "$PURGE" -eq 1 ]; then
    say "Removing settings and lock history"
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    rm -rf "$HOME/Library/Application Support/Doorman"
  fi
  if [ "$removed" -eq 1 ]; then
    say "Doorman has been uninstalled."
  elif [ "$PURGE" -eq 1 ]; then
    say "Settings and lock history have been removed."
  else
    say "Nothing to uninstall."
  fi
}

install() {
  local base
  if [ -n "$VERSION" ]; then
    base="https://github.com/$REPO/releases/download/$VERSION"
  else
    base="https://github.com/$REPO/releases/latest/download"
  fi

  TMP="$(mktemp -d)"

  say "Downloading Doorman${VERSION:+ $VERSION}…"
  curl -fL --proto '=https' --tlsv1.2 --retry 3 --progress-bar -o "$TMP/Doorman.dmg" "$base/Doorman.dmg" \
    || die "Download failed. Check your network, or download the DMG from https://github.com/$REPO/releases"
  curl -fsSL --proto '=https' --tlsv1.2 --retry 3 -o "$TMP/Doorman.dmg.sha256" "$base/Doorman.dmg.sha256" \
    || die "Couldn't download the checksum file."

  say "Verifying checksum…"
  local expected actual
  expected="$(awk '{print $1; exit}' "$TMP/Doorman.dmg.sha256")"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || die "The checksum file is malformed."
  actual="$(shasum -a 256 "$TMP/Doorman.dmg" | awk '{print $1}')"
  [ "$expected" = "$actual" ] || die "Checksum mismatch. The download may be corrupted; please try again."

  MOUNT="$TMP/mount"
  mkdir -p "$MOUNT"
  hdiutil attach "$TMP/Doorman.dmg" -nobrowse -readonly -noautoopen -mountpoint "$MOUNT" -quiet \
    || die "Couldn't open the disk image."

  local src="$MOUNT/Doorman.app"
  [ -d "$src" ] || die "Doorman.app wasn't found in the disk image."
  [ "$(bundle_id_of "$src")" = "$BUNDLE_ID" ] || die "Unexpected app in the disk image."
  codesign --verify --strict "$src" >/dev/null 2>&1 || die "The app's code signature is invalid."
  local version
  version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$src/Contents/Info.plist" 2>/dev/null || echo "?")"

  ensure_replaceable

  if [ ! -w "/Applications" ]; then
    say "Administrator password needed to write to /Applications."
  fi
  say "Installing Doorman $version to /Applications…"
  lock_destination
  STAGE="$(run_privileged mktemp -d "/Applications/.Doorman.XXXXXXXX")"
  run_privileged ditto "$src" "$STAGE/Doorman.app"
  run_privileged codesign --verify --deep --strict "$STAGE/Doorman.app"
  ensure_replaceable
  quit_running_app
  if [ -e "$DEST" ]; then
    run_privileged mv "$DEST" "$STAGE/previous.app"
  fi
  run_privileged mv "$STAGE/Doorman.app" "$DEST"
  run_privileged rm -rf "$STAGE/previous.app"

  hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true
  MOUNT=""

  say "Doorman $version is installed. Look for its icon in the menu bar."
  if [ "$OPEN_APP" -eq 1 ]; then
    open "$DEST"
  fi
}

main() {
  parse_args "$@"
  check_system
  trap cleanup EXIT
  if [ "$UNINSTALL" -eq 1 ]; then
    uninstall
  else
    install
  fi
}

# Everything runs from main, so a partially downloaded script never executes.
main "$@"
