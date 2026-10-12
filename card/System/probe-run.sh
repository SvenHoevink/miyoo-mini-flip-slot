#!/bin/sh
# Run the probe and leave its report where it can be found from a desktop.
# Called by every launcher entry; $1 is the card root.
root="${1:-/mnt/SDCARD}"
out="$root/slot-probe.txt"

sh "$root/System/probe.sh" "$root" > "$out" 2>&1
sync
