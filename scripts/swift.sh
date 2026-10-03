#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/cache/clang .build/cache/swift .build/cache/pm
export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache/clang"
export SWIFT_MODULECACHE_PATH="$PWD/.build/cache/swift"
sdk="${DAYFOLIO_SDK:-$(xcrun --show-sdk-path)}"
# A stable SDK is needed when CLT's preview SDK lacks its matching macro plugins.
if [[ -z "${DAYFOLIO_SDK:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
operation="${1:-build}"
if [[ $# -gt 0 ]]; then shift; fi
exec swift "$operation" --sdk "$sdk" --cache-path "$PWD/.build/cache/pm" --disable-sandbox "$@"
