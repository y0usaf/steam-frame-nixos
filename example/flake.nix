{
  inputs.steam-frame-nixos.url = "github:y0usaf/steam-frame-nixos";

  outputs =
    { steam-frame-nixos, ... }:
    {
      nixosConfigurations.frame = steam-frame-nixos.inputs.nixpkgs.lib.nixosSystem {
        modules = [
          steam-frame-nixos.nixosModules.default
          ./configuration.nix
        ];
      };
    };
}
