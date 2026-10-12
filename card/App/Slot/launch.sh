#!/bin/sh
# Launch slot from the Miyoo launcher. Expects the card root two levels up.
cd "$(dirname "$0")" || exit 1
root="$(cd ../.. && pwd)"
SLOT_ROOT="$root" exec sh "$root/System/launch_frontend.sh"
