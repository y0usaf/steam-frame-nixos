#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"
nm=${1:?usage: stage-slotA.sh /etc/NetworkManager/system-connections/<wifi>.nmconnection}
o=$(build image)
mkdir -p "$stage"
cd "$stage"
zstd -q -d --sparse "$o/frame-nixos-usb.img.zst" -o full.img
dd if=full.img of=rootfs.img bs=512 skip=655394 count=10485760 conv=sparse status=none
rm full.img
total=$(btrfs inspect-internal dump-super rootfs.img | awk '$1 == "total_bytes" { print $2 }')
truncate -s "$total" rootfs.img
mkdir -p mnt
sudo mount -o loop rootfs.img mnt
sudo python3 "$repo/tools/wifi-from-nm.py" "$nm" mnt >/dev/null
sudo umount mnt
rmdir mnt
chmod 600 rootfs.img
sha256sum rootfs.img | cut -d" " -f1 > rootfs.sha256
echo "$stage/rootfs.img"
