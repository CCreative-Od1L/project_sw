#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "iOS build failed: $*" >&2
  exit 1
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${REPO_ROOT:-$(cd -- "${script_dir}/.." && pwd)}"
repo_root="$(cd -- "${repo_root}" && pwd)" || \
  fail "repository root is unavailable: ${repo_root}"
cd -- "${repo_root}" || fail "cannot enter repository root: ${repo_root}"

usage() {
  cat <<'USAGE'
Usage: scripts/build_ios.sh <unsigned-debug|unsigned-release>

Modes:
  unsigned-debug    Build an unsigned debug iOS app bundle.
  unsigned-release  Build an unsigned release iOS app bundle.

Signed builds intentionally require a separate, configured release signing
lane and never silently downgrade to an unsigned artifact.

Set FLUTTER_COMMAND when the Flutter executable needs a wrapper, for example:
  FLUTTER_COMMAND='fvm flutter' scripts/build_ios.sh unsigned-release
USAGE
}

mode="${1:-}"
if [[ "${mode}" == '--help' || "${mode}" == '-h' ]]; then
  usage
  exit 0
fi

case "${mode}" in
  unsigned-debug)
    build_args=(ios --debug --no-codesign --no-pub)
    ;;
  unsigned-release)
    build_args=(ios --release --no-codesign --no-pub)
    ;;
  signed-release)
    fail 'signed iOS builds require the configured macOS signing lane; no unsigned fallback is allowed'
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

[[ "$(uname -s)" == 'Darwin' ]] || \
  fail 'iOS builds require macOS and Xcode'

flutter_command=(flutter)
if [[ -n "${FLUTTER_COMMAND:-}" ]]; then
  read -r -a flutter_command <<< "${FLUTTER_COMMAND}"
fi
command -v "${flutter_command[0]}" >/dev/null 2>&1 || \
  fail "Flutter command is unavailable: ${flutter_command[*]}"

"${flutter_command[@]}" build "${build_args[@]}"
artifact='build/ios/iphoneos/Runner.app'
[[ -d "${artifact}" ]] || fail "expected artifact is missing: ${artifact}"
echo "iOS artifact created: ${artifact}"
