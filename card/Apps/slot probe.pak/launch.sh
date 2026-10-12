#!/bin/sh
# Launcher entry (Allium layout: Apps/<Name>.pak/). Same two-levels-up walk to
# the card root as the App/ variant, and the same shared probe.
cd "$(dirname "$0")" || exit 1
root="$(cd ../.. && pwd)"
exec sh "$root/System/probe-run.sh" "$root"
