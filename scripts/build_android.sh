#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "Android build failed: $*" >&2
  exit 1
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${REPO_ROOT:-$(cd -- "${script_dir}/.." && pwd)}"
repo_root="$(cd -- "${repo_root}" && pwd)" || \
  fail "repository root is unavailable: ${repo_root}"
cd -- "${repo_root}" || fail "cannot enter repository root: ${repo_root}"

usage() {
  cat <<'USAGE'
Usage: scripts/build_android.sh <debug-apk|release-aab>

Modes:
  debug-apk    Build the unsigned development APK.
  release-aab  Build the release AAB using the required signing seam.

Set FLUTTER_COMMAND when the Flutter executable needs a wrapper, for example:
  FLUTTER_COMMAND='fvm flutter' scripts/build_android.sh debug-apk

For Flutter 3.44.7 Android release builds, run pub-enabled tooling after the
locked dependencies have been resolved:
  FLUTTER_BUILD_WITH_PUB=1 scripts/build_android.sh release-aab
USAGE
}

mode="${1:-}"
if [[ "${mode}" == '--help' || "${mode}" == '-h' ]]; then
  usage
  exit 0
fi

case "${mode}" in
  debug-apk)
    build_args=(apk --debug --no-pub)
    artifact='build/app/outputs/flutter-apk/app-debug.apk'
    ;;
  release-aab)
    build_args=(appbundle --release)
    if [[ "${FLUTTER_BUILD_WITH_PUB:-0}" != '1' ]]; then
      build_args+=(--no-pub)
    fi
    artifact='build/app/outputs/bundle/release/app-release.aab'
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

flutter_command=(flutter)
if [[ -n "${FLUTTER_COMMAND:-}" ]]; then
  read -r -a flutter_command <<< "${FLUTTER_COMMAND}"
fi
command -v "${flutter_command[0]}" >/dev/null 2>&1 || \
  fail "Flutter command is unavailable: ${flutter_command[*]}"

"${flutter_command[@]}" build "${build_args[@]}"
[[ -f "${artifact}" ]] || fail "expected artifact is missing: ${artifact}"
echo "Android artifact created: ${artifact}"
