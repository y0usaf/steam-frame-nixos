{ pkgs, ... }:
{
  fileSystems."/persist" = {
    device = "/dev/disk/by-partlabel/syspersist";
    fsType = "ext4";
    options = [
      "ro"
      "noload"
      "nofail"
    ];
  };

  environment.systemPackages = with pkgs; [
    btrfs-progs
    e2fsprogs
    rsync
    gnutar
    zstd
    util-linux
  ];
}
