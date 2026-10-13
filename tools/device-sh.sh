#!/bin/sh
# Run a command on the handheld over Allium's telnet and print only its output.
#
# telnetd negotiates options before the shell appears and echoes what it is
# sent, so the reply carries control bytes and the command line itself. This
# brackets the real output with a marker and prints what lies between. `exit`
# is appended because otherwise telnetd holds the connection and nc never
# returns.
#
# usage: device-sh.sh <ip> <command...>
set -eu

ip="${1:?usage: device-sh.sh <ip> <command...>}"
shift
cmd="$*"
mark="slot$$mark"

{
	printf '\r\n'
	sleep 1
	printf 'echo %s; %s; exit\r\n' "$mark" "$cmd"
	sleep "${SLOT_WAIT:-3}"
} | nc -w "${SLOT_NC_WAIT:-15}" "$ip" 23 2>/dev/null |
	tr -d '\000\r' |
	sed -n "/^$mark\$/,\$p" |
	sed '1d'
