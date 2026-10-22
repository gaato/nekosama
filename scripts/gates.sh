#!/usr/bin/env bash
# The MoonBit gates: native type check, native tests, and format. CI (ci.yml)
# runs them on the pinned toolchain and the canary (canary.yml) on the latest
# and nightly ones, both through this script so the two cannot drift.
set -euo pipefail
cd "$(dirname "$0")/.."

run() {
  echo "+ $*"
  "$@"
}

run moon check --target native
# The native tests build with gcc rather than moon's default C compiler.
run env MOON_CC=gcc moon test --target native
run moon fmt --check
