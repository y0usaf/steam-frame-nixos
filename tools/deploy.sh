#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"
cfg=${1:?usage: tools/deploy.sh FLAKE#nixosConfigurations.NAME}
uuid=$(nix eval --raw "$cfg.config.frame.storage.poolUuid")
if ! frame "[ \"\$(findmnt -n -o UUID --target /)\" = \"$uuid\" ] && [ \"\$(findmnt -n -o FSROOT --target /)\" = /@root ]"; then
  echo "Frame deployment requires the shared Btrfs root; refusing to replace the slot-A recovery profile." >&2
  exit 1
fi
t=$(nix build --no-link --print-out-paths "$cfg.config.system.build.toplevel" \
  --option extra-platforms aarch64-linux --option extra-sandbox-paths "$(qemu_store)")
NIX_SSHOPTS=$ssh_opts nix copy --no-check-sigs --to "ssh-ng://root@$host" "$t"
frame "set -e
nix-env -p /nix/var/nix/profiles/system --set $t
nix-env -p /nix/var/nix/profiles/system --delete-generations +3 >/dev/null
systemd-run --collect --no-ask-password --pipe --quiet --service-type=exec --unit=frame-switch -- $t/bin/switch-to-configuration switch >&2
nix-collect-garbage >/dev/null 2>&1"
echo "$t"
