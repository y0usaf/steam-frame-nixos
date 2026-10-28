let
  spike = toString ./..;
  flake = builtins.getFlake "path:${spike}";
in
(flake.inputs.nixpkgs.lib.nixosSystem {
  modules = [
    "${spike}/modules/frame.nix"
    (
      { lib, pkgs, ... }:
      {
        frame.authorizedKeys = flake.nixosConfigurations.frame-slotA.config.frame.authorizedKeys;
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
