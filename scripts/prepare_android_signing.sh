#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "Android signing preparation failed: $*" >&2
  exit 1
}

keystore_base64="${ANDROID_KEYSTORE_BASE64:-}"
keystore_path="${ANDROID_KEYSTORE_PATH:-}"
[[ -n "${keystore_base64}" ]] || \
  fail 'ANDROID_KEYSTORE_BASE64 is required'
[[ -n "${keystore_path}" ]] || \
  fail 'ANDROID_KEYSTORE_PATH is required'

if [[ -n "${GITHUB_WORKSPACE:-}" && "${keystore_path}" == "${GITHUB_WORKSPACE}"/* ]]; then
  fail 'the signing keystore must be outside the GitHub workspace'
fi

keystore_directory="$(dirname -- "${keystore_path}")"
[[ -d "${keystore_directory}" ]] || \
  fail 'the signing keystore directory does not exist'
[[ ! -L "${keystore_path}" ]] || \
  fail 'the signing keystore path must not be a symbolic link'

umask 077
if ! printf '%s' "${keystore_base64}" | base64 --decode > "${keystore_path}"; then
  rm -f -- "${keystore_path}"
  fail 'ANDROID_KEYSTORE_BASE64 is not valid base64'
fi

[[ -s "${keystore_path}" ]] || {
  rm -f -- "${keystore_path}"
  fail 'the decoded signing keystore is empty'
}

chmod 600 "${keystore_path}"
echo 'Android signing keystore prepared outside the workspace.'
