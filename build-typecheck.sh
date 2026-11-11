#!/bin/bash
# Dev helper for the Monterey port: type-check the app against the active SDK at the macOS 12 target.
cd "$(dirname "$0")"; mkdir -p build
swiftc -typecheck -target "$(uname -m)-apple-macosx12.3" -sdk "$(xcrun --show-sdk-path)" \
  -import-objc-header Sources/MontereyCompat/Bridging.h -I Sources/VMStatisticsCompat -I Sources/HIDEventSystem \
  $(find Sources/Vorssaint -name '*.swift' | sort) > build/typecheck.log 2>&1
echo "errors: $(grep -c 'error:' build/typecheck.log)"
grep 'error:' build/typecheck.log | sed -E 's/:[0-9]+:[0-9]+//' | sort | uniq -c | sort -rn | head -${1:-60}
