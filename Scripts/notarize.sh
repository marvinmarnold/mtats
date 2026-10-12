#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: notarize.sh <path.app|path.dmg>
# Auth: NOTARY_KEYCHAIN_PROFILE (local, e.g. mtats-notary) or
#       APPLE_NOTARY_KEY_FILE + APPLE_NOTARY_KEY_ID + APPLE_NOTARY_ISSUER_ID (CI).
set -euo pipefail
TARGET="$1"
if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then AUTH=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
else AUTH=(--key "$APPLE_NOTARY_KEY_FILE" --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER_ID"); fi
SUBMIT="$TARGET"
if [[ "$TARGET" == *.app ]]; then
  SUBMIT="$(mktemp -d)/$(basename "${TARGET%.app}").zip"
  ditto -c -k --keepParent "$TARGET" "$SUBMIT"
fi
RESULT=$(xcrun notarytool submit "$SUBMIT" "${AUTH[@]}" --wait --timeout 30m --output-format json)
echo "$RESULT"
STATUS=$(/usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' <<<"$RESULT")
ID=$(/usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$RESULT")
if [[ "$STATUS" != "Accepted" ]]; then
  xcrun notarytool log "$ID" "${AUTH[@]}" >&2
  echo "notarize.sh: $TARGET was $STATUS" >&2; exit 1
fi
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
