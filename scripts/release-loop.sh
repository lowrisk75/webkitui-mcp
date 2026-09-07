#!/bin/sh
# Local evidence controller only. No provider calls, signing or installation.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec python3 "$root/scripts/release_loop.py" "$@"
