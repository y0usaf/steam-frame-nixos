{
  config,
  lib,
  pkgs,
  rootUuid,
  ...
}:
let
  valve = pkgs.callPackage ./valve.nix { };
  poolUuid = config.frame.storage.poolUuid;
  sharedPool = poolUuid != null;
  writableUuids = [
    rootUuid
  ]
  ++ lib.optional sharedPool poolUuid
  ++ lib.optional (!sharedPool) "4bac5c02-4a89-4377-8388-ce55ef171552";
  led = color: ''
    echo "${color}" > /sys/class/leds/rgb:status/multi_intensity
    echo 80 > /sys/class/leds/rgb:status/brightness
  '';
in
{
  options.frame.storage.poolUuid = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.strMatching "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
    );
    default = null;
    apply = value: if value == null then null else lib.toLower value;
    description = "UUID of the shared Btrfs storage pool, or null to keep root on slot A.";
  };

  config = {
    assertions = [
      {
        assertion = poolUuid == null || lib.toLower poolUuid != lib.toLower rootUuid;
        message = "The Frame storage pool UUID must differ from the slot-A boot filesystem UUID.";
      }
    ];

    nixpkgs.hostPlatform = "aarch64-linux";
    system.stateVersion = "26.05";

    boot.loader.grub.enable = false;
    boot.kernelPackages = pkgs.linuxPackagesFor valve.kernel;
    hardware.deviceTree.enable = false;
    hardware.firmware = [ valve.firmware ];
    hardware.firmwareCompression = "none";
    boot.initrd.extraFirmwarePaths = [ "qcom/sm8650/qupv3fw.elf" ];

    boot.initrd.systemd.enable = true;
    boot.initrd.includeDefaultModules = false;
    boot.initrd.availableKernelModules = lib.mkForce [ ];
    boot.initrd.kernelModules = lib.mkForce [ ];
    boot.initrd.systemd.storePaths = [ "${pkgs.btrfs-progs}/bin/btrfs" ];
    boot.initrd.systemd.services.grow-root = {
      after = [ "sysroot.mount" ];
      requires = [ "sysroot.mount" ];
      before = [ "initrd-root-fs.target" ];
      requiredBy = [ "initrd-root-fs.target" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.btrfs-progs}/bin/btrfs filesystem resize max /sysroot";
      };
    };
    boot.initrd.services.udev.rules = ''
      ACTION=="add", SUBSYSTEM=="leds", KERNEL=="rgb:status", ATTR{multi_intensity}="0 0 255", ATTR{brightness}="80"
    '';

    fileSystems =
      if sharedPool then
        lib.mapAttrs
          (mount: subvolume: {
            device = "/dev/disk/by-uuid/${poolUuid}";
            fsType = "btrfs";
            options = [
              "subvol=${subvolume}"
              "compress=zstd:3"
              "noatime"
            ];
            neededForBoot = lib.elem mount [
              "/"
              "/nix"
              "/home"
              "/var"
            ];
          })
          {
            "/" = "@root";
            "/nix" = "@nix";
            "/home" = "@home";
            "/games" = "@games";
            "/var" = "@var";
          }
        // {
          "/mnt/frame-boot" = {
            device = "/dev/disk/by-uuid/${rootUuid}";
            fsType = "btrfs";
            options = [
              "subvolid=5"
              "noatime"
            ];
            neededForBoot = true;
          };
          "/boot" = {
            device = "/mnt/frame-boot/boot";
            fsType = "none";
            options = [ "bind" ];
            depends = [ "/mnt/frame-boot" ];
            neededForBoot = true;
          };
        }
      else
        {
          "/" = {
            device = "/dev/disk/by-uuid/${rootUuid}";
            fsType = "btrfs";
          };
        };

    services.udev.extraRules = ''
      ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", DEVPATH=="*/1d84000.ufshc/*", ${
        lib.concatMapStringsSep ", " (uuid: ''ENV{ID_FS_UUID}!="${uuid}"'') writableUuids
      }, RUN+="${pkgs.util-linux}/bin/blockdev --setro $devnode"
      ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="mmcblk*", RUN+="${pkgs.util-linux}/bin/blockdev --setro $devnode"
    '';
    systemd.generators.systemd-gpt-auto-generator = "/dev/null";

    networking.hostName = "frame-nixos";
    networking.useDHCP = false;
    networking.networkmanager = {
      enable = true;
      wifi.powersave = false;
    };
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
      };
    };

    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
      settings.KbdInteractiveAuthentication = false;
    };
    users.users.root.openssh.authorizedKeys.keyFiles = [ ./authorized_keys ];

    systemd.services.frame-led-ready = {
      wantedBy = [ "multi-user.target" ];
      after = [ "sshd.service" ];
      serviceConfig.Type = "oneshot";
      script = led "0 255 0";
    };
    systemd.services.frame-led-failed = {
      wantedBy = [
        "emergency.target"
        "rescue.target"
      ];
      unitConfig.DefaultDependencies = false;
      serviceConfig.Type = "oneshot";
      script = led "255 0 0";
    };

    environment.systemPackages = [ pkgs.libdrm.bin ];

    documentation.enable = false;
    programs.command-not-found.enable = false;
  };
}
