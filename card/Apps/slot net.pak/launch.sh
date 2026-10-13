#!/bin/sh
# Launcher entry: bring the handheld onto the network. The work is in
# System/net-up.sh, which the boot hook also uses when slot is booted instead
# of Allium.
cd "$(dirname "$0")" || exit 1
root="$(cd ../.. && pwd)"
exec sh "$root/System/net-up.sh" "$root" "$root/slot-net.txt"
