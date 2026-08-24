#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "CHANGELOG extraction failed: $*" >&2
  exit 1
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${REPO_ROOT:-$(cd -- "${script_dir}/.." && pwd)}"
repo_root="$(cd -- "${repo_root}" && pwd)" || \
  fail "repository root is unavailable: ${repo_root}"

version="${1:-${RELEASE_VERSION:-}}"
[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
  fail 'version must match <MAJOR>.<MINOR>.<PATCH>'

changelog="${repo_root}/CHANGELOG.md"
[[ -f "${changelog}" ]] || fail 'CHANGELOG.md is missing'

awk -v section="## [${version}]" '
  index($0, section) == 1 {
    in_section = 1
    print
    next
  }
  in_section && /^## \[/ { exit }
  in_section { print }
  END {
    if (!in_section) {
      exit 1
    }
  }
' "${changelog}" || fail "CHANGELOG.md has no section for ${version}"
