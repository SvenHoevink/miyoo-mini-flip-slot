#!/bin/sh
# core_pattern wrapper. The kernel runs the pipe program with no environment of
# ours, so the card path has to be set here rather than inherited; upstream's
# coresave.sh defaults to /mnt/sdcard, which is the Anbernic path.
AGS_CARD=/mnt/SDCARD exec /bin/sh /mnt/SDCARD/System/coresave.sh "$@"
