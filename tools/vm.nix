let
  spike = toString ./..;
  flake = builtins.getFlake "path:${spike}";
in
(flake.inputs.nixpkgs.lib.nixosSystem {
  specialArgs.rootUuid = "47e26947-1018-45a7-95ae-4516d0bcf929";
  modules = [
    "${spike}/frame.nix"
    (
      { lib, pkgs, ... }:
      {
        boot.kernelPackages = lib.mkForce pkgs.linuxPackages;
        boot.initrd.availableKernelModules = lib.mkForce [
          "virtio_pci"
          "virtio_mmio"
          "virtio_blk"
        ];
        boot.initrd.kernelModules = lib.mkForce [
          "crc32c"
          "btrfs"
          "virtio_net"
        ];
      }
    )
  ];
}).config.system.build
