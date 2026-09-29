#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/lib.sh"
net=${host%.*}
scan() {
  for i in $(seq 1 254); do
    (timeout 0.4 bash -c "echo > /dev/tcp/$net.$i/22" 2>/dev/null && echo "$net.$i") &
  done
  wait
}
baseline=$(scan | sort)
while true; do
  for ip in "$host" $(comm -13 <(echo "$baseline") <(scan | sort)); do
    if [ "$(ssh $ssh_opts -o BatchMode=yes "root@$ip" hostname 2>/dev/null)" = frame-nixos ]; then
      echo "$ip"
      exit 0
    fi
  done
  sleep 5
done
