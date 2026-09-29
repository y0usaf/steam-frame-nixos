{
  lib,
  pkgs,
  rootUuid,
  ...
}:
let
  valve = pkgs.callPackage ./valve.nix { };
in
{
  boot.loader.external = {
    enable = true;
    installHook = pkgs.writeShellScript "frame-install-boot" ''
      set -euo pipefail
      export PATH=${
        lib.makeBinPath [
          pkgs.coreutils
          pkgs.util-linux
        ]
      }

      fail() {
        printf '%s\n' "$*" >&2
        exit 1
      }

      [ "$#" -eq 1 ] || fail "Expected one NixOS system path."
      [ -d "$1" ] || fail "NixOS system path does not exist: $1"
      kernel=$(readlink -e -- "$1/kernel") || fail "Cannot resolve the system kernel."
      initrd=$(readlink -e -- "$1/initrd") || fail "Cannot resolve the system initrd."
      dtbDir=$(dirname -- "$kernel")/dtbs/qcom
      shopt -s nullglob
      dtbs=("$dtbDir"/sm8650-*.dtb)
      [ "''${#dtbs[@]}" -gt 0 ] || fail "The kernel has no sm8650 device trees."
      for source in "$kernel" "$initrd" "$dtbDir/sm8650-mp.dtb" "''${dtbs[@]}"; do
        [ -f "$source" ] && [ -s "$source" ] || fail "Boot source is missing or empty: $source"
      done

      [ -d /boot ] || fail "/boot does not exist."
      actualUuid=$(findmnt -n -o UUID -T /boot) || fail "Cannot identify the /boot filesystem."
      [ "''${actualUuid,,}" = "${lib.toLower rootUuid}" ] || fail "/boot is on UUID $actualUuid; expected ${lib.toLower rootUuid}."
      [ ! -L /boot/dtbqcom ] || fail "/boot/dtbqcom must not be a symbolic link."
      [ ! -e /boot/dtbqcom ] || [ -d /boot/dtbqcom ] || fail "/boot/dtbqcom is not a directory."

      stage=$(mktemp -d /boot/.frame-boot.XXXXXX)
      trap 'rm -rf -- "$stage"' EXIT
      trap 'exit 1' HUP INT TERM
      mkdir -- "$stage/dtbqcom"
      install -m 0644 -- "$kernel" "$stage/Image"
      install -m 0644 -- "$dtbDir/sm8650-mp.dtb" "$stage/maindtb.dtb"
      install -m 0644 -- "''${dtbs[@]}" "$stage/dtbqcom/"
      ${pkgs.ubootTools}/bin/mkimage -A arm64 -O linux -T ramdisk -C none -a 0 -e 0 -n "" -d "$initrd" "$stage/initrd.uImage" >/dev/null
      sync -f "$stage"

      mkdir -p -- /boot/dtbqcom
      for dtb in "$stage"/dtbqcom/*.dtb; do
        mv -fT -- "$dtb" "/boot/dtbqcom/$(basename -- "$dtb")"
      done
      mv -fT -- "$stage/maindtb.dtb" /boot/maindtb.dtb
      mv -fT -- "$stage/Image" /boot/Image
      mv -fT -- "$stage/initrd.uImage" /boot/initrd.uImage
      sync -f /boot
    '';
  };

  systemd.services.frame-slot-good = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "sshd.service" ];
    after = [ "sshd.service" ];
    unitConfig.ConditionKernelCommandLine = "rauc.slot=A";
    path = [
      valve.splctl
      pkgs.util-linux
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      cd /dev/disk/by-partlabel
      trap 'blockdev --setro bootenv bootenvb' EXIT
      blockdev --setrw bootenv bootenvb
      splctl set-state A good
      splctl get-boot-count A
    '';
  };
}
