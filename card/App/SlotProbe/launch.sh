#!/bin/sh
# Launcher entry (stock / Onion layout: App/<Name>/). The probe itself lives at
# System/probe.sh so one copy serves every launcher layout.
cd "$(dirname "$0")" || exit 1
root="$(cd ../.. && pwd)"
exec sh "$root/System/probe-run.sh" "$root"
