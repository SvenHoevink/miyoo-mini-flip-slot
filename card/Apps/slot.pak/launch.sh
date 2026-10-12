#!/bin/sh
# Launcher entry (Allium layout: Apps/<Name>.pak/).
cd "$(dirname "$0")" || exit 1
root="$(cd ../.. && pwd)"
SLOT_ROOT="$root" exec sh "$root/System/launch_frontend.sh"
