#!/usr/bin/env bash
set -euo pipefail

PREFIX="/usr/local/bin"
DRY_RUN=0
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"

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

  log "Installing into $PREFIX"

  if [[ "$DRY_RUN" -eq 0 ]]; then
    mkdir -p "$PREFIX"
  fi

  install_file "$SCRIPT_DIR/git-smart" "$PREFIX/git-smart"
  install_file "$SCRIPT_DIR/git-smart-push" "$PREFIX/git-smart-push"

  log "Done."
  log "You can now run:"
  printf '    %s\n' "${PREFIX}/git-smart"
}

main "$@"
