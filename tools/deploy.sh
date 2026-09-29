#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"
t=$(build nixosConfigurations.frame.config.system.build.toplevel)
NIX_SSHOPTS=$ssh_opts nix copy --no-check-sigs --to "ssh-ng://root@$host" "$t"
frame "set -e
nix-env -p /nix/var/nix/profiles/system --set $t
nix-env -p /nix/var/nix/profiles/system --delete-generations +3 >/dev/null
systemd-run --collect --no-ask-password --pipe --quiet --service-type=exec --unit=frame-switch -- $t/bin/switch-to-configuration switch >&2
nix-collect-garbage >/dev/null 2>&1"
echo "$t"
