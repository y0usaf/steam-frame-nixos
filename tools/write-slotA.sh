#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"
img=$stage/rootfs.img
[ -s "$img" ] && [ -s "$stage/rootfs.sha256" ]
steamos 'if findmnt -rn /run/nixos-slotA >/dev/null; then sudo -n umount /run/nixos-slotA; fi; grep -q "rauc.slot=B" /proc/cmdline && [ "$(lsblk -no PARTLABEL /dev/sda4)" = rootfs-A ] && ! findmnt -rn -S /dev/sda4 >/dev/null'
ro=$(steamos 'sudo -n blockdev --getro /dev/sda4')
[ "$ro" = 1 ] && steamos 'sudo -n blockdev --setrw /dev/sda4'
zstd -T0 -3 -c "$img" | steamos 'zstd -dc | sudo -n dd of=/dev/sda4 bs=4M conv=fsync status=none'
remote=$(steamos "sudo -n head -c $(stat -c %s "$img") /dev/sda4 | sha256sum" | cut -d" " -f1)
[ "$ro" = 1 ] && steamos 'sudo -n blockdev --setro /dev/sda4'
[ "$remote" = "$(cat "$stage/rootfs.sha256")" ]
rm -f "$img" "$stage/rootfs.sha256"
