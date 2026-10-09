#!/usr/bin/env bash
# Runs swift with the right SDK: scripts/dev.sh build | run | test [args…]
#
# Incremental builds with only the Command Line Tools sometimes lose track of the macro
# plugins ("plugin for module 'TestingMacros' not found"). When that happens, this retries
# once from a clean build.
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="$(scripts/sdk.sh)"
if [[ -n "$sdk" ]]; then export SDKROOT="$sdk"; fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
if swift "$@" 2>&1 | tee "$log"; then
    exit 0
fi
if grep -q "plugin for module .* not found" "$log"; then
    echo "dev.sh: stale macro plugin state; retrying from a clean build…" >&2
    rm -rf .build
    exec swift "$@"
fi
exit 1
