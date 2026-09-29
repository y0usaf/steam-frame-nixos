{
  lib,
  pkgs,
  rootUuid,
  ...
}:
let
  valve = pkgs.callPackage ./valve.nix { };
  led = color: ''
    echo "${color}" > /sys/class/leds/rgb:status/multi_intensity
    echo 80 > /sys/class/leds/rgb:status/brightness
  '';
in
{
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

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/${rootUuid}";
    fsType = "btrfs";
  };

  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", DEVPATH=="*/1d84000.ufshc/*", ENV{ID_FS_UUID}!="${rootUuid}", ENV{ID_FS_UUID}!="4bac5c02-4a89-4377-8388-ce55ef171552", RUN+="${pkgs.util-linux}/bin/blockdev --setro $devnode"
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
}
