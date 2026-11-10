#!/bin/bash
set -euo pipefail

# SOURCE_ROOT may point at an immutable git-archive baseline.
HERE="$(cd "$(dirname "$0")" && pwd)"
SOURCE_ROOT="${1:-$(cd "$HERE/.." && pwd)}"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/float-ownership.XXXXXX")"
trap 'rm -f "$BUILD/native-ownership" "$BUILD/baseline.log"; rm -rf "$BUILD/native-ownership.dSYM"; rmdir "$BUILD"' EXIT

test "$(shasum -a 256 "$SOURCE_ROOT/4D Plugin API/4DPluginAPI.c" | cut -d' ' -f1)" = \
  2721c3d4338cc2a350599ffcee2a8008abaa756acfd45dd710720c64ca8c8ce3

clang++ -std=c++17 -x objective-c++ -include Carbon/Carbon.h \
  -I"$SOURCE_ROOT/4D Plugin API" -I"$SOURCE_ROOT/4D Plugin API/Classes" \
  -fsanitize=address,undefined -fno-omit-frame-pointer -g \
  -Wno-deprecated-declarations -Wno-return-type-c-linkage \
  "$SOURCE_ROOT/4D Plugin API/4DPluginAPI.c" \
  "$SOURCE_ROOT/4D Plugin API/Classes/"*.cpp \
  "$SOURCE_ROOT/4DPlugin.cpp" "$HERE/native_ownership.mm" \
  -framework Cocoa -framework Carbon -o "$BUILD/native-ownership"

export ASAN_OPTIONS=detect_leaks=0
export UBSAN_OPTIONS=halt_on_error=1
if [ "${2:-}" = "--expect-baseline-defects" ]; then
  for case in path path-empty bytes copy copy-empty gray size thumbnail; do
    representation=allocated-empty
    if [ "$case" = path-empty ]; then representation=null-empty; fi
    case "$case" in
      path) expected="ownership assertion: double disposal of string" ;;
      copy) expected="ERROR: AddressSanitizer: heap-buffer-overflow" ;;
      copy-empty) expected="outstanding strings=1 handles=0 pictures=1" ;;
      *) expected="ownership assertion: picture references leaked" ;;
    esac
    if "$BUILD/native-ownership" "$case" "$representation" > "$BUILD/baseline.log" 2>&1; then
      echo "FAIL baseline unexpectedly passed $case" >&2
      exit 1
    fi
    cat "$BUILD/baseline.log"
    grep -Fq "$expected" "$BUILD/baseline.log"
    echo "EXPECTED BASELINE FAILURE $case"
  done
elif [ "$#" -gt 1 ]; then
  "$BUILD/native-ownership" "$2" "${3:-allocated-empty}"
else
  for case in path path-empty bytes copy copy-empty gray size thumbnail arrays scalars callbacks dispatcher; do
    "$BUILD/native-ownership" "$case"
    "$BUILD/native-ownership" "$case" null-empty
  done
  for case in path copy gray size thumbnail; do
    "$BUILD/native-ownership" "$case" fail-command
    "$BUILD/native-ownership" "$case" fail-handle
    "$BUILD/native-ownership" "$case" unchanged
  done
fi
