#!/bin/sh
# Entry point the Miyoo launcher calls. It runs us with the app directory as cwd.
# Everything of substance is in probe.sh; this only decides where to write.
cd "$(dirname "$0")" || exit 1

# Walk up to the card root: the launcher lives at <root>/App/SlotProbe.
root="$(cd ../.. && pwd)"
out="$root/slot-probe.txt"

sh ./probe.sh "$root" > "$out" 2>&1
cp -f "$out" ./slot-probe.txt 2>/dev/null
sync
