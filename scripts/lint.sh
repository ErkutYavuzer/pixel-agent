#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if command -v swiftlint >/dev/null 2>&1; then
    echo "→ SwiftLint"
    swiftlint lint --quiet
else
    echo "! SwiftLint yüklü değil — atlanıyor (brew install swiftlint)"
fi

if command -v swift-format >/dev/null 2>&1; then
    echo "→ swift-format lint"
    find Sources Tests -name '*.swift' -print0 | xargs -0 swift-format lint --strict
else
    echo "! swift-format yüklü değil — atlanıyor (brew install swift-format)"
fi

echo "✓ Lint tamam"
