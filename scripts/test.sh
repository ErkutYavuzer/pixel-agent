#!/usr/bin/env bash
# Clean build + full test run harness.
#
# **Sprint 30 (v0.2.55):** v0.2.37+ documented intermittent LANFramingTests
# SIGSEGV/SIGBUS in `swift test` ardışık runs. Root cause: stale build cache
# / partial recompile memory layout sensitivity (heisenbug — debug prints
# eklemekle veya clean rebuild ile düzeliyor). Bu script clean rebuild
# garantisi sağlar — local development + CI için tutarlı çıktı.
#
# Idempotent: her seferinde aynı şey. Output stdout'a — exit code testin
# kendisi (0 = pass, ≠0 = fail).
#
# Usage:
#   scripts/test.sh           # full clean rebuild + run
#   scripts/test.sh --quick   # build cache'i koru, sadece swift test

set -e

QUICK_MODE=0
for arg in "$@"; do
    case "$arg" in
        --quick) QUICK_MODE=1 ;;
        *) echo "Unknown arg: $arg"; exit 64 ;;
    esac
done

cd "$(dirname "$0")/.."

if [ "$QUICK_MODE" -eq 0 ]; then
    echo "→ Cleaning build artifacts..."
    rm -rf .build
fi

echo "→ swift test..."
swift test 2>&1 | tee /tmp/pixel-agent-test.log

EXIT_CODE=${PIPESTATUS[0]}

# Summary: total tests run + failure count.
TOTAL=$(awk '/Executed [0-9]+ tests/ { gsub("\t",""); split($0, a, " tests"); split(a[1], b, " "); sum += b[2]; } END { print sum }' /tmp/pixel-agent-test.log)
FAILS=$(grep -c "FAILED" /tmp/pixel-agent-test.log || true)
CRASH=$(grep -E "unexpected signal" /tmp/pixel-agent-test.log | head -1 || true)

echo ""
echo "════════════════════════════════════════"
if [ "$EXIT_CODE" -eq 0 ]; then
    echo "✅ PASS — $TOTAL tests"
else
    echo "❌ FAIL — exit $EXIT_CODE"
    if [ -n "$CRASH" ]; then
        echo "   $CRASH"
        echo "   Tip: clean rebuild flake'i çözebilir → scripts/test.sh (clean mode)"
    fi
fi
echo "════════════════════════════════════════"

exit "$EXIT_CODE"
