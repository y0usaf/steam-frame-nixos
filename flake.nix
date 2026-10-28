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
          ./modules/frame.nix
          ./modules/boot-loader.nix
          ./modules/hardware.nix
          ./modules/session.nix
          ./modules/audio.nix
          ./modules/wivrn.nix
          ./stremio.nix
          ./omarchy.nix
          ./modules/framecorder.nix
          ./beat-saber.nix
          ./modules/steamos-manager.nix
          ./modules/powerbuttond.nix
        ];
      };
      frame = slotA.extendModules {
        modules = [
          {
            frame.storage.poolUuid = "4bac5c02-4a89-4377-8388-ce55ef171552";
            frame.beatSaber.mods = [
              "SongCore"
              "BeatSaverDownloader"
            ];
          }
        ];
      };
      recovery = nixpkgs.lib.nixosSystem {
        specialArgs.rootUuid = bootUuid;
        modules = [
          ./modules/frame.nix
          ./modules/boot-loader.nix
          ./modules/hardware.nix
          ./modules/recovery.nix
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
        deckard-kernel =
          (import ./pkgs/kernel.nix {
            pkgs = nixpkgs.legacyPackages.x86_64-linux;
          }).kernel;
      };
    };
}
