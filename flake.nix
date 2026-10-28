{
  inputs.nixpkgs.url = "https://releases.nixos.org/nixpkgs/nixpkgs-26.11pre1080803.419fe0f449b3/nixexprs.tar.zst";

  outputs =
    { self, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      keys = {
        frame.authorizedKeys = lib.optionals (builtins.pathExists ./authorized_keys) (
          lib.filter (line: line != "") (lib.splitString "\n" (builtins.readFile ./authorized_keys))
        );
      };
      slotA = lib.nixosSystem {
        modules = [
          self.nixosModules.default
          keys
        ];
      };
      recovery = lib.nixosSystem {
        modules = [
          ./modules/frame.nix
          ./modules/boot-loader.nix
          ./modules/hardware.nix
          ./modules/recovery.nix
          keys
        ];
      };
      image =
        nixos:
        pkgs.callPackage ./image.nix {
          inherit nixos;
          bootUuid = nixos.config.frame.storage.slotAUuid;
        };
    in
    {
      nixosModules.default = ./modules;
      nixosConfigurations = {
        frame-slotA = slotA;
        frame-recovery = recovery;
      };
      packages.x86_64-linux = {
        image = image slotA;
        recovery-image = image recovery;
        wivrn-server = pkgs.wivrn;
        deckard-kernel = (import ./pkgs/kernel.nix { inherit pkgs; }).kernel;
      };
    };
}
