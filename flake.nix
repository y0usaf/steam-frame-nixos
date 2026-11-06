{
  inputs.nixpkgs.url = "https://releases.nixos.org/nixpkgs/nixpkgs-26.11pre1080803.419fe0f449b3/nixexprs.tar.zst";

  outputs =
    { self, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      hasKeys = builtins.pathExists ./authorized_keys;
      bringUp = {
        system.stateVersion = "26.05";
        frame.authorizedKeys = lib.optionals (builtins.pathExists ./authorized_keys) (
          lib.filter (line: line != "") (lib.splitString "\n" (builtins.readFile ./authorized_keys))
        );
      };
      slotA = lib.nixosSystem {
        modules = [
          self.nixosModules.default
          bringUp
        ];
      };
      recovery = lib.nixosSystem {
        modules = [
          self.nixosModules.recovery
          bringUp
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
      nixosModules = {
        default = ./modules;
        recovery = ./modules/recovery-system.nix;
      };
      templates.default = {
        path = ./example;
        description = "A Steam Frame system built from nixosModules.default";
      };
      nixosConfigurations = lib.optionalAttrs hasKeys {
        frame-slotA = slotA;
        frame-recovery = recovery;
      };
      packages.x86_64-linux = {
        wivrn-server = pkgs.wivrn;
        deckard-kernel = (import ./pkgs/kernel.nix { inherit pkgs; }).kernel;
      }
      // lib.optionalAttrs hasKeys {
        image = image slotA;
        recovery-image = image recovery;
      };
    };
}
