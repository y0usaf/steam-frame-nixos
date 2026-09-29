#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] && exit 0
q=$(nix build --no-link --print-out-paths --inputs-from "path:$repo" nixpkgs#qemu-user)
printf '%s' ":qemu-aarch64:M::\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:$q/bin/qemu-aarch64:F" > /proc/sys/fs/binfmt_misc/register
