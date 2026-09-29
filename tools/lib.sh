repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
host=${FRAME_HOST:?set FRAME_HOST to the address of the Frame}
ssh_opts="-i $HOME/.ssh/id_rsa_frame -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=error -o ConnectTimeout=10 -o ControlMaster=no -o ControlPath=none"
stage=${XDG_RUNTIME_DIR:?}/agent/frame-nixos

qemu_store() {
  local i
  i=$(awk '$1 == "interpreter" { print $2 }' /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null || true)
  if [ -z "$i" ]; then
    echo "qemu-aarch64 binfmt is not registered; run: sudo $repo/tools/binfmt.sh" >&2
    return 1
  fi
  echo "${i%/bin/*}"
}

build() {
  local q
  q=$(qemu_store)
  nix build --no-link --print-out-paths "path:$repo#$1" \
    --option extra-platforms aarch64-linux --option extra-sandbox-paths "$q"
}

frame() { ssh $ssh_opts "root@$host" "$@"; }
steamos() { ssh $ssh_opts "steamos@$host" "$@"; }
