#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-/tmp/capache-overnight}"
CYCLES="${CYCLES:-8}"
SLEEP_SECONDS="${SLEEP_SECONDS:-300}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IOS_DERIVED_DATA="${IOS_DERIVED_DATA:-/tmp/capache-overnight-ios-dd}"
MAC_DERIVED_DATA="${MAC_DERIVED_DATA:-/tmp/capache-overnight-mac-dd}"

mkdir -p "$LOG_DIR"
cd "$ROOT_DIR" || exit 1

run_step() {
  local cycle="$1"
  local name="$2"
  shift 2

  local log_file="$LOG_DIR/${cycle}-${name}.log"
  printf '[%s] cycle %s: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$cycle" "$name"

  if "$@" >"$log_file" 2>&1; then
    printf '[%s] cycle %s: %s passed\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$cycle" "$name"
    return 0
  fi

  printf '[%s] cycle %s: %s failed, log: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$cycle" "$name" "$log_file"
  tail -n 120 "$log_file"
  return 1
}

for ((cycle = 1; cycle <= CYCLES; cycle++)); do
  run_step "$cycle" diff-check git diff --check || exit 1
  run_step "$cycle" ios-tests env DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild \
    -project cache.xcodeproj \
    -scheme cache \
    -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
    -derivedDataPath "$IOS_DERIVED_DATA" \
    test || exit 1
  run_step "$cycle" mac-catalyst-build env DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild \
    -project cache.xcodeproj \
    -scheme cache \
    -configuration Debug \
    -destination 'generic/platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath "$MAC_DERIVED_DATA" \
    build || exit 1

  if (( cycle < CYCLES )); then
    printf '[%s] cycle %s complete; sleeping %s seconds\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$cycle" "$SLEEP_SECONDS"
    sleep "$SLEEP_SECONDS"
  fi
done

printf '[%s] overnight verification complete: %s cycles passed\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$CYCLES"
