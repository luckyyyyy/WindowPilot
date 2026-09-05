#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/windowpilot-tests.XXXXXX")"
trap 'rm -rf "$LOG_DIR"' EXIT
run_tests() {
  swift test --sanitize=thread "$@" 2>&1 | tee "$LOG_DIR/result.log"
  # AppKit can stop the async test host's run loop with exit 0. Require a
  # complete Swift Testing summary, not only a successful process status.
  grep -E 'Test run with [1-9][0-9]* tests? .*passed' "$LOG_DIR/result.log" > /dev/null
  if grep -E '✘|WARNING: ThreadSanitizer' "$LOG_DIR/result.log"; then return 1; fi
}
run_tests --skip LocalWindowsTests
swift test --sanitize=thread list --skip-build > "$LOG_DIR/tests.txt"
grep "^WindowPilotTests.LocalWindowsTests/" "$LOG_DIR/tests.txt" > /dev/null
# Native window lifecycle cases use fresh processes to isolate AppKit state.
while IFS= read -r name; do
  case "$name" in
    WindowPilotTests.LocalWindowsTests/*)
      method="${name##*/}"; method="${method%\(\)}"
      run_tests --skip-build --filter "$method"
      ;;
  esac
done < "$LOG_DIR/tests.txt"
