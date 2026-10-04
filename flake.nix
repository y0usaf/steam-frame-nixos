{
  inputs.nixpkgs.url = "https://releases.nixos.org/nixpkgs/nixpkgs-26.11pre1080803.419fe0f449b3/nixexprs.tar.zst";

  outputs =
    { nixpkgs, ... }:
    let
      bootUuid = "47e26947-1018-45a7-95ae-4516d0bcf929";
      slotA = nixpkgs.lib.nixosSystem {
        specialArgs = {
          rootUuid = bootUuid;
        };
        modules = [
          ./frame.nix
          ./boot-loader.nix
          ./hardware.nix
          ./session.nix
          ./audio.nix
          ./wivrn.nix
          ./stremio.nix
          ./omarchy.nix
        ];
      };
      frame = slotA.extendModules {
        modules = [
          {
            frame.storage.poolUuid = "4bac5c02-4a89-4377-8388-ce55ef171552";
          }
        ];
      };
      recovery = nixpkgs.lib.nixosSystem {
        specialArgs.rootUuid = bootUuid;
        modules = [
          ./frame.nix
          ./boot-loader.nix
          ./hardware.nix
          ./recovery.nix
        ];
      };
    in
    {
      nixosConfigurations = {
        inherit frame;
        frame-slotA = slotA;
        frame-recovery = recovery;
      };
      packages.x86_64-linux = {
        image = nixpkgs.legacyPackages.x86_64-linux.callPackage ./image.nix {
          inherit bootUuid;
          nixos = slotA;
        };
        recovery-image = nixpkgs.legacyPackages.x86_64-linux.callPackage ./image.nix {
          inherit bootUuid;
          nixos = recovery;
        };
        wivrn-server = nixpkgs.legacyPackages.x86_64-linux.wivrn;
      };
    };
}
