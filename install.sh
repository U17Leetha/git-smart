#!/usr/bin/env bash
set -euo pipefail

PREFIX="/usr/local/bin"
DRY_RUN=0
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
OS_NAME="$(uname -s)"

usage() {
  cat <<'USAGE'
Usage: install.sh [options]

Options:
  --prefix DIR   Install into DIR instead of /usr/local/bin
  --dry-run      Show what would be installed without changing anything
  -h, --help     Show this help
USAGE
}

log() {
  printf '[*] %s\n' "$1"
}

warn() {
  printf '[!] %s\n' "$1" >&2
}

hint_for_required() {
  local cmd="$1"

  case "$OS_NAME" in
    Darwin)
      case "$cmd" in
        git) printf 'Install Xcode Command Line Tools with: xcode-select --install\n' ;;
        ssh) printf 'OpenSSH is usually present on macOS. Verify your PATH or install developer tools.\n' ;;
      esac
      ;;
    Linux)
      case "$cmd" in
        git) printf 'Install git with your package manager, for example: sudo apt install git\n' ;;
        ssh) printf 'Install OpenSSH client, for example: sudo apt install openssh-client\n' ;;
      esac
      ;;
  esac
}

hint_for_optional() {
  local cmd="$1"

  case "$OS_NAME" in
    Darwin)
      case "$cmd" in
        gh) printf 'Optional: install GitHub CLI with Homebrew: brew install gh\n' ;;
        pbcopy) printf 'pbcopy is normally built into macOS.\n' ;;
        open) printf 'open is normally built into macOS.\n' ;;
      esac
      ;;
    Linux)
      case "$cmd" in
        gh) printf 'Optional: install GitHub CLI, for example: sudo apt install gh\n' ;;
        xclip) printf 'Optional: install xclip for clipboard support: sudo apt install xclip\n' ;;
        wl-copy) printf 'Optional: install wl-clipboard for Wayland clipboard support.\n' ;;
        xdg-open) printf 'Optional: install xdg-utils for browser integration.\n' ;;
      esac
      ;;
  esac
}

require_command() {
  local cmd="$1"

  if ! command -v "$cmd" >/dev/null 2>&1; then
    warn "Missing required dependency: $cmd"
    hint_for_required "$cmd" >&2 || true
    exit 1
  fi
}

check_optional_command() {
  local cmd="$1"
  local feature="$2"

  if ! command -v "$cmd" >/dev/null 2>&1; then
    warn "Optional dependency missing: $cmd ($feature)"
    hint_for_optional "$cmd" >&2 || true
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prefix)
        [[ $# -ge 2 ]] || {
          printf '[!] --prefix requires a value\n' >&2
          exit 1
        }
        PREFIX="$2"
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        printf '[!] Unknown option: %s\n' "$1" >&2
        exit 1
        ;;
    esac
    shift
  done
}

check_dependencies() {
  log 'Checking required dependencies...'
  require_command git
  require_command ssh
  require_command install
  require_command mkdir

  log 'Checking optional integrations...'
  check_optional_command gh 'GitHub repo creation during git-smart init'

  case "$OS_NAME" in
    Darwin)
      check_optional_command pbcopy 'clipboard support during git-smart setup'
      check_optional_command open 'git-smart open browser integration'
      ;;
    Linux)
      check_optional_command xdg-open 'git-smart open browser integration'
      check_optional_command wl-copy 'Wayland clipboard support during git-smart setup'
      check_optional_command xclip 'X11 clipboard support during git-smart setup'
      ;;
  esac
}

install_file() {
  local src="$1"
  local dest="$2"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[*] Dry run: install -m 755 %s %s\n' "$src" "$dest"
  else
    install -m 755 "$src" "$dest"
  fi
}

main() {
  parse_args "$@"

  [[ -f "$SCRIPT_DIR/git-smart" ]] || {
    printf '[!] Missing git-smart in %s\n' "$SCRIPT_DIR" >&2
    exit 1
  }
  [[ -f "$SCRIPT_DIR/git-smart-push" ]] || {
    printf '[!] Missing git-smart-push in %s\n' "$SCRIPT_DIR" >&2
    exit 1
  }

  check_dependencies
  log "Installing into $PREFIX"

  if [[ "$DRY_RUN" -eq 0 ]]; then
    mkdir -p "$PREFIX"
  fi

  install_file "$SCRIPT_DIR/git-smart" "$PREFIX/git-smart"
  install_file "$SCRIPT_DIR/git-smart-push" "$PREFIX/git-smart-push"

  log 'Done.'
  log 'You can now run:'
  printf '    %s\n' "${PREFIX}/git-smart"
}

main "$@"
