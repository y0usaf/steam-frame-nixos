{
  config,
  lib,
  pkgs,
  utils,
  rootUuid,
  ...
}:
let
  valve = pkgs.callPackage ./valve.nix { };
  slotA = "/dev/disk/by-uuid/${rootUuid}";
  slotADevice = "${utils.escapeSystemdPath slotA}.device";
  reboot = "${config.boot.initrd.systemd.package}/bin/systemctl --force reboot";
  bootSwap = pkgs.writeShellApplication {
    name = "frame-boot-swap";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
    ];
    text = ''
      usage() {
        echo "usage: frame-boot-swap recovery|pool [boot-dir]" >&2
        exit 2
      }
      if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        usage
      fi
      boot=''${2:-/boot}
      files=(maindtb.dtb Image initrd.uImage)

      install_set() {
        for f in "''${files[@]}"; do
          if [ ! -s "$1/$f" ]; then
            echo "missing $1/$f" >&2
            exit 1
          fi
        done
        for dtb in "$1"/dtbqcom/*.dtb; do
          cp "$dtb" "$boot/dtbqcom/.swap"
          mv -fT "$boot/dtbqcom/.swap" "$boot/dtbqcom/$(basename "$dtb")"
        done
        for f in "''${files[@]}"; do
          cp "$1/$f" "$boot/.$f.swap"
          mv -fT "$boot/.$f.swap" "$boot/$f"
        done
        sync -f "$boot"
      }

      case $1 in
        recovery)
          if ! cmp -s "$boot/initrd.uImage" "$boot/recovery/initrd.uImage"; then
            rm -rf "$boot/pool.new"
            mkdir -p "$boot/pool.new/dtbqcom"
            cp "$boot"/dtbqcom/*.dtb "$boot/pool.new/dtbqcom/"
            for f in "''${files[@]}"; do
              cp "$boot/$f" "$boot/pool.new/$f"
            done
            sync -f "$boot"
            rm -rf "$boot/pool"
            mv -T "$boot/pool.new" "$boot/pool"
            install_set "$boot/recovery"
          fi
          ;;
        pool)
          install_set "$boot/pool"
          rm -f "$boot/attempts"
          ;;
        *)
          usage
          ;;
      esac
      echo "$1"
    '';
  };
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

  environment.systemPackages = [ bootSwap ];

  boot.initrd.systemd.services = lib.mkIf (config.frame.storage.poolUuid != null) {
    frame-boot-attempt = {
      wantedBy = [ "initrd.target" ];
      requires = [ slotADevice ];
      after = [ slotADevice ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = false;
      path = [
        pkgs.coreutils
        pkgs.util-linux
        pkgs.diffutils
        bootSwap
      ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "60s";
      };
      script = ''
        set -euo pipefail
        mkdir -p /run/frame-slot-a
        mount -t btrfs -o rw,subvolid=5 ${slotA} /run/frame-slot-a
        trap 'umount /run/frame-slot-a' EXIT
        boot=/run/frame-slot-a/boot
        attempts=$(cat "$boot/attempts" 2>/dev/null || true)
        case $attempts in
          "" | *[!0-9]*) attempts=0 ;;
        esac
        if [ "$attempts" -ge 3 ]; then
          frame-boot-swap recovery "$boot"
          umount /run/frame-slot-a
          trap - EXIT
          ${reboot}
          exit 0
        fi
        echo $((attempts + 1)) > "$boot/attempts"
        sync -f "$boot"
      '';
    };
    frame-recover-boot = {
      wantedBy = [ "emergency.target" ];
      before = [
        "emergency.service"
        "panic-on-fail.service"
      ];
      unitConfig.DefaultDependencies = false;
      path = [
        pkgs.coreutils
        pkgs.util-linux
        pkgs.diffutils
        bootSwap
      ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "60s";
      };
      script = ''
        set -euo pipefail
        trap '${reboot}' EXIT
        mkdir -p /run/frame-slot-a
        mount -t btrfs -o rw,subvolid=5 ${slotA} /run/frame-slot-a
        frame-boot-swap recovery /run/frame-slot-a/boot
        umount /run/frame-slot-a
      '';
    };
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
      rm -f /boot/attempts
      cd /dev/disk/by-partlabel
      trap 'blockdev --setro bootenv bootenvb' EXIT
      blockdev --setrw bootenv bootenvb
      splctl set-state A good
      splctl get-boot-count A
    '';
  };
}
