#!/bin/bash
# Dev helper for the Monterey port: real (non-typecheck) compile of the app, fan helper and Now Playing adapter.
cd "$(dirname "$0")"; mkdir -p build/obj
TARGET="$(uname -m)-apple-macosx12.3"; SDK="$(xcrun --show-sdk-path)"
OPT="${OPT:--Onone}"
COMMON=(-target "$TARGET" -sdk "$SDK" -import-objc-header Sources/MontereyCompat/Bridging.h)
echo "== app ($OPT) $(date)"
swiftc $OPT -j "$(sysctl -n hw.logicalcpu)" -enable-batch-mode -module-name UnupunctMacTab "${COMMON[@]}" \
  -I Sources/VMStatisticsCompat -I Sources/HIDEventSystem \
  $(find Sources/UnupunctMacTab -name '*.swift' | sort) -o build/UnupunctMacTab > build/compile-app.log 2>&1
echo "app exit: $?  errors: $(grep -c 'error:' build/compile-app.log)"
grep 'error:' build/compile-app.log | sed -E 's/:[0-9]+:[0-9]+//' | sort | uniq -c | sort -rn | head -${1:-40}
echo "== done $(date)"
