# SPDX-License-Identifier: MIT
# shellcheck shell=bash
# Sourced by tests. install_fake_curl <dir> puts a fake `curl` first on PATH that serves files from
# $FAKE_CURL_ROOT (URL path without the host, e.g. mtats-releases/latest.json): present → 200,
# absent → 404. FAKE_CURL_CODES="<path>=<code> ..." forces an HTTP status for one path;
# <code> 000 simulates a transport error (curl exits 6). Each call is logged to $FAKE_CURL_LOG.
install_fake_curl() {
  mkdir -p "$1"
  cat >"$1/curl" <<'SH'
#!/usr/bin/env bash
out=""; fmt=""; url=""
while (($#)); do
  case "$1" in
    -o) out="$2"; shift ;;
    -w) fmt="$2"; shift ;;
    --max-time|--retry|--retry-delay|--connect-timeout) shift ;;
    -*) ;;
    *) url="$1" ;;
  esac
  shift
done
path="${url#*://}"; path="${path#*/}"
[[ -n "${FAKE_CURL_LOG:-}" ]] && echo "$url" >>"$FAKE_CURL_LOG"
code=""
for kv in ${FAKE_CURL_CODES:-}; do [[ "${kv%%=*}" == "$path" ]] && code="${kv#*=}"; done
if [[ "$code" == 000 ]]; then [[ -n "$fmt" ]] && printf '000'; echo "curl: (6) Could not resolve host" >&2; exit 6; fi
if [[ -z "$code" ]]; then if [[ -f "$FAKE_CURL_ROOT/$path" ]]; then code=200; else code=404; fi; fi
if [[ "$code" == 200 ]]; then body="$FAKE_CURL_ROOT/$path"; else body=/dev/null; fi
if [[ -n "$out" ]]; then cat "$body" >"$out"; else cat "$body"; fi
[[ -n "$fmt" ]] && printf '%s' "$code"
exit 0
SH
  chmod +x "$1/curl"
  export PATH="$1:$PATH"
}
