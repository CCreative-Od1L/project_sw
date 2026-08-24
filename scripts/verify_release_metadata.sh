#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${REPO_ROOT:-$(cd -- "${script_dir}/.." && pwd)}"
release_tag="${RELEASE_TAG:-${GITHUB_REF_NAME:-}}"
output_file="${OUTPUT_FILE:-${repo_root}/release-metadata.txt}"
require_annotated_tag="${REQUIRE_ANNOTATED_TAG:-0}"

fail() {
  echo "release metadata validation failed: $*" >&2
  exit 1
}

[[ -n "${release_tag}" ]] || fail 'RELEASE_TAG is required'
[[ "${release_tag}" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || \
  fail "tag must match v<MAJOR>.<MINOR>.<PATCH>: ${release_tag}"

tag_version="${BASH_REMATCH[1]}"
pubspec_version="$(sed -n 's/^version: \([^+[:space:]]*\).*$/\1/p' "${repo_root}/pubspec.yaml" | head -n 1)"
[[ -n "${pubspec_version}" ]] || fail 'pubspec.yaml version is missing'
[[ "${pubspec_version}" == "${tag_version}" ]] || \
  fail "tag ${release_tag} does not match pubspec version ${pubspec_version}"

changelog="${repo_root}/CHANGELOG.md"
[[ -f "${changelog}" ]] || fail 'CHANGELOG.md is missing'
grep -Eq "^## \[${tag_version//./\\.}\]( |$)" "${changelog}" || \
  fail "CHANGELOG.md has no section for ${tag_version}"

commit_sha="$(git -C "${repo_root}" rev-parse HEAD)"
tag_commit_sha="${commit_sha}"
if [[ "${require_annotated_tag}" == '1' ]]; then
  [[ "$(git -C "${repo_root}" cat-file -t "${release_tag}" 2>/dev/null || true)" == 'tag' ]] || \
    fail "${release_tag} is not an annotated tag"
  tag_commit_sha="$(git -C "${repo_root}" rev-list -n 1 "${release_tag}")"
  [[ "${tag_commit_sha}" == "${commit_sha}" ]] || \
    fail "HEAD ${commit_sha} is not the commit targeted by ${release_tag}"
fi

flutter_version="$(sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${repo_root}/.fvmrc" | head -n 1)"
[[ -n "${flutter_version}" ]] || fail '.fvmrc does not pin a Flutter version'

if command -v sha256sum >/dev/null 2>&1; then
  lockfile_sha256="$(sha256sum "${repo_root}/pubspec.lock" | awk '{print $1}')"
else
  lockfile_sha256="$(shasum -a 256 "${repo_root}/pubspec.lock" | awk '{print $1}')"
fi

mkdir -p "$(dirname -- "${output_file}")"
{
  echo "release_tag=${release_tag}"
  echo "version=${tag_version}"
  echo "commit_sha=${commit_sha}"
  echo "tag_commit_sha=${tag_commit_sha}"
  echo "flutter_version=${flutter_version}"
  echo "pubspec_lock_sha256=${lockfile_sha256}"
} > "${output_file}"

echo "release metadata validated for ${release_tag} at ${commit_sha}"
