#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"

swift test --enable-code-coverage

PROFDATA="$ROOT_DIR/.build/arm64-apple-macosx/debug/codecov/default.profdata"
TEST_BINARY="$ROOT_DIR/.build/arm64-apple-macosx/debug/SpeakFlowPackageTests.xctest/Contents/MacOS/SpeakFlowPackageTests"

REPORT="$(xcrun llvm-cov report "$TEST_BINARY" -instr-profile="$PROFDATA")"

echo "$REPORT"
echo
echo "$REPORT" | awk '
/^Sources\// {
  lines += $8
  missed += $9
}
END {
  if (lines == 0) {
    print "Core source line coverage: unavailable"
  } else {
    printf "Core source line coverage: %.2f%%\n", ((lines - missed) / lines) * 100
  }
}'
